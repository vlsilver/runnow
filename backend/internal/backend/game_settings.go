package backend

import (
	"fmt"
	"math"
	"net/http"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameSetting là một tuỳ chọn trên màn tạo ván. App vẽ theo Type và hiện
// Label, Description; thêm hay sửa tuỳ chọn chỉ cần sửa ở đây (createOptions),
// không phải ra bản app mới.
type GameSetting struct {
	Key         string `json:"key"`
	Label       string `json:"label"`
	Description string `json:"description"`
	// Type là "toggle" (bool), "number" (Min..Max, bước Step) hoặc "choice"
	// (một trong Choices).
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
}

type GameSettingChoice struct {
	Value       string `json:"value"`
	Label       string `json:"label"`
	Description string `json:"description"`
}

type GameSettingCondition struct {
	Key    string `json:"key"`
	Equals any    `json:"equals"`
}

const (
	settingToggle = "toggle"
	settingNumber = "number"
	settingChoice = "choice"
)

// gameSettingDef là một tuỳ chọn kèm cách áp vào werewolf.Config. keepDefault:
// không gửi thì áp Default; false thì không gửi là để config như cũ (km các vai
// khi đó theo KmPerUnit).
type gameSettingDef struct {
	GameSetting
	keepDefault bool
	apply       func(c *werewolf.Config, v any)
}

func f64(v float64) *float64 { return &v }

var kmOn = []GameSettingCondition{{Key: "kmOff", Equals: false}}

func roleKmSetting(key string, role werewolf.Role, label, desc string) gameSettingDef {
	return gameSettingDef{
		GameSetting: GameSetting{Key: key, Label: label, Description: desc, Type: settingNumber, Default: 1.0,
			Min: f64(0), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm},
		apply: func(c *werewolf.Config, v any) { setSkillKm(c, role, v.(float64)) },
	}
}

var kmOffOnly = []GameSettingCondition{{Key: "kmOff", Equals: true}}

// scheduleSetting là một ô của lịch hoạt động. Ô không gửi giữ giá trị của lịch
// gốc. Ván còn dùng km thì lịch không tác dụng (khung km cố định 22h) nên bỏ
// qua; kmOff đứng trước trong gameSettingDefs nên lúc này c.KmOff đã áp.
func scheduleSetting(s GameSetting, set func(*werewolf.Schedule, int)) gameSettingDef {
	s.Type, s.EnabledIf = settingNumber, kmOffOnly
	return gameSettingDef{GameSetting: s, apply: func(c *werewolf.Config, v any) {
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
	},
	extendedRoleSetting(werewolf.Elder, "Thêm Già làng",
		"Một Dân thành Già làng. Già làng thuộc phe Dân, chịu được một lần bị sói cắn: cú cắn đầu tiên không ai bảo vệ hay cứu thì vẫn sống, sáng ra làng chỉ thấy đêm đó không ai chết. Cú cắn sau, bị độc, bị treo hay bị bắn thì chết như thường."),
	extendedRoleSetting(werewolf.Idiot, "Thêm Kẻ ngốc",
		"Một Dân thành Kẻ ngốc. Kẻ ngốc thuộc phe Dân: bị làng treo lần đầu thì lật bài cho cả làng thấy và vẫn sống, nhưng mất quyền bỏ phiếu tới hết ván. Bị treo lần nữa, bị cắn, bị độc hay bị bắn thì chết như thường."),
	{
		GameSetting: GameSetting{Key: "kmOff", Label: "Không dùng km", Type: settingToggle, Default: false, Group: groupKm,
			Description: "Bật thì ván chơi như Ma Sói thường: kỹ năng không cần km, mỗi người một phiếu, group không hiện bảng km. Các tuỳ chọn km bên dưới hết tác dụng."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.KmOff = v.(bool) },
	},
	scheduleSetting(GameSetting{Key: "startHour", Label: "Giờ mở vòng đầu", Group: groupTime, Default: 22.0, Min: f64(0), Max: f64(23), Step: f64(1), Unit: "giờ",
		Description: "Giờ trong ngày mở vòng đầu tiên, vòng mở là đêm bắt đầu. Các vòng sau nối tiếp ngay khi vòng trước chốt. Hết các vòng trong ngày thì bot không nhận lựa chọn nào, tới giờ này hôm sau mới chơi tiếp. Chỉ dùng khi không dùng km."},
		func(s *werewolf.Schedule, n int) { s.StartHour = n }),
	scheduleSetting(GameSetting{Key: "roundHours", Label: "Độ dài một vòng", Group: groupRound, Default: 24.0, Min: f64(werewolf.MinRoundHours), Max: f64(werewolf.MaxRoundHours), Step: f64(2), Unit: "tiếng",
		Description: "Một vòng gồm đêm, bản tin, đề cử và biểu quyết. Mọi mốc co theo vòng 24 tiếng: vòng 6 tiếng thì sói có 30 phút để cắn, đêm dài 3 tiếng, biểu quyết là 30 phút cuối vòng. Số vòng nhân độ dài không quá 24 tiếng. Chỉ dùng khi không dùng km."},
		func(s *werewolf.Schedule, n int) { s.RoundHours = n }),
	scheduleSetting(GameSetting{Key: "roundsPerDay", Label: "Số vòng mỗi ngày", Group: groupTime, Default: 1.0, Min: f64(1), Max: f64(24 / werewolf.MinRoundHours), Step: f64(1), Unit: "vòng",
		Description: "Số vòng chơi trong một ngày, nối nhau từ giờ mở vòng đầu. Ví dụ mở 6h, vòng 6 tiếng, 3 vòng thì chơi từ 6h tới 24h, các vòng mở lúc 6h, 12h, 18h. Số vòng nhân độ dài không quá 24 tiếng. Chỉ dùng khi không dùng km."},
		func(s *werewolf.Schedule, n int) { s.Rounds = n }),
	{
		GameSetting: GameSetting{Key: "wolfKm", Label: "Km để Sói cắn", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm,
			Description: "Km mỗi sói còn sống phải góp, tính chung cả phe, thì phe Sói mới cắn được đêm đó. Để 0 là đêm nào sói cũng cắn được. Nên để 0: cắn mà cần km thì sáng ra có người chết là cả làng biết phe Sói đã đủ km, ráp với bảng km công khai là khoanh được sói."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { setSkillKm(c, werewolf.Wolf, v.(float64)) },
	},
	// skillKm đứng trước km riêng từng vai: gửi cả hai thì km riêng thắng.
	{
		GameSetting: GameSetting{Key: "skillKm", Label: "Km mở kỹ năng", Type: settingNumber, Default: 1.0,
			Min: f64(0), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupKm,
			Description: "Km Tiên tri, Bảo vệ, Phù thuỷ phải chạy trong khung 22h hôm trước tới 22h thì đêm đó mới dùng được kỹ năng; Thợ săn xét ở lần chốt 22h gần nhất. Để 0 là không cần km. Sói cắn không theo mức này."},
		apply: func(c *werewolf.Config, v any) {
			for _, r := range []werewolf.Role{werewolf.Seer, werewolf.Guard, werewolf.Witch, werewolf.Hunter} {
				setSkillKm(c, r, v.(float64))
			}
		},
	},
	roleKmSetting("seerKm", werewolf.Seer, "Km cho Tiên tri", "Km Tiên tri phải chạy trong khung 22h hôm trước tới 22h để soi được đêm đó. Để 0 là không cần km."),
	roleKmSetting("guardKm", werewolf.Guard, "Km cho Bảo vệ", "Km Bảo vệ phải chạy trong khung 22h hôm trước tới 22h để bảo vệ được đêm đó. Để 0 là không cần km."),
	roleKmSetting("witchKm", werewolf.Witch, "Km cho Phù thuỷ", "Km Phù thuỷ phải chạy trong khung 22h hôm trước tới 22h để dùng bình đêm đó. Để 0 là không cần km."),
	roleKmSetting("hunterKm", werewolf.Hunter, "Km cho Thợ săn", "Km Thợ săn phải có ở lần chốt 22h gần nhất thì khi chết mới được bắn. Để 0 là không cần km."),
	{
		GameSetting: GameSetting{Key: "villageGate", Label: "Km chung cho phe Dân", Type: settingToggle, Default: false, EnabledIf: kmOn, Group: groupKm,
			Description: "Bật thì Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn không xét km của riêng mình mà xét tổng km của mọi người không phải sói còn sống: phải đủ km của vai nhân số người đó. Cả làng chạy thì vai mới dùng được. Đổi lại người có vai biết tổng km phe Dân, lấy tổng km công khai trừ đi là ra km phe Sói."},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.VillageGate = v.(bool) },
	},
	{
		GameSetting: GameSetting{Key: "vote", Label: "Km và phiếu biểu quyết", Type: settingChoice, Default: string(werewolf.VoteCut), EnabledIf: kmOn, Group: groupVote,
			Description: "Km chốt 22h tác động lên phiếu Treo/Tha thế nào. Tính riêng từng phiên biểu quyết.",
			Choices: []GameSettingChoice{
				{Value: string(werewolf.VoteCut), Label: "Thiếu km thì mất phiếu", Description: "Số phiếu được tính bằng tổng km của người bỏ phiếu chia km một phiếu, làm tròn xuống. Thiếu thì người ít km nhất mất phiếu trước, kể cả người không bấm."},
				{Value: string(werewolf.VoteTop), Label: "Chạy nhiều được x2 phiếu", Description: "Không ai mất phiếu. Những người chạy nhiều nhất, mỗi người đủ km một phiếu, được tính 2 phiếu. Bằng km ở suất cuối thì bốc thăm."},
				{Value: string(werewolf.VoteFlat), Label: "Mỗi người một phiếu", Description: "Km không tác động lên phiếu, chỉ dùng cho kỹ năng."},
			}},
		keepDefault: true,
		apply:       func(c *werewolf.Config, v any) { c.Vote = werewolf.VoteRule(v.(string)) },
	},
	{
		GameSetting: GameSetting{Key: "kmPerUnit", Label: "Km một phiếu", Type: settingNumber, Default: 1.0,
			Min: f64(0.5), Max: f64(20), Step: f64(0.5), Unit: "km", EnabledIf: kmOn, Group: groupVote,
			Description: "Với luật \"Thiếu km thì mất phiếu\": km cho mỗi phiếu được tính. Với luật \"Chạy nhiều được x2 phiếu\": km tối thiểu để vào nhóm x2. Không có tác dụng với luật \"Mỗi người một phiếu\"."},
		apply: func(c *werewolf.Config, v any) { c.KmPerUnit = v.(float64) },
	},
	{
		GameSetting: GameSetting{Key: "topVoters", Label: "Số người được x2 phiếu", Type: settingNumber, Default: 0.0,
			Min: f64(0), Max: f64(10), Step: f64(1), Unit: "người", Group: groupVote,
			EnabledIf:   []GameSettingCondition{{Key: "kmOff", Equals: false}, {Key: "vote", Equals: string(werewolf.VoteTop)}},
			Description: "Chỉ dùng với luật \"Chạy nhiều được x2 phiếu\". Để 0 là bằng số sói còn sống cộng 1, để sói không chiếm hết các suất x2."},
		apply: func(c *werewolf.Config, v any) { c.TopVoters = int(v.(float64)) },
	},
}

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
	case settingNumber:
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
		return invalidSetting(d.Key, "không có lựa chọn này")
	}
	return nil
}
