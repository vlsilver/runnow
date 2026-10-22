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
// nhớ/quên và tra web. Kênh app và Telegram cùng đi qua task agent-dm (kèm
// channel) và agent-turn (kèm roomID); lõi chỉ dùng kênh để chọn chỗ đọc lịch
// sử và chỗ ghi câu trả lời.

const (
	agentDMHistory    = 20
	agentRoomHistory  = 40
	agentToolRounds   = 3
	agentReplyMaxRune = 600
	// Các giới hạn dưới là mặc định; admin sửa được ở agentState/config (xem
	// agentConfigFields).
	agentDMDailyMax   = 100 // trần câu trả lời chat riêng mỗi người mỗi ngày
	agentDMBaseDaily  = 10  // câu trả lời chat riêng có sẵn mỗi ngày
	agentDMPerKm      = 10  // câu trả lời thêm cho mỗi km chạy trọn hôm nay
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

// agentLLM là phần gọi model, tách ra để test thay bằng model giả. Search là
// lượt grounding riêng, vì GoogleSearch không đi chung với function calling
// trong cùng một request.
type agentLLM interface {
	Generate(ctx context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error)
	Search(ctx context.Context, query string) (*genai.GenerateContentResponse, error)
}

// genaiAgentLLM gọi cùng model với 3i nên dùng chung thinking level và trần
// mỗi lần gọi (xem thinkingConfig, generateWithRetry).
type genaiAgentLLM struct {
	client         *genai.Client
	model          string
	thinking       string
	attemptTimeout time.Duration
}

func (g genaiAgentLLM) Generate(ctx context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error) {
	cfg := &genai.GenerateContentConfig{
		SystemInstruction: &genai.Content{Parts: []*genai.Part{{Text: system}}},
		Tools:             tools,
		ThinkingConfig:    thinkingConfig(g.thinking),
	}
	return generateWithRetry(ctx, g.client, g.model, contents, cfg, g.attemptTimeout)
}

func (g genaiAgentLLM) Search(ctx context.Context, query string) (*genai.GenerateContentResponse, error) {
	return googleSearch(ctx, g.client, g.model, query)
}

type AgentService struct {
	store   *AgentStore
	llm     agentLLM
	enqueue taskPublishFunc
	// chatID là group Telegram của club, để recall_person tra cả người chỉ có
	// trên Telegram; rỗng thì chỉ tra thành viên phòng bot.
	chatID string
	// channelReply gửi câu trả lời chat riêng ra kênh ngoài app; nil thì chỉ
	// ghi Firestore. Xem SetChannelReply.
	channelReply AgentReplyFunc
	// roomOut gửi tin của bot trong phòng ngoài app (tg-psc) ra kênh đó; nil
	// thì chỉ ghi Firestore. Xem SetRoomOut.
	roomOut AgentRoomOutFunc
	// imageGen và imageStore bật tool generate_image; nil thì không vẽ. Xem
	// SetImages.
	imageGen   agentImageLLM
	imageStore agentImageStore
}

// AgentReplyFunc nhận câu trả lời chat riêng của bot ở kênh không phải app
// (Telegram) để gửi ra kênh đó. reply.Seq là seq của câu trả lời trong chat
// riêng của kênh. Hàm có thể bị gọi nhiều lần cho cùng một câu (task chạy lại,
// Cloud Tasks giao trùng), nên phải idempotent theo (uid, channel, reply.Seq),
// ví dụ ghi outbox với doc ID cố định. Trả lỗi thì task agent-dm chạy lại và
// gọi lại hàm với đúng câu đó.
type AgentReplyFunc func(ctx context.Context, uid, channel string, reply AgentMessage) error

// AgentRoomOutFunc nhận tin seq của bot (chủ uid) trong phòng roomID không phải
// main để gửi ra kênh của phòng đó; imagePath khác rỗng là tin kèm ảnh bot vẽ.
// Như AgentReplyFunc, hàm có thể bị gọi nhiều lần cho cùng một tin nên phải
// idempotent theo (roomID, seq); trả lỗi thì task agent-turn chạy lại và gọi lại
// với đúng tin đó.
type AgentRoomOutFunc func(ctx context.Context, roomID string, seq int64, uid, text, imagePath string) error

func NewAgentService(store *AgentStore, llm agentLLM, enqueue taskPublishFunc) *AgentService {
	return &AgentService{store: store, llm: llm, enqueue: enqueue}
}

// SetChannelReply gắn hàm gửi câu trả lời ra kênh ngoài app. Gọi lúc dựng
// dependencies, trước khi nhận task.
func (a *AgentService) SetChannelReply(fn AgentReplyFunc) { a.channelReply = fn }

// SetRoomOut gắn hàm gửi tin của bot ra phòng ngoài app. Gọi lúc dựng
// dependencies, trước khi nhận task.
func (a *AgentService) SetRoomOut(fn AgentRoomOutFunc) { a.roomOut = fn }

// Channel và RoomID bỏ trống khi là app và main, để payload của kênh app giữ
// đúng dạng cũ: bot bản trước giải mã payload với DisallowUnknownFields, gặp
// field lạ là bỏ task. Nhờ vậy api và bot deploy trước sau thế nào cũng được.
type agentDMTask struct {
	UID     string `json:"uid"`
	Seq     int64  `json:"seq"`
	Channel string `json:"channel,omitempty"`
}

type agentTurnTask struct {
	AfterSeq int64  `json:"afterSeq"`
	RoomID   string `json:"roomID,omitempty"`
}

// TaskID của kênh app và phòng main giữ công thức cũ, để task bản trước đã
// enqueue và task bản này cho cùng một tin vẫn khử trùng với nhau. Kênh và
// phòng khác thêm tên vào identity nên seq trùng nhau không đụng ID.
func agentDMTaskFor(uid, channel string, seq int64) PublishTask {
	task, identity := agentDMTask{UID: uid, Seq: seq}, []any{uid, seq}
	if channel != agentChannelApp {
		task.Channel, identity = channel, []any{uid, channel, seq}
	}
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/agent-dm", Payload: task, TaskID: StableTaskID("agent-dm", identity)}
}

func agentTurnTaskFor(roomID string, afterSeq int64, at time.Time) PublishTask {
	task, identity := agentTurnTask{AfterSeq: afterSeq}, any(afterSeq)
	if roomID != agentMainRoom {
		task.RoomID, identity = roomID, []any{roomID, afterSeq}
	}
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/agent-turn", Payload: task, TaskID: StableTaskID("agent-turn", identity), ScheduleTime: &at}
}

func vnDay(t time.Time) string { return t.In(vietnam).Format("20060102") }

const agentDMPrompt = `Bạn là "%s", bot cá nhân của %s trong app chạy bộ 3i Run. Đây là chat riêng giữa bạn và chủ của bạn%s.
Chủ dạy bạn về họ, sở thích và kiến thức để bạn nói chuyện thay họ trong "phòng bot", nơi người thật và bot của các thành viên khác cùng chat.

TÍNH CÁCH (chủ viết):
%s

BỘ NHỚ (mỗi dòng: [id] nội dung):
%s%s

CÁCH LÀM:
- Chủ kể điều đáng nhớ lâu dài về họ, về cách bạn nên nói, hay kiến thức họ muốn bạn biết thì gọi remember. Mỗi mục một ý, viết gọn ở ngôi thứ ba ("Chủ thích..."), không chép nguyên cả đoạn.
- Điều đã nhớ mà nay đổi thì gọi update_memory đúng id. Chủ bảo quên thì gọi forget.
- Không nhớ chuyện vặt lúc tán gẫu, mật khẩu, số tài khoản, hay thông tin nhạy cảm của người khác.
- Mọi thứ trong bộ nhớ có thể được dùng khi bạn chat trong phòng bot. Chủ kể chuyện riêng tư mà muốn bạn nhớ thì nhắc họ điều đó.
- Chủ hỏi thông tin thực tế hay mới mà bạn không chắc (giải chạy, thời tiết, tin tức, địa điểm, giá) thì gọi web_search rồi trả lời bằng giọng của bạn, có thể dẫn 1 nguồn. Không đưa kết quả tra web vào bộ nhớ.
- Chủ hỏi về buổi chạy, số km hôm nay hay kèo thì gọi get_owner_today, get_owner_recent_run, get_owner_contracts hoặc get_club_contracts rồi trả lời bằng số tool trả về, không đoán số. Muốn rủ chủ chạy thì xem số hôm nay trước.
- Trả lời ngắn, tự nhiên, bằng tiếng Việt, đúng tính cách ở trên. Nhớ, sửa hay quên xong thì nói ngắn cho chủ biết đã làm gì.`

// agentDMWhere nói chat riêng đang ở đâu; kênh app để trống, giữ nguyên prompt cũ.
var agentDMWhere = map[string]string{agentChannelApp: "", agentChannelTelegram: " trên Telegram, qua tài khoản Telegram riêng của bạn"}

const agentRoomPrompt = `Bạn là "%s", bot cá nhân của %s, đang chat trong phòng bot của app 3i Run. Trong phòng có người thật và bot của từng thành viên. Bạn nói theo cách của chủ mình, nhưng bạn là bot, không giả làm chính chủ.

TÍNH CÁCH (chủ viết):
%s

ĐIỀU BẠN BIẾT VỀ CHỦ VÀ KIẾN THỨC CỦA BẠN:
%s%s

THÀNH VIÊN TRONG PHÒNG:
%s

LUẬT:
- Viết đúng MỘT tin tiếp theo của bạn, 1 đến 3 câu, tiếng Việt tự nhiên như chat nhóm. Không mở đầu bằng tên mình.
- Đáp người vừa nói hoặc tiếp chủ đề đang bàn; muốn hỏi ai thì gọi tên người hay bot đó.
- Không lặp lại ý đã nói. Câu chuyện đã cạn, hoặc tin vừa rồi không cần bạn đáp, thì trả đúng ` + agentPass + `.
- Không bịa chuyện về chủ ngoài những gì bạn biết. Không nói xấu, không công kích ai.
- Muốn nhắc tới buổi chạy, số km hay kèo thì gọi tool đọc số rồi mới nói, và chỉ nói số tool trả về. Không có tool đọc số của chủ nghĩa là chủ để hồ sơ riêng tư, nên đừng nói số của chủ.
- Chỉ gọi web_search khi có người trong phòng hỏi thông tin thực tế hay mới mà bạn không chắc (giải chạy, thời tiết, tin tức, địa điểm); tra xong thì trả lời bằng giọng của bạn, có thể dẫn 1 nguồn. Tán gẫu thì không tra.`

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

var agentWebSearchDecl = &genai.FunctionDeclaration{
	Name:        "web_search",
	Description: "Tra Google lấy thông tin thực tế hay mới: giải chạy, thời tiết, tin tức, địa điểm, giá. Trả câu trả lời kèm nguồn.",
	Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
		"query": {Type: genai.TypeString, Description: "Câu tìm đủ ngữ cảnh, vd 'thời tiết Hà Nội sáng 21/10/2026'."},
	}, Required: []string{"query"}},
}

