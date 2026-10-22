package backend

import (
	"context"
	"time"

	"google.golang.org/genai"
)

// Bot cá nhân đọc số chạy và kèo của chủ bằng chính các hàm của 3i, nhưng theo
// uid của chủ chứ không khớp tên. Chat riêng thì luôn đọc được. Trong phòng bot
// thì chỉ khi chủ để hồ sơ công khai, vì câu bot nói ở đó ai cũng đọc; cùng luật
// với tool của 3i và tường thuật live. Kèo của club thì ở đâu cũng đọc được.

var (
	agentOwnerTodayDecl = &genai.FunctionDeclaration{
		Name:        "get_owner_today",
		Description: "Số km chạy, km đi bộ và số bước HÔM NAY (giờ Việt Nam) của chủ bạn.",
		Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
	}
	agentOwnerRunDecl = &genai.FunctionDeclaration{
		Name:        "get_owner_recent_run",
		Description: "Chi tiết một buổi chạy của chủ bạn: ngày, km, pace, nhịp tim, splits từng km. Mặc định buổi gần nhất.",
		Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
			"offset": {Type: genai.TypeInteger, Description: "0 là buổi gần nhất, 1 là buổi trước đó, cứ thế."},
		}},
	}
	agentOwnerContractsDecl = &genai.FunctionDeclaration{
		Name:        "get_owner_contracts",
		Description: "Các kèo chủ bạn đang tham gia và tiến độ của chủ trong từng kèo, kèm giáo án HLV chủ đang theo (coachPlans: số buổi đã tập trên tổng buổi). Trên app giáo án HLV nằm chung danh sách kèo.",
		Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
	}
	agentClubContractsDecl = &genai.FunctionDeclaration{
		Name:        "get_club_contracts",
		Description: "Các kèo đang chạy của club: tên, chỉ tiêu, tiến độ chung, số người tham gia, ngày kết thúc.",
		Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
	}
)

// agentRunData là phần dữ liệu chạy mà bot của uid được đọc trong một lượt.
type agentRunData struct {
	tools *BotTools
	owner memberRow
	// ownerOK là được đọc số của chủ; false thì chỉ đọc kèo của club.
	ownerOK bool
	wall    time.Time
}

// runData dựng phần dữ liệu chạy cho bot của uid. inRoom thì số của chủ chỉ
// có khi hồ sơ của chủ công khai.
func (a *AgentService) runData(ctx context.Context, uid, ownerName string, inRoom bool, wall time.Time) (agentRunData, error) {
	d := agentRunData{tools: NewBotTools(a.store.db), owner: memberRow{uid: uid, Name: ownerName}, ownerOK: true, wall: wall}
	if inRoom {
		profile, err := resolveProfile(ctx, a.store.db, uid)
		if err != nil {
			return agentRunData{}, err
		}
		d.ownerOK = stringValue(profile["profileVisibility"]) == "public"
	}
	return d, nil
}

func (d agentRunData) decls() []*genai.FunctionDeclaration {
	if !d.ownerOK {
		return []*genai.FunctionDeclaration{agentClubContractsDecl}
	}
	return []*genai.FunctionDeclaration{agentOwnerTodayDecl, agentOwnerRunDecl, agentOwnerContractsDecl, agentClubContractsDecl}
}

// run chạy call nếu là tool dữ liệu chạy; ok false khi không phải. Tool về chủ
// mà lượt này không được đọc thì trả lỗi cho model, phòng model gọi tool không
// được khai. Firestore lỗi thì trả lỗi để task chạy lại.
func (d agentRunData) run(ctx context.Context, call *genai.FunctionCall) (out map[string]any, ok bool, err error) {
	var res any
	switch call.Name {
	case agentClubContractsDecl.Name:
		res, err = d.tools.GetRunContracts(ctx, nil)
	case agentOwnerTodayDecl.Name, agentOwnerRunDecl.Name, agentOwnerContractsDecl.Name:
		if !d.ownerOK {
			return map[string]any{"error": "chủ để hồ sơ riêng tư, không nói số của chủ ở đây"}, true, nil
		}
		res, err = d.ownerTool(ctx, call)
	default:
		return nil, false, nil
	}
	if err != nil {
		return nil, true, err
	}
	m, _ := res.(map[string]any)
	return m, true, nil
}

func (d agentRunData) ownerTool(ctx context.Context, call *genai.FunctionCall) (any, error) {
	switch call.Name {
	case agentOwnerRunDecl.Name:
		return d.tools.recentRun(ctx, d.owner, int(number(call.Args["offset"])))
	case agentOwnerContractsDecl.Name:
		return d.tools.memberContracts(ctx, d.owner.uid, d.owner.Name)
	}
	now := d.wall.In(vietnam)
	start := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, vietnam)
	day, err := d.tools.memberDay(ctx, d.owner.uid, start)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"date": dateKey(start), "runKm": day.RunKm, "runCount": day.RunCount,
		"walkKm": day.WalkKm, "steps": day.Steps, "totalKm": day.TotalKm,
	}, nil
}
