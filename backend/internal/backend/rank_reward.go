package backend

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Quà BXH: admin treo quà thật (áo, tất, voucher…) cho một bảng của một kỳ ở
// rankRewards/{boardId}, đúng khoá của bảng sẽ chốt. Lúc chốt kỳ writeBoard đọc
// doc này và gắn quà vào thẻ của người thắng trong cùng batch, nên quà trên thẻ
// luôn khớp hạng đã chốt. Quà trao ngoài app: app chỉ ghi ai trúng, người trao
// đã trao chưa, người trúng đã nhận chưa.
//
// Sửa quà theo kỳ: kỳ chưa bắt đầu thì sửa tự do; kỳ đang chạy thì chỉ thêm,
// món đã treo giữ nguyên hạng và tên, vì người ta đang chạy vì món đó; hết kỳ
// thì khoá, để quà lúc chốt đúng là quà người ta thấy lúc chạy.
const (
	rankRewardMaxItems     = 10
	rankRewardNameMaxRunes = 40
	rankRewardMaxPhotos    = 5
	rankRewardPushPath     = "/tasks/rank-reward-push"
	rankRewardPushKind     = "rank_reward"

	rankRewardUpcoming = "upcoming"
	rankRewardRunning  = "running"
	rankRewardClosed   = "closed"
)

// rankRewardIcons là bộ icon app vẽ sẵn; app gặp key lạ thì vẽ icon "other".
var rankRewardIcons = []string{"shirt", "socks", "cap", "shoes", "bottle", "medal", "voucher", "watch", "bag", "other"}