func agentRoomTools() []*genai.Tool {
	return []*genai.Tool{{FunctionDeclarations: []*genai.FunctionDeclaration{agentWebSearchDecl}}}
}

func agentDMTools() []*genai.Tool {
	str := func(desc string) *genai.Schema { return &genai.Schema{Type: genai.TypeString, Description: desc} }
	return []*genai.Tool{{FunctionDeclarations: []*genai.FunctionDeclaration{
		agentWebSearchDecl,
		{Name: "remember", Description: "Thêm một mục vào bộ nhớ lâu dài của bot.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"text": str("Nội dung cần nhớ, một ý, tối đa 500 ký tự.")}, Required: []string{"text"}}},
		{Name: "update_memory", Description: "Sửa một mục đã nhớ.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"id": str("id của mục, trong ngoặc vuông ở BỘ NHỚ."), "text": str("Nội dung mới.")}, Required: []string{"id", "text"}}},
		{Name: "forget", Description: "Xoá một mục đã nhớ.", Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{"id": str("id của mục cần xoá.")}, Required: []string{"id"}}},
	}}}
}

// ReplyDM trả lời tin seq của chủ trong chat riêng của kênh channel. Chạy lại
// an toàn: tin đã trả lời thì bỏ; mục nhớ thêm bằng tool có id cố định theo
// kênh và seq nên không nhân đôi. Chủ đã gửi tin mới hơn thì bỏ, task của tin
// mới trả lời gộp. Kênh ngoài app thì câu trả lời đi tiếp qua channelReply,
// kể cả khi task chạy lại sau khi đã ghi, để lần gửi trước lỗi được gửi lại.
func (a *AgentService) ReplyDM(ctx context.Context, uid, channel string, seq int64, wall time.Time) error {
	ch, ok := agentDMChannels[channel]
	if !ok {
		return fmt.Errorf("agent dm: không có kênh %q", channel)
	}
	ref := a.store.agentRef(uid)
	doc, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil // chủ đã xoá tài khoản
	}
	if err != nil {
		return err
	}
	d := doc.Data()
	if answered := int64(number(d[ch.answeredField])); answered >= seq || int64(number(d[ch.userSeqField])) != seq {
		if answered == seq {
			return a.redeliverDMReply(ctx, uid, ch, seq)
		}
		return nil
	}
	// Trần câu trả lời mỗi ngày đếm chung mọi kênh, vì chi phí tính theo người.
	allowed, quota, err := a.consumeDMBudget(ctx, uid, wall)
	if err != nil {
		return err
	}
	reply, image := dmLimitReply(quota), ""
	if allowed {
		reply, image, err = a.dmAnswer(ctx, uid, ch, seq, stringValue(d["name"]), stringValue(d["persona"]), wall)
		// Chạm trần chi phí giữa chừng (kể cả sau vòng tool đầu) thì vẫn trả câu
		// nghỉ, để tin của chủ không treo ở "đang gõ" tới ngày mai.
		if errors.Is(err, errAgentOverBudget) {
			reply, image, err = agentBudgetReply, "", nil
		}
		if err != nil {
			return err
		}
	}
	msg, written, err := a.store.AppendDMReply(ctx, uid, ch, seq, reply, image, wall)
	if err != nil || !written {
		return err
	}
	return a.deliverDMReply(ctx, uid, ch, msg)
}

