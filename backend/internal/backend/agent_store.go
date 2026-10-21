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
// nhớ do chính họ dạy. Bot là phần lõi nằm ở backend; app (chat riêng, phòng
// bot) và sau này Telegram chỉ là kênh giao tiếp, nên mỗi tin ghi kèm channel
// và mọi kênh dùng chung một lịch sử, một bộ nhớ.
//
//	agents/{uid}                    tên, persona, inRoom, dmSeq, dmUserSeq, answeredSeq
//	agents/{uid}/memories/{id}      từng mục bộ nhớ
//	agents/{uid}/dm/{seq}           chat riêng giữa chủ và bot
//	agentRooms/main                 seq và state lượt nói của các bot
//	agentRooms/main/messages/{seq}  tin trong phòng, của người lẫn bot
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

	agentChannelApp = "app"

	agentSourceManual = "manual"
	agentSourceChat   = "chat"

	agentMainRoom = "main"
)

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
}

type AgentMessage struct {
	Seq  int64     `json:"seq"`
	Role string    `json:"role"`
	Text string    `json:"text"`
	At   time.Time `json:"at"`
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
	out := agentAccess{open: cfg["open"] == true, members: make([]string, 0, len(set))}
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
	ok, err := s.allowed(ctx, uid)
	if err != nil {
		return AgentMe{}, err
	}
	out := AgentMe{Memories: []AgentMemory{}, MemoryLimit: agentMemoryLimit, Learned: []AgentLearnedFact{}, LearnedLimit: agentLearnedLimit}
	if !ok {
		return out, nil
	}
	out.Enabled = true
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
		return out, nil
	case err != nil:
		return AgentMe{}, err
	}
	out.Agent = &AgentProfile{Name: stringValue(doc.Data()["name"]), Persona: stringValue(doc.Data()["persona"]), Created: true}
	if out.Memories, err = s.Memories(ctx, uid); err != nil {
		return AgentMe{}, err
	}
	return out, nil
}

// SaveProfile tạo hoặc sửa tên và persona. Lần lưu đầu là lúc bot ra đời, và
// bot vào phòng luôn như trước giờ; sửa sau đó không đụng inRoom, để chủ đã cho
// bot ra khỏi phòng thì lưu lại hồ sơ cũng không kéo bot vào lại.
func (s *AgentStore) SaveProfile(ctx context.Context, uid, name, persona string, wall time.Time) (AgentProfile, error) {
	name, persona = strings.TrimSpace(name), strings.TrimSpace(persona)
	if name == "" || utf8.RuneCountInString(name) > agentNameMaxRunes {
		return AgentProfile{}, errAgentName
	}
	if utf8.RuneCountInString(persona) > agentPersonaMaxRunes {
		return AgentProfile{}, errAgentPersona
	}
	if err := s.requireMember(ctx, uid); err != nil {
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

// PostDM ghi tin của chủ vào chat riêng và trả seq của tin đó. Tin trả lời do
// bot ghi sau qua AppendDMReply.
func (s *AgentStore) PostDM(ctx context.Context, uid, text, channel string, wall time.Time) (AgentMessage, error) {
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > agentTextMaxRunes {
		return AgentMessage{}, errAgentText
	}
	// Che từ tục như phòng bot và chat phe Ma Sói, kể cả tin từ Telegram sau này.
	text = maskProfanity(text)
	if err := s.requireMember(ctx, uid); err != nil {
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
		if last := timeValue(doc.Data()["dmUserAt"]); !last.IsZero() && wall.Sub(last) < agentMinGap {
			return errAgentTooFast
		}
		seq := int64(number(doc.Data()["dmSeq"])) + 1
		msg = AgentMessage{Seq: seq, Role: agentRoleUser, Text: text, At: wall}
		if err := tx.Create(ref.Collection("dm").Doc(seqDocID(seq)), map[string]any{"seq": seq, "role": agentRoleUser, "text": text, "channel": channel, "at": wall}); err != nil {
			return err
		}
		return tx.Update(ref, []firestore.Update{{Path: "dmSeq", Value: seq}, {Path: "dmUserSeq", Value: seq}, {Path: "dmUserAt", Value: wall}, {Path: "dmUserChannel", Value: channel}})
	})
	return msg, err
}

// dmHistory là tối đa limit tin chat riêng tới seq upTo, cũ trước.
func (s *AgentStore) dmHistory(ctx context.Context, uid string, upTo int64, limit int) ([]AgentMessage, error) {
	docs, err := s.agentRef(uid).Collection("dm").Where("seq", "<=", upTo).OrderBy("seq", firestore.Desc).Limit(limit).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]AgentMessage, 0, len(docs))
	for _, d := range docs {
		m := d.Data()
		out = append(out, AgentMessage{Seq: int64(number(m["seq"])), Role: stringValue(m["role"]), Text: stringValue(m["text"]), At: timeValue(m["at"])})
	}
	slices.Reverse(out)
	return out, nil
}

// AppendDMReply ghi câu trả lời cho tin seq của chủ, qua đúng kênh chủ vừa
// dùng. Trả false khi không ghi: đã trả lời rồi (task chạy lại) hoặc chủ đã
// gửi tin mới hơn, tin mới đó có task riêng và sẽ được trả lời gộp.
func (s *AgentStore) AppendDMReply(ctx context.Context, uid string, seq int64, text string, wall time.Time) (bool, error) {
	ref := s.agentRef(uid)
	written := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		written = false
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		d := doc.Data()
		if int64(number(d["answeredSeq"])) >= seq || int64(number(d["dmUserSeq"])) != seq {
			return nil
		}
		next := int64(number(d["dmSeq"])) + 1
		if err := tx.Create(ref.Collection("dm").Doc(seqDocID(next)), map[string]any{"seq": next, "role": agentRoleAgent, "text": text, "channel": stringValue(d["dmUserChannel"]), "at": wall}); err != nil {
			return err
		}
		written = true
		return tx.Update(ref, []firestore.Update{{Path: "dmSeq", Value: next}, {Path: "answeredSeq", Value: seq}})
	})
	return written, err
}
