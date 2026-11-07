package backend

import (
	"fmt"
	"math"
	"net/http"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameSetting là một tuỳ chọn trên màn tạo ván. App vẽ theo Type và hiện
// Label, Description; thêm hay sửa tuỳ chọn chỉ cần sửa ở đây (createOptions),
// không phải ra bản app mới.
type GameSetting struct {
	Key         string `json:"key"`
	Label       string `json:"label"`
	Description string `json:"description"`
	// Type là "toggle" (bool), "number" (Min..Max, bước Step), "choice" (một
	// trong Choices), "phase" (như number: độ dài một pha, phút; app vẽ
	// chung bốn pha thành vòng đồng hồ, app cũ không biết type này nên ẩn) hoặc
	// "text" (chuỗi tối đa Max ký tự, Lines dòng nhập; app cũ cũng ẩn).
	Type    string              `json:"type"`
	Default any                 `json:"default"`
	Min     *float64            `json:"min,omitempty"`
	Max     *float64            `json:"max,omitempty"`
	Step    *float64            `json:"step,omitempty"`
	Unit    string              `json:"unit,omitempty"`
	Choices []GameSettingChoice `json:"choices,omitempty"`
	// EnabledIf: tuỳ chọn chỉ có tác dụng khi mọi điều kiện đúng; app làm mờ khi
	// có điều kiện sai. Giá trị vẫn gửi lên được, server bỏ qua phần không tác dụng.
	EnabledIf []GameSettingCondition `json:"enabledIf,omitempty"`
	// Group là key của tab trên màn tạo ván (GameCreateOptions.Groups). Rỗng thì
	// màn tạo ván theo tab không hiện; giá trị lấy theo kiểu ván dựng sẵn.
	Group string `json:"group,omitempty"`
	// Section là tên khối trong tab: các tuỳ chọn cùng Section vẽ chung một
	// khối, ô bật tắt thành thẻ thu gọn (tên, Hint), chạm mở ra Description và
	// Warn. Rỗng thì vẽ như thường. App cũ bỏ qua ba field này.
	Section string `json:"section,omitempty"`
	// Hint là nhãn ngắn trên thẻ, ví dụ số lượt.
	Hint string `json:"hint,omitempty"`
	// Warn là cái giá người tạo ván cần cân, ví dụ dấu vết công khai.
	Warn string `json:"warn,omitempty"`
	// Role: tuỳ chọn của một vai; app chỉ hiện khi vai đó có trong bộ bài.
	Role string `json:"role,omitempty"`
	// Icon là tên biểu tượng; có thì app vẽ tuỳ chọn thành thẻ kỹ năng có nút
	// Chi tiết mở Description.
	Icon string `json:"icon,omitempty"`
	// Parent là key của thẻ chứa tuỳ chọn này (cùng Section, đứng trước); app
	// vẽ thành dòng con trong thẻ đó, thẻ cha ẩn thì vẽ như thường.
	Parent string `json:"parent,omitempty"`
	// Lines là số dòng của ô nhập "text"; 1 là ô một dòng.
	Lines int `json:"lines,omitempty"`
}

type GameSettingChoice struct {
	Value       string `json:"value"`
	Label       string `json:"label"`
	Description string `json:"description"`
	// Hint là dòng ngắn dưới tên lựa chọn; Details là các dòng mở bằng nút Chi
	// tiết. App cũ bỏ qua hai field này.
	Hint    string              `json:"hint,omitempty"`
	Details []GameSettingDetail `json:"details,omitempty"`
}

// GameSettingDetail là một dòng giải thích: Icon là key icon của app.
type GameSettingDetail struct {
	Icon  string `json:"icon"`
	Title string `json:"title"`
	Text  string `json:"text"`
}

type GameSettingCondition struct {
	Key    string `json:"key"`
	Equals any    `json:"equals"`
}

const (
	settingToggle = "toggle"
	settingNumber = "number"
	settingChoice = "choice"
	settingPhase  = "phase"
	// settingRoundPhases: danh sách bốn pha (phút) của từng vòng trong ngày.
	// App cũ không biết loại này nên không vẽ, không gửi.
	settingRoundPhases = "roundPhases"
	settingText        = "text"
)

// gameSettingDef là một tuỳ chọn kèm cách áp vào werewolf.Config. keepDefault:
// không gửi thì áp Default; false thì không gửi là để config như cũ (km các vai
// khi đó theo KmPerUnit).
type gameSettingDef struct {
	GameSetting
	keepDefault bool
	// legacyChoices là giá trị còn nhận nhưng không hiện cho người tạo ván.
	legacyChoices []string
	apply         func(c *werewolf.Config, v any)
	// read là giá trị đang áp trong c, cùng kiểu với giá trị app gửi; nil là
	// tuỳ chọn không áp ở ván này (vai không có trong bộ bài, không thêm sói,
	// không có đặc quyền nào cần km). Dùng cho phần xem lại thiết lập ván.
	read func(c werewolf.Config) any
}

func f64(v float64) *float64 { return &v }

var kmOn = []GameSettingCondition{{Key: "kmOff", Equals: false}}

func roleKmSetting(key string, role werewolf.Role, label, desc string) gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: key, Label: label, Description: desc, Type: settingNumber, Default: 1.0,
			Min: f64(0), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm,
			Section: sectionKm, Hint: roleLabels[role], Role: string(role), Icon: string(role)},
		// Luôn áp để km app hiện là km ván dùng, không lặng lẽ theo kmPerUnit.
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { setSkillKm(c, role, v.(float64)) },
		read: func(c werewolf.Config) any {
			if slices.Contains(c.Disabled, role) {
				return nil
			}
			return c.SkillMeters(role) / 1000
		},
	}
}