func (a *AgentService) deliverDMReply(ctx context.Context, uid string, ch agentDMChannel, reply AgentMessage) error {
	if ch.name == agentChannelApp || a.channelReply == nil {
		return nil // app đọc thẳng Firestore
	}
	return a.channelReply(ctx, uid, ch.name, reply)
}

// redeliverDMReply gửi lại câu trả lời đã ghi cho tin seq (luôn ở seq+1, xem
// AppendDMReply), cho trường hợp lần chạy trước ghi xong mà gửi lỗi.
func (a *AgentService) redeliverDMReply(ctx context.Context, uid string, ch agentDMChannel, seq int64) error {
	if ch.name == agentChannelApp || a.channelReply == nil {
		return nil
	}
	doc, err := a.store.agentRef(uid).Collection(ch.collection).Doc(seqDocID(seq + 1)).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	reply := dmMessage(doc.Data())
	if reply.Role != agentRoleAgent {
		return nil
	}
	return a.deliverDMReply(ctx, uid, ch, reply)
}

// consumeDMBudget đếm câu trả lời chat riêng trong ngày (giờ VN) trên doc bot,
// chặn ở hạn mức theo km hôm nay. Km đọc ngoài transaction: hai tin cùng lúc
// vẫn bị transaction chặn ở cùng một max, còn km đổi giữa chừng (buổi chạy mới
// đồng bộ, buổi trùng bị bỏ) chỉ lệch mốc ở đúng tin đó.
func (a *AgentService) consumeDMBudget(ctx context.Context, uid string, wall time.Time) (bool, agentDMQuota, error) {
	lim, err := a.store.limits(ctx)
	if err != nil {
		return false, agentDMQuota{}, err
	}
	q, err := a.store.dmQuota(ctx, lim, uid, wall)
	if err != nil {
		return false, agentDMQuota{}, err
	}
	ref, allowed := a.store.agentRef(uid), false
	err = a.store.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		day, count := vnDay(wall), int64(0)
		if stringValue(doc.Data()["dmDay"]) == day {
			count = int64(number(doc.Data()["dmDayCount"]))
		}
		if allowed = count < q.max; !allowed {
			return nil
		}
		return tx.Update(ref, []firestore.Update{{Path: "dmDay", Value: day}, {Path: "dmDayCount", Value: count + 1}})
	})
	return allowed, q, err
}

