package backend

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// Phần đọc ký ức tự học (agent_learn.go) cho prompt và tool của bot.

// agentLearnedPerPerson: mỗi người có mặt trong đoạn chat chỉ đưa chừng này ký
// ức mới nhất vào prompt, để prompt không phình theo số người; cần hơn thì
// model gọi recall_person.
const agentLearnedPerPerson = 15

var errLearnedNotFound = &HTTPError{Status: http.StatusNotFound, Code: "learned_not_found", Message: "Không có mục ký ức này."}

// learnedTGPrefix đánh dấu ký ức nằm ở doc theo tg id khi đưa cho model hay
// app, vì id ký ức chỉ duy nhất trong một doc.
const learnedTGPrefix = "tg-"

// learnedGroup là ký ức nhóm còn hạn.
func (s *AgentStore) learnedGroup(ctx context.Context, now time.Time) ([]learnedFact, error) {
	doc, err := docMap(learnedCol(s.db).Doc(agentGroupScope).Get(ctx))
	if err != nil {
		return nil, err
	}
	return liveFacts(doc["facts"], now), nil
}

// learnedOf là ký ức tự học của từng uid: doc theo uid, cộng doc theo tg id
// đang liên kết (học từ trước khi liên kết), id của doc sau có learnedTGPrefix.
// uid cũng có thể là key tg-{id} của người chưa liên kết.
func (s *AgentStore) learnedOf(ctx context.Context, uids []string, now time.Time) (map[string][]learnedFact, error) {
	out := map[string][]learnedFact{}
	if len(uids) == 0 {
		return out, nil
	}
	linkRefs := make([]*firestore.DocumentRef, len(uids))
	for i, uid := range uids {
		linkRefs[i] = s.db.Collection("telegramLinks").Doc(uid)
	}
	links, err := s.db.GetAll(ctx, linkRefs)
	if err != nil {
		return nil, err
	}
	owner := map[string]string{}
	var refs []*firestore.DocumentRef
	for i, uid := range uids {
		owner[uid] = uid
		refs = append(refs, learnedCol(s.db).Doc(uid))
		if tg := tgIDString(links[i].Data()["tgUserId"]); links[i].Exists() && tg != "" {
			owner[learnTGScope(tg)] = uid
			refs = append(refs, learnedCol(s.db).Doc(learnTGScope(tg)))
		}
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		if !d.Exists() {
			continue
		}
		uid := owner[d.Ref.ID]
		for _, f := range liveFacts(d.Data()["facts"], now) {
			if d.Ref.ID != uid {
				f.ID = learnedTGPrefix + f.ID
			}
			out[uid] = append(out[uid], f)
		}
	}
	return out, nil
}

// ForgetLearnedFact xoá một ký ức tự học về uid theo id như learnedOf trả, và
// ghi learnLog để biết ai xoá. Mục không còn thì errLearnedNotFound.
func (s *AgentStore) ForgetLearnedFact(ctx context.Context, uid, id string, now time.Time) error {
	key, factID := uid, id
	if rest, ok := strings.CutPrefix(id, learnedTGPrefix); ok {
		link, err := docMap(s.db.Collection("telegramLinks").Doc(uid).Get(ctx))
		if err != nil {
			return err
		}
		tg := tgIDString(link["tgUserId"])
		if tg == "" {
			return errLearnedNotFound
		}
		key, factID = learnTGScope(tg), rest
	}
	return s.forgetLearnedIn(ctx, key, factID, "owner:"+uid, now)
}

// SetNoLearn bật hay tắt "Đừng học về tôi" cho uid. Bật thì ghi cờ trước rồi
// mới xoá ký ức đã học (forgetLearned): xoá lỗi giữa chừng thì cờ đã có nên
// lượt học sau không học thêm, app bấm lại thì xoá tiếp. Tắt thì chỉ học lại từ
// tin mới, ký ức đã xoá không quay về.
func (s *AgentStore) SetNoLearn(ctx context.Context, uid string, on bool, now time.Time) error {
	var op any = firestore.ArrayRemove(uid)
	if on {
		op = firestore.ArrayUnion(uid)
	}
	if _, err := learnOptOutRef(s.db).Set(ctx, map[string]any{"uids": op, "updatedAt": now}, firestore.MergeAll); err != nil {
		return err
	}
	slog.InfoContext(ctx, "agent.no_learn", "uid", uid, "on", on)
	if !on {
		return nil
	}
	return forgetLearned(ctx, s.db, uid)
}