var kmOffOnly = []GameSettingCondition{{Key: "kmOff", Equals: true}}

// scheduleSetting là một ô của lịch hoạt động. Ô không gửi giữ giá trị của lịch
// gốc. Ván còn dùng km thì lịch không tác dụng (khung km cố định 22h) nên bỏ
// qua; kmOff đứng trước trong gameSettingDefs nên lúc này c.KmOff đã áp.
func scheduleSetting(s GameSetting, set func(*werewolf.Schedule, int), get func(werewolf.Schedule) int) gameSettingDef {
	s.Type, s.EnabledIf = settingNumber, kmOffOnly
	read := func(c werewolf.Config) any { return float64(get(scheduleOf(c))) }
	return gameSettingDef{GameSetting: s, read: read, apply: func(c *werewolf.Config, v any) {
		if !c.KmOff {
			return
		}
		if c.Schedule == nil {
			def := werewolf.DefaultSchedule()
			c.Schedule = &def
		}
		set(c.Schedule, int(v.(float64)))
	}}
}

// roundsPerDaySetting là số vòng mỗi ngày, dùng cho cả ván km. Ván km mở
// 22h và các vòng cộng lại đúng 24 tiếng, nên vòng dài 24/số vòng; app gửi
// kèm bốn pha thì các ô pha (đứng sau) đè lại độ dài vòng. Số vòng không chia
// đều 24 tiếng thì Validate từ chối.
// maxRoundsPerDay giữ mỗi vòng ít nhất 6 tiếng để người chơi kịp chạy và bấm.
const maxRoundsPerDay = 4

func roundsPerDaySetting() gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: "roundsPerDay", Label: "Số vòng mỗi ngày", Type: settingNumber, Group: groupRound,
			Default: 1.0, Min: f64(1), Max: f64(maxRoundsPerDay), Step: f64(1), Unit: "vòng",
			Description: "Số vòng chơi trong một ngày, nối nhau từ giờ mở vòng đầu. Ví dụ mở 6h, vòng 6 tiếng, 3 vòng thì chơi từ 6h tới 24h, các vòng mở lúc 6h, 12h, 18h. Ván dùng km mở vòng đầu lúc 22h và các vòng chia đều 24 tiếng (1, 2, 3 hoặc 4 vòng); km chốt lúc 22h nên các vòng trong ngày dùng chung km của ngày chạy trước."},
		apply: func(c *werewolf.Config, v any) {
			if c.Schedule == nil {
				def := werewolf.DefaultSchedule()
				c.Schedule = &def
			}
			n := int(v.(float64))
			c.Schedule.Rounds = n
			if !c.KmOff {
				c.Schedule.RoundHours = 24 / n
			}
		},
		read: func(c werewolf.Config) any { return float64(max(scheduleOf(c).Rounds, 1)) },
	}
}

// defaultPhases là độ dài (phút) bốn pha của lịch gốc: 22h–0h, 0h–10h,
// 10h–20h, 20h–22h.
var defaultPhases = []int{120, 600, 600, 120}

