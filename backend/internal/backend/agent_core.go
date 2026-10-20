package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Lõi của bot cá nhân: dựng prompt từ persona và bộ nhớ, gọi LLM, chạy tool
// nhớ/quên. Lõi không biết tin đến từ kênh nào; kênh app gọi qua task
// agent-dm và agent-turn, kênh Telegram sau này cũng gọi đúng hai hàm này.

const (
	agentDMHistory    = 20
	agentRoomHistory  = 40
	agentToolRounds   = 3
	agentReplyMaxRune = 600
	agentDMDailyMax   = 100 // câu trả lời chat riêng mỗi người mỗi ngày
	agentRoomDailyMax = 300 // tin bot trong phòng mỗi ngày
	// agentChainMax: sau mỗi tin người, các bot nói với nhau tối đa chừng này tin
	// rồi dừng, chờ người nói tiếp. Chặn vòng lặp bot-bot đốt quota.
	agentChainMax = 6
	// agentTurnDelay giãn các tin bot cho giống người chat và để người kịp chen vào.
	agentTurnDelay      = 6 * time.Second
	agentFirstTurnDelay = 3 * time.Second
	agentPass           = "[PASS]"
	agentBudgetReply    = "Hôm nay mình nói nhiều quá rồi, mai mình nói tiếp nhé."
)

// agentLLM là phần gọi model, tách ra để test thay bằng model giả.
type agentLLM interface {
	Generate(ctx context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error)
}

type genaiAgentLLM struct {
	client *genai.Client
	model  string
}

func (g genaiAgentLLM) Generate(ctx context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error) {
	cfg := &genai.GenerateContentConfig{SystemInstruction: &genai.Content{Parts: []*genai.Part{{Text: system}}}, Tools: tools}
	return g.client.Models.GenerateContent(ctx, g.model, contents, cfg)
}

type AgentService struct {
	store   *AgentStore
	llm     agentLLM
	enqueue taskPublishFunc
}

func NewAgentService(store *AgentStore, llm agentLLM, enqueue taskPublishFunc) *AgentService {
	return &AgentService{store: store, llm: llm, enqueue: enqueue}
}

type agentDMTask struct {
	UID string `json:"uid"`
	Seq int64  `json:"seq"`
}

type agentTurnTask struct {
	AfterSeq int64 `json:"afterSeq"`
}

func agentDMTaskFor(uid string, seq int64) PublishTask {
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/agent-dm", Payload: agentDMTask{UID: uid, Seq: seq}, TaskID: StableTaskID("agent-dm", []any{uid, seq})}
}

func agentTurnTaskFor(afterSeq int64, at time.Time) PublishTask {
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/agent-turn", Payload: agentTurnTask{AfterSeq: afterSeq}, TaskID: StableTaskID("agent-turn", afterSeq), ScheduleTime: &at}
}

func vnDay(t time.Time) string { return t.In(vietnam).Format("20060102") }

const agentDMPrompt = `Bạn là "%s", bot cá nhân của %s trong app chạy bộ 3i Run. Đây là chat riêng giữa bạn và chủ của bạn.
Chủ dạy bạn về họ, sở thích và kiến thức để bạn nói chuyện thay họ trong "phòng bot", nơi người thật và bot của các thành viên khác cùng chat.

TÍNH CÁCH (chủ viết):
%s

BỘ NHỚ (mỗi dòng: [id] nội dung):
%s

CÁCH LÀM:
- Chủ kể điều đáng nhớ lâu dài về họ, về cách bạn nên nói, hay kiến thức họ muốn bạn biết thì gọi remember. Mỗi mục một ý, viết gọn ở ngôi thứ ba ("Chủ thích..."), không chép nguyên cả đoạn.
- Điều đã nhớ mà nay đổi thì gọi update_memory đúng id. Chủ bảo quên thì gọi forget.
- Không nhớ chuyện vặt lúc tán gẫu, mật khẩu, số tài khoản, hay thông tin nhạy cảm của người khác.
- Mọi thứ trong bộ nhớ có thể được dùng khi bạn chat trong phòng bot. Chủ kể chuyện riêng tư mà muốn bạn nhớ thì nhắc họ điều đó.
- Trả lời ngắn, tự nhiên, bằng tiếng Việt, đúng tính cách ở trên. Nhớ, sửa hay quên xong thì nói ngắn cho chủ biết đã làm gì.`

