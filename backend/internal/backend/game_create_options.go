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
}

type GameRoundMark struct {
	Label string  `json:"label"`
	At    float64 `json:"at"`
}

const (
	groupTime  = "time"
	groupRound = "round"
	groupRoles = "roles"
	groupVote  = "vote"
	groupKm    = "km"
)

var gameSettingGroups = []GameSettingGroup{
	{Key: groupTime, Label: "Lịch", Icon: "clock",
		OffNote: "Ván đua km chơi mỗi ngày một vòng, mở lúc 22h, vì km tính theo ngày chạy từ 22h hôm trước tới 22h. Muốn tự đặt giờ thì chọn kiểu Cổ điển."},
	{Key: groupRound, Label: "Vòng chơi", Icon: "moon",
		OffNote: "Ván đua km có vòng dài 24 tiếng. Muốn vòng ngắn hơn thì chọn kiểu Cổ điển."},
	{Key: groupRoles, Label: "Vai", Icon: "people"},
	{Key: groupVote, Label: "Phiếu", Icon: "vote",
		OffNote: "Ván không dùng km: mỗi người một phiếu. Chọn Chuẩn PSC hay Chạy bung để chỉnh luật phiếu."},
	{Key: groupKm, Label: "Km", Icon: "run",
		OffNote: "Ván không dùng km: kỹ năng dùng tự do. Chọn Chuẩn PSC hay Chạy bung để chỉnh km."},
}

var gamePresets = []GamePreset{
	{Key: "std", Label: "Chuẩn PSC", Icon: "run", Default: true,
		Summary: "Ván tuần quen thuộc, chạy đủ thì giữ phiếu",
		Details: []string{
			"Sói, Dân và 5 vai: Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn, Cupid.",
			"Mỗi ngày một vòng, mở lúc 22h.",
			"Thiếu km thì mất phiếu.",
			"Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn mỗi ngày cần 1 km để dùng kỹ năng. Sói cắn không cần km.",
		},
		Settings: map[string]any{}},
	{Key: "hard", Label: "Chạy bung", Icon: "bolt",
		Summary: "Chạy nhiều được nói nặng, kỹ năng cần nhiều km hơn",
		Details: []string{
			"Thêm Già làng vào 5 vai của ván chuẩn.",
			"Mỗi ngày một vòng, mở lúc 22h.",
			"Không ai mất phiếu; người chạy nhiều nhất được tính 2 phiếu.",
			"Tiên tri, Bảo vệ, Phù thuỷ, Thợ săn mỗi ngày cần 2 km để dùng kỹ năng. Sói cắn không cần km.",
		},
		Settings: map[string]any{string(werewolf.Elder): true, "vote": string(werewolf.VoteTop), "skillKm": 2.0}},
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
	return GameRoundPlan{
		Phases: []GameRoundPhase{
			{Key: "night", Label: "Đêm", From: 0, To: at(werewolf.PhaseNight),
				Description: "Sói chọn người cắn. Tiên tri soi, Bảo vệ che. Đêm đầu Cupid ghép đôi."},
			{Key: "dawn", Label: "Rạng sáng", From: at(werewolf.PhaseNight), To: at(werewolf.PhaseDawn),
				Description: "Phù thuỷ cứu người bị cắn hoặc độc một người. Tiên tri, Bảo vệ chưa làm thì làm nốt."},
			{Key: "day", Label: "Ngày", From: at(werewolf.PhaseDawn), To: at(werewolf.PhaseDay),
				Description: "Bot đăng bản tin đêm. Cả làng bàn và đề cử, tối đa 3 người lên giàn."},
			{Key: "trial", Label: "Biểu quyết", From: at(werewolf.PhaseDay), To: at(werewolf.PhaseTrial),
				Description: "Biểu quyết Treo hay Tha từng người trên giàn. Hết giờ thì chốt phiếu, vòng mới mở ngay."},
		},
		Reminders: []GameRoundMark{
			{Label: "Nhắc đề cử", At: hours(nominate)},
			{Label: "Nhắc biểu quyết", At: hours(vote)},
		},
		Start: gameStartNote,
	}
}

// gameCreateOptions là mọi thứ màn tạo ván cần, gửi kèm danh sách ván.
func gameCreateOptions() GameCreateOptions {
	out := GameCreateOptions{
		Settings: gameCreateSettings(),
		Groups:   gameSettingGroups,
		Presets:  gamePresets,
		Round:    gameRoundPlan(),
	}
	clock := ruleClock(werewolf.Config{})
	for _, r := range toggleRoles {
		out.Roles = append(out.Roles, GameRoleOption{Key: string(r), Label: roleLabels[r],
			Description: clockText(roleRules[r], clock), Default: true})
	}
	return out
}