// dmAnswer trả câu trả lời và đường dẫn ảnh bot vẽ cho tin này (rỗng là không
// có ảnh).
func (a *AgentService) dmAnswer(ctx context.Context, uid string, ch agentDMChannel, seq int64, name, persona string, wall time.Time) (string, string, error) {
	names, err := a.store.displayNames(ctx, []string{uid})
	if err != nil {
		return "", "", err
	}
	mems, err := a.store.Memories(ctx, uid)
	if err != nil {
		return "", "", err
	}
	history, err := a.store.dmHistory(ctx, uid, ch, seq, agentDMHistory)
	if err != nil {
		return "", "", err
	}
	owner, err := a.store.learnedOf(ctx, []string{uid}, wall)
	if err != nil {
		return "", "", err
	}
	group, err := a.store.learnedGroup(ctx, wall)
	if err != nil {
		return "", "", err
	}
	learned := learnedBlock(owner[uid], group, nil, true)
	system := fmt.Sprintf(agentDMPrompt, name, names[uid], agentDMWhere[ch.name], personaText(persona), memoryLines(mems, true), learned)
	runData, err := a.runData(ctx, uid, names[uid], false, wall)
	if err != nil {
		return "", "", err
	}
	msgKey := fmt.Sprintf("%s%d", ch.memoryPrefix, seq)
	var images *agentImageTurn
	if ch.name == agentChannelTelegram {
		images = a.imageTurn(uid, msgKey, true, wall)
	}
	if images != nil {
		system += agentDMImageRule
	}
	tools := agentDMTools()
	if learned != "" {
		tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, agentRecallPersonDecl, agentForgetLearnedDecl)
	}
	tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, runData.decls()...)
	tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, images.decls()...)
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
		contents = append(contents, &genai.Content{Role: role, Parts: []*genai.Part{{Text: withImageNote(m.Text, m.ImagePath)}}})
	}
	added := 0
	// Gán lại ctx để lượt web_search trong closure cũng mang nhãn agent.dm.
	ctx = withLLMLabel(ctx, "agent.dm", uid)
	text, err := a.toolLoop(ctx, "agent dm", system, contents, tools, func(call *genai.FunctionCall) (map[string]any, error) {
		switch call.Name {
		case agentWebSearchDecl.Name:
			return a.webSearch(ctx, call), nil
		case agentRecallPersonDecl.Name:
			return a.recallPerson(ctx, call, wall)
		}
		if out, ok, err := runData.run(ctx, call); ok {
			return out, err
		}
		if out, ok, err := images.run(ctx, call); ok {
			return out, err
		}
		return a.runMemoryTool(ctx, uid, msgKey, &added, call, wall)
	})
	if err != nil {
		return "", "", err
	}
	if text == "" && images.imagePath() == "" {
		return "", "", errors.New("agent dm: model không trả lời")
	}
	// Che từ tục như câu bot nói trong phòng (cleanRoomReply), không gọi lại model.
	return maskProfanity(truncateRunes(text, agentReplyMaxRune)), images.imagePath(), nil
}