// forgetLearnedIn xoá ký ức factID khỏi doc key. by ghi vào learnLog.
func (s *AgentStore) forgetLearnedIn(ctx context.Context, key, factID, by string, now time.Time) error {
	ref := learnedCol(s.db).Doc(key)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := docMap(tx.Get(ref))
		if err != nil {
			return err
		}
		facts := anyList(doc["facts"])
		i := slices.IndexFunc(facts, func(v any) bool {
			m, _ := v.(map[string]any)
			return stringValue(m["id"]) == factID
		})
		if i < 0 || factID == "" {
			return errLearnedNotFound
		}
		before := stringValue(facts[i].(map[string]any)["text"])
		if err := tx.Update(ref, []firestore.Update{{Path: "facts", Value: slices.Delete(facts, i, i+1)}, {Path: "updatedAt", Value: now}}); err != nil {
			return err
		}
		log := map[string]any{"scope": key, "op": "FORGET", "factId": factID, "before": before, "after": "", "by": by, "at": now, "expiresAt": now.Add(agentLearnedTTL)}
		return tx.Set(learnLogCol(s.db).Doc(fmt.Sprintf("forget-%s-%s", key, factID)), log)
	})
}

// learnedPerson là ký ức của một người khác có mặt trong đoạn chat.
type learnedPerson struct {
	name  string
	facts []learnedFact
}

// AgentLearnedFact là một ký ức tự học trả cho app. Source là "learned" hay
// "migrated" (chuyển từ tóm tắt cũ của 3i).
type AgentLearnedFact struct {
	ID        string    `json:"id"`
	Text      string    `json:"text"`
	Source    string    `json:"source"`
	UpdatedAt time.Time `json:"updatedAt"`
}

func learnedFactsJSON(facts []learnedFact) []AgentLearnedFact {
	out := make([]AgentLearnedFact, len(facts))
	for i, f := range facts {
		source := f.Source
		if source == "" {
			source = "learned"
		}
		out[i] = AgentLearnedFact{ID: f.ID, Text: f.Text, Source: source, UpdatedAt: f.UpdatedAt}
	}
	return out
}

// LearnedAbout là ký ức tự học về uid, id như ForgetLearnedFact nhận.
func (s *AgentStore) LearnedAbout(ctx context.Context, uid string, now time.Time) ([]AgentLearnedFact, error) {
	by, err := s.learnedOf(ctx, []string{uid}, now)
	if err != nil {
		return nil, err
	}
	return learnedFactsJSON(by[uid]), nil
}

// GroupFacts là ký ức nhóm còn hạn cho thành viên phòng bot.
func (s *AgentStore) GroupFacts(ctx context.Context, uid string, now time.Time) ([]AgentLearnedFact, error) {
	if err := s.requireMember(ctx, uid); err != nil {
		return nil, err
	}
	facts, err := s.learnedGroup(ctx, now)
	if err != nil {
		return nil, err
	}
	return learnedFactsJSON(facts), nil
}

// ForgetGroupFact xoá một ký ức nhóm; quyền admin do nơi gọi kiểm.
func (s *AgentStore) ForgetGroupFact(ctx context.Context, admin, id string, now time.Time) error {
	return s.forgetLearnedIn(ctx, agentGroupScope, id, "admin:"+admin, now)
}

// learnedSubject là một người cần đưa ký ức vào prompt 3i: uid khi biết tài
// khoản app, không thì tg là id Telegram của người gửi.
type learnedSubject struct{ uid, tg, name string }

