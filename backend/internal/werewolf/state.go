package werewolf

import (
	"fmt"
	"slices"
	"sort"
	"time"
)

// Phase là đoạn giữa hai lần chốt trong một vòng (bảng 1.3). Engine chỉ biết thứ
// tự các đoạn; giờ đồng hồ của từng mốc, chạy bù và pause là việc của máy phase
// (E5), máy này gọi Step khi tới hạn.
type Phase string

const (
	PhaseSetup Phase = "setup" // Start → 22h đêm 1: DM lá bài, Cupid ghép
	PhaseNight Phase = "night" // 22h → 0h: sói chọn; tiên tri, bảo vệ; Cupid nếu là đêm 1
	PhaseDawn  Phase = "dawn"  // 0h → 10h: phù thuỷ; tiên tri, bảo vệ
	PhaseDay   Phase = "day"   // 10h → 20h: đề cử
	PhaseTrial Phase = "trial" // 20h → 22h: biểu quyết
	PhaseEnded Phase = "ended"
)

// Team là phe thắng.
type Team string

const (
	TeamVillage Team = "village"
	TeamWolves  Team = "wolves"
	TeamLovers  Team = "lovers" // cặp đôi Sói–Dân (R6, R24)
)

// Cause là lý do chết, chỉ nằm trong secret/state. Bản tin không nêu (C3).
type Cause string

const (
	CauseBite   Cause = "bite"
	CausePoison Cause = "poison"
	CauseHang   Cause = "hang"
	CauseShot   Cause = "shot"
	CauseLover  Cause = "lover"
	CauseLeft   Cause = "left" // rời PSC hoặc xoá tài khoản (R33)
)

type Player struct {
	Role       Role  `json:"role"`
	Alive      bool  `json:"alive"`
	DeathRound int   `json:"deathRound,omitempty"`
	Cause      Cause `json:"cause,omitempty"`
}

// HunterTurn là lượt bắn của thợ săn vừa chết (R5). Khung giờ do E5 giữ: 10h–12h
// nếu chết trong đêm, 22h–23h nếu chết lúc chốt ngày.
type HunterTurn struct {
	UID   string `json:"uid"`
	Phase Phase  `json:"phase"` // phase lúc mở lượt, để E5 tính giờ đóng
}

// State là toàn bộ trạng thái một ván. Lớp Firestore (W1) tách phần công khai
// sang games/{id}, phần còn lại vào secret/state.
type State struct {
	Config Config `json:"config"`
	Seed   Seed   `json:"seed"`
	Round  int    `json:"round"` // vòng n gồm đêm n và ngày n; setup thuộc vòng 1
	Phase  Phase  `json:"phase"`
	Paused bool   `json:"paused,omitempty"`
	// NightAt là mốc 22h mở đêm của vòng hiện tại; mọi hạn trong vòng tính từ đây
	// (schedule.go). Pause rồi resume thì mốc này dời theo ngày (R14).
	NightAt time.Time `json:"nightAt"`
	// Extra là phần admin dời hạn (Extend) của lượt ExtraKey (một PhaseKey).
	Extra    time.Duration `json:"extra,omitempty"`
	ExtraKey string        `json:"extraKey,omitempty"`
	// Reminded là PhaseKey đã gửi tin nhắc (18h, 21h), để chạy lại không nhắc hai lần.
	Reminded string             `json:"reminded,omitempty"`
	Players  map[string]*Player `json:"players"`

	// Km là snapshot km (mét) của lần chốt 22h gần nhất. Dùng cho kỹ năng của đêm
	// kế tiếp và cho thợ săn (R26, R5).
	Km map[string]float64 `json:"km,omitempty"`

	Lovers       []string `json:"lovers,omitempty"` // 0 hoặc 2 uid, áp lúc 0h đêm 1
	SavePotion   bool     `json:"savePotion"`       // còn bình cứu
	PoisonPotion bool     `json:"poisonPotion"`     // còn bình độc
	LastGuarded  string   `json:"lastGuarded"`      // lần bảo vệ hợp lệ gần nhất đã chốt (R3)
	Bitten       string   `json:"bitten,omitempty"` // sói chốt lúc 0h; phù thuỷ thấy người này (R4)
	// Nominees là những người lên giàn lúc 20h, theo thứ tự phiên biểu quyết
	// (VoteKinds). Nominee là người đầu tiên: state ghi trước khi có nhiều
	// người lên giàn chỉ có field này, và bản cũ của service vẫn đọc nó.
	Nominees []string `json:"nominees,omitempty"`
	Nominee  string   `json:"nominee,omitempty"`

	Hunter *HunterTurn `json:"hunter,omitempty"`
	Winner Team        `json:"winner,omitempty"`
}

// NewState dựng ván lúc Start, sau khi đã chia vai. Đêm 1 là FirstNight(start).
func NewState(seed Seed, cfg Config, roles map[string]Role, start time.Time) *State {
	cfg.Disabled = append([]Role(nil), cfg.Disabled...) // chụp cấu hình (R10)
	st := &State{Config: cfg, Seed: seed, Round: 1, Phase: PhaseSetup, NightAt: FirstNight(start), Players: map[string]*Player{}, SavePotion: true, PoisonPotion: true}
	for uid, r := range roles {
		st.Players[uid] = &Player{Role: r, Alive: true}
	}
	return st
}