// toolLoop gọi model, chạy các tool nó gọi rồi gọi lại, tới khi model trả chữ
// hoặc hết agentToolRounds vòng. Lỗi từ run thì dừng để task chạy lại.
func (a *AgentService) toolLoop(ctx context.Context, label, system string, contents []*genai.Content, tools []*genai.Tool, run func(*genai.FunctionCall) (map[string]any, error)) (string, error) {
	for round := 0; round < agentToolRounds; round++ {
		resp, err := a.llm.Generate(ctx, system, contents, tools)
		if err != nil {
			return "", fmt.Errorf("%s llm: %w", label, err)
		}
		calls := resp.FunctionCalls()
		if len(calls) == 0 {
			return strings.TrimSpace(resp.Text()), nil
		}
		if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil {
			return "", fmt.Errorf("%s: model trả về rỗng", label)
		}
		contents = append(contents, resp.Candidates[0].Content)
		results := make([]*genai.Part, 0, len(calls))
		for _, call := range calls {
			out, err := run(call)
			if err != nil {
				return "", err
			}
			results = append(results, genai.NewPartFromFunctionResponse(call.Name, out))
		}
		contents = append(contents, &genai.Content{Role: genai.RoleUser, Parts: results})
	}
	return "", fmt.Errorf("%s: model gọi tool quá %d vòng", label, agentToolRounds)
}

