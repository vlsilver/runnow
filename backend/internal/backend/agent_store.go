package backend

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Bot cá nhân (thử nghiệm): mỗi thành viên có một bot với tên, persona và bộ
// nhớ do chính họ dạy. Bot là phần lõi nằm ở backend; app và Telegram chỉ là
// kênh giao tiếp. Mọi kênh dùng chung hồ sơ, bộ nhớ, ký ức tự học và trần câu
// trả lời mỗi ngày, nhưng mỗi kênh có cuộc chat riêng: lịch sử và seq riêng,
// model chỉ đọc lịch sử của kênh đang trả lời (xem agentDMChannels).
//
//	agents/{uid}                    tên, persona, inRoom, seq của từng kênh, dmDay/dmDayCount
//	agents/{uid}/memories/{id}      từng mục bộ nhớ
//	agents/{uid}/dm/{seq}           chat riêng trong app
//	agents/{uid}/tgdm/{seq}         chat riêng trên Telegram
//	agents/{uid}/consent/ai         đồng ý gửi dữ liệu cho AI (agent_consent.go)
//	agentRooms/{room}               seq và state lượt nói của các bot (main, tg-psc)
//	agentRooms/{room}/messages/{seq} tin trong phòng, của người lẫn bot
//
// Ai được dùng: agentState/config.open bật thì mọi tài khoản đăng nhập; tắt thì
// chỉ allowlist gameState/config.adminUids cộng agentState/config.memberUids.
// Allowlist vẫn giữ khi đã mở, để tắt cờ là quay về như cũ mà không cần deploy.
// Đọc mỗi request nên sửa là có hiệu lực ngay.

const (
	agentNameMaxRunes    = 40
	agentPersonaMaxRunes = 1500
	agentMemoryMaxRunes  = 500
	agentMemoryLimit     = 50
	agentTextMaxRunes    = 1000
	agentPageSize        = 30
	agentMinGap          = time.Second

	agentRoleUser  = "user"
	agentRoleAgent = "agent"

	agentKindHuman = "human"
	agentKindAgent = "agent"

	agentChannelApp      = "app"
	agentChannelTelegram = "telegram"

	agentSourceManual = "manual"
	agentSourceChat   = "chat"

	// agentMainRoom là phòng bot trong app; agentTelegramRoom là topic "Phòng
	// bot" của PSC. Hai phòng không nối với nhau: seq, chuỗi và trần ngày riêng.
	agentMainRoom     = "main"
	agentTelegramRoom = "tg-psc"
)

// agentDMChannel là chỗ lưu cuộc chat riêng của một kênh: collection tin và các
// field đếm trên agents/{uid}. Kênh app giữ nguyên tên field cũ, để dữ liệu đã
// ghi và app 1.5.0 không phải đổi gì.
type agentDMChannel struct {
	name       string
	collection string
	// seqField là seq tin mới nhất; userSeqField là seq tin mới nhất của chủ;
	// answeredField là seq tin của chủ đã được trả lời; userAtField là lúc chủ
	// gửi tin gần nhất, để chặn gửi dồn.
	seqField, userSeqField, answeredField, userAtField string
	// countedField là seq tin của chủ đã được đếm vào hạn mức chat riêng, để
	// task chạy lại sau lỗi không đếm cùng một tin lần nữa.
	countedField string
	// memoryPrefix đứng đầu id mục nhớ bot thêm từ tin seq của kênh này, để
	// cùng một seq ở hai kênh không ghi đè mục nhớ của nhau.
	memoryPrefix string
}

var agentDMChannels = map[string]agentDMChannel{
	agentChannelApp:      {name: agentChannelApp, collection: "dm", seqField: "dmSeq", userSeqField: "dmUserSeq", answeredField: "answeredSeq", userAtField: "dmUserAt", countedField: "dmCountedSeq", memoryPrefix: "dm"},
	agentChannelTelegram: {name: agentChannelTelegram, collection: "tgdm", seqField: "tgSeq", userSeqField: "tgUserSeq", answeredField: "tgAnsweredSeq", userAtField: "tgUserAt", countedField: "tgCountedSeq", memoryPrefix: "tg"},
}

