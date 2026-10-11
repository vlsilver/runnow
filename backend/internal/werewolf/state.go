package werewolf

import (
	"fmt"
	"sort"
)

// Phase là đoạn giữa hai lần chốt trong một vòng (bảng 1.3). Engine chỉ biết thứ
// tự các đoạn; giờ đồng hồ của từng mốc, chạy bù và pause là việc của máy phase
// (E5), máy này gọi Step khi tới hạn.
type Phase string

const (
	PhaseSetup Phase = "setup" // Start → 22h đêm 1: DM lá bài, Cupid ghép
	PhaseNight Phase = "night" // 22h → 0h: sói chọn; tiên tri, bảo vệ; Cupid nếu là đêm 1
	PhaseDawn  Phase = "dawn"  // 0h → 10h: phù thuỷ; tiên tri, bảo vệ
	PhaseDay   Phase = "day"   // 10h → 17h: đề cử
	PhaseTrial Phase = "trial" // 17h → 22h: bào chữa, biểu quyết
	PhaseEnded Phase = "ended"
)

// MaxRounds: hết vòng 14 mà chưa ai thắng thì Dân thắng (R13).
const MaxRounds = 14

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
	Config  Config             `json:"config"`
	Seed    Seed               `json:"seed"`
	Round   int                `json:"round"` // vòng n gồm đêm n và ngày n; setup thuộc vòng 1
	Phase   Phase              `json:"phase"`
	Paused  bool               `json:"paused,omitempty"`
	Players map[string]*Player `json:"players"`

	// Km là snapshot km (mét) của lần chốt 22h gần nhất. Dùng cho kỹ năng của đêm
	// kế tiếp và cho thợ săn (R26, R5).
	Km map[string]float64 `json:"km,omitempty"`

	Lovers       []string `json:"lovers,omitempty"`  // 0 hoặc 2 uid, áp lúc 0h đêm 1
	SavePotion   bool     `json:"savePotion"`        // còn bình cứu
	PoisonPotion bool     `json:"poisonPotion"`      // còn bình độc
	LastGuarded  string   `json:"lastGuarded"`       // lần bảo vệ hợp lệ gần nhất đã chốt (R3)
	Bitten       string   `json:"bitten,omitempty"`  // sói chốt lúc 0h; phù thuỷ thấy người này (R4)
	Nominee      string   `json:"nominee,omitempty"` // người lên giàn lúc 17h

	Hunter *HunterTurn `json:"hunter,omitempty"`
	Winner Team        `json:"winner,omitempty"`
}

// NewState dựng ván lúc Start, sau khi đã chia vai.
func NewState(seed Seed, cfg Config, roles map[string]Role) *State {
	cfg.Disabled = append([]Role(nil), cfg.Disabled...) // chụp cấu hình (R10)
	st := &State{Config: cfg, Seed: seed, Round: 1, Phase: PhaseSetup, Players: map[string]*Player{}, SavePotion: true, PoisonPotion: true}
	for uid, r := range roles {
		st.Players[uid] = &Player{Role: r, Alive: true}
	}
	return st
}

// PhaseKey định danh lần chốt kế tiếp, dùng cho CAS ở W1 và làm nhãn ngẫu nhiên.
func (st *State) PhaseKey() string {
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
	if st.Hunter != nil {
		h := *st.Hunter
		c.Hunter = &h
	}
	return &c
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

// Peek là kết quả soi của tiên tri: Sói hay Dân. Sói đang yêu vẫn ra Sói (R2).
func (st *State) Peek(target string) Team {
	if st.role(target) == Wolf {
		return TeamWolves
	}
	return TeamVillage
}
