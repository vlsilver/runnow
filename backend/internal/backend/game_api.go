package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// API đọc và đăng ký của Ma Sói (3.8). Mọi mốc giờ trả ra là giờ thật: ván thử
// đã bị đẩy giờ thì trừ độ lệch trước khi trả, nên app đếm ngược theo serverNow
// như nhau cho cả hai loại ván. Không hàm nào ở đây trả vai của người còn sống,
// trừ /me của chính người đó.

var (
	errGameNotFound      = &HTTPError{Status: http.StatusNotFound, Code: "not_found", Message: "Không tìm thấy ván."}
	errNotGamePlayer     = &HTTPError{Status: http.StatusNotFound, Code: "not_player", Message: "Bạn không chơi ván này."}
	errNotAdmin          = &HTTPError{Status: http.StatusForbidden, Code: "not_admin", Message: "Chỉ admin làm được việc này."}
	errRegistrationShut  = &HTTPError{Status: http.StatusConflict, Code: "phase_closed", Message: "Ván đã hết hạn đăng ký hoặc đã bắt đầu."}
	errGameFull          = &HTTPError{Status: http.StatusConflict, Code: "game_full", Message: fmt.Sprintf("Ván đã đủ %d người.", werewolf.MaxPlayers)}
	errInvalidDeadline   = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_deadline", Message: "Hạn đăng ký phải ở sau lúc này."}
	errTestModeNeedsChat = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_chat", Message: "Ván thử phải có chatId của group test."}
)

const gameTitle = "Ma Sói"

// toggleRoles là các vai admin bật tắt được lúc tạo ván (R8), theo thứ tự hiện
// trên form. Config.Validate vẫn là chốt chặn nếu danh sách này lệch engine.
var toggleRoles = []werewolf.Role{werewolf.Seer, werewolf.Guard, werewolf.Witch, werewolf.Hunter, werewolf.Cupid}

// GameViewer là người gọi API và bản app họ đang dùng (header X-App-Version).
type GameViewer struct {
	UID        string
	AppVersion string
}

// gameConfig là gameState/config, chủ repo ghi tay (S10). Đọc mỗi request, nên
// sửa là có hiệu lực ngay, không cần deploy.
type gameConfig struct {
	admins, testers map[string]bool
	minAppVersion   string
	pscInviteURL    string            // link mời vào PSC, gắn vào mục in_psc khi chưa đạt
	cards           map[string]string // vai → URL ảnh lá bài; "back" là mặt sau
}

func (c gameConfig) isAdmin(uid string) bool  { return c.admins[uid] }
func (c gameConfig) isTester(uid string) bool { return c.admins[uid] || c.testers[uid] }

func (s *GameStore) loadConfig(ctx context.Context) (gameConfig, error) {
	cfg := gameConfig{admins: map[string]bool{}, testers: map[string]bool{}, cards: map[string]string{}}
	doc, err := s.db.Collection("gameState").Doc("config").Get(ctx)
	if status.Code(err) == codes.NotFound {
		return cfg, nil
	}
	if err != nil {
		return cfg, err
	}
	d := doc.Data()
	for _, v := range anyList(d["adminUids"]) {
		cfg.admins[stringValue(v)] = true
	}
	for _, v := range anyList(d["testerUids"]) {
		cfg.testers[stringValue(v)] = true
	}
	cfg.minAppVersion = strings.TrimSpace(stringValue(d["minAppVersion"]))
	cfg.pscInviteURL = strings.TrimSpace(stringValue(d["pscInviteUrl"]))
	if cards, ok := d["cards"].(map[string]any); ok {
		for k, v := range cards {
			cfg.cards[k] = stringValue(v)
		}
	}
	return cfg, nil
}

func anyList(v any) []any {
	l, _ := v.([]any)
	return l
}

// appVersionOK so bản app với minAppVersion theo từng số, bỏ phần +build và
// -pre. Thiếu header (bản 1.4.3 chưa gửi) hoặc sai dạng thì coi là bản cũ.
// minAppVersion sai dạng cũng chặn: cấu hình sai thì lộ ra ngay lúc test.
func appVersionOK(have, min string) bool {
	if min == "" {
		return true
	}
	h, ok := parseVersion(have)
	if !ok {
		return false
	}
	m, ok := parseVersion(min)
	if !ok {
		return false
	}
	for i := 0; i < max(len(h), len(m)); i++ {
		a, b := versionPart(h, i), versionPart(m, i)
		if a != b {
			return a > b
		}
	}
	return true
}

func parseVersion(v string) ([]int, bool) {
	v = strings.TrimSpace(v)
	if i := strings.IndexAny(v, "+-"); i >= 0 {
		v = v[:i]
	}
	if v == "" {
		return nil, false
	}
	parts := strings.Split(v, ".")
	out := make([]int, len(parts))
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || n < 0 {
			return nil, false
		}
		out[i] = n
	}
	return out, true
}

func versionPart(v []int, i int) int {
	if i < len(v) {
		return v[i]
	}
	return 0
}

// GameRequirement là một điều kiện để đăng ký (2.3). Action là việc app làm khi
// người dùng bấm vào mục chưa đạt.
type GameRequirement struct {
	Key    string             `json:"key"`
	OK     bool               `json:"ok"`
	Label  string             `json:"label"`
	Action *RequirementAction `json:"action,omitempty"`
}

type RequirementAction struct {
	Type string `json:"type"` // link_telegram | open_url | update_app
	URL  string `json:"url,omitempty"`
}

// viewerLink là liên kết Telegram của một uid, chỉ tính khi hai doc trỏ nhau.
type viewerLink struct {
	tgUserID    int64
	linked      bool
	inPsc       bool
	displayName string
	username    string
}

type docGetter func(*firestore.DocumentRef) (*firestore.DocumentSnapshot, error)

func ctxGetter(ctx context.Context) docGetter {
	return func(ref *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) {
		snap, err := ref.Get(ctx)
		if status.Code(err) == codes.NotFound {
			return snap, nil
		}
		return snap, err
	}
}

func txGetter(tx *firestore.Transaction) docGetter {
	return func(ref *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) { return getOptional(tx, ref) }
}

func (s *GameStore) readLink(get docGetter, uid string) (viewerLink, error) {
	byUID, err := get(s.db.Collection("telegramLinks").Doc(uid))
	if err != nil || !byUID.Exists() {
		return viewerLink{}, err
	}
	tg := tgIDString(byUID.Data()["tgUserId"])
	if tg == "" {
		return viewerLink{}, nil
	}
	link, err := get(s.db.Collection("tgLinks").Doc(tg))
	if err != nil || !link.Exists() || stringValue(link.Data()["uid"]) != uid {
		return viewerLink{}, err
	}
	id, _ := strconv.ParseInt(tg, 10, 64)
	return viewerLink{tgUserID: id, linked: true, inPsc: link.Data()["inPsc"] == true, displayName: stringValue(link.Data()["displayName"]), username: stringValue(link.Data()["username"])}, nil
}

