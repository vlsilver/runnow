package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// Chuyển tóm tắt cũ của 3i (botMemory/{chatID}, một đoạn viết liền tới 10.000
// ký tự) sang ký ức tự học. Tóm tắt là nơi duy nhất còn chuyện cũ hơn 30 ngày,
// vì botMessages hết hạn sau 30 ngày. Chạy bằng migrations/learn-from-botmemory,
// hai bước:
//
//	plan   model tách tóm tắt thành từng ký ức, gắn mỗi ký ức vào người theo
//	       tên, trả về để ghi ra file. Không ghi Firestore.
//	apply  ghi đúng các ký ức trong file vào learned/*. Không gọi model, nên
//	       thứ được ghi là thứ đã đọc trong file; sửa tay file trước khi apply
//	       cũng được.
//
// Mỗi dòng tóm tắt phải nằm trong một ký ức hoặc trong danh sách bỏ kèm lý do;
// dòng không nằm ở đâu thì plan liệt kê ở Uncovered để người đọc tự xét.

const learnMigrationSource = "migrated"

const learnMigratePrompt = `Bạn chuyển bộ nhớ cũ của bot một nhóm chạy bộ sang dạng danh sách ký ức rời.
Đầu vào là một hay nhiều bản tóm tắt (A, B, ...) về cùng một nhóm, mỗi dòng có mã trong ngoặc vuông, vd [A12]. Các bản có thể trùng ý nhau.
Tách thành các ký ức, mỗi ký ức một ý trọn vẹn, đọc riêng vẫn hiểu, viết tiếng Việt, tối đa 300 ký tự. Ý trùng giữa các dòng hay giữa các bản thì gộp thành một ký ức.
person: ký ức chỉ nói về một người thì ghi tên người đó đúng như trong tóm tắt, và text mở đầu bằng tên đó. Ký ức về cả nhóm, một đội hay nhiều người thì để rỗng.
lines: mã mọi dòng mà ký ức lấy ý.
Không bịa, không thêm ý không có trong tóm tắt. Không đoán giới tính: không gọi anh, chị, cô, chú; cần thì nhắc lại tên. Giữ mốc thời gian đúng như tóm tắt ghi.
Mọi dòng phải nằm trong lines của ít nhất một ký ức, hoặc trong dropped kèm lý do ngắn. Chỉ bỏ dòng tiêu đề, dòng không có ý gì, hoặc ý về lỗi kỹ thuật của bot (vd tin nhắn gửi hai lần). Đừng bỏ ý chỉ vì nó nhỏ hay cũ.
Ký ức không có person tối đa 45 mục; mỗi người tối đa 20 mục; cần thì gộp các ý gần nhau.`

var learnMigrateSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"items": {Type: genai.TypeArray, Items: &genai.Schema{
			Type: genai.TypeObject,
			Properties: map[string]*genai.Schema{
				"text":   {Type: genai.TypeString},
				"person": {Type: genai.TypeString, Description: "tên người, rỗng nếu là ký ức nhóm"},
				"lines":  {Type: genai.TypeArray, Items: &genai.Schema{Type: genai.TypeString}},
			},
			Required: []string{"text", "person", "lines"},
		}},
		"dropped": {Type: genai.TypeArray, Items: &genai.Schema{
			Type: genai.TypeObject,
			Properties: map[string]*genai.Schema{
				"line":   {Type: genai.TypeString},
				"reason": {Type: genai.TypeString},
			},
			Required: []string{"line", "reason"},
		}},
	},
	Required: []string{"items", "dropped"},
}

// LearnMigration là kết quả bước plan, cũng là đầu vào của apply.
type LearnMigration struct {
	Chats     []string             `json:"chats"`
	Lines     []LearnMigrationLine `json:"lines"`
	Items     []LearnMigrationItem `json:"items"`
	Dropped   []LearnMigrationDrop `json:"dropped"`
	Uncovered []string             `json:"uncovered"`
}

type LearnMigrationLine struct {
	ID   string `json:"id"`
	Chat string `json:"chat"`
	Text string `json:"text"`
}

type LearnMigrationItem struct {
	ID     string   `json:"id"`
	Text   string   `json:"text"`
	Person string   `json:"person"`
	Lines  []string `json:"lines"`
	// Target là doc ký ức sẽ ghi: _group, uid, tg-{id}; rỗng thì apply bỏ qua.
	Target string `json:"target"`
	// Note giải thích vì sao Target rỗng.
	Note string `json:"note,omitempty"`
}