// agentRoomChannels là các phòng bot đang có và kênh của tin trong phòng đó.
// Phòng ngoài danh sách thì bị từ chối, để roomID sai trong task không đẻ ra
// phòng rác.
var agentRoomChannels = map[string]string{agentMainRoom: agentChannelApp, agentTelegramRoom: agentChannelTelegram}

var (
	errAgentDisabled  = &HTTPError{Status: http.StatusForbidden, Code: "agent_disabled", Message: "Bạn chưa được mời dùng bot thử nghiệm."}
	errAgentNotFound  = &HTTPError{Status: http.StatusNotFound, Code: "agent_not_found", Message: "Bạn chưa tạo bot."}
	errAgentName      = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_name", Message: fmt.Sprintf("Tên bot trống hoặc dài quá %d ký tự.", agentNameMaxRunes)}
	errAgentPersona   = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_persona", Message: fmt.Sprintf("Tính cách dài quá %d ký tự.", agentPersonaMaxRunes)}
	errAgentMemory    = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_memory", Message: fmt.Sprintf("Mục nhớ trống hoặc dài quá %d ký tự.", agentMemoryMaxRunes)}
	errAgentMemoryMax = &HTTPError{Status: http.StatusConflict, Code: "memory_full", Message: fmt.Sprintf("Bộ nhớ đã đủ %d mục, xoá bớt rồi thêm.", agentMemoryLimit)}
	errAgentNoMemory  = &HTTPError{Status: http.StatusNotFound, Code: "memory_not_found", Message: "Không còn mục nhớ này."}
	errAgentText      = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_text", Message: fmt.Sprintf("Tin nhắn trống hoặc dài quá %d ký tự.", agentTextMaxRunes)}
	errAgentTooFast   = &HTTPError{Status: http.StatusTooManyRequests, Code: "too_fast", Message: "Gửi chậm lại một chút."}
)

type AgentStore struct {
	db *firestore.Client
}

func NewAgentStore(db *firestore.Client) *AgentStore { return &AgentStore{db: db} }

type AgentProfile struct {
	Name    string `json:"name"`
	Persona string `json:"persona"`
	// Created: false là hồ sơ mặc định, chưa ghi; bot chưa vào phòng và chưa
	// chat riêng được cho tới khi chủ lưu lần đầu.
	Created bool `json:"created"`
	// CreatedAt là lần chủ lưu hồ sơ đầu tiên; nil khi chưa tạo bot.
	CreatedAt *time.Time `json:"createdAt,omitempty"`
}