const agentRoomPrompt = `Bạn là "%s", bot cá nhân của %s, đang chat trong phòng bot của app 3i Run. Trong phòng có người thật và bot của từng thành viên. Bạn nói theo cách của chủ mình, nhưng bạn là bot, không giả làm chính chủ.

TÍNH CÁCH (chủ viết):
%s

ĐIỀU BẠN BIẾT VỀ CHỦ VÀ KIẾN THỨC CỦA BẠN:
%s

THÀNH VIÊN TRONG PHÒNG:
%s

LUẬT:
- Viết đúng MỘT tin tiếp theo của bạn, 1 đến 3 câu, tiếng Việt tự nhiên như chat nhóm. Không mở đầu bằng tên mình.
- Đáp người vừa nói hoặc tiếp chủ đề đang bàn; muốn hỏi ai thì gọi tên người hay bot đó.
- Không lặp lại ý đã nói. Câu chuyện đã cạn, hoặc tin vừa rồi không cần bạn đáp, thì trả đúng ` + agentPass + `.
- Không bịa chuyện về chủ ngoài những gì bạn biết. Không nói xấu, không công kích ai.`

func memoryLines(mems []AgentMemory, withID bool) string {
	if len(mems) == 0 {
		return "(chưa có gì)"
	}
	var b strings.Builder
	for _, m := range mems {
		if withID {
			fmt.Fprintf(&b, "[%s] %s\n", m.ID, m.Text)
		} else {
			fmt.Fprintf(&b, "- %s\n", m.Text)
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

func personaText(p string) string {
	if strings.TrimSpace(p) == "" {
		return "(chủ chưa viết; cứ thân thiện, vui vẻ)"
	}
	return p
}

func agentMemoryTools() []*genai.Tool {
	str := func(desc string) *genai.Schema { return &genai.Schema{Type: genai.TypeString, Description: desc} }
	return []*genai.Tool{{FunctionDeclarations: []*genai.FunctionDeclaration{
		{Name: "remember", Description: "Thêm một mục vào bộ nhớ lâu dài của bot.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"text": str("Nội dung cần nhớ, một ý, tối đa 500 ký tự.")}, Required: []string{"text"}}},
		{Name: "update_memory", Description: "Sửa một mục đã nhớ.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"id": str("id của mục, trong ngoặc vuông ở BỘ NHỚ."), "text": str("Nội dung mới.")}, Required: []string{"id", "text"}}},
		{Name: "forget", Description: "Xoá một mục đã nhớ.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"id": str("id của mục cần xoá.")}, Required: []string{"id"}}},
	}}}
}

// ReplyDM trả lời tin seq của chủ trong chat riêng. Chạy lại an toàn: tin đã
// trả lời thì bỏ; mục nhớ thêm bằng tool có id cố định theo seq nên không nhân
// đôi. Chủ đã gửi tin mới hơn thì bỏ, task của tin mới trả lời gộp.
func (a *AgentService) ReplyDM(ctx context.Context, uid string, seq int64, wall time.Time) error {
	ref := a.store.agentRef(uid)
	doc, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil // chủ đã xoá tài khoản
	}
	if err != nil {
		return err
	}
	d := doc.Data()
	if int64(number(d["answeredSeq"])) >= seq || int64(number(d["dmUserSeq"])) != seq {
		return nil
	}
	allowed, err := a.consumeDMBudget(ctx, ref, wall)
	if err != nil {
		return err
	}
	reply := agentBudgetReply
	if allowed {
		if reply, err = a.dmAnswer(ctx, uid, seq, stringValue(d["name"]), stringValue(d["persona"]), wall); err != nil {
			return err
		}
	}
	_, err = a.store.AppendDMReply(ctx, uid, seq, reply, wall)
	return err
}

// consumeDMBudget đếm câu trả lời chat riêng trong ngày (giờ VN) trên doc bot.
func (a *AgentService) consumeDMBudget(ctx context.Context, ref *firestore.DocumentRef, wall time.Time) (bool, error) {
	allowed := false
	err := a.store.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		day, count := vnDay(wall), int64(0)
		if stringValue(doc.Data()["dmDay"]) == day {
			count = int64(number(doc.Data()["dmDayCount"]))
		}
		if allowed = count < agentDMDailyMax; !allowed {
			return nil
		}
		return tx.Update(ref, []firestore.Update{{Path: "dmDay", Value: day}, {Path: "dmDayCount", Value: count + 1}})
	})
	return allowed, err
}

func (a *AgentService) dmAnswer(ctx context.Context, uid string, seq int64, name, persona string, wall time.Time) (string, error) {
	names, err := a.store.displayNames(ctx, []string{uid})
	if err != nil {
		return "", err
	}
	mems, err := a.store.Memories(ctx, uid)
	if err != nil {
		return "", err
	}
	history, err := a.store.dmHistory(ctx, uid, seq, agentDMHistory)
	if err != nil {
		return "", err
	}
	system := fmt.Sprintf(agentDMPrompt, name, names[uid], personaText(persona), memoryLines(mems, true))
	contents := make([]*genai.Content, 0, len(history))
	for _, m := range history {
		// Gemini cần lượt đầu là user; cửa sổ 20 tin có thể cắt ngay tin bot.
		if len(contents) == 0 && m.Role == agentRoleAgent {
			continue
		}
		role := string(genai.RoleUser)
		if m.Role == agentRoleAgent {
			role = string(genai.RoleModel)
		}
		contents = append(contents, &genai.Content{Role: role, Parts: []*genai.Part{{Text: m.Text}}})
	}
	added := 0
	for round := 0; round < agentToolRounds; round++ {
		resp, err := a.llm.Generate(ctx, system, contents, agentMemoryTools())
		if err != nil {
			return "", fmt.Errorf("agent dm llm: %w", err)
		}
		calls := resp.FunctionCalls()
		if len(calls) == 0 {
			text := strings.TrimSpace(resp.Text())
			if text == "" {
				return "", errors.New("agent dm: model không trả lời")
			}
			return truncateRunes(text, agentReplyMaxRune), nil
		}
		if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil {
			return "", errors.New("agent dm: model trả về rỗng")
		}
		contents = append(contents, resp.Candidates[0].Content)
		results := make([]*genai.Part, 0, len(calls))
		for _, call := range calls {
			out, err := a.runMemoryTool(ctx, uid, seq, &added, call, wall)
			if err != nil {
				return "", err
			}
			results = append(results, genai.NewPartFromFunctionResponse(call.Name, out))
		}
		contents = append(contents, &genai.Content{Role: genai.RoleUser, Parts: results})
	}
	return "", fmt.Errorf("agent dm: model gọi tool quá %d vòng", agentToolRounds)
}

// runMemoryTool chạy một lệnh nhớ/sửa/quên. Lỗi nghiệp vụ (bộ nhớ đầy, mục
// không còn, nội dung sai) trả vào cho model để nó báo chủ; lỗi Firestore thì
// dừng để task chạy lại.
func (a *AgentService) runMemoryTool(ctx context.Context, uid string, seq int64, added *int, call *genai.FunctionCall, wall time.Time) (map[string]any, error) {
	arg := func(k string) string { return strings.TrimSpace(stringValue(call.Args[k])) }
	var err error
	out := map[string]any{"ok": true}
	switch call.Name {
	case "remember":
		*added++
		var m AgentMemory
		m, err = a.store.AddMemory(ctx, uid, fmt.Sprintf("dm%d-%d", seq, *added), arg("text"), agentSourceChat, wall)
		out["id"] = m.ID
	case "update_memory":
		_, err = a.store.UpdateMemory(ctx, uid, arg("id"), arg("text"), wall)
	case "forget":
		err = a.store.DeleteMemory(ctx, uid, arg("id"))
	default:
		return map[string]any{"error": "không có tool " + call.Name}, nil
	}
	var httpErr *HTTPError
	if errors.As(err, &httpErr) {
		return map[string]any{"error": httpErr.Message}, nil
	}
	if err != nil {
		return nil, err
	}
	slog.InfoContext(ctx, "agent.memory_tool", "uid", uid, "tool", call.Name)
	return out, nil
}

func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return strings.TrimSpace(string(r[:max]))
}

// RoomTurn cho một bot nói tiếp sau tin afterSeq. Task cũ (đã có tin mới hơn)
// thì bỏ, vì tin mới có task riêng. Ghi xong thì hẹn lượt kế nếu chuỗi bot
// chưa chạm agentChainMax. Chạy lại an toàn: turnOf cho biết lượt này đã ghi,
// khi đó chỉ hẹn lại lượt kế.
func (a *AgentService) RoomTurn(ctx context.Context, afterSeq int64, wall time.Time) error {
	ref := a.store.roomRef(agentMainRoom)
	doc, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	room := doc.Data()
	seq := int64(number(room["seq"]))
	if turnOf, ok := room["turnOf"]; ok && int64(number(turnOf)) == afterSeq {
		if seq == afterSeq+1 {
			return a.scheduleNext(ctx, room, seq, wall)
		}
		return nil
	}
	if seq != afterSeq || int64(number(room["chain"])) >= agentChainMax || roomBudgetLeft(room, wall) <= 0 {
		return nil
	}
	members, err := a.store.members(ctx)
	if err != nil {
		return err
	}
	agents, err := a.store.roomAgents(ctx, members)
	if err != nil {
		return err
	}
	transcript, err := a.store.roomTranscript(ctx, afterSeq, agentRoomHistory)
	if err != nil {
		return err
	}
	if len(transcript) == 0 {
		return nil
	}
	speaker, ok := pickSpeaker(agents, room, transcript[len(transcript)-1])
	if !ok {
		return nil
	}
	text, err := a.roomReply(ctx, speaker, agents, members, transcript)
	if err != nil {
		return err
	}
	if text == "" {
		slog.InfoContext(ctx, "agent.room_pass", "afterSeq", afterSeq, "speaker", speaker.uid)
		return nil
	}
	written, err := a.store.appendRoomTurn(ctx, afterSeq, speaker, text, wall)
	if err != nil || !written {
		return err
	}
	room["chain"] = number(room["chain"]) + 1
	return a.scheduleNext(ctx, room, afterSeq+1, wall)
}

func (a *AgentService) scheduleNext(ctx context.Context, room map[string]any, seq int64, wall time.Time) error {
	if int64(number(room["chain"])) >= agentChainMax || a.enqueue == nil {
		return nil
	}
	_, err := a.enqueue(ctx, agentTurnTaskFor(seq, wall.Add(agentTurnDelay)))
	return err
}

// roomUsedToday là số tin bot đã nói hôm nay (giờ VN).
func roomUsedToday(room map[string]any, wall time.Time) int64 {
	if stringValue(room["day"]) != vnDay(wall) {
		return 0
	}
	return int64(number(room["dayCount"]))
}

func roomBudgetLeft(room map[string]any, wall time.Time) int64 {
	return agentRoomDailyMax - roomUsedToday(room, wall)
}

// pickSpeaker chọn bot nói tiếp: không phải bot vừa nói; bot được gọi tên trong
// tin cuối đi trước; còn lại là bot lâu chưa nói nhất, hoà thì theo uid.
func pickSpeaker(agents []roomAgent, room map[string]any, last map[string]any) (roomAgent, bool) {
	exclude := ""
	if stringValue(last["kind"]) == agentKindAgent {
		exclude = stringValue(last["uid"])
	}
	text := strings.ToLower(stringValue(last["text"]))
	var best *roomAgent
	bestSeq := int64(0)
	for i := range agents {
		ag := &agents[i]
		if ag.uid == exclude {
			continue
		}
		if name := strings.ToLower(strings.TrimSpace(ag.name)); name != "" && strings.Contains(text, name) {
			return *ag, true
		}
		spoke := int64(number(nested(room, "lastSpoke", ag.uid)))
		if best == nil || spoke < bestSeq {
			best, bestSeq = ag, spoke
		}
	}
	if best == nil {
		return roomAgent{}, false
	}
	return *best, true
}

func (a *AgentService) roomReply(ctx context.Context, speaker roomAgent, agents []roomAgent, members []string, transcript []map[string]any) (string, error) {
	uids := append([]string(nil), members...)
	for _, m := range transcript {
		uids = append(uids, stringValue(m["uid"]))
	}
	names, err := a.store.displayNames(ctx, uniqueStrings(uids))
	if err != nil {
		return "", err
	}
	mems, err := a.store.Memories(ctx, speaker.uid)
	if err != nil {
		return "", err
	}
	bots := map[string]string{}
	for _, ag := range agents {
		bots[ag.uid] = ag.name
	}
	var roster strings.Builder
	for _, uid := range members {
		fmt.Fprintf(&roster, "- %s (người)\n", names[uid])
		if b := bots[uid]; b != "" {
			fmt.Fprintf(&roster, "- %s (bot của %s)\n", b, names[uid])
		}
	}
	system := fmt.Sprintf(agentRoomPrompt, speaker.name, names[speaker.uid], personaText(speaker.persona), memoryLines(mems, false), strings.TrimRight(roster.String(), "\n"))
	var chat strings.Builder
	chat.WriteString("ĐOẠN CHAT GẦN ĐÂY:\n")
	for _, m := range transcript {
		if stringValue(m["kind"]) == agentKindAgent {
			fmt.Fprintf(&chat, "%s (bot của %s): %s\n", stringValue(m["name"]), names[stringValue(m["uid"])], stringValue(m["text"]))
		} else {
			fmt.Fprintf(&chat, "%s (người): %s\n", names[stringValue(m["uid"])], stringValue(m["text"]))
		}
	}
	fmt.Fprintf(&chat, "\nViết tin tiếp theo của %s.", speaker.name)
	resp, err := a.llm.Generate(ctx, system, []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: chat.String()}}}}, nil)
	if err != nil {
		return "", fmt.Errorf("agent room llm: %w", err)
	}
	return cleanRoomReply(resp.Text(), speaker.name), nil
}

