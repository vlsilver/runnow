package backend

import (
	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameKmGoal là một mốc km người gọi đang nhắm tới, tính tới lần chốt km 22h kế
// tiếp: mốc đó quyết định phiếu ở phiên treo và kỹ năng của đêm ngay sau. App vẽ
// thanh HaveKm/NeedKm theo Label; Key để app chọn icon, gặp khoá lạ thì vẽ mặc định.
type GameKmGoal struct {
	Key    string  `json:"key"` // vote | vote_top | skill | team_skill
	Label  string  `json:"label"`
	NeedKm float64 `json:"needKm"`
	// HaveKm là km đang gom tới mốc chốt; nil ở ván thử (không đọc buổi chạy thật).
	HaveKm *float64 `json:"haveKm,omitempty"`
}

// skillGoalLabels là câu mốc kỹ năng của vai có lượt cần km riêng từng người.
var skillGoalLabels = map[werewolf.Role]string{
	werewolf.Seer:   "Soi ở đêm tới",
	werewolf.Guard:  "Bảo vệ ở đêm tới",
	werewolf.Witch:  "Dùng thuốc ở đêm tới",
	werewolf.Hunter: "Giữ phát bắn khi ngã",
}

// kmGoals là các mốc km của uid. Rỗng khi uid đã chết, và khi ván tắt km (lúc
// đó VoteMode là flat, SkillMeters là 0, team nil).
func kmGoals(st *werewolf.State, uid string, live *liveKm, team *GameTeamKm) []GameKmGoal {
	me := st.Players[uid]
	if me == nil || !me.Alive {
		return nil
	}
	var have *float64
	if m, ok := live.metersOf(uid); ok {
		k := m / 1000
		have = &k
	}
	var out []GameKmGoal
	unit := kmPerUnit(st.Config)
	if st.CanVote(uid) {
		switch st.Config.VoteMode() {
		case werewolf.VoteCut, werewolf.VoteSolo:
			// Đủ X km thì chắc chắn giữ phiếu: người mất phiếu là n - floor(tổng/X)
			// người ít km nhất, mà người có ≥ X km nằm trong số đó thì tổng ≥ (số
			// được tính + 1)·X, trái với cách đếm.
			out = append(out, GameKmGoal{Key: "vote", Label: "Giữ phiếu biểu quyết", NeedKm: unit, HaveKm: have})
		case werewolf.VoteTop:
			// Chỉ là điều kiện cần: top tính riêng từng phiên, trừ người lên giàn,
			// nên hạng của người gọi chỉ biết lúc chốt (bot báo dự đoán trong group).
			out = append(out, GameKmGoal{Key: "vote_top", Label: "Đủ km để tranh suất x2 phiếu", NeedKm: unit, HaveKm: have})
		}
	}
	if team != nil {
		out = append(out, GameKmGoal{Key: "team_skill", Label: "Phe Sói cắn ở đêm tới", NeedKm: team.Need, HaveKm: team.Today})
	}
	// villageGate mở kỹ năng theo tổng km phe Dân: tổng đó trừ vào bảng km công
	// khai là ra km phe Sói, nên không trả mốc này (câu luật của vai nói cách tính).
	label, ok := skillGoalLabels[me.Role]
	if me.Role == werewolf.Wolf && st.Config.KmTie() && st.Config.VoteMode() == werewolf.VoteSolo {
		// Riêng: phiếu cắn của sói chỉ theo km của chính sói đó.
		label, ok = "Có phiếu cắn ở đêm tới", true
	}
	if me.Role == werewolf.Witch && !st.SavePotion && !st.PoisonPotion {
		ok = false
	}
	if ok && !st.Config.VillageGate && !st.Config.GroupSkills() {
		if need := st.Config.SkillMeters(me.Role) / 1000; need > 0 {
			out = append(out, GameKmGoal{Key: "skill", Label: label, NeedKm: need, HaveKm: have})
		}
	}
	return out
}