type AgentMemory struct {
	ID        string    `json:"id"`
	Text      string    `json:"text"`
	Source    string    `json:"source"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type AgentMe struct {
	Enabled     bool          `json:"enabled"`
	Agent       *AgentProfile `json:"agent,omitempty"`
	Memories    []AgentMemory `json:"memories"`
	MemoryLimit int           `json:"memoryLimit"`
	// Learned là ký ức bot tự học về chính người gọi, kể cả khi chưa tạo bot.
	Learned      []AgentLearnedFact `json:"learned"`
	LearnedLimit int                `json:"learnedLimit"`
	// NoLearn: đã bật "Đừng học về tôi", bot không tự học từ tin của người này.
	NoLearn bool `json:"noLearn"`
	// Today chỉ có khi enabled, để GET me của người chưa được mời vẫn rẻ.
	Today *AgentToday `json:"today,omitempty"`
	AgentConsent
	// Telegram chỉ có khi MyBot trên Telegram bật và chủ đã tạo bot; app cũ bỏ
	// qua field lạ.
	Telegram *AgentTelegram `json:"telegram,omitempty"`
}

// AgentToday là lượt đã dùng hôm nay (giờ VN) để app hiện "tin hôm nay" và báo
// bot đang nghỉ trước khi người dùng nhắn rồi mới nhận câu nghỉ.
type AgentToday struct {
	DMUsed int64 `json:"dmUsed"`
	// DMMax là hạn mức chat riêng hôm nay đã tính theo km (xem DMByKm).
	DMMax    int64 `json:"dmMax"`
	RoomUsed int64 `json:"roomUsed"`
	RoomMax  int64 `json:"roomMax"`
	// Resting là lý do bot đang trả câu nghỉ: "budget" (cả hệ thống chạm trần
	// tiền AI) hay "dm_limit" (người này hết lượt chat riêng); null là không nghỉ.
	// Budget đứng trước vì nó chặn mọi bot, nâng lượt chat riêng cũng không mở lại.
	Resting *string `json:"resting"`
	// DMByKm là cách tính DMMax, chỉ có khi đã tạo bot.
	DMByKm *AgentDMByKm `json:"dmByKm,omitempty"`
	// Images chỉ có khi bật vẽ ảnh và đã tạo bot; app cũ bỏ qua field lạ.
	Images *AgentImagesToday `json:"images,omitempty"`
}

// AgentDMByKm: DMMax = min(trần, Base + PerKm × số km trọn chạy và đi bộ hôm nay), để
// app hiện km hôm nay mở được bao nhiêu câu và chạy thêm bao nhiêu thì mở tiếp.
type AgentDMByKm struct {
	Base  int64   `json:"base"`
	PerKm int64   `json:"perKm"`
	RunKm float64 `json:"runKm"`
	// NextKm và NextMax là mốc km trọn kế tiếp và DMMax ở mốc đó; null khi chạy
	// thêm cũng không mở thêm câu nào.
	NextKm  *float64 `json:"nextKm"`
	NextMax *int64   `json:"nextMax"`
}

// AgentImagesToday là lượt vẽ ảnh hôm nay (giờ VN) theo km chủ đã chạy, để app
// hiện còn mấy ảnh và chạy thêm bao nhiêu thì mở mốc kế tiếp.
type AgentImagesToday struct {
	Used  int64   `json:"used"`
	Limit int64   `json:"limit"`
	RunKm float64 `json:"runKm"`
	// NextKm và NextLimit là mốc kế tiếp; null khi đã ở mốc cao nhất.
	NextKm    *float64 `json:"nextKm"`
	NextLimit *int64   `json:"nextLimit"`
	// Tiers là cả bảng mốc, km tăng dần, để app vẽ đủ các bậc trong ngày mà
	// không giữ bảng riêng.
	Tiers []AgentImageTier `json:"tiers"`
}

type AgentImageTier struct {
	Km    float64 `json:"km"`
	Limit int64   `json:"limit"`
}

const (
	agentRestingBudget  = "budget"
	agentRestingDMLimit = "dm_limit"
)

type AgentMessage struct {
	Seq  int64     `json:"seq"`
	Role string    `json:"role"`
	Text string    `json:"text"`
	At   time.Time `json:"at"`
	// ImagePath là ảnh bot vẽ kèm tin, chỉ có ở kênh Telegram. Không ra API của
	// app, vì app chưa hiện ảnh trong chat.
	ImagePath string `json:"-"`
}

type AgentDMPage struct {
	Messages []AgentMessage `json:"messages"`
	Cursor   string         `json:"cursor,omitempty"`
	HasNewer bool           `json:"hasNewer"`
	// Waiting: tin cuối của chủ chưa được bot trả lời, app hiện "đang gõ".
	Waiting bool `json:"waiting"`
}

func (s *AgentStore) agentRef(uid string) *firestore.DocumentRef {
	return s.db.Collection("agents").Doc(uid)
}

func (s *AgentStore) roomRef(room string) *firestore.DocumentRef {
	return s.db.Collection("agentRooms").Doc(room)
}

// agentAccess là quyền dùng bot đọc một lần cho cả request.
type agentAccess struct {
	open bool
	// members là allowlist, sort để thứ tự tất định.
	members []string
	// cfg là doc agentState/config đã đọc, để Me lấy giới hạn mà không đọc lại.
	cfg map[string]any
}

func (a agentAccess) allows(uid string) bool { return a.open || slices.Contains(a.members, uid) }

// access đọc cờ open và allowlist.
func (s *AgentStore) access(ctx context.Context) (agentAccess, error) {
	game, err := getData(ctx, s.db.Collection("gameState").Doc("config"))
	if err != nil {
		return agentAccess{}, err
	}
	cfg, err := getData(ctx, s.db.Collection("agentState").Doc("config"))
	if err != nil {
		return agentAccess{}, err
	}
	set := map[string]bool{}
	for _, v := range append(anyList(game["adminUids"]), anyList(cfg["memberUids"])...) {
		if uid := stringValue(v); uid != "" {
			set[uid] = true
		}
	}
	out := agentAccess{open: cfg["open"] == true, members: make([]string, 0, len(set)), cfg: cfg}
	for uid := range set {
		out.members = append(out.members, uid)
	}
	slices.Sort(out.members)
	return out, nil
}

// allowed: uid dùng được bot, vì cờ open đang bật hoặc uid nằm trong allowlist.
func (s *AgentStore) allowed(ctx context.Context, uid string) (bool, error) {
	acc, err := s.access(ctx)
	if err != nil {
		return false, err
	}
	return acc.allows(uid), nil
}

func (s *AgentStore) requireMember(ctx context.Context, uid string) error {
	ok, err := s.allowed(ctx, uid)
	if err != nil {
		return err
	}
	if !ok {
		return errAgentDisabled
	}
	return nil
}

// displayNames đọc tên hiển thị từ publicProfiles; thiếu thì "Thành viên".
func (s *AgentStore) displayNames(ctx context.Context, uids []string) (map[string]string, error) {
	out := map[string]string{}
	if len(uids) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(uids))
	for i, uid := range uids {
		refs[i] = s.db.Collection("publicProfiles").Doc(uid)
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for i, d := range docs {
		name := ""
		if d.Exists() {
			name = strings.TrimSpace(stringValue(d.Data()["displayName"]))
		}
		if name == "" {
			name = "Thành viên"
		}
		out[uids[i]] = name
	}
	return out, nil
}

func defaultAgentName(owner string) string {
	name := []rune("Bot của " + owner)
	if len(name) > agentNameMaxRunes {
		name = name[:agentNameMaxRunes]
	}
	return string(name)
}

// Me trả hồ sơ bot và bộ nhớ của uid. Người chưa có quyền nhận enabled false
// chứ không phải lỗi, để app chỉ cần ẩn mục bot.
func (s *AgentStore) Me(ctx context.Context, uid string, wall time.Time) (AgentMe, error) {
	acc, err := s.access(ctx)
	if err != nil {
		return AgentMe{}, err
	}
	out := AgentMe{Memories: []AgentMemory{}, MemoryLimit: agentMemoryLimit, Learned: []AgentLearnedFact{}, LearnedLimit: agentLearnedLimit, AgentConsent: AgentConsent{ConsentVersion: agentAIConsentVersion}}
	if !acc.allows(uid) {
		return out, nil
	}
	out.Enabled = true
	if out.ConsentRequired, err = s.consentRequired(ctx, acc, uid); err != nil {
		return AgentMe{}, err
	}
	if out.Learned, err = s.LearnedAbout(ctx, uid, wall); err != nil {
		return AgentMe{}, err
	}
	optOut, err := learnOptOut(ctx, s.db)
	if err != nil {
		return AgentMe{}, err
	}
	out.NoLearn = optOut[uid]
	doc, err := s.agentRef(uid).Get(ctx)
	switch {
	case status.Code(err) == codes.NotFound:
		names, err := s.displayNames(ctx, []string{uid})
		if err != nil {
			return AgentMe{}, err
		}
		out.Agent = &AgentProfile{Name: defaultAgentName(names[uid])}
		if out.Today, err = s.today(ctx, acc.cfg, uid, nil, wall); err != nil {
			return AgentMe{}, err
		}
		return out, nil
	case err != nil:
		return AgentMe{}, err
	}
	out.Agent = &AgentProfile{Name: stringValue(doc.Data()["name"]), Persona: stringValue(doc.Data()["persona"]), Created: true}
	if at := timeValue(doc.Data()["createdAt"]); !at.IsZero() {
		out.Agent.CreatedAt = &at
	}
	if out.Memories, err = s.Memories(ctx, uid); err != nil {
		return AgentMe{}, err
	}
	if out.Today, err = s.today(ctx, acc.cfg, uid, doc.Data(), wall); err != nil {
		return AgentMe{}, err
	}
	return out, nil
}

// today đọc cùng các bộ đếm mà consumeDMBudget, roomBudgetLeft và
// AgentBudget.admit dùng để chặn, nên app báo nghỉ đúng lúc bot thật sự nghỉ.
// agent là doc bot, nil khi chưa tạo bot. Doc usage chỉ đọc khi có trần tiền,
// km chỉ đọc khi đã tạo bot.
func (s *AgentStore) today(ctx context.Context, cfg map[string]any, uid string, agent map[string]any, wall time.Time) (*AgentToday, error) {
	lim := parseAgentLimits(ctx, cfg)
	budget := parseAgentBudgetConfig(cfg).dailyUsd
	refs := []*firestore.DocumentRef{s.roomRef(agentMainRoom)}
	if budget > 0 {
		refs = append(refs, s.db.Collection("agentState").Doc("usage").Collection("days").Doc(agentUsageDay(wall)))
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	// GetAll không lỗi khi doc chưa có; Data() của doc đó là nil, đếm là 0.
	out := &AgentToday{DMMax: newAgentDMQuota(lim, 0).max, RoomUsed: roomUsedToday(docs[0].Data(), wall), RoomMax: lim.roomDailyMax}
	if agent != nil {
		q, err := s.dmQuota(ctx, lim, uid, wall)
		if err != nil {
			return nil, err
		}
		out.DMMax = q.max
		out.DMByKm = &AgentDMByKm{Base: lim.dmBase, PerKm: lim.dmPerKm, RunKm: q.runKm, NextKm: q.nextKm, NextMax: q.nextMax}
	}
	if stringValue(agent["dmDay"]) == vnDay(wall) {
		out.DMUsed = int64(number(agent["dmDayCount"]))
	}
	switch {
	case budget > 0 && number(docs[1].Data()["costUsd"]) >= budget:
		out.Resting = new(agentRestingBudget)
	case out.DMUsed >= out.DMMax:
		out.Resting = new(agentRestingDMLimit)
	}
	return out, nil
}

// todayKm là km uid chạy và đi bộ hôm nay (giờ VN), gồm cả quãng đường Apple
// Health tự đồng bộ (xem memberDayStats.DayKm). Các hạn mức theo km của bot cá
// nhân cùng đọc ở đây, để app hiện một số km. JSON vẫn gọi số này là runKm.
func (s *AgentStore) todayKm(ctx context.Context, uid string, wall time.Time) (float64, error) {
	now := wall.In(vietnam)
	day, err := NewBotTools(s.db).memberDay(ctx, uid, time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, vietnam))
	return day.DayKm, err
}

// SaveProfile tạo hoặc sửa tên và persona. Lần lưu đầu là lúc bot ra đời, và
// bot vào phòng luôn như trước giờ; sửa sau đó không đụng inRoom, để chủ đã cho
// bot ra khỏi phòng thì lưu lại hồ sơ cũng không kéo bot vào lại. Phải đồng ý
// AI trước, vì bot vào phòng là persona và bộ nhớ của chủ tới model ở lượt nói
// do người khác gọi.
func (s *AgentStore) SaveProfile(ctx context.Context, uid, name, persona string, wall time.Time) (AgentProfile, error) {
	name, persona = strings.TrimSpace(name), strings.TrimSpace(persona)
	if name == "" || utf8.RuneCountInString(name) > agentNameMaxRunes {
		return AgentProfile{}, errAgentName
	}
	if utf8.RuneCountInString(persona) > agentPersonaMaxRunes {
		return AgentProfile{}, errAgentPersona
	}
	if err := s.requireConsent(ctx, uid); err != nil {
		return AgentProfile{}, err
	}
	ref := s.agentRef(uid)
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		_, err := tx.Get(ref)
		update := map[string]any{"name": name, "persona": persona, "updatedAt": wall}
		if status.Code(err) == codes.NotFound {
			update["createdAt"] = wall
			update["inRoom"] = true
		} else if err != nil {
			return err
		}
		return tx.Set(ref, update, firestore.MergeAll)
	})
	if err != nil {
		return AgentProfile{}, err
	}
	return AgentProfile{Name: name, Persona: persona, Created: true}, nil
}

// requireAgent: uid trong danh sách và đã tạo bot.
func (s *AgentStore) requireAgent(ctx context.Context, uid string) error {
	if err := s.requireMember(ctx, uid); err != nil {
		return err
	}
	_, err := s.agentRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return errAgentNotFound
	}
	return err
}

// Memories trả bộ nhớ theo thứ tự thêm vào, cũ trước.
func (s *AgentStore) Memories(ctx context.Context, uid string) ([]AgentMemory, error) {
	docs, err := s.agentRef(uid).Collection("memories").OrderBy("createdAt", firestore.Asc).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]AgentMemory, 0, len(docs))
	for _, d := range docs {
		out = append(out, AgentMemory{ID: d.Ref.ID, Text: stringValue(d.Data()["text"]), Source: stringValue(d.Data()["source"]), UpdatedAt: timeValue(d.Data()["updatedAt"])})
	}
	return out, nil
}

func validMemory(text string) (string, error) {
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > agentMemoryMaxRunes {
		return "", errAgentMemory
	}
	return text, nil
}

// AddMemory thêm một mục. id rỗng thì tự sinh; bot truyền id cố định theo tin
// chat để task chạy lại ghi đè chứ không nhân đôi mục nhớ.
func (s *AgentStore) AddMemory(ctx context.Context, uid, id, text, source string, wall time.Time) (AgentMemory, error) {
	text, err := validMemory(text)
	if err != nil {
		return AgentMemory{}, err
	}
	col := s.agentRef(uid).Collection("memories")
	ref := col.NewDoc()
	if id != "" {
		ref = col.Doc(id)
	}
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		docs, err := tx.Documents(col.Limit(agentMemoryLimit + 1)).GetAll()
		if err != nil {
			return err
		}
		exists := slices.ContainsFunc(docs, func(d *firestore.DocumentSnapshot) bool { return d.Ref.ID == ref.ID })
		if !exists && len(docs) >= agentMemoryLimit {
			return errAgentMemoryMax
		}
		if exists {
			return tx.Update(ref, []firestore.Update{{Path: "text", Value: text}, {Path: "updatedAt", Value: wall}})
		}
		return tx.Create(ref, map[string]any{"text": text, "source": source, "createdAt": wall, "updatedAt": wall})
	})
	if err != nil {
		return AgentMemory{}, err
	}
	return AgentMemory{ID: ref.ID, Text: text, Source: source, UpdatedAt: wall}, nil
}

func (s *AgentStore) UpdateMemory(ctx context.Context, uid, id, text string, wall time.Time) (AgentMemory, error) {
	text, err := validMemory(text)
	if err != nil {
		return AgentMemory{}, err
	}
	if id == "" {
		return AgentMemory{}, errAgentNoMemory
	}
	ref := s.agentRef(uid).Collection("memories").Doc(id)
	source := ""
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return errAgentNoMemory
		}
		if err != nil {
			return err
		}
		source = stringValue(doc.Data()["source"])
		return tx.Update(ref, []firestore.Update{{Path: "text", Value: text}, {Path: "updatedAt", Value: wall}})
	})
	if err != nil {
		return AgentMemory{}, err
	}
	return AgentMemory{ID: id, Text: text, Source: source, UpdatedAt: wall}, nil
}

// DeleteMemory xoá một mục; mục đã mất thì coi như xong, để bấm xoá hai lần
// không báo lỗi.
func (s *AgentStore) DeleteMemory(ctx context.Context, uid, id string) error {
	if id == "" {
		return errAgentNoMemory
	}
	_, err := s.agentRef(uid).Collection("memories").Doc(id).Delete(ctx)
	return err
}

// seqDocID giữ doc ID theo thứ tự seq khi xem trong console.
func seqDocID(seq int64) string { return fmt.Sprintf("%010d", seq) }

// pageBySeq đọc một trang tin, mới trước, theo cùng quy ước với chat phe:
// không tham số là trang mới nhất; cursor lùi về tin cũ hơn; after lấy tối đa
// một trang tin ngay sau seq đó, để poll lấp được đoạn app chưa có.
func pageBySeq(ctx context.Context, col *firestore.CollectionRef, cursor, after string) (docs []*firestore.DocumentSnapshot, next string, hasNewer bool, err error) {
	if cursor != "" && after != "" {
		return nil, "", false, invalidRequest()
	}
	q := col.OrderBy("seq", firestore.Desc).Limit(agentPageSize)
	switch {
	case cursor != "":
		n, err := strconv.ParseInt(cursor, 10, 64)
		if err != nil || n < 1 {
			return nil, "", false, invalidRequest()
		}
		q = col.Where("seq", "<", n).OrderBy("seq", firestore.Desc).Limit(agentPageSize)
	case after != "":
		n, err := strconv.ParseInt(after, 10, 64)
		if err != nil || n < 0 {
			return nil, "", false, invalidRequest()
		}
		q = col.Where("seq", ">", n).OrderBy("seq", firestore.Asc).Limit(agentPageSize + 1)
	}
	docs, err = q.Documents(ctx).GetAll()
	if err != nil {
		return nil, "", false, err
	}
	if after != "" {
		if len(docs) > agentPageSize {
			docs, hasNewer = docs[:agentPageSize], true
		}
		slices.Reverse(docs)
	} else if len(docs) == agentPageSize {
		next = strconv.FormatInt(int64(number(docs[len(docs)-1].Data()["seq"])), 10)
	}
	return docs, next, hasNewer, nil
}

func (s *AgentStore) DM(ctx context.Context, uid, cursor, after string) (AgentDMPage, error) {
	if err := s.requireMember(ctx, uid); err != nil {
		return AgentDMPage{}, err
	}
	doc, err := s.agentRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return AgentDMPage{Messages: []AgentMessage{}}, nil
	}
	if err != nil {
		return AgentDMPage{}, err
	}
	docs, next, hasNewer, err := pageBySeq(ctx, s.agentRef(uid).Collection("dm"), cursor, after)
	if err != nil {
		return AgentDMPage{}, err
	}
	out := AgentDMPage{Messages: make([]AgentMessage, 0, len(docs)), Cursor: next, HasNewer: hasNewer}
	out.Waiting = number(doc.Data()["answeredSeq"]) < number(doc.Data()["dmUserSeq"])
	for _, d := range docs {
		m := d.Data()
		out.Messages = append(out.Messages, AgentMessage{Seq: int64(number(m["seq"])), Role: stringValue(m["role"]), Text: stringValue(m["text"]), At: timeValue(m["at"])})
	}
	return out, nil
}

// PostDM ghi tin của chủ vào chat riêng của kênh channel và trả seq của tin đó
// (seq riêng của kênh). Tin trả lời do bot ghi sau qua AppendDMReply.
func (s *AgentStore) PostDM(ctx context.Context, uid, text, channel string, wall time.Time) (AgentMessage, error) {
	ch, ok := agentDMChannels[channel]
	if !ok {
		return AgentMessage{}, fmt.Errorf("agent dm: không có kênh %q", channel)
	}
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > agentTextMaxRunes {
		return AgentMessage{}, errAgentText
	}
	// Che từ tục như phòng bot và chat phe Ma Sói, kể cả tin từ Telegram.
	text = maskProfanity(text)
	if err := s.requireConsent(ctx, uid); err != nil {
		return AgentMessage{}, err
	}
	ref := s.agentRef(uid)
	var msg AgentMessage
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return errAgentNotFound
		}
		if err != nil {
			return err
		}
		if last := timeValue(doc.Data()[ch.userAtField]); !last.IsZero() && wall.Sub(last) < agentMinGap {
			return errAgentTooFast
		}
		seq := int64(number(doc.Data()[ch.seqField])) + 1
		msg = AgentMessage{Seq: seq, Role: agentRoleUser, Text: text, At: wall}
		if err := tx.Create(ref.Collection(ch.collection).Doc(seqDocID(seq)), map[string]any{"seq": seq, "role": agentRoleUser, "text": text, "channel": ch.name, "at": wall}); err != nil {
			return err
		}
		updates := []firestore.Update{{Path: ch.seqField, Value: seq}, {Path: ch.userSeqField, Value: seq}, {Path: ch.userAtField, Value: wall}}
		if ch.name == agentChannelApp {
			// Bản trước đọc field này để gắn kênh cho câu trả lời; giữ để rollback
			// về bản đó vẫn ghi đúng "app".
			updates = append(updates, firestore.Update{Path: "dmUserChannel", Value: ch.name})
		}
		return tx.Update(ref, updates)
	})
	return msg, err
}

// dmHistory là tối đa limit tin chat riêng của kênh ch tới seq upTo, cũ trước.
func (s *AgentStore) dmHistory(ctx context.Context, uid string, ch agentDMChannel, upTo int64, limit int) ([]AgentMessage, error) {
	docs, err := s.agentRef(uid).Collection(ch.collection).Where("seq", "<=", upTo).OrderBy("seq", firestore.Desc).Limit(limit).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]AgentMessage, 0, len(docs))
	for _, d := range docs {
		out = append(out, dmMessage(d.Data()))
	}
	slices.Reverse(out)
	return out, nil
}

func dmMessage(m map[string]any) AgentMessage {
	return AgentMessage{Seq: int64(number(m["seq"])), Role: stringValue(m["role"]), Text: stringValue(m["text"]), At: timeValue(m["at"]), ImagePath: stringValue(m["imagePath"])}
}

// AppendDMReply ghi câu trả lời cho tin seq của chủ vào chat riêng của kênh ch,
// kèm ảnh bot vẽ nếu imagePath khác rỗng. Trả false khi không ghi: đã trả lời
// rồi (task chạy lại) hoặc chủ đã gửi tin mới hơn, tin mới đó có task riêng và
// sẽ được trả lời gộp. Câu trả lời luôn ở seq+1: chỉ ghi khi tin cuối của kênh
// là tin seq của chủ.
func (s *AgentStore) AppendDMReply(ctx context.Context, uid string, ch agentDMChannel, seq int64, text, imagePath string, wall time.Time) (AgentMessage, bool, error) {
	ref := s.agentRef(uid)
	var msg AgentMessage
	written := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		written = false
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		d := doc.Data()
		if int64(number(d[ch.answeredField])) >= seq || int64(number(d[ch.userSeqField])) != seq {
			return nil
		}
		next := int64(number(d[ch.seqField])) + 1
		msg = AgentMessage{Seq: next, Role: agentRoleAgent, Text: text, At: wall, ImagePath: imagePath}
		row := map[string]any{"seq": next, "role": agentRoleAgent, "text": text, "channel": ch.name, "at": wall}
		if imagePath != "" {
			row["imagePath"] = imagePath
		}
		if err := tx.Create(ref.Collection(ch.collection).Doc(seqDocID(next)), row); err != nil {
			return err
		}
		written = true
		return tx.Update(ref, []firestore.Update{{Path: ch.seqField, Value: next}, {Path: ch.answeredField, Value: seq}})
	})
	return msg, written, err
}