// phaseSetting là ô độ dài một pha (phút), dùng cho cả ván km lẫn cổ điển.
// App sửa pha nào thì gửi đủ bốn ô; ô không gửi lấy độ dài của lịch gốc. Độ dài
// vòng là tổng bốn pha, đè lên roundHours (các ô pha đứng sau roundHours).
// Ván km thì lịch giữ 22h, một vòng; Validate chặn nếu tổng khác 24 tiếng.
func phaseSetting(i int, key, label, desc string) gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: key, Label: label, Type: settingPhase, Group: groupRound, Unit: "phút",
			Default: float64(defaultPhases[i]), Min: f64(werewolf.MinPhaseMinutes), Step: f64(werewolf.PhaseStepMinutes),
			Max:         f64(24*60 - 3*werewolf.MinPhaseMinutes),
			Description: desc + " Pha nào cũng ít nhất 1 tiếng. Ván dùng km thì bốn pha cộng lại phải đúng 24 tiếng, vì km chốt lúc 22h."},
		apply: func(c *werewolf.Config, v any) {
			if c.Schedule == nil {
				def := werewolf.DefaultSchedule()
				c.Schedule = &def
			}
			s := c.Schedule
			if s.Phases == nil {
				s.Phases = slices.Clone(defaultPhases)
			}
			s.Phases[i] = int(v.(float64))
			total := 0
			for _, m := range s.Phases {
				total += m
			}
			// Tổng lệch giờ tròn thì Validate báo lỗi, vì RoundHours không khớp.
			s.RoundHours = total / 60
		},
		read: func(c werewolf.Config) any { return float64(phasesOf(scheduleOf(c))[i]) },
	}
}

// roundPhasesSetting là lịch pha riêng của từng vòng khi chơi nhiều vòng mỗi
// ngày: phần tử i là bốn pha của vòng thứ i+1, theo thứ tự như các ô pha. Đứng
// sau các ô pha và đè lên chúng: vòng 1 lấy làm Phases để ô pha đọc ngược ra
// đúng. Số vòng và tổng mỗi vòng do Validate của engine kiểm.
func roundPhasesSetting() gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: "roundPhases", Label: "Lịch từng vòng", Type: settingRoundPhases, Group: groupRound, Unit: "phút",
			Default: []any{[]any{120.0, 600.0, 600.0, 120.0}},
			Min:     f64(werewolf.MinPhaseMinutes), Step: f64(werewolf.PhaseStepMinutes), Max: f64(24*60 - 3*werewolf.MinPhaseMinutes),
			Description: "Chơi nhiều vòng mỗi ngày thì mỗi vòng chia giờ bốn pha riêng. Vòng nào cũng dài như nhau, nên giờ mở các vòng giữ nguyên."},
		apply: func(c *werewolf.Config, v any) {
			if c.Schedule == nil {
				def := werewolf.DefaultSchedule()
				c.Schedule = &def
			}
			var rounds [][]int
			for _, r := range v.([]any) {
				var phases []int
				for _, m := range r.([]any) {
					phases = append(phases, int(m.(float64)))
				}
				rounds = append(rounds, phases)
			}
			s := c.Schedule
			s.RoundPhases = rounds
			s.Phases = slices.Clone(rounds[0])
			total := 0
			for _, m := range s.Phases {
				total += m
			}
			s.RoundHours = total / 60
		},
		read: func(c werewolf.Config) any {
			rounds := scheduleOf(c).RoundPhases
			if rounds == nil {
				return nil
			}
			out := make([]any, len(rounds))
			for i, r := range rounds {
				phases := make([]any, len(r))
				for j, m := range r {
					phases[j] = float64(m)
				}
				out[i] = phases
			}
			return out
		},
	}
}

// extendedRoleSetting bật một vai mở rộng (werewolf.ExtendedRoles); key là tên vai.
func extendedRoleSetting(role werewolf.Role, label, desc string) gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: string(role), Label: label, Description: desc, Type: settingToggle, Default: false, Group: groupRoles},
		keepDefault: true,
		apply: func(c *werewolf.Config, v any) {
			if v.(bool) {
				c.Extended = append(c.Extended, role)
			}
		},
		read: func(c werewolf.Config) any { return slices.Contains(c.Extended, role) },
	}
}

const darkSection = "Phe Sói · Đặc quyền hắc ám"

// darkSetting bật một đặc quyền của phe Sói (werewolf.DarkPower).
func darkSetting(key string, p werewolf.DarkPower, icon, label, hint, desc, warn string) gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: key, Label: label, Description: desc, Type: settingToggle, Default: false, Group: groupRoles,
			Section: darkSection, Hint: hint, Warn: warn, Icon: icon},
		keepDefault: true,
		apply: func(c *werewolf.Config, v any) {
			if v.(bool) {
				c.Dark = append(c.Dark, p)
			}
		},
		read: func(c werewolf.Config) any { return slices.Contains(c.Dark, p) },
	}
}

func setSkillKm(c *werewolf.Config, role werewolf.Role, km float64) {
	if c.SkillKm == nil {
		c.SkillKm = map[werewolf.Role]float64{}
	}
	c.SkillKm[role] = km
}