func requirementsFor(link viewerLink, appVersion string, cfg gameConfig) []GameRequirement {
	reqs := []GameRequirement{
		{Key: "telegram_linked", OK: link.linked, Label: "Đã liên kết Telegram"},
		{Key: "in_psc", OK: link.linked && link.inPsc, Label: "Đang ở trong group PSC"},
		{Key: "app_version", OK: appVersionOK(appVersion, cfg.minAppVersion), Label: "Bản app đủ mới"},
	}
	if !reqs[0].OK {
		reqs[0].Action = &RequirementAction{Type: "link_telegram"}
	}
	// Chưa liên kết thì chưa biết có ở PSC không, vẫn đưa link: mở link khi đã ở
	// trong group thì Telegram chỉ mở group ra. Vào xong, bot nhận chat_member và
	// ghi inPsc, nên link phải là link mời thường, không phải link cần duyệt.
	if !reqs[1].OK && cfg.pscInviteURL != "" {
		reqs[1].Action = &RequirementAction{Type: "open_url", URL: cfg.pscInviteURL}
	}
	if cfg.minAppVersion != "" {
		reqs[2].Label = "Bản app từ " + cfg.minAppVersion + " trở lên"
	}
	if !reqs[2].OK {
		reqs[2].Action = &RequirementAction{Type: "update_app"}
	}
	return reqs
}

func requirementsMet(reqs []GameRequirement) bool {
	for _, r := range reqs {
		if !r.OK {
			return false
		}
	}
	return true
}

// ---- Danh sách ván ----

type GameList struct {
	Viewer        GameListViewer    `json:"viewer"`
	CreateOptions GameCreateOptions `json:"createOptions"`
	Items         []GameListItem    `json:"items"`
}

type GameListViewer struct {
	CanCreate bool `json:"canCreate"`
}

type GameCreateOptions struct {
	Roles []GameRoleOption `json:"roles"`
}

type GameRoleOption struct {
	Key     string `json:"key"`
	Label   string `json:"label"`
	Default bool   `json:"default"`
}

type GameListItem struct {
	ID           string     `json:"id"`
	Title        string     `json:"title"`
	Subtitle     string     `json:"subtitle"`
	Status       string     `json:"status"`
	StatusLabel  string     `json:"statusLabel"`
	PlayerCount  int        `json:"playerCount"`
	MinPlayers   int        `json:"minPlayers"`
	MaxPlayers   int        `json:"maxPlayers"`
	HasTodo      bool       `json:"hasTodo"`
	NextDeadline *time.Time `json:"nextDeadline"`
	UpdatedAt    time.Time  `json:"updatedAt"`
	TestMode     bool       `json:"testMode"`
}

const (
	gameListLimit = 10
	// gameListKeepClosed: ván đã hết hay đã huỷ còn trên feed bấy lâu.
	gameListKeepClosed = 24 * time.Hour
)

// List trả các ván trong 10 ván mới nhất còn đáng hiện: ván đã đóng quá
// gameListKeepClosed thì bỏ. Ván thử chỉ hiện với admin, người test và người
// đã đăng ký vào ván đó.
func (s *GameStore) List(ctx context.Context, v GameViewer, wall time.Time) (GameList, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return GameList{}, err
	}
	out := GameList{Viewer: GameListViewer{CanCreate: cfg.isAdmin(v.UID)}, Items: []GameListItem{}}
	for _, r := range toggleRoles {
		out.CreateOptions.Roles = append(out.CreateOptions.Roles, GameRoleOption{Key: string(r), Label: roleLabels[r], Default: true})
	}
	docs, err := s.db.Collection("games").OrderBy("createdAt", firestore.Desc).Limit(gameListLimit).Documents(ctx).GetAll()
	if err != nil {
		return out, err
	}
	refs := make([]*firestore.DocumentRef, len(docs))
	for i, d := range docs {
		refs[i] = d.Ref.Collection("players").Doc(v.UID)
	}
	mine, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return out, err
	}
	for i, d := range docs {
		g := d.Data()
		registered := mine[i].Exists()
		if g["testMode"] == true && !cfg.isTester(v.UID) && !registered {
			continue
		}
		if gameClosed(stringValue(g["status"])) && wall.Sub(timeValue(g["updatedAt"])) > gameListKeepClosed {
			continue
		}
		item := GameListItem{
			ID: d.Ref.ID, Title: gameTitle, Status: apiStatus(g), StatusLabel: statusLabel(g),
			PlayerCount: int(number(g["playerCount"])), MinPlayers: werewolf.MinPlayers, MaxPlayers: werewolf.MaxPlayers,
			UpdatedAt: timeValue(g["updatedAt"]), TestMode: g["testMode"] == true,
		}
		item.Subtitle = gameSubtitle(g, item.PlayerCount)
		item.NextDeadline = nextDeadline(g)
		if registered && stringValue(g["status"]) == gameRunning {
			if item.HasTodo, err = s.hasTodo(ctx, d.Ref, g, v.UID, wall); err != nil {
				return out, err
			}
		}
		out.Items = append(out.Items, item)
	}
	return out, nil
}

// apiStatus: store giữ pause bằng cờ paused để status không đổi khi resume;
// API trả paused như một trạng thái (3.7).
func apiStatus(g map[string]any) string {
	st := stringValue(g["status"])
	if st == gameRunning && g["paused"] == true {
		return "paused"
	}
	return st
}

func statusLabel(g map[string]any) string {
	if apiStatus(g) == "paused" {
		return "Tạm dừng"
	}
	return statusLabels[stringValue(g["status"])]
}

func gameSubtitle(g map[string]any, players int) string {
	switch stringValue(g["status"]) {
	case gameRegistering:
		return fmt.Sprintf("%d/%d người đã đăng ký", players, werewolf.MaxPlayers)
	case gameStarting:
		return "Bot đang chia bài"
	case gameRunning:
		if g["paused"] == true {
			return "Ván đang tạm dừng"
		}
		return phaseLabelOf(g)
	case gameEnded:
		return teamLabels[werewolf.Team(stringValue(g["winner"]))] + " thắng"
	}
	return ""
}

func phaseLabelOf(g map[string]any) string {
	if strings.HasSuffix(stringValue(g["phaseKey"]), "/hunter") {
		return "Thợ săn đang chọn người bắn"
	}
	return phaseLabel(int(number(g["round"])), werewolf.Phase(stringValue(g["phase"])))
}

// nextDeadline là mốc khoá kế tiếp theo giờ thật: hạn đăng ký, hạn bắn của thợ
// săn, hoặc hạn phase. Không lấy nextAt vì nó gồm cả giờ nhắc 18h, 21h.
func nextDeadline(g map[string]any) *time.Time {
	var t time.Time
	switch stringValue(g["status"]) {
	case gameRegistering:
		t = timeValue(g["registrationDeadline"])
	case gameRunning:
		if g["paused"] == true {
			return nil
		}
		t = timeValue(g["deadline"])
		if strings.HasSuffix(stringValue(g["phaseKey"]), "/hunter") {
			t = timeValue(g["nextAt"])
		}
		if !t.IsZero() {
			t = t.Add(-clockOffset(g))
		}
	}
	if t.IsZero() {
		return nil
	}
	return &t
}