// runMemoryTool chạy một lệnh nhớ/sửa/quên. Mục thêm mới có id msgKey-n theo
// tin đang trả lời (msgKey như "dm5", "tg5"), để task chạy lại ghi đè chứ không
// nhân đôi, và seq trùng nhau ở hai kênh không ghi đè mục của nhau. Lỗi nghiệp
// vụ (bộ nhớ đầy, mục không còn, nội dung sai) trả vào cho model để nó báo chủ;
// lỗi Firestore thì dừng để task chạy lại.
func (a *AgentService) runMemoryTool(ctx context.Context, uid, msgKey string, added *int, call *genai.FunctionCall, wall time.Time) (map[string]any, error) {
	arg := func(k string) string { return strings.TrimSpace(stringValue(call.Args[k])) }
	var err error
	out := map[string]any{"ok": true}
	switch call.Name {
	case "remember":
		*added++
		var m AgentMemory
		m, err = a.store.AddMemory(ctx, uid, fmt.Sprintf("%s-%d", msgKey, *added), arg("text"), agentSourceChat, wall)
		out["id"] = m.ID
	case "update_memory":
		_, err = a.store.UpdateMemory(ctx, uid, arg("id"), arg("text"), wall)
	case "forget":
		err = a.store.DeleteMemory(ctx, uid, arg("id"))
	case agentForgetLearnedDecl.Name:
		err = a.store.ForgetLearnedFact(ctx, uid, arg("id"), wall)
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

// webSearch chạy tool web_search. Tra hỏng thì báo cho model để nó xin lỗi
// người hỏi, như web_search của bot 3i, thay vì bắt cả câu trả lời chạy lại.
func (a *AgentService) webSearch(ctx context.Context, call *genai.FunctionCall) map[string]any {
	query := strings.TrimSpace(stringValue(call.Args["query"]))
	if query == "" {
		return map[string]any{"ok": false, "reason": "thiếu query"}
	}
	resp, err := a.llm.Search(ctx, query)
	if err != nil {
		slog.WarnContext(ctx, "agent.web_search_failed", "error", err)
		return map[string]any{"ok": false, "reason": "tra web hỏng, xin lỗi và bảo thử lại sau"}
	}
	slog.InfoContext(ctx, "agent.web_search")
	return groundedResult(resp)
}

func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return strings.TrimSpace(string(r[:max]))
}

// RoomTurn cho một bot nói tiếp sau tin afterSeq trong phòng roomID. Task cũ
// (đã có tin mới hơn) thì bỏ, vì tin mới có task riêng. Ghi xong thì gửi tin ra
// kênh của phòng (phòng ngoài app) rồi hẹn lượt kế nếu chuỗi bot chưa chạm
// chainMax. Chạy lại an toàn: turnOf cho biết lượt này đã ghi, khi đó chỉ gửi
// lại tin đã ghi và hẹn lại lượt kế. Seq, chuỗi và trần ngày nằm trên doc
// của từng phòng, nên chainMax và roomDailyMax tính riêng cho mỗi phòng.
func (a *AgentService) RoomTurn(ctx context.Context, roomID string, afterSeq int64, wall time.Time) error {
	if _, ok := agentRoomChannels[roomID]; !ok {
		return fmt.Errorf("agent room: không có phòng %q", roomID)
	}
	ref := a.store.roomRef(roomID)
	doc, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	room := doc.Data()
	lim, err := a.store.limits(ctx)
	if err != nil {
		return err
	}
	seq := int64(number(room["seq"]))
	if turnOf, ok := room["turnOf"]; ok && int64(number(turnOf)) == afterSeq {
		// Lần trước có thể đã ghi mà gửi lỗi; gửi lại kể cả khi đã có tin mới
		// hơn, vì tin của bot vẫn đứng ở afterSeq+1.
		if err := a.redeliverRoomTurn(ctx, roomID, afterSeq+1); err != nil {
			return err
		}
		if seq == afterSeq+1 {
			return a.scheduleNext(ctx, lim, roomID, room, seq, wall)
		}
		return nil
	}
	if seq != afterSeq || int64(number(room["chain"])) >= lim.chainMax || roomBudgetLeft(lim, room, wall) <= 0 {
		return nil
	}
	acc, err := a.store.access(ctx)
	if err != nil {
		return err
	}
	transcript, err := a.store.roomTranscript(ctx, roomID, afterSeq, agentRoomHistory)
	if err != nil {
		return err
	}
	if len(transcript) == 0 {
		return nil
	}
	agents, err := a.store.roomSpeakers(ctx, roomID, acc, lastHuman(transcript))
	if err != nil {
		return err
	}
	speaker, ok := pickSpeaker(agents, room, transcript[len(transcript)-1])
	if !ok {
		return nil
	}
	text, image, err := a.roomReply(ctx, roomID, speaker, agents, acc.roster(agents), transcript, wall)
	if errors.Is(err, errAgentOverBudget) {
		// Chạm trần chi phí: một bot báo nghỉ rồi dừng chuỗi, không hẹn lượt kế,
		// để mỗi tin người chỉ nhận một câu nghỉ chứ không phải chainMax câu.
		// Task chạy lại sau khi đã ghi thì vẫn hẹn lượt kế (nhánh turnOf ở trên),
		// nên lượt kế thấy câu nghỉ đứng cuối thì thôi.
		if last := transcript[len(transcript)-1]; stringValue(last["kind"]) == agentKindAgent && stringValue(last["text"]) == agentBudgetReply {
			return nil
		}
		written, err := a.store.appendRoomTurn(ctx, lim, roomID, afterSeq, speaker, agentBudgetReply, "", wall)
		if err != nil || !written {
			return err
		}
		return a.deliverRoomTurn(ctx, roomID, afterSeq+1, speaker.uid, agentBudgetReply, "")
	}
	if err != nil {
		return err
	}
	if text == "" && image == "" {
		slog.InfoContext(ctx, "agent.room_pass", "room", roomID, "afterSeq", afterSeq, "speaker", speaker.uid)
		return nil
	}
	written, err := a.store.appendRoomTurn(ctx, lim, roomID, afterSeq, speaker, text, image, wall)
	if err != nil || !written {
		return err
	}
	if err := a.deliverRoomTurn(ctx, roomID, afterSeq+1, speaker.uid, text, image); err != nil {
		return err
	}
	room["chain"] = number(room["chain"]) + 1
	return a.scheduleNext(ctx, lim, roomID, room, afterSeq+1, wall)
}

// deliverRoomTurn gửi tin seq của bot ra kênh của phòng. Phòng main thì app
// đọc thẳng Firestore.
func (a *AgentService) deliverRoomTurn(ctx context.Context, roomID string, seq int64, uid, text, imagePath string) error {
	if roomID == agentMainRoom || a.roomOut == nil {
		return nil
	}
	return a.roomOut(ctx, roomID, seq, uid, text, imagePath)
}

// redeliverRoomTurn gửi lại tin seq đã ghi, nếu đó là tin của bot.
func (a *AgentService) redeliverRoomTurn(ctx context.Context, roomID string, seq int64) error {
	if roomID == agentMainRoom || a.roomOut == nil {
		return nil
	}
	doc, err := a.store.roomRef(roomID).Collection("messages").Doc(seqDocID(seq)).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	m := doc.Data()
	if stringValue(m["kind"]) != agentKindAgent {
		return nil
	}
	return a.roomOut(ctx, roomID, seq, stringValue(m["uid"]), stringValue(m["text"]), stringValue(m["imagePath"]))
}

func (a *AgentService) scheduleNext(ctx context.Context, lim agentLimits, roomID string, room map[string]any, seq int64, wall time.Time) error {
	if int64(number(room["chain"])) >= lim.chainMax || a.enqueue == nil {
		return nil
	}
	_, err := a.enqueue(ctx, agentTurnTaskFor(roomID, seq, wall.Add(agentTurnDelay)))
	return err
}

// roomUsedToday là số tin bot đã nói hôm nay (giờ VN).
func roomUsedToday(room map[string]any, wall time.Time) int64 {
	if stringValue(room["day"]) != vnDay(wall) {
		return 0
	}
	return int64(number(room["dayCount"]))
}

func roomBudgetLeft(lim agentLimits, room map[string]any, wall time.Time) int64 {
	return lim.roomDailyMax - roomUsedToday(room, wall)
}

// lastHuman là uid của người nhắn gần nhất trong transcript, rỗng nếu không có.
func lastHuman(transcript []map[string]any) string {
	for i := len(transcript) - 1; i >= 0; i-- {
		if stringValue(transcript[i]["kind"]) == agentKindHuman {
			return stringValue(transcript[i]["uid"])
		}
	}
	return ""
}

// pickSpeaker chọn bot nói tiếp: không phải bot vừa nói; bot mà tin cuối reply
// hay @nhắc trên Telegram đi trước, rồi tới bot được gọi tên trong tin cuối;
// còn lại là bot lâu chưa nói nhất, hoà thì theo uid.
func pickSpeaker(agents []roomAgent, room map[string]any, last map[string]any) (roomAgent, bool) {
	if ag, ok := addressedBot(agents, last); ok {
		return ag, true
	}
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

// addressedBot là bot con mà tin người last reply tới, hay được @username trong
// tin đó. Chỉ có ở phòng tg-psc, nơi roomAgent mang botID và username.
func addressedBot(agents []roomAgent, last map[string]any) (roomAgent, bool) {
	if stringValue(last["kind"]) != agentKindHuman {
		return roomAgent{}, false
	}
	if to := stringValue(last["replyToBot"]); to != "" {
		for _, ag := range agents {
			if ag.botID == to {
				return ag, true
			}
		}
	}
	text := strings.ToLower(stringValue(last["text"]))
	for _, ag := range agents {
		if ag.username != "" && mentions(text, strings.ToLower(ag.username)) {
			return ag, true
		}
	}
	return roomAgent{}, false
}

// mentions: text có "@username" đứng riêng, không phải phần đầu của username
// dài hơn (@a_bot không khớp @a_bot2). Username Telegram chỉ có [a-z0-9_].
func mentions(text, username string) bool {
	tag := "@" + username
	for i := strings.Index(text, tag); i >= 0; {
		end := i + len(tag)
		if end == len(text) || !isUsernameByte(text[end]) {
			return true
		}
		j := strings.Index(text[end:], tag)
		if j < 0 {
			return false
		}
		i = end + j
	}
	return false
}

func isUsernameByte(c byte) bool {
	return c == '_' || ('a' <= c && c <= 'z') || ('0' <= c && c <= '9')
}

// roomReply trả tin tiếp theo của speaker và đường dẫn ảnh nó vẽ (rỗng là không
// có ảnh). Tin rỗng mà không có ảnh là bot nhường lượt.
func (a *AgentService) roomReply(ctx context.Context, roomID string, speaker roomAgent, agents []roomAgent, members []string, transcript []map[string]any, wall time.Time) (string, string, error) {
	uids := append([]string(nil), members...)
	present := []string{speaker.uid}
	for _, m := range transcript {
		uids = append(uids, stringValue(m["uid"]))
		present = append(present, stringValue(m["uid"]))
	}
	present = uniqueStrings(present)
	names, err := a.store.displayNames(ctx, uniqueStrings(uids))
	if err != nil {
		return "", "", err
	}
	mems, err := a.store.Memories(ctx, speaker.uid)
	if err != nil {
		return "", "", err
	}
	learned, err := a.store.learnedOf(ctx, present, wall)
	if err != nil {
		return "", "", err
	}
	group, err := a.store.learnedGroup(ctx, wall)
	if err != nil {
		return "", "", err
	}
	var others []learnedPerson
	for _, uid := range present[1:] {
		if len(learned[uid]) > 0 {
			others = append(others, learnedPerson{name: names[uid], facts: learned[uid]})
		}
	}
	learnedText := learnedBlock(learned[speaker.uid], group, others, false)
	runData, err := a.runData(ctx, speaker.uid, names[speaker.uid], true, wall)
	if err != nil {
		return "", "", err
	}
	var images *agentImageTurn
	if roomID == agentTelegramRoom {
		// Key theo tin đang đáp; ảnh nằm dưới doc của chủ bot nên bot khác đáp
		// cùng tin không đụng nhau.
		images = a.imageTurn(speaker.uid, fmt.Sprintf("room-%s-%d", roomID, int64(number(transcript[len(transcript)-1]["seq"]))), runData.ownerOK, wall)
	}
	tools := agentRoomTools()
	if learnedText != "" {
		tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, agentRecallPersonDecl)
	}
	tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, runData.decls()...)
	tools[0].FunctionDeclarations = append(tools[0].FunctionDeclarations, images.decls()...)
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
	system := fmt.Sprintf(agentRoomPrompt, speaker.name, names[speaker.uid], personaText(speaker.persona), memoryLines(mems, false), learnedText, strings.TrimRight(roster.String(), "\n"))
	if images != nil {
		system += agentRoomImageRule
	}
	var chat strings.Builder
	chat.WriteString("ĐOẠN CHAT GẦN ĐÂY:\n")
	for _, m := range transcript {
		if stringValue(m["kind"]) == agentKindAgent {
			fmt.Fprintf(&chat, "%s (bot của %s): %s\n", stringValue(m["name"]), names[stringValue(m["uid"])], withImageNote(stringValue(m["text"]), stringValue(m["imagePath"])))
		} else {
			fmt.Fprintf(&chat, "%s (người): %s\n", names[stringValue(m["uid"])], stringValue(m["text"]))
		}
	}
	fmt.Fprintf(&chat, "\nViết tin tiếp theo của %s.", speaker.name)
	ctx = withLLMLabel(ctx, "agent.room_turn", speaker.uid)
	text, err := a.toolLoop(ctx, "agent room", system, []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: chat.String()}}}}, tools, func(call *genai.FunctionCall) (map[string]any, error) {
		switch call.Name {
		case agentWebSearchDecl.Name:
			return a.webSearch(ctx, call), nil
		case agentRecallPersonDecl.Name:
			return a.recallPerson(ctx, call, wall)
		}
		if out, ok, err := runData.run(ctx, call); ok {
			return out, err
		}
		if out, ok, err := images.run(ctx, call); ok {
			return out, err
		}
		return map[string]any{"error": "không có tool " + call.Name}, nil
	})
	if err != nil {
		return "", "", err
	}
	return cleanRoomReply(text, speaker.name), images.imagePath(), nil
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
// vào lúc model đang viết) và còn ngân sách ngày của phòng.
func (s *AgentStore) appendRoomTurn(ctx context.Context, lim agentLimits, roomID string, afterSeq int64, speaker roomAgent, text, imagePath string, wall time.Time) (bool, error) {
	ref := s.roomRef(roomID)
	written := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		written = false
		room, err := readRoom(tx, ref)
		if err != nil {
			return err
		}
		if int64(number(room["seq"])) != afterSeq || int64(number(room["chain"])) >= lim.chainMax || roomBudgetLeft(lim, room, wall) <= 0 {
			return nil
		}
		seq := afterSeq + 1
		msg := map[string]any{"seq": seq, "kind": agentKindAgent, "uid": speaker.uid, "name": speaker.name, "text": text, "channel": agentRoomChannels[roomID], "at": wall}
		if imagePath != "" {
			msg["imagePath"] = imagePath
		}
		if err := tx.Create(ref.Collection("messages").Doc(seqDocID(seq)), msg); err != nil {
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
