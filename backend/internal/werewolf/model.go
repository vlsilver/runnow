// Package werewolf là luật Ma Sói (features/ma_soi_plan.md, mục 1). Mọi hàm ở
// đây là hàm thuần: không đọc Firestore, không gọi đồng hồ, ngẫu nhiên lấy từ
// seed của ván. Nhờ vậy cùng đầu vào luôn ra cùng kết quả, và replay được ván.
package werewolf

import (
	"crypto/rand"
	"errors"
	"fmt"
	"slices"
)

// Role là vai của một người chơi. Giá trị chuỗi được lưu vào Firestore, đừng đổi.
type Role string

const (
	Wolf     Role = "wolf"
	Seer     Role = "seer"
	Guard    Role = "guard"
	Witch    Role = "witch"
	Hunter   Role = "hunter"
	Cupid    Role = "cupid"
	Villager Role = "villager"
	// Vai mở rộng: chỉ có trong bộ bài khi admin bật (Config.Extended).
	Elder Role = "elder"
	Idiot Role = "idiot"
)

// specialRoles theo thứ tự thêm vào khi số người tăng (bảng 1.2).
var specialRoles = []Role{Seer, Guard, Witch, Hunter, Cupid}

// extendedRoles là vai mở rộng, theo thứ tự thêm vào bộ bài. Mỗi vai bật lên
// lấy chỗ của một Dân, nên ván không bật giữ nguyên bộ bài cũ.
var extendedRoles = []Role{Elder, Idiot}

// ExtendedRoles trả các vai mở rộng theo thứ tự cố định.
func ExtendedRoles() []Role { return append([]Role(nil), extendedRoles...) }

// ValidRole: r là một trong các vai ở bảng 1.1, hoặc vai mở rộng.
func ValidRole(r Role) bool {
	return r == Wolf || r == Villager || isSpecial(r) || slices.Contains(extendedRoles, r)
}

func isSpecial(r Role) bool {
	for _, s := range specialRoles {
		if s == r {
			return true
		}
	}
	return false
}

// Config là cấu hình của một ván, chụp vào ván lúc Start và không đổi nữa (R10).
type Config struct {
	// KmPerUnit là X: km cần cho một lượt kỹ năng hoặc một phiếu. 0 nghĩa là
	// dùng mặc định 1 km.
	KmPerUnit float64 `json:"kmPerUnit"`
	// Disabled là các vai đặc biệt admin tắt. Vai bị tắt thành Dân (R8).
	Disabled []Role `json:"disabled,omitempty"`
	TestMode bool   `json:"testMode,omitempty"`
	// NoTelegram: ván chỉ chơi trong app. Bot không đăng gì lên Telegram,
	// đăng ký không cần liên kết Telegram hay ở trong group.
	NoTelegram bool `json:"noTelegram,omitempty"`
	// ExtraWolves là số sói thêm so với bảng 1.2, lấy chỗ của Dân. Sói không
	// vượt 1/3 số người, phần thừa bị bỏ.
	ExtraWolves int `json:"extraWolves,omitempty"`
	// Wolves khác 0 là bộ bài tự chỉnh: đúng Wolves sói (không vượt 1/3 số
	// người) và mọi vai đặc biệt không bị tắt, bỏ qua bảng 1.2 và ExtraWolves.
	Wolves int `json:"wolves,omitempty"`
	// KmOff: ván không dùng km. Kỹ năng không cần km, phiếu nào cũng tính.
	KmOff bool `json:"kmOff,omitempty"`
	// SkillKm là km một vai cần cho một lượt kỹ năng; với Sói là km cho mỗi sói
	// còn sống, tính chung cả phe. Vai không có trong map thì theo KmPerUnit; 0 là
	// không cần km.
	SkillKm map[Role]float64 `json:"skillKm,omitempty"`
	// Vote là cách km tác động lên phiếu biểu quyết; rỗng là VoteCut.
	Vote VoteRule `json:"vote,omitempty"`
	// TopVoters là số người được x2 phiếu của VoteTop, hoặc số người được
	// TopWeight phiếu; 0 là số sói còn sống + 1.
	TopVoters int `json:"topVoters,omitempty"`
	// TopWeight (luật km): bật đặc quyền "Top N được x phiếu" chạy cùng VoteCut
	// hoặc VoteSolo; 0 là tắt. Top tính trên người còn phiếu, gồm cả sói.
	TopWeight int `json:"topWeight,omitempty"`
	// MaxHang là số người lên giàn tối đa mỗi vòng, 1..MaxNominees; 0 là MaxNominees.
	MaxHang int `json:"maxHang,omitempty"`
	// VillageGate: kỹ năng của vai không phải sói mở theo tổng km người không
	// phải sói còn sống (đủ km của vai × số người đó), thay cho km từng người.
	VillageGate bool `json:"villageGate,omitempty"`
	// Schedule là khung giờ hoạt động; nil là lịch gốc: một vòng một ngày, mở
	// đêm lúc 22h.
	Schedule *Schedule `json:"schedule,omitempty"`
	// Extended là các vai mở rộng admin bật, mỗi vai một lá thay cho một Dân.
	Extended []Role `json:"extended,omitempty"`
	// Dark là các đặc quyền phe Sói admin bật (dark.go). DarkKm là km mỗi sói
	// còn sống cần để mở đặc quyền trong đêm; 0 là mặc định 1 km.
	Dark   []DarkPower `json:"dark,omitempty"`
	DarkKm float64     `json:"darkKm,omitempty"`
	// Ruleset là đời luật của ván. Ván tạo trước khi có field này là 0 và giữ
	// luật cũ tới hết ván; ván mới mang RulesetKm.
	Ruleset int `json:"ruleset,omitempty"`
}