func timeValue(v any) time.Time {
	t, _ := v.(time.Time)
	return t
}

func (s *GameStore) loadState(ctx context.Context, game *firestore.DocumentRef) (*werewolf.State, error) {
	sec, err := secretRef(game).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return decodeState(sec.Data())
}

// loadMine đọc lựa chọn của uid ở vòng round: bản cho engine (bỏ lựa chọn đã
// xoá) và doc thô theo kind (để hiện selected).
func (s *GameStore) loadMine(ctx context.Context, game *firestore.DocumentRef, round int, uid string) ([]werewolf.Action, map[werewolf.Kind]map[string]any, error) {
	kinds := werewolf.Kinds()
	refs := make([]*firestore.DocumentRef, len(kinds))
	for i, k := range kinds {
		refs[i] = actionRef(game, round, uid, k)
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, nil, err
	}
	var mine []werewolf.Action
	raw := map[werewolf.Kind]map[string]any{}
	for i, d := range docs {
		if !d.Exists() {
			continue
		}
		if a, ok := decodeAction(d.Data()); ok {
			mine = append(mine, a)
			raw[kinds[i]] = d.Data()
		}
	}
	return mine, raw, nil
}

// todoKinds là việc uid bấm được ngay mà chưa bấm.
func todoKinds(st *werewolf.State, uid string, mine []werewolf.Action, now time.Time) []werewolf.Kind {
	done := map[werewolf.Kind]bool{}
	for _, a := range mine {
		done[a.Kind] = true
	}
	var out []werewolf.Kind
	for _, k := range st.Available(uid) {
		if !done[k] && werewolf.Precheck(st, k, uid, mine, now) == nil {
			out = append(out, k)
		}
	}
	return out
}

// hasTodo bật badge trên feed Kèo, nơi ai cũng liếc thấy, nên chỉ tính việc
// mọi người còn sống đều có. Việc riêng của vai (cắn, soi, cứu…) mà bật badge
// thì lộ vai; những việc đó đã có DM và màn chi tiết ván.
func (s *GameStore) hasTodo(ctx context.Context, game *firestore.DocumentRef, g map[string]any, uid string, wall time.Time) (bool, error) {
	st, err := s.loadState(ctx, game)
	if err != nil || st == nil {
		return false, err
	}
	mine, _, err := s.loadMine(ctx, game, st.Round, uid)
	if err != nil {
		return false, err
	}
	for _, k := range todoKinds(st, uid, mine, gameNow(g, wall)) {
		if groupKind(k) {
			return true, nil
		}
	}
	return false, nil
}

// ---- Người chơi và feed ----

type gamePlayerInfo struct {
	uid, name, avatar string
	fake              bool
	data              map[string]any
}

// loadPlayers đọc players/* của ván cùng tên, ảnh trong publicProfiles. Xếp theo
// lúc đăng ký để danh sách không nhảy chỗ giữa các lần tải.
func (s *GameStore) loadPlayers(ctx context.Context, game *firestore.DocumentRef) ([]gamePlayerInfo, error) {
	docs, err := game.Collection("players").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	players := make([]gamePlayerInfo, len(docs))
	var refs []*firestore.DocumentRef
	var realIdx []int
	for i, d := range docs {
		p := gamePlayerInfo{uid: d.Ref.ID, name: stringValue(d.Data()["name"]), fake: d.Data()["fake"] == true, data: d.Data()}
		players[i] = p
		if !p.fake {
			refs = append(refs, s.db.Collection("publicProfiles").Doc(p.uid))
			realIdx = append(realIdx, i)
		}
	}
	if len(refs) > 0 {
		profiles, err := s.db.GetAll(ctx, refs)
		if err != nil {
			return nil, err
		}
		for j, prof := range profiles {
			if !prof.Exists() {
				continue
			}
			p := &players[realIdx[j]]
			if name := stringValue(prof.Data()["displayName"]); name != "" {
				p.name = name
			}
			p.avatar = stringValue(prof.Data()["avatarUrl"])
		}
	}
	for i := range players {
		if players[i].name == "" {
			players[i].name = "Người chơi"
		}
	}
	sort.SliceStable(players, func(i, j int) bool {
		a, b := timeValue(players[i].data["registeredAt"]), timeValue(players[j].data["registeredAt"])
		if !a.Equal(b) {
			return a.Before(b)
		}
		return players[i].uid < players[j].uid
	})
	return players, nil
}

func playerIndex(players []gamePlayerInfo) map[string]gamePlayerInfo {
	out := map[string]gamePlayerInfo{}
	for _, p := range players {
		out[p.uid] = p
	}
	return out
}

type GameFeed struct {
	Items  []GameFeedItem `json:"items"`
	Cursor string         `json:"cursor,omitempty"`
}

type GameFeedItem struct {
	Seq   int64     `json:"seq"`
	At    time.Time `json:"at"`
	Title string    `json:"title"`
	Lines []string  `json:"lines"`
	// picks: mục diễn biến từng lần bấm (writePickFeed), không phải bản tin.
	picks bool
}

const feedPageSize = 20

// loadFeed trả một trang feed, mới trước. cursor là seq cuối của trang trước;
// rỗng là trang đầu. Trang còn đầy thì trả cursor để tải tiếp.
func (s *GameStore) loadFeed(ctx context.Context, game *firestore.DocumentRef, cursor string, players map[string]gamePlayerInfo) (GameFeed, error) {
	q := game.Collection("feed").OrderBy("seq", firestore.Desc).Limit(feedPageSize)
	if cursor != "" {
		n, err := strconv.ParseInt(cursor, 10, 64)
		if err != nil || n < 1 {
			return GameFeed{}, invalidRequest()
		}
		q = game.Collection("feed").Where("seq", "<", n).OrderBy("seq", firestore.Desc).Limit(feedPageSize)
	}
	docs, err := q.Documents(ctx).GetAll()
	if err != nil {
		return GameFeed{}, err
	}
	feed := GameFeed{Items: []GameFeedItem{}}
	for _, d := range docs {
		item, err := feedItem(d.Data(), players)
		if err != nil {
			return feed, fmt.Errorf("feed/%s: %w", d.Ref.ID, err)
		}
		if len(item.Lines) > 0 {
			feed.Items = append(feed.Items, item)
		}
	}
	if len(docs) == feedPageSize {
		feed.Cursor = strconv.FormatInt(int64(number(docs[len(docs)-1].Data()["seq"])), 10)
	}
	return feed, nil
}