type LearnMigrationDrop struct {
	Line   string `json:"line"`
	Reason string `json:"reason"`
}

// LearnMigrationResult là kết quả apply, theo id ký ức.
type LearnMigrationResult struct {
	Added     []string `json:"added"`
	Existing  []string `json:"existing"`
	Full      []string `json:"full"`
	Unmatched []string `json:"unmatched"`
}

// NewGenaiLearnService là LearnService gọi Vertex, cho lệnh chạy ngoài service.
func NewGenaiLearnService(db *firestore.Client, client *genai.Client, model, chatID string) *LearnService {
	return NewLearnService(NewAgentStore(db), genaiLearnLLM{client: client, model: model}, chatID)
}

// PlanMigration đọc tóm tắt của các chat, nhờ model tách thành ký ức và gắn
// người. Chỉ đọc Firestore.
func (l *LearnService) PlanMigration(ctx context.Context, chats []string) (*LearnMigration, error) {
	plan := &LearnMigration{Chats: chats}
	var in strings.Builder
	for i, chat := range chats {
		doc, err := docMap(l.db.Collection("botMemory").Doc(chat).Get(ctx))
		if err != nil {
			return nil, err
		}
		text := strings.TrimSpace(stringValue(doc["text"]))
		if text == "" {
			return nil, fmt.Errorf("botMemory/%s không có tóm tắt", chat)
		}
		label := string(rune('A' + i))
		fmt.Fprintf(&in, "TÓM TẮT %s:\n", label)
		n := 0
		for _, raw := range strings.Split(text, "\n") {
			if raw = strings.TrimSpace(raw); raw == "" {
				continue
			}
			n++
			ln := LearnMigrationLine{ID: fmt.Sprintf("%s%d", label, n), Chat: chat, Text: raw}
			plan.Lines = append(plan.Lines, ln)
			fmt.Fprintf(&in, "[%s] %s\n", ln.ID, ln.Text)
		}
		in.WriteString("\n")
	}
	resp, err := l.llm.Learn(ctx, learnMigratePrompt, in.String(), learnMigrateSchema)
	if err != nil {
		return nil, fmt.Errorf("agent learn migrate: %w", err)
	}
	var out struct {
		Items   []LearnMigrationItem `json:"items"`
		Dropped []LearnMigrationDrop `json:"dropped"`
	}
	if err := json.Unmarshal([]byte(resp.Text()), &out); err != nil {
		return nil, fmt.Errorf("agent learn migrate: model trả JSON hỏng: %w", err)
	}
	people, err := learnPeople(ctx, l.store, l.chatID)
	if err != nil {
		return nil, err
	}
	covered := map[string]bool{}
	for _, it := range out.Items {
		// Ký ức rỗng hay quá dài thì bỏ, và dòng của nó không tính là đã chuyển.
		it.Text = strings.TrimSpace(it.Text)
		if it.Text == "" || utf8.RuneCountInString(it.Text) > agentMemoryMaxRunes {
			continue
		}
		for _, id := range it.Lines {
			covered[id] = true
		}
		if slices.ContainsFunc(plan.Items, func(p LearnMigrationItem) bool { return p.Text == it.Text }) {
			continue
		}
		it.ID = fmt.Sprintf("mig-%d", len(plan.Items)+1)
		it.Person = strings.TrimSpace(it.Person)
		it.Target, it.Note = agentGroupScope, ""
		if it.Person != "" {
			it.Target, it.Note = people.resolve(it.Person)
		}
		plan.Items = append(plan.Items, it)
	}
	for _, d := range out.Dropped {
		covered[d.Line] = true
		plan.Dropped = append(plan.Dropped, d)
	}
	for _, ln := range plan.Lines {
		if !covered[ln.ID] {
			plan.Uncovered = append(plan.Uncovered, ln.ID)
		}
	}
	return plan, nil
}

// learnPeopleIndex tra tên người trong group Telegram ra doc ký ức của họ.
type learnPeopleIndex map[string]map[string]bool

func learnPersonKey(name string) string {
	return strings.ToLower(strings.Join(strings.Fields(strings.TrimPrefix(strings.TrimSpace(name), "@")), " "))
}

func (p learnPeopleIndex) add(name, target string) {
	if k := learnPersonKey(name); k != "" && target != "" {
		if p[k] == nil {
			p[k] = map[string]bool{}
		}
		p[k][target] = true
	}
}