// RulesetKm: mọi cuộc bầu (đề cử, Treo/Tha, sói bầu cắn) bằng phiếu thì nhóm
// phiếu có tổng km cao hơn thắng, vẫn bằng thì bốc thăm; sói cắn theo phiếu bầu.
const RulesetKm = 1

func (c Config) KmTie() bool { return c.Ruleset >= RulesetKm }

// GroupSkills: ván luật km chọn Theo nhóm thì vai phe Dân dùng chung km
// (State.skillCut), thay cho VillageGate của ván cũ.
func (c Config) GroupSkills() bool { return c.KmTie() && c.VoteMode() == VoteCut }

// Schedule: mỗi ngày Rounds vòng nối nhau, vòng đầu mở đêm lúc StartHour giờ
// VN, mỗi vòng dài RoundHours tiếng; hết khung thì đợi tới StartHour hôm sau.
// Các mốc trong vòng co giãn theo lịch gốc 24 tiếng (bảng 1.3).
type Schedule struct {
	StartHour  int `json:"startHour"`
	RoundHours int `json:"roundHours"`
	Rounds     int `json:"rounds"`
	// Phases là độ dài (phút) của Đêm, Rạng sáng, Ngày, Biểu quyết, cộng lại
	// đúng RoundHours. Có thì mốc trong mỗi pha co giãn theo pha đó của lịch
	// gốc; nil thì cả vòng co giãn đều như trước.
	Phases []int `json:"phases,omitempty"`
	// RoundPhases là bốn pha riêng của từng vòng trong ngày, theo thứ tự mở
	// từ StartHour; có thì đè Phases. Vòng nào cũng dài đúng RoundHours, nên
	// giờ mở các vòng không đổi, chỉ mốc trong vòng đổi.
	RoundPhases [][]int `json:"roundPhases,omitempty"`
}

// Giới hạn của Phases: pha nào cũng ít nhất MinPhaseMinutes, dời theo bước
// PhaseStepMinutes.
const (
	MinPhaseMinutes  = 60
	PhaseStepMinutes = 30
)

// Giới hạn của Schedule. RoundHours chẵn thì một giờ của lịch gốc thành số
// phút chẵn (RoundHours × 2,5 phút), mốc nào cũng tròn phút.
const (
	MinRoundHours = 4
	MaxRoundHours = 24
)

// VoteRule là cách km tác động lên phiếu biểu quyết. Giá trị chuỗi nằm trong
// config của ván, đừng đổi.
type VoteRule string

const (
	// VoteCut (R30): được tính floor(tổng km / X) phiếu, người ít km nhất mất phiếu.
	VoteCut VoteRule = "cut"
	// VoteTop: không ai mất phiếu; N người chạy nhiều nhất, mỗi người đủ X km,
	// được tính 2 phiếu.
	VoteTop VoteRule = "top"
	// VoteFlat: km không tác động lên phiếu.
	VoteFlat VoteRule = "flat"
	// VoteSolo (luật km): ai đủ X km thì phiếu người đó được tính, không xét tổng.
	VoteSolo VoteRule = "solo"
)

// Giới hạn của TopWeight.
const (
	MinTopWeight = 2
	MaxTopWeight = 5
)

// NomineeSeats là số suất lên giàn mỗi vòng (MaxHang).
func (c Config) NomineeSeats() int {
	if c.MaxHang == 0 {
		return MaxNominees
	}
	return c.MaxHang
}

// VoteMode là luật phiếu đang áp: tắt km thì luôn là VoteFlat.
func (c Config) VoteMode() VoteRule {
	switch {
	case c.KmOff:
		return VoteFlat
	case c.Vote == "":
		return VoteCut
	}
	return c.Vote
}