// feedItem dựng chữ cho một dòng feed. Feed chỉ chứa event công khai (publicEvents),
// nên ở đây không lọc lại.
func feedItem(d map[string]any, players map[string]gamePlayerInfo) (GameFeedItem, error) {
	var evs []werewolf.Event
	if err := json.Unmarshal([]byte(stringValue(d["events"])), &evs); err != nil {
		return GameFeedItem{}, err
	}
	at := timeValue(d["wallAt"])
	if at.IsZero() {
		at = timeValue(d["at"])
	}
	item := GameFeedItem{Seq: int64(number(d["seq"])), At: at, Lines: []string{}}
	round, phase, hunter := parsePhaseKey(stringValue(d["phaseKey"]))
	name := func(uid string) string {
		if p, ok := players[uid]; ok {
			return p.name
		}
		return "Người chơi"
	}
	var picks []pick
	for _, raw := range anyList(d["picks"]) {
		var p pick
		if err := json.Unmarshal([]byte(stringValue(raw)), &p); err != nil {
			return GameFeedItem{}, err
		}
		picks = append(picks, p)
	}
	// Hai lần bấm sát nhau có thể commit lệch thứ tự bấm.
	slices.SortStableFunc(picks, func(a, b pick) int { return a.At.Compare(b.At) })
	for _, p := range picks {
		item.picks = true
		item.Lines = append(item.Lines, p.At.In(vietnam).Format("15:04")+" "+p.text(name))
	}
	deaths := 0
	for _, e := range evs {
		switch e.Kind {
		case werewolf.EventDeath:
			deaths++
			if e.Role == "" && e.Team != "" { // chỉ lộ phe (roleHidden)
				item.Lines = append(item.Lines, fmt.Sprintf("%s đã chết, thuộc %s.", name(e.UID), teamLabels[e.Team]))
			} else {
				item.Lines = append(item.Lines, fmt.Sprintf("%s đã chết. Lá bài: %s.", name(e.UID), roleLabels[e.Role]))
			}
		case werewolf.EventNominee:
			nominees := e.Targets
			if len(nominees) == 0 && e.UID != "" {
				nominees = []string{e.UID} // event ghi trước khi có nhiều phiên
			}
			switch len(nominees) {
			case 0:
				item.Lines = append(item.Lines, "Không ai được đề cử, hôm nay không ai lên giàn.")
				continue
			case 1:
				line := fmt.Sprintf("%s lên giàn với %d đề cử", name(nominees[0]), e.Counts[nominees[0]])
				if e.Draw {
					line += ", bốc thăm vì hoà"
				}
				item.Lines = append(item.Lines, line+".")
				continue
			}
			parts := make([]string, len(nominees))
			for i, uid := range nominees {
				parts[i] = fmt.Sprintf("%s (%d đề cử)", name(uid), e.Counts[uid])
			}
			line := fmt.Sprintf("%d người lên giàn: %s", len(nominees), strings.Join(parts, ", "))
			if e.Draw {
				line += ". Suất cuối bốc thăm vì hoà"
			}
			item.Lines = append(item.Lines, line+".")
		case werewolf.EventVoteCut:
			names := make([]string, len(e.Targets))
			for i, uid := range e.Targets {
				names[i] = name(uid)
			}
			line := fmt.Sprintf("Tổng km chưa đủ nên %s mất phiếu", strings.Join(names, ", "))
			if e.UID != "" {
				line = fmt.Sprintf("Phiên %s: tổng km chưa đủ nên %s mất phiếu", name(e.UID), strings.Join(names, ", "))
			}
			if e.Draw {
				line += ", bốc thăm vì bằng km"
			}
			item.Lines = append(item.Lines, line+".")
		case werewolf.EventVoteResult:
			if e.Reason == werewolf.ReasonNoTrial {
				item.Lines = append(item.Lines, fmt.Sprintf("%s đã rời PSC, bỏ biểu quyết.", name(e.UID)))
				continue
			}
			verdict := "được tha"
			if e.Hanged {
				verdict = "bị treo"
			}
			item.Lines = append(item.Lines, fmt.Sprintf("Treo %d, Tha %d: %s %s.", e.Hang, e.Spare, name(e.UID), verdict))
		case werewolf.EventHunterTurn:
			item.Lines = append(item.Lines, fmt.Sprintf("%s là Thợ săn, được bắn một người.", name(e.UID)))
		case werewolf.EventWinner:
			item.Lines = append(item.Lines, teamLabels[e.Team]+" thắng.")
		}
	}
	switch {
	case hunter:
		item.Title = "Thợ săn bắn"
	case phase == werewolf.PhaseDawn:
		item.Title = fmt.Sprintf("Bản tin đêm %d", round)
		if deaths == 0 {
			item.Lines = append([]string{"Đêm qua không ai chết."}, item.Lines...)
		}
	case phase == werewolf.PhaseDay && item.picks:
		item.Title = fmt.Sprintf("Diễn biến đề cử ngày %d", round)
	case phase == werewolf.PhaseDay:
		item.Title = fmt.Sprintf("Đề cử ngày %d", round)
	case phase == werewolf.PhaseTrial && item.picks:
		item.Title = fmt.Sprintf("Diễn biến biểu quyết ngày %d", round)
	case phase == werewolf.PhaseTrial:
		item.Title = fmt.Sprintf("Biểu quyết ngày %d", round)
	default:
		item.Title = fmt.Sprintf("Đêm %d", round)
	}
	return item, nil
}

// parsePhaseKey đọc "r3/day" hay "r3/day/hunter" (State.PhaseKey).
func parsePhaseKey(key string) (int, werewolf.Phase, bool) {
	parts := strings.Split(key, "/")
	if len(parts) < 2 {
		return 0, "", false
	}
	n, _ := strconv.Atoi(strings.TrimPrefix(parts[0], "r"))
	return n, werewolf.Phase(parts[1]), len(parts) > 2 && parts[2] == "hunter"
}

// ---- Chi tiết ván ----

type GameDetail struct {
	ID                   string            `json:"id"`
	Title                string            `json:"title"`
	Status               string            `json:"status"`
	StatusLabel          string            `json:"statusLabel"`
	TestMode             bool              `json:"testMode"`
	Version              int64             `json:"version"`
	ServerNow            time.Time         `json:"serverNow"`
	RefreshAfterSeconds  int               `json:"refreshAfterSeconds"`
	RulesText            string            `json:"rulesText"`
	Phase                *GamePhase        `json:"phase"`
	Players              []GamePlayer      `json:"players"`
	PlayerCount          int               `json:"playerCount"`
	MinPlayers           int               `json:"minPlayers"`
	MaxPlayers           int               `json:"maxPlayers"`
	RegistrationDeadline *time.Time        `json:"registrationDeadline"`
	Feed                 GameFeed          `json:"feed"`
	Requirements         []GameRequirement `json:"requirements"`
	IsRegistered         bool              `json:"isRegistered"`
	IsAdmin              bool              `json:"isAdmin"`
	MinAppVersion        string            `json:"minAppVersion"`
	Winner               string            `json:"winner,omitempty"`
	WinnerLabel          string            `json:"winnerLabel,omitempty"`
	// TaskKey chỉ trả cho admin ở ván thử, để gửi kèm admin/advance.
	TaskKey string `json:"taskKey,omitempty"`
	// StartError chỉ trả cho admin: lần Start gần nhất bị bot trả về đăng ký.
	StartError *GameStartError `json:"startError,omitempty"`
	// KmTable là đầu cột của bảng km hai cột (players[].lastKm, players[].todayKm).
	// Nil khi ván không chạy.
	KmTable *GameKmTable `json:"kmTable,omitempty"`
}

