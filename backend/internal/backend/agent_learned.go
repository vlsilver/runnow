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
	for i, p := range others {
		if i == 0 {
			b.WriteString("\n\nBẠN BIẾT VỀ NGƯỜI TRONG ĐOẠN CHAT (có thể đã cũ; người đó nói khác thì tin người đó):\n")
		}
		fmt.Fprintf(&b, "%s:\n", p.name)
		writeFacts(&b, newestFacts(p.facts, agentLearnedPerPerson), false)
	}
	if b.Len() == 0 {
		return ""
	}
	if withID {
		b.WriteString("\nChủ bảo quên điều bạn tự học thì gọi forget_learned đúng id trong ngoặc vuông.")
	}
	b.WriteString("\nCần biết về một người được nhắc tên mà không có ở trên thì gọi recall_person. Đừng tự kể chuyện riêng của người khác khi không ai hỏi.")
	return strings.TrimRight(b.String(), "\n")
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