// MaxExtraWolves là số sói thêm tối đa admin chọn được.
const MaxExtraWolves = 2

// Validate từ chối cấu hình mà luật không cho: chỉ tắt được vai đặc biệt (R8).
func (c Config) Validate() error {
	if c.KmPerUnit < 0 {
		return fmt.Errorf("kmPerUnit âm: %v", c.KmPerUnit)
	}
	if c.ExtraWolves < 0 || c.ExtraWolves > MaxExtraWolves {
		return fmt.Errorf("extraWolves phải từ 0 tới %d: %v", MaxExtraWolves, c.ExtraWolves)
	}
	if c.Wolves < 0 || c.Wolves > MaxPlayers/3 {
		return fmt.Errorf("wolves phải từ 0 tới %d: %v", MaxPlayers/3, c.Wolves)
	}
	switch c.Vote {
	case "", VoteCut, VoteTop, VoteFlat, VoteSolo:
	default:
		return fmt.Errorf("luật phiếu lạ %q", c.Vote)
	}
	if c.TopVoters < 0 || c.TopVoters > MaxPlayers {
		return fmt.Errorf("topVoters phải từ 0 tới %d: %v", MaxPlayers, c.TopVoters)
	}
	if c.TopWeight != 0 && (c.TopWeight < MinTopWeight || c.TopWeight > MaxTopWeight) {
		return fmt.Errorf("topWeight phải là 0 hoặc từ %d tới %d: %v", MinTopWeight, MaxTopWeight, c.TopWeight)
	}
	if c.MaxHang < 0 || c.MaxHang > MaxNominees {
		return fmt.Errorf("maxHang phải từ 0 tới %d: %v", MaxNominees, c.MaxHang)
	}
	for i, r := range c.Extended {
		if !slices.Contains(extendedRoles, r) {
			return fmt.Errorf("vai %q không phải vai mở rộng", r)
		}
		if slices.Contains(c.Extended[:i], r) {
			return fmt.Errorf("vai mở rộng %q bị bật hai lần", r)
		}
	}
	if err := c.validateDark(); err != nil {
		return err
	}
	for r, km := range c.SkillKm {
		if !kmRole(r) {
			return fmt.Errorf("vai %q không có kỹ năng cần km", r)
		}
		if km < 0 {
			return fmt.Errorf("km của vai %q âm: %v", r, km)
		}
	}
	if s := c.Schedule; s != nil {
		if s.StartHour < 0 || s.StartHour > 23 {
			return fmt.Errorf("giờ bắt đầu phải từ 0 tới 23: %v", s.StartHour)
		}
		// Có Phases thì mốc tính theo từng pha, không cần RoundHours chẵn.
		if s.RoundHours < MinRoundHours || s.RoundHours > MaxRoundHours || (s.Phases == nil && s.RoundPhases == nil && s.RoundHours%2 != 0) {
			return fmt.Errorf("mỗi vòng phải dài từ %d tới %d tiếng, số chẵn: %v", MinRoundHours, MaxRoundHours, s.RoundHours)
		}
		if s.Rounds < 1 || s.Rounds*s.RoundHours > 24 {
			return fmt.Errorf("số vòng mỗi ngày phải từ 1, cả khung không quá 24 tiếng: %v vòng × %v tiếng", s.Rounds, s.RoundHours)
		}
		if err := s.validatePhases(); err != nil {
			return err
		}
		// Km chốt theo khung 22h hôm trước tới 22h, nên ván km mở vòng đầu lúc
		// 22h và các vòng trong ngày cộng lại đúng 24 tiếng: vòng cuối chốt
		// đúng mốc chốt km.
		if !c.KmOff && (s.StartHour != 22 || s.Rounds*s.RoundHours != 24) {
			return errors.New("ván dùng km phải mở vòng đầu lúc 22h, các vòng trong ngày cộng lại đúng 24 tiếng")
		}
	}
	for _, r := range c.Disabled {
		if !isSpecial(r) {
			return fmt.Errorf("không tắt được vai %q, chỉ tắt được vai đặc biệt", r)
		}
	}
	return nil
}

func (c Config) disabled(r Role) bool {
	for _, d := range c.Disabled {
		if d == r {
			return true
		}
	}
	return false
}

// Seed là nguồn ngẫu nhiên duy nhất của một ván, sinh lúc Start, nằm trong
// secret/state. Ai có seed là đoán được vai, nên không bao giờ trả ra ngoài.
type Seed [32]byte

func NewSeed() (Seed, error) {
	var s Seed
	_, err := rand.Read(s[:])
	return s, err
}