type GameKmTable struct {
	LastLabel  string     `json:"lastLabel"`
	TodayLabel string     `json:"todayLabel"`
	AsOf       *time.Time `json:"asOf,omitempty"` // lúc tính todayKm; nil ở ván thử
	UnitKm     float64    `json:"unitKm"`         // mốc km cho một kỹ năng đêm, một phiếu
	Note       string     `json:"note"`
}

// GameTeamKm là km của cả phe khi luật tính theo phe (phe Sói cắn).
type GameTeamKm struct {
	Label     string   `json:"label"`
	Last      float64  `json:"last"`
	Today     *float64 `json:"today,omitempty"`
	Need      float64  `json:"need"`
	NeedLabel string   `json:"needLabel"`
}

type GamePhase struct {
	Key      string     `json:"key"`
	Label    string     `json:"label"`
	Deadline *time.Time `json:"deadline"`
	State    string     `json:"state"` // open | closing: đã quá hạn, đang chờ bước chốt chạy
}

type GamePlayer struct {
	UID               string   `json:"uid"`
	Name              string   `json:"name"`
	AvatarURL         string   `json:"avatarUrl,omitempty"`
	Alive             bool     `json:"alive"`
	// RevealedRoleLabel là cái group đã biết về người chết: tên lá bài, hoặc
	// chỉ "Phe Dân"/"Phe Sói" với người bị treo, khi đó không có RevealedCardURL.
	RevealedRoleLabel string   `json:"revealedRoleLabel,omitempty"`
	RevealedCardURL   string   `json:"revealedCardUrl,omitempty"`
	DeathRound        int      `json:"deathRound,omitempty"`
	OnTrial           bool     `json:"onTrial,omitempty"`
	LastKm            *float64 `json:"lastKm,omitempty"`
	// TodayKm là km đang gom tới mốc 22h kế tiếp của người còn sống (kmTable).
	TodayKm *float64 `json:"todayKm,omitempty"`
	Fake              bool     `json:"fake,omitempty"`
}

// readVisibleGame đọc ván và trả 404 nếu người gọi không được thấy nó (ván thử
// của người khác). registered là người gọi có players/{uid} thật.
func (s *GameStore) readVisibleGame(ctx context.Context, gameID string, cfg gameConfig, uid string) (*firestore.DocumentSnapshot, bool, error) {
	if gameID == "" || len(gameID) > 64 || strings.Contains(gameID, "/") {
		return nil, false, errGameNotFound
	}
	game := s.gameRef(gameID)
	g, err := game.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, false, errGameNotFound
	}
	if err != nil {
		return nil, false, err
	}
	p, err := ctxGetter(ctx)(game.Collection("players").Doc(uid))
	if err != nil {
		return nil, false, err
	}
	registered := p.Exists() && p.Data()["fake"] != true
	if g.Data()["testMode"] == true && !cfg.isTester(uid) && !registered {
		return nil, false, errGameNotFound
	}
	return g, registered, nil
}

func (s *GameStore) Detail(ctx context.Context, gameID string, v GameViewer, wall time.Time) (GameDetail, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return GameDetail{}, err
	}
	g, registered, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return GameDetail{}, err
	}
	data := g.Data()
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return GameDetail{}, err
	}
	index := playerIndex(players)
	feed, err := s.loadFeed(ctx, g.Ref, "", index)
	if err != nil {
		return GameDetail{}, err
	}
	link, err := s.readLink(ctxGetter(ctx), v.UID)
	if err != nil {
		return GameDetail{}, err
	}
	out := GameDetail{
		ID: g.Ref.ID, Title: gameTitle, Status: apiStatus(data), StatusLabel: statusLabel(data),
		TestMode: data["testMode"] == true, Version: int64(number(data["version"])), ServerNow: wall,
		RulesText: gameRulesText, PlayerCount: len(players), MinPlayers: werewolf.MinPlayers, MaxPlayers: werewolf.MaxPlayers,
		Feed: feed, Requirements: requirementsFor(link, v.AppVersion, cfg),
		IsRegistered: registered, IsAdmin: cfg.isAdmin(v.UID), MinAppVersion: cfg.minAppVersion,
		Winner: stringValue(data["winner"]),
	}
	out.WinnerLabel = teamLabels[werewolf.Team(out.Winner)]
	if t := timeValue(data["registrationDeadline"]); !t.IsZero() {
		out.RegistrationDeadline = &t
	}
	if out.IsAdmin && out.TestMode && stringValue(data["status"]) == gameRunning {
		out.TaskKey = stringValue(data["taskKey"])
	}
	if out.IsAdmin {
		out.StartError = startErrorOf(data)
	}
	if stringValue(data["status"]) == gameRunning {
		deadline := nextDeadline(data)
		out.Phase = &GamePhase{Key: stringValue(data["phaseKey"]), Label: phaseLabelOf(data), Deadline: deadline, State: "open"}
		if deadline != nil && !wall.Before(*deadline) {
			out.Phase.State = "closing"
		}
	}
	out.RefreshAfterSeconds = refreshAfter(data, out.Phase, wall)

	km, err := s.lastKm(ctx, g.Ref, data, players)
	if err != nil {
		return out, err
	}
	var st *werewolf.State
	if stringValue(data["status"]) == gameRunning {
		if st, err = s.loadState(ctx, g.Ref); err != nil {
			return out, err
		}
	}
	live, err := s.liveKm(ctx, g.Ref, data, st, wall)
	if err != nil {
		return out, err
	}
	out.KmTable = kmTable(data, st, live, wall)
	nominees := gameNominees(data)
	out.Players = make([]GamePlayer, 0, len(players))
	for _, p := range players {
		gp := GamePlayer{UID: p.uid, Name: p.name, AvatarURL: p.avatar, Alive: p.data["alive"] != false, Fake: p.fake, OnTrial: slices.Contains(nominees, p.uid)}
		if label, role := revealedLabel(data, p.uid); label != "" {
			gp.RevealedRoleLabel, gp.RevealedCardURL = label, cfg.cards[string(role)]
		}
		gp.DeathRound = int(number(p.data["deathRound"]))
		if m, ok := km[p.uid]; ok {
			k := m / 1000
			gp.LastKm = &k
		}
		if m, ok := live.metersOf(p.uid); ok && gp.Alive {
			k := m / 1000
			gp.TodayKm = &k
		}
		out.Players = append(out.Players, gp)
	}
	return out, nil
}