// PhaseKey định danh lần chốt kế tiếp, dùng cho CAS ở W1 và làm nhãn ngẫu nhiên.
// Lượt thợ săn có key riêng, vì nó là một lần chốt nằm giữa phase.
func (st *State) PhaseKey() string {
	if st.Hunter != nil {
		return fmt.Sprintf("r%d/%s/hunter", st.Round, st.Phase)
	}
	return fmt.Sprintf("r%d/%s", st.Round, st.Phase)
}

func (st *State) clone() *State {
	c := *st
	c.Players = make(map[string]*Player, len(st.Players))
	for uid, p := range st.Players {
		cp := *p
		c.Players[uid] = &cp
	}
	if st.Km != nil {
		c.Km = make(map[string]float64, len(st.Km))
		for k, v := range st.Km {
			c.Km[k] = v
		}
	}
	c.Lovers = append([]string(nil), st.Lovers...)
	c.Nominees = append([]string(nil), st.Nominees...)
	if st.Hunter != nil {
		h := *st.Hunter
		c.Hunter = &h
	}
	return &c
}

// TrialNominees là những người lên giàn hôm nay, theo thứ tự phiên. State ghi
// trước khi có nhiều người lên giàn chỉ có Nominee.
func (st *State) TrialNominees() []string {
	if len(st.Nominees) > 0 {
		return append([]string(nil), st.Nominees...)
	}
	if st.Nominee != "" {
		return []string{st.Nominee}
	}
	return nil
}

// NomineeOf là người lên giàn của phiên biểu quyết kind, rỗng nếu phiên đó
// không có ai (hoặc kind không phải biểu quyết).
func (st *State) NomineeOf(kind Kind) string {
	i := slices.Index(voteKinds, kind)
	if nominees := st.TrialNominees(); i >= 0 && i < len(nominees) {
		return nominees[i]
	}
	return ""
}

// setNominees ghi người lên giàn, cả Nominee cho bản đọc cũ.
func (st *State) setNominees(uids []string) {
	st.Nominees, st.Nominee = uids, ""
	if len(uids) > 0 {
		st.Nominee = uids[0]
	}
}

func (st *State) alive(uid string) bool {
	p := st.Players[uid]
	return p != nil && p.Alive
}

func (st *State) role(uid string) Role {
	if p := st.Players[uid]; p != nil {
		return p.Role
	}
	return ""
}

// aliveUIDs trả người còn sống, sort theo uid để mọi lần rút ngẫu nhiên tất định.
func (st *State) aliveUIDs() []string {
	var out []string
	for uid, p := range st.Players {
		if p.Alive {
			out = append(out, uid)
		}
	}
	sort.Strings(out)
	return out
}

// loverOf trả người yêu của uid, rỗng nếu uid không ở trong cặp.
func (st *State) loverOf(uid string) string {
	if len(st.Lovers) != 2 {
		return ""
	}
	switch uid {
	case st.Lovers[0]:
		return st.Lovers[1]
	case st.Lovers[1]:
		return st.Lovers[0]
	}
	return ""
}

// mixedCouple: cặp đôi một Sói một không phải Sói thành phe thứ ba (R6). Hai Sói
// vẫn là phe Sói, hai Dân vẫn là phe Dân.
func (st *State) mixedCouple() bool {
	if len(st.Lovers) != 2 {
		return false
	}
	return (st.role(st.Lovers[0]) == Wolf) != (st.role(st.Lovers[1]) == Wolf)
}

// unitMeters là X đổi ra mét. KmPerUnit = 0 nghĩa là mặc định 1 km.
func (c Config) unitMeters() float64 {
	if c.KmPerUnit == 0 {
		return 1000
	}
	return c.KmPerUnit * 1000
}

func (st *State) hasKm(uid string) bool {
	return st.Km[uid] >= st.Config.unitMeters()
}

// TeamOf là phe của uid khi xét thắng thua: hai người trong cặp Sói–Dân thành
// phe ba (R23, R24), còn lại theo vai.
func (st *State) TeamOf(uid string) Team {
	if st.mixedCouple() && st.loverOf(uid) != "" {
		return TeamLovers
	}
	if st.role(uid) == Wolf {
		return TeamWolves
	}
	return TeamVillage
}

// Winners là uid phe thắng, kể cả người đã chết, theo thứ tự uid. Ván chưa có
// phe thắng thì rỗng.
func (st *State) Winners() []string {
	if st.Winner == "" {
		return nil
	}
	var out []string
	for uid := range st.Players {
		if st.TeamOf(uid) == st.Winner {
			out = append(out, uid)
		}
	}
	sort.Strings(out)
	return out
}

// Peek là kết quả soi của tiên tri: Sói hay Dân. Sói đang yêu vẫn ra Sói (R2).
func (st *State) Peek(target string) Team {
	return Side(st.role(target))
}

// Side là phe lộ ra khi chỉ nói Sói hay Dân chứ không nói vai: tiên tri soi,
// hay người bị treo. Không xét cặp đôi, nên Sói đang yêu vẫn ra Sói.
func Side(r Role) Team {
	if r == Wolf {
		return TeamWolves
	}
	return TeamVillage
}