// rewardPhotoName là tên file app đặt khi tải ảnh quà lên Storage (quà BXH
// và quà kèo), khớp storage.rules.
var rewardPhotoName = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}\.jpg$`)

var (
	errRankBoardUnknown   = &HTTPError{Status: http.StatusNotFound, Code: "unknown_board", Message: "Không có bảng xếp hạng này."}
	errRankRewardLocked   = &HTTPError{Status: http.StatusConflict, Code: "reward_locked", Message: "Kỳ này đã hết, không sửa quà được nữa."}
	errRankRewardShrink   = &HTTPError{Status: http.StatusConflict, Code: "reward_shrink", Message: "Kỳ đang chạy: chỉ thêm quà, không bớt hay đổi hạng, tên của quà đã treo."}
	errRankRewardGiver    = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_giver", Message: "Người trao phải là admin."}
	errRankRewardInvalid  = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_reward", Message: "Quà không hợp lệ."}
	errRankRewardNoWinner = &HTTPError{Status: http.StatusNotFound, Code: "no_reward", Message: "Thẻ này không có quà."}
	errRankRewardReceived = &HTTPError{Status: http.StatusConflict, Code: "reward_received", Message: "Quà đã tính là nhận rồi, không bỏ đánh dấu trao được."}
)

// rankBoardKey là bảng mà một boardId trỏ tới.
type rankBoardKey struct {
	id     string
	r      rankRange
	sport  rankSport
	period Period
}

// parseRankBoardID nhận "week_2026-11-17_run": ngày phải là ngày đầu kỳ theo
// lịch VN, như rankBoardID viết ra.
func parseRankBoardID(id string) (rankBoardKey, bool) {
	parts := strings.Split(id, "_")
	if len(parts) != 3 {
		return rankBoardKey{}, false
	}
	r, sport := rankRange(parts[0]), rankSport(parts[2])
	if (r != rankWeek && r != rankMonth) || !slices.Contains(rankSports, sport) {
		return rankBoardKey{}, false
	}
	day, err := time.ParseInLocation("2006-01-02", parts[1], vietnam)
	if err != nil {
		return rankBoardKey{}, false
	}
	periods := PeriodsAt(day)
	period := periods.Week
	if r == rankMonth {
		period = periods.Month
	}
	if !period.Start.Equal(day) {
		return rankBoardKey{}, false
	}
	return rankBoardKey{id: id, r: r, sport: sport, period: period}, true
}

func (k rankBoardKey) state(now time.Time) string {
	switch {
	case now.Before(k.period.Start):
		return rankRewardUpcoming
	case now.Before(k.period.End):
		return rankRewardRunning
	default:
		return rankRewardClosed
	}
}

// RankRewardItem là một món quà cho các hạng FromRank..ToRank. Chung hạng thì
// ai cũng nhận.
type RankRewardItem struct {
	ID       string   `json:"id"`
	FromRank int      `json:"fromRank"`
	ToRank   int      `json:"toRank"`
	Name     string   `json:"name"`
	Icon     string   `json:"icon"`
	Photos   []string `json:"photos"`
}

type RankRewardInput struct {
	GiverUID string           `json:"giverUid"`
	Items    []RankRewardItem `json:"items"`
}

type RankRewardWinner struct {
	UID         string     `json:"uid"`
	DisplayName string     `json:"displayName"`
	Rank        int        `json:"rank"`
	ItemID      string     `json:"itemId"`
	Name        string     `json:"name"`
	GivenAt     *time.Time `json:"givenAt"`
	ReceivedAt  *time.Time `json:"receivedAt"`
}

// RankRewardView là quà của một bảng như trang admin thấy. Winners chỉ có khi
// bảng đã chốt.
type RankRewardView struct {
	BoardID   string             `json:"boardId"`
	State     string             `json:"state"`
	GiverUID  string             `json:"giverUid"`
	GiverName string             `json:"giverName"`
	Items     []RankRewardItem   `json:"items"`
	Winners   []RankRewardWinner `json:"winners"`
}

// rankRewards là doc rankRewards/{boardId} đã đọc.
type rankRewards struct {
	giverUID, giverName string
	items               []RankRewardItem
}

// itemFor là món của hạng rank, nil khi hạng đó không có quà.
func (r *rankRewards) itemFor(rank int) *RankRewardItem {
	if r == nil {
		return nil
	}
	for i := range r.items {
		if r.items[i].FromRank <= rank && rank <= r.items[i].ToRank {
			return &r.items[i]
		}
	}
	return nil
}

func rankRewardsFrom(data map[string]any) *rankRewards {
	if data == nil {
		return nil
	}
	out := &rankRewards{giverUID: stringValue(data["giverUid"]), giverName: stringValue(data["giverName"])}
	for _, raw := range anyList(data["items"]) {
		m, _ := raw.(map[string]any)
		item := RankRewardItem{ID: stringValue(m["id"]), FromRank: int(number(m["fromRank"])), ToRank: int(number(m["toRank"])), Name: stringValue(m["name"]), Icon: stringValue(m["icon"]), Photos: []string{}}
		for _, p := range anyList(m["photos"]) {
			item.Photos = append(item.Photos, stringValue(p))
		}
		out.items = append(out.items, item)
	}
	return out
}

func rankRewardItemsData(items []RankRewardItem) []any {
	out := make([]any, 0, len(items))
	for _, it := range items {
		out = append(out, map[string]any{"id": it.ID, "fromRank": it.FromRank, "toRank": it.ToRank, "name": it.Name, "icon": it.Icon, "photos": it.Photos})
	}
	return out
}

// cardReward là phần quà ghi vào thẻ của người trúng.
func (r *rankRewards) cardReward(it *RankRewardItem) map[string]any {
	return map[string]any{
		"itemId": it.ID, "name": it.Name, "icon": it.Icon, "photos": it.Photos,
		"giverUid": r.giverUID, "giverName": r.giverName,
		"givenAt": nil, "receivedAt": nil,
	}
}

// rankRewardAutoReceived: trao quá 14 ngày mà người trúng chưa bấm thì coi như
// đã nhận (app tính giống vậy ở rankRewardAutoReceived).
const rankRewardAutoReceived = 14 * 24 * time.Hour

// rewardReceived: người trúng đã báo nhận, hoặc đã trao đủ lâu để coi như nhận.
func rewardReceived(reward map[string]any, now time.Time) bool {
	if reward["receivedAt"] != nil {
		return true
	}
	given := timePtr(reward["givenAt"])
	return given != nil && now.Sub(*given) >= rankRewardAutoReceived
}

// adminIn: uid nằm trong adminUids của gameState/config đã đọc.
func adminIn(cfg *firestore.DocumentSnapshot, uid string) bool {
	return cfg.Exists() && slices.ContainsFunc(anyList(cfg.Data()["adminUids"]), func(v any) bool { return stringValue(v) == uid })
}

func loadRankRewards(ctx context.Context, db *firestore.Client, boardID string) (*rankRewards, error) {
	data, err := getData(ctx, db.Collection("rankRewards").Doc(boardID))
	if err != nil {
		return nil, err
	}
	return rankRewardsFrom(data), nil
}

type RankRewardService struct {
	db    *firestore.Client
	links *TelegramLinkService
}

func NewRankRewardService(db *firestore.Client, links *TelegramLinkService) *RankRewardService {
	return &RankRewardService{db: db, links: links}
}

// normalizeRankRewardItems kiểm và chuẩn hoá danh sách quà gửi lên: tên bỏ khoảng trắng hai
// đầu, món mới được cấp id, hạng không chồng nhau, sắp theo hạng.
func normalizeRankRewardItems(boardID string, items []RankRewardItem) ([]RankRewardItem, error) {
	if len(items) > rankRewardMaxItems {
		return nil, errRankRewardInvalid
	}
	out := make([]RankRewardItem, 0, len(items))
	ids := map[string]bool{}
	for _, it := range items {
		var ok bool
		if it.ID, it.Name, it.Photos, ok = normalizeRewardItem(it.ID, it.Name, it.Icon, it.Photos, "rankRewards/"+boardID+"/", ids); !ok {
			return nil, errRankRewardInvalid
		}
		if it.FromRank < 1 || it.FromRank > it.ToRank || it.ToRank > rankTopN {
			return nil, errRankRewardInvalid
		}
		out = append(out, it)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].FromRank < out[j].FromRank })
	for i := 1; i < len(out); i++ {
		if out[i].FromRank <= out[i-1].ToRank {
			return nil, errRankRewardInvalid
		}
	}
	return out, nil
}

// normalizeRewardItem kiểm phần chung của một món quà (BXH hay kèo): tên bỏ
// khoảng trắng hai đầu, dài 1..rankRewardNameMaxRunes, không ký tự điều khiển;
// icon trong bộ có sẵn; tối đa rankRewardMaxPhotos ảnh không trùng, nằm dưới
// photoPrefix. Món mới được cấp id; id trùng trong ids thì không hợp lệ.
func normalizeRewardItem(id, name, icon string, photos []string, photoPrefix string, ids map[string]bool) (string, string, []string, bool) {
	name = strings.TrimSpace(name)
	n := utf8.RuneCountInString(name)
	if n == 0 || n > rankRewardNameMaxRunes || strings.IndexFunc(name, unicode.IsControl) >= 0 {
		return "", "", nil, false
	}
	if !slices.Contains(rankRewardIcons, icon) || len(photos) > rankRewardMaxPhotos {
		return "", "", nil, false
	}
	if photos == nil {
		photos = []string{}
	}
	seen := map[string]bool{}
	for _, p := range photos {
		file, ok := strings.CutPrefix(p, photoPrefix)
		if !ok || !rewardPhotoName.MatchString(file) || seen[p] {
			return "", "", nil, false
		}
		seen[p] = true
	}
	if id == "" {
		id = newRankRewardID()
	}
	if ids[id] {
		return "", "", nil, false
	}
	ids[id] = true
	return id, name, photos, true
}

func newRankRewardID() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b) // crypto/rand.Read không trả lỗi từ Go 1.24
	return hex.EncodeToString(b)
}

// keepsOld: mọi món cũ còn đủ, cùng hạng và tên. Món cũ chỉ được đổi icon,
// ảnh; id gửi lên mà không có trong món cũ thì không hợp lệ.
func keepsOld(old *rankRewards, items []RankRewardItem) bool {
	if old == nil {
		return true
	}
	for _, o := range old.items {
		i := slices.IndexFunc(items, func(it RankRewardItem) bool { return it.ID == o.ID })
		if i < 0 || items[i].FromRank != o.FromRank || items[i].ToRank != o.ToRank || items[i].Name != o.Name {
			return false
		}
	}
	return true
}

func knownIDs(old *rankRewards, sent []RankRewardItem) bool {
	for _, it := range sent {
		if it.ID == "" {
			continue
		}
		if old == nil || !slices.ContainsFunc(old.items, func(o RankRewardItem) bool { return o.ID == it.ID }) {
			return false
		}
	}
	return true
}

// Set ghi quà của một bảng. Đọc và ghi trong một transaction, nên hai admin
// sửa cùng lúc thì luật "kỳ đang chạy chỉ thêm" vẫn đúng với bản ghi sau.
func (s *RankRewardService) Set(ctx context.Context, by, boardID string, in RankRewardInput, now time.Time) error {
	key, ok := parseRankBoardID(boardID)
	if !ok {
		return errRankBoardUnknown
	}
	state := key.state(now)
	if state == rankRewardClosed {
		return errRankRewardLocked
	}
	items, err := normalizeRankRewardItems(boardID, in.Items)
	if err != nil {
		return err
	}
	giverName := ""
	if len(items) > 0 {
		if giverName, err = s.giver(ctx, in.GiverUID); err != nil {
			return err
		}
	}
	ref := s.db.Collection("rankRewards").Doc(boardID)
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		cfg, err := getOptional(tx, s.db.Collection("gameState").Doc("config"))
		if err != nil {
			return err
		}
		if !adminIn(cfg, by) {
			return errNotAdmin
		}
		if len(items) > 0 && !adminIn(cfg, in.GiverUID) {
			return errRankRewardGiver
		}
		snap, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		var old *rankRewards
		if snap.Exists() {
			old = rankRewardsFrom(snap.Data())
		}
		if !knownIDs(old, in.Items) {
			return errRankRewardInvalid
		}
		if state == rankRewardRunning && !keepsOld(old, items) {
			return errRankRewardShrink
		}
		if len(items) == 0 {
			return tx.Delete(ref)
		}
		return tx.Set(ref, map[string]any{
			"range": string(key.r), "sport": string(key.sport),
			"periodStart": dateKey(key.period.Start), "periodEnd": dateKey(key.period.End),
			"giverUid": in.GiverUID, "giverName": giverName,
			"items": rankRewardItemsData(items), "updatedAt": now, "updatedBy": by,
		})
	})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "rank_reward.set", "by", by, "board", boardID, "state", state, "items", len(items))
	return nil
}

// giver là tên người trao, chép vào quà để hiện ngay trên thẻ.
func (s *RankRewardService) giver(ctx context.Context, uid string) (string, error) {
	name, ok, err := profileGiver(ctx, s.db, uid)
	if err == nil && !ok {
		err = errRankRewardGiver
	}
	return name, err
}

// profileGiver là tên của uid để chép vào quà. ok=false khi uid rỗng hay không
// có hồ sơ công khai. Telegram thì không chép: doc quà ai đăng nhập cũng đọc
// được, nên người trúng hỏi qua giverTelegram lúc cần.
func profileGiver(ctx context.Context, db *firestore.Client, uid string) (name string, ok bool, err error) {
	if uid == "" {
		return "", false, nil
	}
	prof, err := getData(ctx, db.Collection("publicProfiles").Doc(uid))
	if err != nil || prof == nil {
		return "", false, err
	}
	return preferredName(prof), true, nil
}

// giverTelegram là username Telegram hiện tại của người trao, rỗng khi chưa
// liên kết. Dùng chung cho quà BXH và quà kèo.
func giverTelegram(ctx context.Context, links *TelegramLinkService, uid string) (string, error) {
	if links == nil || uid == "" {
		return "", nil
	}
	link, err := links.Link(ctx, uid)
	if err != nil {
		return "", err
	}
	return link.TgUsername, nil
}

// Contact là Telegram người trao quà trên thẻ hạng của uid; chỉ người trúng
// có thẻ đó, người khác nhận no_reward.
func (s *RankRewardService) Contact(ctx context.Context, uid, boardID string) (string, error) {
	if _, ok := parseRankBoardID(boardID); !ok {
		return "", errRankBoardUnknown
	}
	card, err := getData(ctx, s.db.Collection("users").Doc(uid).Collection("rankCards").Doc(boardID))
	if err != nil {
		return "", err
	}
	reward, _ := card["reward"].(map[string]any)
	if reward == nil {
		return "", errRankRewardNoWinner
	}
	return giverTelegram(ctx, s.links, stringValue(reward["giverUid"]))
}

// View trả quà của một bảng cho trang admin; bảng đã chốt thì kèm người trúng.
func (s *RankRewardService) View(ctx context.Context, boardID string, now time.Time) (RankRewardView, error) {
	key, ok := parseRankBoardID(boardID)
	if !ok {
		return RankRewardView{}, errRankBoardUnknown
	}
	out := RankRewardView{BoardID: boardID, State: key.state(now), Items: []RankRewardItem{}, Winners: []RankRewardWinner{}}
	rewards, err := loadRankRewards(ctx, s.db, boardID)
	if err != nil {
		return out, err
	}
	if rewards != nil {
		out.GiverUID, out.GiverName, out.Items = rewards.giverUID, rewards.giverName, rewards.items
	}
	board, err := getData(ctx, s.db.Collection("rankBoards").Doc(boardID))
	if err != nil || board == nil {
		return out, err
	}
	for _, raw := range anyList(board["entries"]) {
		e, _ := raw.(map[string]any)
		if e["reward"] == nil {
			continue
		}
		uid := stringValue(e["uid"])
		card, err := getData(ctx, s.db.Collection("users").Doc(uid).Collection("rankCards").Doc(boardID))
		if err != nil {
			return out, err
		}
		reward, _ := card["reward"].(map[string]any)
		if reward == nil {
			continue
		}
		out.Winners = append(out.Winners, RankRewardWinner{
			UID: uid, DisplayName: stringValue(e["displayName"]), Rank: int(number(e["rank"])),
			ItemID: stringValue(reward["itemId"]), Name: stringValue(reward["name"]),
			GivenAt: timePtr(reward["givenAt"]), ReceivedAt: timePtr(reward["receivedAt"]),
		})
	}
	return out, nil
}

func timePtr(v any) *time.Time {
	if t, ok := v.(time.Time); ok {
		return &t
	}
	return nil
}

// SetGiven: admin đánh dấu đã trao (given=true) hoặc bỏ đánh dấu. Bỏ được khi
// quà chưa tính là nhận (rewardReceived). Gọi lại bao nhiêu lần cũng vậy.
// marked báo lần gọi này vừa ghi givenAt, để chỗ gọi báo người trúng một lần.
func (s *RankRewardService) SetGiven(ctx context.Context, by, boardID, uid string, given bool, now time.Time) (marked bool, err error) {
	ref := s.db.Collection("users").Doc(uid).Collection("rankCards").Doc(boardID)
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		marked = false
		cfg, err := getOptional(tx, s.db.Collection("gameState").Doc("config"))
		if err != nil {
			return err
		}
		if !adminIn(cfg, by) {
			return errNotAdmin
		}
		reward, err := cardRewardIn(tx, ref)
		if err != nil {
			return err
		}
		if !given {
			if rewardReceived(reward, now) {
				return errRankRewardReceived
			}
			return tx.Update(ref, []firestore.Update{{Path: "reward.givenAt", Value: nil}})
		}
		if reward["givenAt"] != nil {
			return nil
		}
		marked = true
		return tx.Update(ref, []firestore.Update{{Path: "reward.givenAt", Value: now}})
	})
	if err != nil {
		return false, err
	}
	slog.InfoContext(ctx, "rank_reward.given", "by", by, "board", boardID, "uid", uid, "given", given)
	return marked, nil
}

// MarkReceived: người trúng báo đã nhận quà. Chưa ai bấm đã trao thì ghi luôn
// givenAt, vì quà đã tới tay thì chắc chắn đã trao.
func (s *RankRewardService) MarkReceived(ctx context.Context, uid, boardID string, now time.Time) error {
	ref := s.db.Collection("users").Doc(uid).Collection("rankCards").Doc(boardID)
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		reward, err := cardRewardIn(tx, ref)
		if err != nil {
			return err
		}
		if reward["receivedAt"] != nil {
			return nil
		}
		updates := []firestore.Update{{Path: "reward.receivedAt", Value: now}}
		if reward["givenAt"] == nil {
			updates = append(updates, firestore.Update{Path: "reward.givenAt", Value: now})
		}
		return tx.Update(ref, updates)
	})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "rank_reward.received", "board", boardID, "uid", uid)
	return nil
}

func cardRewardIn(tx *firestore.Transaction, ref *firestore.DocumentRef) (map[string]any, error) {
	snap, err := getOptional(tx, ref)
	if err != nil {
		return nil, err
	}
	if !snap.Exists() {
		return nil, errRankRewardNoWinner
	}
	reward, _ := snap.Data()["reward"].(map[string]any)
	if reward == nil {
		return nil, errRankRewardNoWinner
	}
	return reward, nil
}

// DeliverRankRewardPush báo người trúng quà của một bảng vừa chốt. Một push chung
// cho mọi người trúng: Send hỏng hết thì Cloud Tasks gửi lại cả lượt, không ai
// nhận hai lần vì chỉ có một lượt.
func DeliverRankRewardPush(ctx context.Context, db *firestore.Client, push *PushService, boardID string) error {
	off, err := pushKindOff(ctx, db, rankRewardPushKind)
	if err != nil || off {
		return err
	}
	key, ok := parseRankBoardID(boardID)
	if !ok {
		return nil
	}
	board, err := db.Collection("rankBoards").Doc(boardID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	var uids []string
	for _, raw := range anyList(board.Data()["entries"]) {
		e, _ := raw.(map[string]any)
		if e["reward"] != nil {
			uids = append(uids, stringValue(e["uid"]))
		}
	}
	if len(uids) == 0 {
		return nil
	}
	return push.Send(ctx, uids, pushNote{
		Title: "Bạn có quà BXH " + rankPeriodWord(key.r),
		Body:  "Mở thẻ hạng để xem quà và nhắn người trao.",
		Data:  map[string]string{"kind": rankRewardPushKind, "boardId": boardID},
	})
}

func (s *Server) rankRewardRoutes() {
	read := func(w http.ResponseWriter, r *http.Request) error {
		view, err := s.deps.RankRewards.View(r.Context(), r.PathValue("board"), s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, view)
	}
	s.route("GET /v1/admin/rank-rewards/{board}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		return read(w, r)
	}))
	s.route("PUT /v1/admin/rank-rewards/{board}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		var body RankRewardInput
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.RankRewards.Set(r.Context(), uid, r.PathValue("board"), body, s.now()); err != nil {
			return err
		}
		return read(w, r)
	}))
	for method, given := range map[string]bool{"POST": true, "DELETE": false} {
		s.route(method+" /v1/admin/rank-rewards/{board}/winners/{uid}/given", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
			now := s.now()
			marked, err := s.deps.RankRewards.SetGiven(r.Context(), uid, r.PathValue("board"), r.PathValue("uid"), given, now)
			if err != nil {
				return err
			}
			if marked {
				s.notifyGiftGiven(r.Context(), giftGivenTask(giftFromRank, r.PathValue("board"), r.PathValue("uid"), now))
			}
			return read(w, r)
		}))
	}
	s.route("GET /v1/rank-cards/{board}/reward/contact", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		tg, err := s.deps.RankRewards.Contact(r.Context(), uid, r.PathValue("board"))
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"giverTg": tg})
	}))
	s.route("POST /v1/rank-cards/{board}/reward/received", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.RankRewards.MarkReceived(r.Context(), uid, r.PathValue("board"), s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
}

type rankRewardPushTask struct {
	BoardID string `json:"boardId"`
}

// rankRewardPush: task push quà, hẹn từ writeBoard sau khi bảng ghi xong.
func (s *Server) rankRewardPush(w http.ResponseWriter, r *http.Request) error {
	var task rankRewardPushTask
	if decodeJSON(r, &task) != nil || task.BoardID == "" || s.deps.Push == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := DeliverRankRewardPush(r.Context(), s.deps.Firestore, s.deps.Push, task.BoardID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