// refreshAfter là số giây app nên đợi trước khi tải lại: ngay sau hạn kế tiếp
// khi ván đang chạy, thưa hơn khi chẳng có gì sắp đổi. 0 là không cần tự tải.
func refreshAfter(g map[string]any, phase *GamePhase, wall time.Time) int {
	switch apiStatus(g) {
	case gameRegistering:
		return 60
	case gameStarting:
		return 5
	case "paused":
		return 120
	case gameRunning:
		if phase != nil && phase.State == "closing" {
			return 10
		}
		next := timeValue(g["nextAt"])
		if next.IsZero() {
			return 60
		}
		secs := int(next.Add(-clockOffset(g)).Sub(wall).Seconds()) + 5
		return min(max(secs, 15), 300)
	}
	return 0
}

// lastKm là km của lần chốt 22h gần nhất, theo mét: snapshot của vòng đang tới
// nếu đã ghi, không thì của vòng trước.
func (s *GameStore) lastKm(ctx context.Context, game *firestore.DocumentRef, g map[string]any, players []gamePlayerInfo) (map[string]float64, error) {
	out := map[string]float64{}
	if stringValue(g["status"]) != gameRunning && stringValue(g["status"]) != gameEnded {
		return out, nil
	}
	round := int(number(g["round"]))
	if werewolf.Phase(stringValue(g["phase"])) == werewolf.PhaseSetup {
		round = 0
	}
	var refs []*firestore.DocumentRef
	for _, p := range players {
		refs = append(refs, roundRef(game, round).Collection("km").Doc(p.uid))
		if round > 0 {
			refs = append(refs, roundRef(game, round-1).Collection("km").Doc(p.uid))
		}
	}
	if len(refs) == 0 {
		return out, nil
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		if _, done := out[d.Ref.ID]; d.Exists() && !done {
			out[d.Ref.ID] = number(d.Data()["meters"])
		}
	}
	return out, nil
}

// Feed trả trang feed cũ hơn cursor.
func (s *GameStore) Feed(ctx context.Context, gameID, cursor string, v GameViewer) (GameFeed, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return GameFeed{}, err
	}
	g, _, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return GameFeed{}, err
	}
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return GameFeed{}, err
	}
	return s.loadFeed(ctx, g.Ref, cursor, playerIndex(players))
}

// ---- /me ----

type GameMe struct {
	Status      string           `json:"status"`
	Role        string           `json:"role,omitempty"`
	RoleLabel   string           `json:"roleLabel,omitempty"`
	RoleRules   string           `json:"roleRules,omitempty"`
	CardURL     string           `json:"cardUrl,omitempty"`
	CardBackURL string           `json:"cardBackUrl,omitempty"`
	Alive       bool             `json:"alive"`
	Potions     *GamePotions     `json:"potions,omitempty"`
	Notes       []GameNote       `json:"notes"`
	InviteLinks []GameInvite     `json:"inviteLinks"`
	Chats       []GameChatLink   `json:"chats"`
	Actions     []GameAction     `json:"actions"`
	AllRoles    []GameRoleReveal `json:"allRoles,omitempty"`
	TeamKm      *GameTeamKm      `json:"teamKm,omitempty"` // chỉ sói còn sống
	// CardTier là bậc thẻ người gọi bốc được, có từ lúc chia bài. CardOwned true
	// khi ván đã kết thúc và người gọi thuộc phe thắng: thẻ đã nằm trong
	// users/{uid}/gameCards. CardRounds là số vòng đã chơi, chỉ có khi ván đã
	// kết thúc (lúc đó ván không còn gửi phase): đúng số in trên thẻ.
	CardTier   string `json:"cardTier,omitempty"`
	CardOwned  bool   `json:"cardOwned"`
	CardRounds int    `json:"cardRounds,omitempty"`
}

type GamePotions struct {
	Save   bool `json:"save"`
	Poison bool `json:"poison"`
}

type GameNote struct {
	Round int    `json:"round"`
	Text  string `json:"text"`
}

type GameInvite struct {
	Label string `json:"label"`
	URL   string `json:"url"`
}

// GameChatLink là một chat phe người gọi vào được (game_chat.go).
type GameChatLink struct {
	Key     string `json:"key"`
	Label   string `json:"label"`
	CanSend bool   `json:"canSend"`
}

type GameAction struct {
	Kind           string        `json:"kind"`
	Label          string        `json:"label"`
	Help           string        `json:"help"`
	Input          string        `json:"input"`
	Options        []GameOption  `json:"options"`
	Selected       *GameSelected `json:"selected"`
	OpensAt        *time.Time    `json:"opensAt"`
	ClosesAt       *time.Time    `json:"closesAt"`
	Enabled        bool          `json:"enabled"`
	DisabledReason string        `json:"disabledReason,omitempty"`
	ConfirmText    string        `json:"confirmText,omitempty"`
}

type GameOption struct {
	ID        string `json:"id"`
	Label     string `json:"label"`
	AvatarURL string `json:"avatarUrl,omitempty"`
}

type GameSelected struct {
	Targets []string `json:"targets,omitempty"`
	Choice  string   `json:"choice,omitempty"`
}

