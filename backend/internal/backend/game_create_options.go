package backend

import (
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Phần trình bày của màn tạo ván: tab, kiểu ván dựng sẵn, lịch một vòng. Chữ
// và giá trị nằm ở đây để đổi tab hay thêm kiểu ván không cần ra bản app mới.

// GameSettingGroup là một tab trên màn tạo ván. OffNote hiện thay cho các tuỳ
// chọn của tab khi không tuỳ chọn nào đang có tác dụng (như ván không dùng km).
type GameSettingGroup struct {
	Key     string `json:"key"`
	Label   string `json:"label"`
	Icon    string `json:"icon"`
	OffNote string `json:"offNote,omitempty"`
}

// GamePreset là một kiểu ván dựng sẵn. Chọn kiểu thì app lấy Roles và Settings
// làm giá trị rồi gửi lên như người tạo tự chỉnh; key không có thì theo mặc định.
type GamePreset struct {
	Key      string          `json:"key"`
	Label    string          `json:"label"`
	Icon     string          `json:"icon"`
	Summary  string          `json:"summary"`
	Details  []string        `json:"details"`
	Default  bool            `json:"default"`
	Roles    map[string]bool `json:"roles"`
	Settings map[string]any  `json:"settings"`
}

// GameRoundPlan là diễn biến một vòng để app vẽ. From, To, At tính bằng giờ kể
// từ lúc mở đêm theo vòng gốc 24 tiếng; app co theo độ dài vòng người tạo chọn.
type GameRoundPlan struct {
	Phases    []GameRoundPhase `json:"phases"`
	Reminders []GameRoundMark  `json:"reminders"`
	// Start nói ván bắt đầu thế nào và chạy tới bao giờ.
	Start string `json:"start"`
}

type GameRoundPhase struct {
	Key         string  `json:"key"`
	Label       string  `json:"label"`
	Description string  `json:"description"`
	From        float64 `json:"from"`
	To          float64 `json:"to"`
	// SettingKey là ô (type "phase") giữ độ dài pha này, để app cho kéo.
	SettingKey string `json:"settingKey,omitempty"`
}

// GameRoundMark: At là giờ theo vòng gốc (app cũ co đều theo vòng). Phase và
// Frac là chỗ của mốc trong pha chứa nó (0..1), để app tính lại khi chia pha.
type GameRoundMark struct {
	Label string  `json:"label"`
	At    float64 `json:"at"`
	Phase string  `json:"phase,omitempty"`
	Frac  float64 `json:"frac,omitempty"`
}

const (
	groupTime  = "time"
	groupRound = "round"
	groupRoles = "roles"
	groupKm    = "km"
	groupTalk  = "talk"
)

var gameSettingGroups = []GameSettingGroup{
	{Key: groupTime, Label: "Lịch", Icon: "clock",
		OffNote: "Ván đua km mở vòng đầu lúc 22h, vì km tính theo ngày chạy từ 22h hôm trước tới 22h. Muốn tự đặt giờ thì chọn kiểu Cổ điển."},
	// Tab Vòng chơi không cần OffNote: số vòng mỗi ngày và giờ từng pha chỉnh
	// được cả ở ván km.
	{Key: groupRound, Label: "Vòng chơi", Icon: "moon"},
	{Key: groupRoles, Label: "Vai", Icon: "people"},
	// Tab Kỹ năng gom luật phiếu và km mỗi lượt; không cần OffNote vì "Không
	// dùng km" nằm ở đây và luôn chỉnh được.
	{Key: groupKm, Label: "Kỹ năng", Icon: "run"},
	// Tab Giao tiếp: ván có đăng lên Telegram không, đăng vào topic nào.
	{Key: groupTalk, Label: "Giao tiếp", Icon: "chat"},
}

var gamePresets = []GamePreset{
	{Key: "std", Label: "Chuẩn PSC", Icon: "run", Default: true,
		Summary: "Ván tuần quen thuộc, chạy đủ thì giữ phiếu",
		Details: []string{
			"Sói, Dân và 5 vai: Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn, Cupid.",
			"Mỗi ngày một vòng, mở lúc 22h.",
			"Km theo nhóm: cộng km cả nhóm chia ra số lượt, thiếu thì người chạy ít nhất mất lượt trước.",
			"Mỗi phiếu và mỗi lượt kỹ năng cần 1 km. Sói nào cũng có phiếu bầu cắn.",
		},
		Settings: map[string]any{}},
	{Key: "hard", Label: "Chạy bung", Icon: "bolt",
		Summary: "Chạy nhiều được nói nặng, kỹ năng cần nhiều km hơn",
		Details: []string{
			"Thêm Già làng vào 5 vai của ván chuẩn.",
			"Mỗi ngày một vòng, mở lúc 22h.",
			"Km riêng: ai tự chạy đủ km thì người đó được bỏ phiếu, dùng kỹ năng.",
			"Người chạy nhiều nhất được tính 2 phiếu.",
			"Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn mỗi lượt cần 2 km. Sói nào cũng có phiếu bầu cắn.",
			"Phe Sói có Tàng Hình và Vu Khống để lừa Tiên tri, mở khi cả phe chạy đủ 1 km mỗi sói.",
		},
		Settings: map[string]any{string(werewolf.Elder): true, "vote": string(werewolf.VoteSolo), "topOn": true,
			"seerKm": 2.0, "guardKm": 2.0, "witchKm": 2.0, "hunterKm": 2.0, "darkCloak": true, "darkFrame": true}},
	{Key: "classic", Label: "Cổ điển", Icon: "moon",
		Summary: "Ma Sói thường, không cần chạy",
		Details: []string{
			"Sói, Dân và 5 vai như ván chuẩn.",
			"Không dùng km: kỹ năng dùng tự do, mỗi người một phiếu, group không hiện bảng km.",
			"Tự đặt giờ mở vòng đầu, độ dài một vòng và số vòng mỗi ngày.",
		},
		Settings: map[string]any{"kmOff": true}},
}

const gameStartNote = "Admin bấm bắt đầu thì bot gửi lá bài ngay. Vòng đầu mở ở giờ mở vòng gần nhất, cách lúc bắt đầu ít nhất 2 tiếng. Ván chạy tới khi một phe thắng, không giới hạn số vòng."

func gameRoundPlan() GameRoundPlan {
	var base werewolf.Config
	hours := func(d time.Duration) float64 { return d.Hours() }
	at := func(p werewolf.Phase) float64 { return hours(base.PhaseOffset(p)) }
	nominate, vote := base.ReminderOffsets()
	phases := []GameRoundPhase{
		{Key: "night", Label: "Đêm", From: 0, To: at(werewolf.PhaseNight), SettingKey: "nightMin",
			Description: "Sói chọn người cắn. Tiên tri soi, Bảo vệ che. Đêm đầu Cupid ghép đôi."},
		{Key: "dawn", Label: "Rạng sáng", From: at(werewolf.PhaseNight), To: at(werewolf.PhaseDawn), SettingKey: "dawnMin",
			Description: "Phù thuỷ cứu người bị cắn hoặc độc một người. Tiên tri, Bảo vệ chưa làm thì làm nốt."},
		{Key: "day", Label: "Ngày", From: at(werewolf.PhaseDawn), To: at(werewolf.PhaseDay), SettingKey: "dayMin",
			Description: "Bot đăng bản tin đêm. Cả làng bàn và đề cử, tối đa 3 người lên giàn."},
		{Key: "trial", Label: "Biểu quyết", From: at(werewolf.PhaseDay), To: at(werewolf.PhaseTrial), SettingKey: "trialMin",
			Description: "Biểu quyết Treo hay Tha từng người trên giàn. Hết giờ thì chốt phiếu, vòng mới mở ngay."},
	}
	mark := func(label string, d time.Duration) GameRoundMark {
		h := hours(d)
		m := GameRoundMark{Label: label, At: h}
		for _, p := range phases {
			if h > p.From && h <= p.To {
				m.Phase, m.Frac = p.Key, (h-p.From)/(p.To-p.From)
				break
			}
		}
		return m
	}
	return GameRoundPlan{
		Phases:    phases,
		Reminders: []GameRoundMark{mark("Nhắc đề cử", nominate), mark("Nhắc biểu quyết", vote)},
		Start:     gameStartNote,
	}
}

// GameDeckPlan là bộ bài của tab Vai. Theo số người: bot chia lúc đủ người
// theo Tiers, vai đặc biệt thêm theo thứ tự Roles. Tự chỉnh: người tạo đặt số
// sói vào tuỳ chọn WolvesKey (khác 0) và bật tắt từng vai, Dân bù chỗ còn lại.
// Preview là số người app lấy để xem trước bộ bài.
type GameDeckPlan struct {
	Note      string         `json:"note"`
	FixedNote string         `json:"fixedNote"`
	WolvesKey string         `json:"wolvesKey"`
	Preview   int            `json:"preview"`
	Tiers     []GameDeckTier `json:"tiers"`
}

// GameDeckTier: từ From tới To người thì chia Wolves sói và Specials vai đặc
// biệt đầu tiên.
type GameDeckTier struct {
	From     int `json:"from"`
	To       int `json:"to"`
	Wolves   int `json:"wolves"`
	Specials int `json:"specials"`
}

const deckWolvesKey = "wolves"

// gameDeckPlan đọc bảng chia từ werewolf.Composition, nên bảng trên app luôn
// khớp với lúc bot chia thật.
func gameDeckPlan() GameDeckPlan {
	plan := GameDeckPlan{
		Note:      "Bot chia lúc đủ người, theo số người thật: đông thêm sói, thêm vai. Vai thêm theo thứ tự Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn, Cupid. Già làng, Kẻ ngốc thì tự bật.",
		FixedNote: "Chia đúng số lá đã chỉnh. Người thật nhiều hay ít hơn thì Dân bù vào.",
		WolvesKey: deckWolvesKey,
		Preview:   12,
	}
	for n := werewolf.MinPlayers; n <= werewolf.MaxPlayers; n++ {
		roles, err := werewolf.Composition(n, werewolf.Config{})
		if err != nil {
			panic(err) // n luôn trong khoảng Composition nhận
		}
		var t GameDeckTier
		for _, r := range roles {
			switch r {
			case werewolf.Wolf:
				t.Wolves++
			case werewolf.Villager:
			default:
				t.Specials++
			}
		}
		if k := len(plan.Tiers) - 1; k >= 0 && plan.Tiers[k].Wolves == t.Wolves && plan.Tiers[k].Specials == t.Specials {
			plan.Tiers[k].To = n
			continue
		}
		t.From, t.To = n, n
		plan.Tiers = append(plan.Tiers, t)
	}
	return plan
}

// gameCreateOptions là mọi thứ màn tạo ván cần, gửi kèm danh sách ván.
func gameCreateOptions() GameCreateOptions {
	out := GameCreateOptions{
		Settings: gameCreateSettings(),
		Groups:   gameSettingGroups,
		Presets:  gamePresets,
		Round:    gameRoundPlan(),
		Deck:     gameDeckPlan(),
	}
	clock := ruleClock(werewolf.Config{})
	for _, r := range toggleRoles {
		out.Roles = append(out.Roles, GameRoleOption{Key: string(r), Label: roleLabels[r],
			Description: clockText(roleRules[r], clock), Default: true})
	}
	return out
}