var gameSettingDefs = []gameSettingDef{
	{
		GameSetting: GameSetting{Key: "extraWolves", Label: "Thêm sói", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(werewolf.MaxExtraWolves), Step: f64(1), Unit: "sói", Group: groupRoles,
			Description: "Thêm sói so với số chuẩn theo số người: 10 người 2 sói, 11–16 người 3 sói, 17–20 người 4 sói, từ 21 người 5 sói. Sói thêm lấy chỗ của Dân. Sói không vượt 1/3 số người, phần thừa bị bỏ."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.ExtraWolves = int(v.(float64)) },
		read: func(c werewolf.Config) any {
			if c.ExtraWolves == 0 {
				return nil
			}
			return float64(c.ExtraWolves)
		},
	},
	{
		// Màn tạo ván vẽ ô này trong bộ bài tự chỉnh (GameDeckPlan.WolvesKey).
		GameSetting: GameSetting{Key: deckWolvesKey, Label: "Số sói", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(werewolf.MaxPlayers / 3), Step: f64(1), Unit: "sói", Group: groupRoles,
			Description: "Bộ bài tự chỉnh: chia đúng số sói này (không vượt 1/3 số người) và mọi vai đang bật, Dân bù chỗ còn lại. 0 là chia theo số người."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.Wolves = int(v.(float64)) },
		read: func(c werewolf.Config) any {
			if c.Wolves == 0 {
				return nil
			}
			return float64(c.Wolves)
		},
	},
	extendedRoleSetting(werewolf.Elder, "Già làng",
		"Một Dân thành Già làng. Già làng thuộc phe Dân, chịu được một lần bị sói cắn: cú cắn đầu tiên không ai bảo vệ hay cứu thì vẫn sống, sáng ra làng chỉ thấy đêm đó không ai chết. Cú cắn sau, bị độc, bị treo hay bị bắn thì chết như thường."),
	extendedRoleSetting(werewolf.Idiot, "Kẻ ngốc",
		"Một Dân thành Kẻ ngốc. Kẻ ngốc thuộc phe Dân: bị làng treo lần đầu thì lật bài cho cả làng thấy và vẫn sống, nhưng mất quyền bỏ phiếu tới hết ván. Bị treo lần nữa, bị cắn, bị độc hay bị bắn thì chết như thường."),
	darkSetting("darkCloak", werewolf.DarkCloak, "cloak", "Sói Tàng Hình", "Mỗi sói 1 lần cả ván",
		"Đêm đó phe Sói chọn một sói, Tiên tri soi sói này ra Dân.",
		""),
	darkSetting("darkFrame", werewolf.DarkFrame, "frame", "Sói Vu Khống", "Mỗi đêm",
		"Đêm đó phe Sói chọn một người không phải sói, Tiên tri soi người này ra Sói.",
		""),
	darkSetting("darkSilent", werewolf.DarkSilent, "silent", "Cắn Im Lặng", "Mỗi đêm",
		"Người bị cắn không chết lúc sáng mà chết ngay sau phiên biểu quyết hôm sau, nên vẫn được bỏ phiếu. Phù thuỷ vẫn thấy và vẫn cứu được.",
		"Có người chết sau biểu quyết là cả làng biết đêm trước phe Sói đủ km."),
	darkSetting("darkVote", werewolf.DarkVote, "vote", "Phiếu Đôi", "Mỗi ngày",
		"Đêm đó phe Sói chọn một sói, phiếu của sói này tính 2 ở phiên biểu quyết hôm sau.",
		"Bảng phiếu công khai ghi ai chọn gì, nên tổng phiếu nhiều hơn số người là lộ có phiếu đôi ở phía đó."),
	darkSetting("darkPierce", werewolf.DarkPierce, "pierce", "Sói Đột Biến", "1 lần cả ván",
		"Cú cắn đêm đó xuyên qua Bảo vệ.",
		"Bảo vệ thấy người chết đúng là người mình đã che, nên biết sói vừa dùng đặc quyền."),
	{
		GameSetting: GameSetting{Key: "darkKm", Label: "Km để mở", Type: settingNumber, Default: 1.0,
			Min: f64(0.5), Max: f64(werewolf.MaxDarkKm), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupRoles,
			Section: darkSection, Hint: "× số sói còn sống",
			Description: "Đêm nào tổng km của sói còn sống đủ mức này nhân số sói thì đêm đó phe Sói dùng được một đặc quyền. Không đủ thì vẫn cắn bình thường. Ván không dùng km thì mỗi đặc quyền một lần cả ván."},
		apply: func(c *werewolf.Config, v any) { c.DarkKm = v.(float64) },
		read: func(c werewolf.Config) any {
			if len(c.Dark) == 0 {
				return nil
			}
			return c.DarkKm
		},
	},
	{
		GameSetting: GameSetting{Key: "kmOff", Label: "Không dùng km", Hint: "Chơi như Ma Sói thường", Type: settingToggle, Default: false, Group: groupKm,
			Description: "Bật thì ván chơi như Ma Sói thường: kỹ năng không cần km, mỗi người một phiếu, group không hiện bảng km. Các tuỳ chọn km bên dưới hết tác dụng."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.KmOff = v.(bool) },
		read:        func(c werewolf.Config) any { return c.KmOff },
	},
	scheduleSetting(GameSetting{Key: "startHour", Label: "Giờ mở vòng đầu", Group: groupTime, Default: 22.0, Min: f64(0), Max: f64(23), Step: f64(1), Unit: "giờ",
		Description: "Giờ trong ngày mở vòng đầu tiên, vòng mở là đêm bắt đầu. Các vòng sau nối tiếp ngay khi vòng trước chốt. Hết các vòng trong ngày thì bot không nhận lựa chọn nào, tới giờ này hôm sau mới chơi tiếp. Chỉ dùng khi không dùng km."},
		func(s *werewolf.Schedule, n int) { s.StartHour = n }, func(s werewolf.Schedule) int { return s.StartHour }),
	scheduleSetting(GameSetting{Key: "roundHours", Label: "Độ dài một vòng", Group: groupRound, Default: 24.0, Min: f64(werewolf.MinRoundHours), Max: f64(werewolf.MaxRoundHours), Step: f64(2), Unit: "tiếng",
		Description: "Một vòng gồm đêm, bản tin, đề cử và biểu quyết. Mọi mốc co theo vòng 24 tiếng: vòng 6 tiếng thì sói có 30 phút để cắn, đêm dài 3 tiếng, biểu quyết là 30 phút cuối vòng. Số vòng nhân độ dài không quá 24 tiếng. Chỉ dùng khi không dùng km."},
		func(s *werewolf.Schedule, n int) { s.RoundHours = n }, func(s werewolf.Schedule) int { return s.RoundHours }),
	roundsPerDaySetting(),
	phaseSetting(0, "nightMin", "Độ dài pha Đêm", "Sói chọn người cắn; Tiên tri soi, Bảo vệ che."),
	phaseSetting(1, "dawnMin", "Độ dài pha Rạng sáng", "Phù thuỷ cứu hoặc độc; Tiên tri, Bảo vệ làm nốt."),
	phaseSetting(2, "dayMin", "Độ dài pha Ngày", "Bot đăng bản tin đêm, cả làng bàn và đề cử lên giàn."),
	phaseSetting(3, "trialMin", "Độ dài pha Biểu quyết", "Treo hay Tha từng người trên giàn."),
	roundPhasesSetting(),
	{
		GameSetting: GameSetting{Key: "vote", Label: "Chế độ dùng kỹ năng", Type: settingChoice, Default: string(werewolf.VoteCut), EnabledIf: kmOn, Group: groupKm,
			Section:     sectionMode,
			Description: "Km chốt 22h quyết định ai được bỏ phiếu và ai dùng được kỹ năng. Áp cho biểu quyết, sói bầu cắn và kỹ năng phe Dân.",
			Choices: []GameSettingChoice{
				{Value: string(werewolf.VoteCut), Label: "Theo nhóm", Hint: "Km cả nhóm chia ra số lượt",
					Description: "Cộng km cả nhóm, chia cho km mỗi lượt ra số lượt được dùng. Thiếu thì người chạy ít nhất mất lượt trước.",
					Details: []GameSettingDetail{
						{Icon: "sum", Title: "Cách tính", Text: "Cộng km cả nhóm, chia cho km mỗi lượt: ra bao nhiêu thì bấy nhiêu lượt được dùng. Thiếu thì người chạy ít nhất mất lượt trước. Bằng km đúng ở ngưỡng thì bot bốc thăm."},
						{Icon: "vote", Title: "Biểu quyết", Text: "10 người chạy tổng 7 km, 1 km một phiếu: 7 phiếu được tính, 3 người chạy ít nhất không được tính, kể cả người không bấm."},
						{Icon: "people", Title: "Kỹ năng phe Dân", Text: "Cộng km phe Dân còn sống. Tiên tri, Bảo vệ, Phù thuỷ cần 1 km mỗi người, phe chạy 2 km: 2 vai dùng được, vai có km ít nhất mất lượt đêm đó."},
						{Icon: "wolf", Title: "Sói cắn", Text: "Sói bầu người cắn, mỗi sói một phiếu. Cộng km cả phe Sói chia km một phiếu ra số phiếu được tính, sói chạy ít nhất mất phiếu trước. Ai nhiều phiếu nhất thì bị cắn."},
						{Icon: "run", Title: "Bằng phiếu", Text: "Bên có tổng km cao hơn thắng. Vẫn bằng thì bốc thăm."},
					}},
				{Value: string(werewolf.VoteSolo), Label: "Riêng", Hint: "Ai đủ km người đó dùng",
					Description: "Ai chạy đủ km của lượt thì người đó dùng, không phụ thuộc người khác.",
					Details: []GameSettingDetail{
						{Icon: "one", Title: "Cách tính", Text: "Ai chạy đủ km của lượt thì người đó dùng, không phụ thuộc người khác."},
						{Icon: "vote", Title: "Biểu quyết", Text: "1 km một phiếu: ai chạy đủ 1 km thì phiếu được tính, chưa đủ thì phiếu không tính."},
						{Icon: "seer", Title: "Kỹ năng", Text: "Tiên tri cần 1 km: tự chạy đủ 1 km thì đêm đó soi được."},
						{Icon: "wolf", Title: "Sói cắn", Text: "Sói bầu người cắn, mỗi sói một phiếu. Sói nào tự chạy đủ km một phiếu thì phiếu đó được tính. Ai nhiều phiếu nhất thì bị cắn."},
						{Icon: "run", Title: "Bằng phiếu", Text: "Bên có tổng km cao hơn thắng. Vẫn bằng thì bốc thăm."},
					}},
			}},
		// Ván cũ và app cũ có thể còn gửi hai luật trước khi có Theo nhóm/Riêng.
		legacyChoices: []string{string(werewolf.VoteTop), string(werewolf.VoteFlat)},
		keepDefault:   true,
		apply:         func(c *werewolf.Config, v any) { c.Vote = werewolf.VoteRule(v.(string)) },
		read:          func(c werewolf.Config) any { return string(c.VoteMode()) },
	},
	{
		GameSetting: GameSetting{Key: "kmPerUnit", Label: "Biểu quyết", Hint: "Mọi người · km một phiếu", Type: settingNumber, Default: 1.0,
			Min: f64(0.5), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm, Section: sectionKm, Icon: "vote",
			Description: "Ai còn sống cũng được bỏ phiếu treo một người, kể cả Sói. Km ở đây là km cho một phiếu, tính theo chế độ đã chọn."},
		apply: func(c *werewolf.Config, v any) { c.KmPerUnit = v.(float64) },
		read:  func(c werewolf.Config) any { return kmPerUnit(c) },
	},
	{
		GameSetting: GameSetting{Key: "maxHang", Label: "Treo tối đa mỗi vòng", Type: settingNumber, Default: float64(werewolf.MaxNominees),
			Min: f64(1), Max: f64(float64(werewolf.MaxNominees)), Step: f64(1), Unit: "người", Group: groupKm, Section: sectionKm, Parent: "kmPerUnit",
			Description: "Số người được lên giàn mỗi vòng, mỗi người một phiên Treo/Tha riêng."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.MaxHang = int(v.(float64)) },
		read:        func(c werewolf.Config) any { return float64(c.NomineeSeats()) },
	},
	{
		GameSetting: GameSetting{Key: "wolfKm", Label: "Bầu cắn", Hint: "Phe Sói · km một phiếu", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm, Section: sectionKm, Icon: "wolf",
			Warn:        "Dễ lộ sói",
			Description: "Mỗi đêm phe Sói cắn một người. Mỗi sói bầu một phiếu, ai nhiều phiếu nhất thì bị cắn; bằng phiếu thì bên có tổng km cao hơn thắng, vẫn bằng thì bốc thăm. Km ở đây là km cho một phiếu cắn, tính theo chế độ đã chọn. 0 là mọi sói đều có phiếu. Nên để 0: cắn mà cần km thì sáng ra có người chết là cả làng biết phe Sói đủ km, ráp với bảng km công khai là khoanh được sói."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { setSkillKm(c, werewolf.Wolf, v.(float64)) },
		read:        func(c werewolf.Config) any { return c.SkillMeters(werewolf.Wolf) / 1000 },
	},
	roleKmSetting("seerKm", werewolf.Seer, "Soi", "Đủ km thì đêm đó soi được một người, biết là Sói hay Dân."),
	roleKmSetting("guardKm", werewolf.Guard, "Che", "Đủ km thì đêm đó che được một người khỏi bị cắn."),
	roleKmSetting("witchKm", werewolf.Witch, "Dùng thuốc", "Đủ km thì đêm đó dùng được bình cứu hoặc bình độc. Cả ván mỗi bình một lần."),
	roleKmSetting("hunterKm", werewolf.Hunter, "Bắn khi ngã", "Ngã xuống mà đủ km ở lần chốt 22h gần nhất thì được bắn mang theo một người. Chết vì bình độc thì không bắn được."),
	// topOn đứng trước topWeight: tắt thì TopWeight về 0, bật thì topWeight ghi đè.
	{
		GameSetting: GameSetting{Key: "topOn", Label: "Top N được x phiếu", Hint: "Người chạy nhiều nhất", Type: settingToggle, Default: false,
			EnabledIf: kmOn, Group: groupKm, Section: sectionTop, Icon: "bolt",
			Description: "Người chạy nhiều nhất trong ngày được tính nhiều phiếu hơn, mỗi người phải đủ km một phiếu. Áp cho mọi người trong top, kể cả Sói: chỉ phe Dân được thì bảng phiếu công khai lộ ai là sói."},
		keepDefault: true,
		apply: func(c *werewolf.Config, v any) {
			c.TopWeight = 0
			if v.(bool) {
				c.TopWeight = werewolf.MinTopWeight
			}
		},
		read: func(c werewolf.Config) any { return c.TopWeight > 0 },
	},
	{
		GameSetting: GameSetting{Key: "topVoters", Label: "Số người", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(10), Step: f64(1), Unit: "người", Group: groupKm, Section: sectionTop, Parent: "topOn",
			EnabledIf:   []GameSettingCondition{{Key: "kmOff", Equals: false}, {Key: "topOn", Equals: true}},
			Hint:        "0 là số sói + 1",
			Description: "Để 0 là bằng số sói còn sống cộng 1, để sói không chiếm hết các suất."},
		apply: func(c *werewolf.Config, v any) { c.TopVoters = int(v.(float64)) },
		read:  func(c werewolf.Config) any { return float64(c.TopVoters) },
	},
	{
		GameSetting: GameSetting{Key: "topWeight", Label: "Phiếu mỗi người", Type: settingNumber, Default: float64(werewolf.MinTopWeight),
			Min: f64(werewolf.MinTopWeight), Max: f64(werewolf.MaxTopWeight), Step: f64(1), Unit: "phiếu", Group: groupKm, Section: sectionTop, Parent: "topOn",
			EnabledIf:   []GameSettingCondition{{Key: "kmOff", Equals: false}, {Key: "topOn", Equals: true}},
			Description: "Mỗi người trong top được tính bấy nhiêu phiếu."},
		apply: func(c *werewolf.Config, v any) {
			if c.TopWeight > 0 {
				c.TopWeight = int(v.(float64))
			}
		},
		read: func(c werewolf.Config) any { return float64(max(c.TopWeight, werewolf.MinTopWeight)) },
	},
	{
		GameSetting: GameSetting{Key: "telegram", Label: "Telegram group", Hint: "Bot 3i đăng tin vào group", Type: settingToggle, Default: true, Group: groupTalk,
			Description: "Bật thì bot 3i đăng diễn biến ván vào group Telegram và nhắn riêng cho từng người, người chơi phải liên kết Telegram để đăng ký. Tắt thì ván chỉ chơi trong app."},
		apply: func(c *werewolf.Config, v any) { c.NoTelegram = !v.(bool) },
		read:  func(c werewolf.Config) any { return !c.NoTelegram },
	},
	{
		GameSetting: GameSetting{Key: "botName", Label: "Tên bot của ván", Type: settingText, Default: "Cú Đêm", Max: f64(roomBotNameMax), Lines: 1, Group: groupTalk,
			Description: "Gọi tên này trong Phòng chung thì bot trả lời. Để trống là ván không có bot."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.BotName = strings.TrimSpace(v.(string)) },
		read:        textRead(func(c werewolf.Config) string { return c.BotName }),
	},
	{
		GameSetting: GameSetting{Key: "botPersona", Label: "Tính cách bot", Type: settingText, Default: "", Max: f64(roomBotPersonaMax), Lines: 4, Group: groupTalk,
			Description: "Bot nói chuyện theo tính cách này. Bot chỉ biết những gì cả phòng thấy, không biết vai của ai."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.BotPersona = strings.TrimSpace(v.(string)) },
		read:        textRead(func(c werewolf.Config) string { return c.BotPersona }),
	},
}

// textRead: ô chữ để trống thì không hiện ở phần xem lại thiết lập.
func textRead(get func(werewolf.Config) string) func(werewolf.Config) any {
	return func(c werewolf.Config) any {
		if s := get(c); s != "" {
			return s
		}
		return nil
	}
}

// Khối của tab Kỹ năng, theo thứ tự trên màn tạo ván.
const (
	sectionMode = "Chế độ dùng kỹ năng"
	sectionKm   = "Km mỗi lượt"
	sectionTop  = "Đặc quyền phe Dân"
)

// gameCreateSettings là danh sách tuỳ chọn gửi cho màn tạo ván.
func gameCreateSettings() []GameSetting {
	out := make([]GameSetting, len(gameSettingDefs))
	for i, d := range gameSettingDefs {
		out[i] = d.GameSetting
	}
	return out
}

func invalidSetting(key, why string) error {
	return &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_setting", Message: fmt.Sprintf("Tuỳ chọn %q không hợp lệ: %s.", key, why)}
}

// applyGameSettings áp các tuỳ chọn app gửi lên vào c. Key lạ hay giá trị sai
// kiểu, ngoài khoảng thì trả 422, không bỏ qua lặng lẽ.
func applyGameSettings(c *werewolf.Config, in map[string]any) error {
	// Chỉ ván mới đi qua đây nên mang đời luật mới nhất; ván đang chạy giữ
	// Ruleset đã chụp lúc tạo.
	c.Ruleset = werewolf.RulesetKm
	known := map[string]bool{}
	for _, d := range gameSettingDefs {
		known[d.Key] = true
	}
	for key := range in {
		if !known[key] {
			return invalidSetting(key, "không có tuỳ chọn này")
		}
	}
	for _, d := range gameSettingDefs {
		v, ok := in[d.Key]
		if !ok {
			if !d.keepDefault {
				continue
			}
			v = d.Default
		}
		if err := d.check(v); err != nil {
			return err
		}
		d.apply(c, v)
	}
	return nil
}

func (d gameSettingDef) check(v any) error {
	switch d.Type {
	case settingToggle:
		if _, ok := v.(bool); !ok {
			return invalidSetting(d.Key, "phải là bật hoặc tắt")
		}
	case settingNumber, settingPhase:
		n, ok := v.(float64)
		if !ok {
			return invalidSetting(d.Key, "phải là số")
		}
		if n < *d.Min || n > *d.Max {
			return invalidSetting(d.Key, fmt.Sprintf("phải từ %s tới %s", formatKm(*d.Min), formatKm(*d.Max)))
		}
		if steps := (n - *d.Min) / *d.Step; math.Abs(steps-math.Round(steps)) > 1e-9 {
			return invalidSetting(d.Key, "phải theo bước "+formatKm(*d.Step))
		}
	case settingRoundPhases:
		rounds, ok := v.([]any)
		if !ok || len(rounds) == 0 || len(rounds) > maxRoundsPerDay {
			return invalidSetting(d.Key, fmt.Sprintf("phải là lịch của 1 tới %d vòng", maxRoundsPerDay))
		}
		for _, r := range rounds {
			phases, ok := r.([]any)
			if !ok || len(phases) != len(defaultPhases) {
				return invalidSetting(d.Key, fmt.Sprintf("mỗi vòng phải có đủ %d pha", len(defaultPhases)))
			}
			for _, m := range phases {
				n, ok := m.(float64)
				if !ok || n < *d.Min || n > *d.Max || math.Mod(n, *d.Step) != 0 {
					return invalidSetting(d.Key, fmt.Sprintf("pha nào cũng từ %s tới %s phút, theo bước %s", formatKm(*d.Min), formatKm(*d.Max), formatKm(*d.Step)))
				}
			}
		}
	case settingChoice:
		s, ok := v.(string)
		if !ok {
			return invalidSetting(d.Key, "phải là một lựa chọn")
		}
		for _, c := range d.Choices {
			if c.Value == s {
				return nil
			}
		}
		if slices.Contains(d.legacyChoices, s) {
			return nil
		}
		return invalidSetting(d.Key, "không có lựa chọn này")
	case settingText:
		s, ok := v.(string)
		if !ok {
			return invalidSetting(d.Key, "phải là chữ")
		}
		if n := utf8.RuneCountInString(strings.TrimSpace(s)); n > int(*d.Max) {
			return invalidSetting(d.Key, fmt.Sprintf("dài tối đa %d ký tự", int(*d.Max)))
		}
		if d.Lines == 1 && strings.ContainsAny(s, "\r\n") {
			return invalidSetting(d.Key, "chỉ một dòng")
		}
	}
	return nil
}