type GameRoleReveal struct {
	UID       string `json:"uid"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	RoleLabel string `json:"roleLabel"`
	CardURL   string `json:"cardUrl,omitempty"`
}

// Me là phần riêng của người chơi: vai, việc đang mở, ghi chú chỉ người đó được
// biết. Người ngoài ván (hoặc bị loại lúc Start) nhận 404.
func (s *GameStore) Me(ctx context.Context, gameID string, v GameViewer, wall time.Time) (GameMe, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return GameMe{}, err
	}
	g, registered, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return GameMe{}, err
	}
	if !registered {
		return GameMe{}, errNotGamePlayer
	}
	data := g.Data()
	out := GameMe{Status: apiStatus(data), Alive: true, Notes: []GameNote{}, InviteLinks: []GameInvite{}, Chats: []GameChatLink{}, Actions: []GameAction{}}
	st, err := s.loadState(ctx, g.Ref)
	if err != nil {
		return out, err
	}
	if st == nil {
		return out, nil // chưa chia bài
	}
	me := st.Players[v.UID]
	if me == nil {
		return GameMe{}, errNotGamePlayer
	}
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return out, err
	}
	index := playerIndex(players)
	name := func(uid string) string {
		if p, ok := index[uid]; ok {
			return p.name
		}
		return "Người chơi"
	}
	out.Role, out.RoleLabel, out.Alive = string(me.Role), roleLabels[me.Role], me.Alive
	out.RoleRules = strings.ReplaceAll(roleRules[me.Role], "X km", formatKm(kmPerUnit(st.Config))+" km")
	out.CardURL, out.CardBackURL = cfg.cards[string(me.Role)], cfg.cards["back"]
	out.CardTier = string(gameCardTier(st.Seed, v.UID))
	if me.Role == werewolf.Witch {
		out.Potions = &GamePotions{Save: st.SavePotion, Poison: st.PoisonPotion}
	}
	if out.Notes, err = s.notes(ctx, g.Ref, st, v.UID, name); err != nil {
		return out, err
	}
	for _, key := range []string{chatWolves, chatLovers} {
		if member, canSend := chatAccess(st, data, key, v.UID); member {
			out.Chats = append(out.Chats, GameChatLink{Key: key, Label: chatLabels[key], CanSend: canSend})
		}
	}
	if st.Phase == werewolf.PhaseEnded {
		out.CardOwned = slices.Contains(st.Winners(), v.UID)
		out.CardRounds = st.Round
		for _, uid := range sortedPlayers(st) {
			r := st.Players[uid].Role
			out.AllRoles = append(out.AllRoles, GameRoleReveal{UID: uid, Name: name(uid), Role: string(r), RoleLabel: roleLabels[r], CardURL: cfg.cards[string(r)]})
		}
		return out, nil
	}
	mine, raw, err := s.loadMine(ctx, g.Ref, st.Round, v.UID)
	if err != nil {
		return out, err
	}
	out.Actions = meActions(st, v.UID, mine, raw, players, gameNow(data, wall), clockOffset(data))
	if me.Role == werewolf.Wolf && me.Alive {
		if out.TeamKm, err = s.wolfTeamKm(ctx, g.Ref, data, st, wall); err != nil {
			return out, err
		}
	}
	return out, nil
}

func kmPerUnit(c werewolf.Config) float64 {
	if c.KmPerUnit == 0 {
		return 1
	}
	return c.KmPerUnit
}

func formatKm(km float64) string {
	return strings.TrimSuffix(strings.TrimSuffix(strconv.FormatFloat(km, 'f', 1, 64), "0"), ".")
}

// notes là những gì vai của uid được biết: đồng đội sói, người yêu kèm vai,
// người bị cắn (phù thuỷ, lúc rạng sáng), kết quả soi. Kết quả soi đã trả thì
// giữ kể cả khi lượt soi bị huỷ sau đó (R19).
func (s *GameStore) notes(ctx context.Context, game *firestore.DocumentRef, st *werewolf.State, uid string, name func(string) string) ([]GameNote, error) {
	notes := []GameNote{}
	me := st.Players[uid]
	if me.Role == werewolf.Wolf {
		var mates []string
		for _, other := range sortedPlayers(st) {
			if other != uid && st.Players[other].Role == werewolf.Wolf {
				mates = append(mates, name(other))
			}
		}
		text := "Bạn là con sói duy nhất."
		if len(mates) > 0 {
			text = "Đồng đội Sói: " + strings.Join(mates, ", ") + "."
		}
		notes = append(notes, GameNote{Round: 1, Text: text})
	}
	if partner := loverOf(st, uid); partner != "" {
		notes = append(notes, GameNote{Round: 1, Text: fmt.Sprintf("Người yêu của bạn: %s (%s).", name(partner), roleLabels[st.Players[partner].Role])})
	}
	if me.Role == werewolf.Witch && me.Alive && st.Phase == werewolf.PhaseDawn {
		text := "Đêm nay không ai bị cắn."
		if st.Bitten != "" {
			text = "Đêm nay sói cắn " + name(st.Bitten) + "."
		}
		notes = append(notes, GameNote{Round: st.Round, Text: text})
	}
	if me.Role == werewolf.Seer {
		var refs []*firestore.DocumentRef
		for r := 1; r <= st.Round; r++ {
			refs = append(refs, actionRef(game, r, uid, werewolf.KindSeerPeek))
		}
		docs, err := s.db.GetAll(ctx, refs)
		if err != nil {
			return nil, err
		}
		for i, d := range docs {
			if !d.Exists() {
				continue
			}
			peek := werewolf.Team(stringValue(d.Data()["peek"]))
			targets := anyList(d.Data()["targets"])
			if peek == "" || len(targets) == 0 {
				continue
			}
			side := "Dân"
			if peek == werewolf.TeamWolves {
				side = "Sói"
			}
			notes = append(notes, GameNote{Round: i + 1, Text: fmt.Sprintf("Đêm %d: %s là %s.", i+1, name(stringValue(targets[0])), side)})
		}
	}
	return notes, nil
}

// selfInvalid: các kind không chọn chính mình được (Validate từ chối).
var selfInvalid = map[werewolf.Kind]bool{
	werewolf.KindSeerPeek: true, werewolf.KindWitchPoison: true, werewolf.KindHunterShoot: true, werewolf.KindNominate: true,
}

// meActions dựng actions[] cho widget chung của app. Lý do khoá lấy từ
// Precheck; mục tiêu cụ thể thì lúc bấm Validate mới kiểm, options chỉ bỏ những
// người chắc chắn bị từ chối.
func meActions(st *werewolf.State, uid string, mine []werewolf.Action, raw map[werewolf.Kind]map[string]any, players []gamePlayerInfo, now time.Time, offset time.Duration) []GameAction {
	out := []GameAction{}
	for _, kind := range st.Available(uid) {
		text := actionTexts[kind]
		a := GameAction{Kind: string(kind), Label: text.label, Help: text.help, Input: text.input, ConfirmText: text.confirm, Options: []GameOption{}}
		if nominee := st.NomineeOf(kind); nominee != "" {
			// Mỗi người lên giàn một thẻ biểu quyết, gọi theo tên để không nhầm phiên.
			name := playerName(playerIndex(players), nominee)
			a.Label, a.Help = "Biểu quyết: "+name, "Treo hay tha "+name+". Đổi được tới 22h."
		}
		switch text.input {
		case "choice":
			a.Options = append(a.Options, GameOption{ID: werewolf.ChoiceHang, Label: choiceLabels[werewolf.ChoiceHang]}, GameOption{ID: werewolf.ChoiceSpare, Label: choiceLabels[werewolf.ChoiceSpare]})
		case "single_target", "two_targets":
			for _, p := range players {
				if pl := st.Players[p.uid]; pl == nil || !pl.Alive {
					continue
				}
				if p.uid == uid && selfInvalid[kind] {
					continue
				}
				if kind == werewolf.KindWolfBite && p.uid == loverOf(st, uid) {
					continue
				}
				if kind == werewolf.KindGuard && p.uid == st.LastGuarded {
					continue
				}
				a.Options = append(a.Options, GameOption{ID: p.uid, Label: p.name, AvatarURL: p.avatar})
			}
		}
		if d, ok := raw[kind]; ok {
			sel := &GameSelected{Choice: stringValue(d["choice"])}
			for _, t := range anyList(d["targets"]) {
				sel.Targets = append(sel.Targets, stringValue(t))
			}
			a.Selected = sel
		}
		opens, closes := st.Window(kind)
		if !opens.IsZero() {
			t := opens.Add(-offset)
			a.OpensAt = &t
		}
		if !closes.IsZero() {
			t := closes.Add(-offset)
			a.ClosesAt = &t
		}
		if err := werewolf.Precheck(st, kind, uid, mine, now); err != nil {
			a.DisabledReason = disabledReason(st, kind, err)
		} else {
			a.Enabled = true
		}
		out = append(out, a)
	}
	return out
}

// ---- Tạo ván, đăng ký ----

type CreateGameRequest struct {
	Roles                map[string]bool `json:"roles"`
	RegistrationDeadline *time.Time      `json:"registrationDeadline"`
	TestMode             bool            `json:"testMode"`
	ChatID               string          `json:"chatId"`
	ThreadID             int64           `json:"threadId"`
	KmPerUnit            float64         `json:"kmPerUnit"`
}

// Create mở ván mới, chỉ admin. Ván thật chạy trong PSC; ván thử phải chỉ ra
// group test, CreateGame kiểm group đó không phải PSC.
func (s *GameStore) Create(ctx context.Context, req CreateGameRequest, v GameViewer, wall time.Time) (string, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return "", err
	}
	if !cfg.isAdmin(v.UID) {
		return "", errNotAdmin
	}
	gc := werewolf.Config{KmPerUnit: req.KmPerUnit, TestMode: req.TestMode}
	for key, on := range req.Roles {
		if !werewolf.ValidRole(werewolf.Role(key)) {
			return "", errInvalidRole
		}
		if !on {
			gc.Disabled = append(gc.Disabled, werewolf.Role(key))
		}
	}
	sort.Slice(gc.Disabled, func(i, j int) bool { return gc.Disabled[i] < gc.Disabled[j] })
	if err := gc.Validate(); err != nil {
		return "", &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_config", Message: "Cấu hình ván không hợp lệ: " + err.Error()}
	}
	in := NewGameInput{CreatedBy: v.UID, ChatID: s.pscChatID, ThreadID: req.ThreadID, Config: gc}
	if req.TestMode {
		if strings.TrimSpace(req.ChatID) == "" {
			return "", errTestModeNeedsChat
		}
		in.ChatID = strings.TrimSpace(req.ChatID)
	}
	if req.RegistrationDeadline != nil {
		if !req.RegistrationDeadline.After(wall) {
			return "", errInvalidDeadline
		}
		in.RegistrationDeadline = *req.RegistrationDeadline
	}
	return s.CreateGame(ctx, in, wall)
}

type RegistrationResult struct {
	IsRegistered bool `json:"isRegistered"`
	PlayerCount  int  `json:"playerCount"`
}

// Register thêm người gọi vào ván đang đăng ký. Ván thử của người khác thì
// readVisibleGame đã trả 404. Gọi lại khi đã đăng ký thì trả kết quả cũ. Transaction đọc và ghi games/{id}, nên hai người đăng ký cùng lúc
// không vượt được giới hạn số người (werewolf.MaxPlayers).
func (s *GameStore) Register(ctx context.Context, gameID string, v GameViewer, wall time.Time) (RegistrationResult, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return RegistrationResult{}, err
	}
	if _, _, err := s.readVisibleGame(ctx, gameID, cfg, v.UID); err != nil {
		return RegistrationResult{}, err
	}
	game := s.gameRef(gameID)
	var res RegistrationResult
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if err := registrationOpen(g.Data(), wall); err != nil {
			return err
		}
		players, err := tx.Documents(game.Collection("players")).GetAll()
		if err != nil {
			return err
		}
		res = RegistrationResult{IsRegistered: true, PlayerCount: len(players)}
		for _, p := range players {
			if p.Ref.ID == v.UID {
				return nil
			}
		}
		link, err := s.readLink(txGetter(tx), v.UID)
		if err != nil {
			return err
		}
		if reqs := requirementsFor(link, v.AppVersion, cfg); !requirementsMet(reqs) {
			return &HTTPError{Status: http.StatusUnprocessableEntity, Code: "requirements_unmet", Message: "Bạn chưa đủ điều kiện đăng ký.", Extra: map[string]any{"requirements": reqs}}
		}
		if len(players) >= werewolf.MaxPlayers {
			return errGameFull
		}
		prof, err := getOptional(tx, s.db.Collection("publicProfiles").Doc(v.UID))
		if err != nil {
			return err
		}
		name := link.displayName
		if prof.Exists() && stringValue(prof.Data()["displayName"]) != "" {
			name = stringValue(prof.Data()["displayName"])
		}
		if err := tx.Create(game.Collection("players").Doc(v.UID), map[string]any{
			"uid": v.UID, "tgUserId": link.tgUserID, "name": name, "registeredAt": wall,
		}); err != nil {
			return err
		}
		res.PlayerCount++
		return tx.Update(game, []firestore.Update{{Path: "playerCount", Value: res.PlayerCount}, {Path: "updatedAt", Value: wall}})
	})
	return res, err
}

// Unregister rút người gọi khỏi ván đang đăng ký. Chưa đăng ký thì coi như xong.
func (s *GameStore) Unregister(ctx context.Context, gameID string, v GameViewer, wall time.Time) (RegistrationResult, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return RegistrationResult{}, err
	}
	if _, _, err := s.readVisibleGame(ctx, gameID, cfg, v.UID); err != nil {
		return RegistrationResult{}, err
	}
	game := s.gameRef(gameID)
	var res RegistrationResult
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRegistering {
			return errRegistrationShut
		}
		players, err := tx.Documents(game.Collection("players")).GetAll()
		if err != nil {
			return err
		}
		res = RegistrationResult{PlayerCount: len(players)}
		var mine *firestore.DocumentSnapshot
		for _, p := range players {
			if p.Ref.ID == v.UID && p.Data()["fake"] != true {
				mine = p
			}
		}
		if mine == nil {
			return nil
		}
		if err := tx.Delete(mine.Ref); err != nil {
			return err
		}
		res.PlayerCount--
		return tx.Update(game, []firestore.Update{{Path: "playerCount", Value: res.PlayerCount}, {Path: "updatedAt", Value: wall}})
	})
	return res, err
}

// registrationOpen: ván đang đăng ký và chưa quá hạn đăng ký.
func registrationOpen(g map[string]any, wall time.Time) error {
	if stringValue(g["status"]) != gameRegistering {
		return errRegistrationShut
	}
	if t := timeValue(g["registrationDeadline"]); !t.IsZero() && !wall.Before(t) {
		return errRegistrationShut
	}
	return nil
}

// RequireAdmin trả 403 not_admin nếu uid không nằm trong adminUids.
func (s *GameStore) RequireAdmin(ctx context.Context, uid string) error {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return err
	}
	if !cfg.isAdmin(uid) {
		return errNotAdmin
	}
	return nil
}