// learnedPeople là ký ức của các subject còn ký ức, giữ thứ tự đưa vào; hai
// subject cùng một người thì lấy subject đầu.
func (s *AgentStore) learnedPeople(ctx context.Context, subjects []learnedSubject, now time.Time) ([]learnedPerson, error) {
	var linkRefs []*firestore.DocumentRef
	for _, p := range subjects {
		if p.uid == "" && p.tg != "" {
			linkRefs = append(linkRefs, s.db.Collection("tgLinks").Doc(p.tg))
		}
	}
	linked := map[string]string{}
	if len(linkRefs) > 0 {
		links, err := s.db.GetAll(ctx, linkRefs)
		if err != nil {
			return nil, err
		}
		for _, l := range links {
			if l.Exists() {
				linked[l.Ref.ID] = stringValue(l.Data()["uid"])
			}
		}
	}
	keys := make([]string, len(subjects))
	for i, p := range subjects {
		switch {
		case p.uid != "":
			keys[i] = p.uid
		case linked[p.tg] != "":
			keys[i] = linked[p.tg]
		case p.tg != "":
			keys[i] = learnTGScope(p.tg)
		}
	}
	by, err := s.learnedOf(ctx, uniqueStrings(keys), now)
	if err != nil {
		return nil, err
	}
	var out []learnedPerson
	seen := map[string]bool{}
	for i, p := range subjects {
		if k := keys[i]; k != "" && !seen[k] && len(by[k]) > 0 {
			seen[k] = true
			out = append(out, learnedPerson{name: p.name, facts: by[k]})
		}
	}
	return out, nil
}

// ForgetTelegramFact xoá một ký ức tự học về người dùng Telegram tg theo id như
// learnedPeople trả cho chính người đó, và ghi learnLog.
func (s *AgentStore) ForgetTelegramFact(ctx context.Context, tg, id string, now time.Time) error {
	if tg == "" {
		return errLearnedNotFound
	}
	link, err := docMap(s.db.Collection("tgLinks").Doc(tg).Get(ctx))
	if err != nil {
		return err
	}
	key, factID := learnTGScope(tg), id
	if uid := stringValue(link["uid"]); uid != "" {
		key = uid
		if rest, ok := strings.CutPrefix(id, learnedTGPrefix); ok {
			key, factID = learnTGScope(tg), rest
		}
	}
	return s.forgetLearnedIn(ctx, key, factID, "tg:"+tg, now)
}

// learnedBlock là phần ký ức tự học chèn vào prompt bot cá nhân. Rỗng khi
// chưa học được gì, để prompt giữ nguyên như trước khi bật học. withID cho
// chat riêng, nơi chủ bảo quên được.
func learnedBlock(owner []learnedFact, group []learnedFact, others []learnedPerson, withID bool) string {
	var b strings.Builder
	if len(owner) > 0 {
		b.WriteString("\n\nBẠN TỰ HỌC ĐƯỢC VỀ CHỦ (rút từ tin chủ nói trong phòng bot và group Telegram, có thể đã cũ):\n")
		writeFacts(&b, owner, withID)
	}
	if len(group) > 0 {
		b.WriteString("\n\nBẠN BIẾT VỀ NHÓM (rút từ tin trong nhóm, có thể đã cũ):\n")
		writeFacts(&b, group, false)
	}
	writePeople(&b, others)
	if b.Len() == 0 {
		return ""
	}
	if withID {
		b.WriteString("\nChủ bảo quên điều bạn tự học thì gọi forget_learned đúng id trong ngoặc vuông.")
	}
	b.WriteString("\nCần biết về một người được nhắc tên mà không có ở trên thì gọi recall_person. Đừng tự kể chuyện riêng của người khác khi không ai hỏi.")
	return strings.TrimRight(b.String(), "\n")
}

// botLearnedBlock là phần ký ức tự học chèn vào prompt 3i thay cho tóm tắt
// botMemory của group club. self là người đang chat riêng với 3i, có id để họ
// bảo quên được.
func botLearnedBlock(group []learnedFact, self *learnedPerson, others []learnedPerson) string {
	var b strings.Builder
	if len(group) > 0 {
		b.WriteString("\n\nBẠN BIẾT VỀ GROUP CLUB (rút từ tin trong group, có thể đã cũ):\n")
		writeFacts(&b, group, false)
	}
	if self != nil {
		fmt.Fprintf(&b, "\n\nBẠN BIẾT VỀ %s, NGƯỜI ĐANG CHAT VỚI BẠN (có thể đã cũ; họ nói khác thì tin họ):\n", self.name)
		writeFacts(&b, self.facts, true)
		b.WriteString("Họ bảo quên điều gì về họ thì gọi forget_my_fact đúng id trong ngoặc vuông.\n")
	}
	writePeople(&b, others)
	if b.Len() == 0 {
		return ""
	}
	b.WriteString("\nCần biết về một người được nhắc tên mà không có ở trên thì gọi recall_person.")
	return strings.TrimRight(b.String(), "\n")
}