// cleanRoomReply bỏ phần model hay tự thêm (tên mình ở đầu, ngoặc kép), cắt
// độ dài và che từ tục. Trả rỗng khi bot nhường lượt.
func cleanRoomReply(text, name string) string {
	text = strings.TrimSpace(text)
	if strings.Contains(text, agentPass) {
		return ""
	}
	text = strings.Trim(strings.TrimSpace(stripSpeakerPrefix(text, name)), "\"“”")
	if utf8.RuneCountInString(text) == 0 {
		return ""
	}
	return maskProfanity(truncateRunes(text, agentReplyMaxRune))
}

// stripSpeakerPrefix bỏ tên mình mà model hay chép lại theo dạng dòng trong
// đoạn chat: "Tên (bot của X): ...", "Tên: ..." hoặc "[Tên] ...". Tên chỉ là
// chữ đầu câu ("Tên mình là...") thì giữ nguyên.
func stripSpeakerPrefix(text, name string) string {
	rest, ok := strings.CutPrefix(strings.TrimPrefix(text, "["), name)
	if !ok {
		return text
	}
	rest = strings.TrimPrefix(rest, "]")
	if strings.HasPrefix(rest, " (") {
		if i := strings.Index(rest, "):"); i >= 0 {
			return rest[i+2:]
		}
		return text
	}
	if after, ok := strings.CutPrefix(strings.TrimLeft(rest, " "), ":"); ok {
		return after
	}
	if strings.HasPrefix(text, "[") {
		return rest
	}
	return text
}