// resolve chỉ nhận tên khớp đúng một người; trùng tên thì không đoán.
func (p learnPeopleIndex) resolve(name string) (target, note string) {
	targets := p[learnPersonKey(name)]
	switch len(targets) {
	case 0:
		return "", "không thấy tên trong group Telegram"
	case 1:
		for t := range targets {
			return t, ""
		}
	}
	keys := make([]string, 0, len(targets))
	for t := range targets {
		keys = append(keys, t)
	}
	slices.Sort(keys)
	return "", "trùng tên: " + strings.Join(keys, ", ")
}

// learnPeople chỉ lấy người có mặt trên group Telegram chatID: tóm tắt cũ rút
// từ group, nên tên app của người chưa từng liên kết Telegram dễ trùng nhầm
// hơn là đúng. Người đã liên kết thì theo uid, với tên lúc liên kết, username,
// tên app và tên trong tin; người chưa liên kết thì theo tg id, với tên trong
// tin.
func learnPeople(ctx context.Context, store *AgentStore, chatID string) (learnPeopleIndex, error) {
	people := learnPeopleIndex{}
	links, err := store.db.Collection("tgLinks").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	linked := map[string]string{}
	var uids []string
	for _, d := range links {
		m := d.Data()
		uid := stringValue(m["uid"])
		if uid == "" {
			continue
		}
		linked[d.Ref.ID] = uid
		uids = append(uids, uid)
		people.add(stringValue(m["displayName"]), uid)
		people.add(stringValue(m["username"]), uid)
	}
	names, err := store.displayNames(ctx, uniqueStrings(uids))
	if err != nil {
		return nil, err
	}
	for uid, name := range names {
		if name != "Thành viên" { // tên mặc định khi chưa đặt
			people.add(name, uid)
		}
	}
	if chatID == "" {
		return people, nil
	}
	msgs, err := store.db.Collection("botConversations").Doc(chatID).Collection("botMessages").
		Where("role", "==", string(genai.RoleUser)).Select("name", "tgUserId").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	for _, d := range msgs {
		tg := stringValue(d.Data()["tgUserId"])
		if tg == "" {
			continue
		}
		target := linked[tg]
		if target == "" {
			target = learnTGScope(tg)
		}
		people.add(stringValue(d.Data()["name"]), target)
	}
	return people, nil
}

// ApplyMigration ghi ký ức của plan vào learned/*, mỗi doc một transaction.
// Chạy lại an toàn: ký ức đã có id trong doc thì bỏ qua. Doc đã đủ
// agentLearnedLimit thì phần dư nằm ở Full, không ghi.
func (l *LearnService) ApplyMigration(ctx context.Context, plan *LearnMigration, now time.Time) (LearnMigrationResult, error) {
	var res LearnMigrationResult
	byTarget := map[string][]LearnMigrationItem{}
	var targets []string
	for _, it := range plan.Items {
		if it.Target == "" {
			res.Unmatched = append(res.Unmatched, it.ID)
			continue
		}
		if byTarget[it.Target] == nil {
			targets = append(targets, it.Target)
		}
		byTarget[it.Target] = append(byTarget[it.Target], it)
	}
	slices.Sort(targets)
	for _, target := range targets {
		ref := learnedCol(l.db).Doc(target)
		var added, existing, full []string
		err := l.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			added, existing, full = nil, nil, nil
			doc, err := docMap(tx.Get(ref))
			if err != nil {
				return err
			}
			facts := liveFacts(doc["facts"], now)
			for _, it := range byTarget[target] {
				switch {
				case slices.ContainsFunc(facts, func(f learnedFact) bool { return f.ID == it.ID }):
					existing = append(existing, it.ID)
				case len(facts) >= agentLearnedLimit:
					full = append(full, it.ID)
				default:
					facts = append(facts, learnedFact{ID: it.ID, Text: it.Text, CreatedAt: now, UpdatedAt: now, Source: learnMigrationSource})
					added = append(added, it.ID)
				}
			}
			if len(added) == 0 {
				return nil
			}
			// MergeAll giữ batch và nextId của task học.
			return tx.Set(ref, map[string]any{"facts": learnedFactMaps(facts), "updatedAt": now}, firestore.MergeAll)
		})
		if err != nil {
			return res, fmt.Errorf("learned/%s: %w", target, err)
		}
		res.Added = append(res.Added, added...)
		res.Existing = append(res.Existing, existing...)
		res.Full = append(res.Full, full...)
	}
	return res, nil
}