func writePeople(b *strings.Builder, people []learnedPerson) {
	for i, p := range people {
		if i == 0 {
			b.WriteString("\n\nBẠN BIẾT VỀ NGƯỜI TRONG ĐOẠN CHAT (có thể đã cũ; người đó nói khác thì tin người đó):\n")
		}
		fmt.Fprintf(b, "%s:\n", p.name)
		writeFacts(b, newestFacts(p.facts, agentLearnedPerPerson), false)
	}
}

func writeFacts(b *strings.Builder, facts []learnedFact, withID bool) {
	for _, f := range facts {
		if withID {
			fmt.Fprintf(b, "[%s] %s\n", f.ID, f.Text)
		} else {
			fmt.Fprintf(b, "- %s\n", f.Text)
		}
	}
}

// newestFacts là n ký ức mới sửa nhất, giữ thứ tự cũ.
func newestFacts(facts []learnedFact, n int) []learnedFact {
	if len(facts) <= n {
		return facts
	}
	sorted := slices.Clone(facts)
	slices.SortStableFunc(sorted, func(a, b learnedFact) int { return b.UpdatedAt.Compare(a.UpdatedAt) })
	keep := map[string]bool{}
	for _, f := range sorted[:n] {
		keep[f.ID] = true
	}
	return slices.DeleteFunc(slices.Clone(facts), func(f learnedFact) bool { return !keep[f.ID] })
}

var agentRecallPersonDecl = &genai.FunctionDeclaration{
	Name:        "recall_person",
	Description: "Tra những gì bot đã học được về một người trong nhóm, theo tên.",
	Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
		"name": {Type: genai.TypeString, Description: "Tên người, đúng như mọi người gọi trong nhóm."},
	}, Required: []string{"name"}},
}

var botForgetMyFactDecl = &genai.FunctionDeclaration{
	Name:        "forget_my_fact",
	Description: "Xoá một điều bot biết về chính người đang chat riêng với bot.",
	Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
		"id": {Type: genai.TypeString, Description: "id trong ngoặc vuông ở mục NGƯỜI ĐANG CHAT VỚI BẠN."},
	}, Required: []string{"id"}},
}

var agentForgetLearnedDecl = &genai.FunctionDeclaration{
	Name:        "forget_learned",
	Description: "Xoá một điều bot tự học được về chủ.",
	Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
		"id": {Type: genai.TypeString, Description: "id trong ngoặc vuông ở mục BẠN TỰ HỌC ĐƯỢC VỀ CHỦ."},
	}, Required: []string{"id"}},
}

func (a *AgentService) recallPerson(ctx context.Context, call *genai.FunctionCall, now time.Time) (map[string]any, error) {
	return recallPerson(ctx, a.store, a.chatID, stringValue(call.Args["name"]), now)
}

// recallPerson chạy tool recall_person: tra tên trong thành viên phòng bot và
// người trên group Telegram chatID. Tên không khớp hay trùng thì báo cho model.
func recallPerson(ctx context.Context, store *AgentStore, chatID, name string, now time.Time) (map[string]any, error) {
	name = strings.TrimSpace(name)
	people, err := learnPeople(ctx, store, chatID)
	if err != nil {
		return nil, err
	}
	members, err := store.members(ctx)
	if err != nil {
		return nil, err
	}
	names, err := store.displayNames(ctx, members)
	if err != nil {
		return nil, err
	}
	for uid, n := range names {
		if n != "Thành viên" {
			people.add(n, uid)
		}
	}
	key, note := people.resolve(name)
	if key == "" {
		return map[string]any{"ok": false, "reason": note}, nil
	}
	// key tg-{id} không có telegramLinks nên learnedOf chỉ đọc đúng doc đó.
	by, err := store.learnedOf(ctx, []string{key}, now)
	if err != nil {
		return nil, err
	}
	facts := by[key]
	texts := make([]string, len(facts))
	for i, f := range facts {
		texts[i] = f.Text
	}
	slog.InfoContext(ctx, "agent.recall_person", "found", len(texts))
	if len(texts) == 0 {
		return map[string]any{"ok": true, "facts": texts, "note": "chưa học được gì về người này"}, nil
	}
	return map[string]any{"ok": true, "facts": texts}, nil
}