func uniqueStrings(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if s != "" && !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

// appendRoomTurn ghi tin của bot nếu phòng vẫn đứng ở afterSeq (không ai chen
// vào lúc model đang viết) và còn ngân sách ngày.
func (s *AgentStore) appendRoomTurn(ctx context.Context, afterSeq int64, speaker roomAgent, text string, wall time.Time) (bool, error) {
	ref := s.roomRef(agentMainRoom)
	written := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		written = false
		room, err := readRoom(tx, ref)
		if err != nil {
			return err
		}
		if int64(number(room["seq"])) != afterSeq || int64(number(room["chain"])) >= agentChainMax || roomBudgetLeft(room, wall) <= 0 {
			return nil
		}
		seq := afterSeq + 1
		if err := tx.Create(ref.Collection("messages").Doc(seqDocID(seq)), map[string]any{"seq": seq, "kind": agentKindAgent, "uid": speaker.uid, "name": speaker.name, "text": text, "channel": agentChannelApp, "at": wall}); err != nil {
			return err
		}
		day := vnDay(wall)
		written = true
		return tx.Set(ref, map[string]any{
			"seq": seq, "chain": int64(number(room["chain"])) + 1, "lastSpeaker": speaker.uid, "turnOf": afterSeq,
			"lastSpoke": map[string]any{speaker.uid: seq},
			"day":       day, "dayCount": roomUsedToday(room, wall) + 1, "updatedAt": wall,
		}, firestore.MergeAll)
	})
	return written, err
}
