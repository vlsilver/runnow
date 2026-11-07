package backend

import (
	"fmt"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameSetupSection là một khối của phần xem lại thiết lập ván, cùng tên khối
// và thứ tự với màn tạo ván.
type GameSetupSection struct {
	Title string          `json:"title"`
	Items []GameSetupItem `json:"items"`
}

// GameSetupItem là một tuỳ chọn đang áp: Value đã viết sẵn kèm đơn vị. Sub là
// dòng con của dòng có Icon ngay trên nó.
type GameSetupItem struct {
	Key   string `json:"key"`
	Icon  string `json:"icon,omitempty"`
	Label string `json:"label"`
	Value string `json:"value"`
	Sub   bool   `json:"sub,omitempty"`
}

// voteLegacyLabels là tên hai luật phiếu trước khi có Theo nhóm/Riêng; ván cũ
// còn mang.
var voteLegacyLabels = map[string]string{
	string(werewolf.VoteTop):  "Top km được 2 phiếu",
	string(werewolf.VoteFlat): "Mỗi người một phiếu",
}

// gameSetupFor là thiết lập của ván đọc ngược từ config qua read của từng tuỳ
// chọn. Chỉ hiện cái đang áp: tuỳ chọn có điều kiện sai, bật tắt đang tắt và
// tuỳ chọn read trả nil thì bỏ.
func gameSetupFor(c werewolf.Config) []GameSetupSection {
	values := map[string]any{}
	for _, d := range gameSettingDefs {
		values[d.Key] = d.read(c)
	}
	titles := map[string]string{}
	for _, g := range gameSettingGroups {
		titles[g.Key] = g.Label
	}
	var out []GameSetupSection
	at := map[string]int{}
	shown := map[string]bool{}
	for _, d := range gameSettingDefs {
		v := values[d.Key]
		if v == nil || !settingEnabled(d.EnabledIf, values) || v == false {
			continue
		}
		title := d.Section
		if title == "" {
			title = titles[d.Group]
		}
		i, ok := at[title]
		if !ok {
			i = len(out)
			at[title] = i
			out = append(out, GameSetupSection{Title: title})
		}
		shown[d.Key] = true
		out[i].Items = append(out[i].Items, GameSetupItem{
			Key: d.Key, Icon: d.Icon, Label: d.Label, Value: d.setupValue(v),
			Sub: d.Parent != "" && shown[d.Parent],
		})
	}
	return out
}

func settingEnabled(conds []GameSettingCondition, values map[string]any) bool {
	for _, c := range conds {
		if values[c.Key] != c.Equals {
			return false
		}
	}
	return true
}

func (d gameSettingDef) setupValue(v any) string {
	switch d.Type {
	case settingToggle:
		return "Bật"
	case settingChoice:
		s := v.(string)
		for _, c := range d.Choices {
			if c.Value == s {
				return c.Label
			}
		}
		if l, ok := voteLegacyLabels[s]; ok {
			return l
		}
		return s
	case settingPhase:
		return formatMinutes(int(v.(float64)))
	}
	n := v.(float64)
	switch {
	case d.Key == "topVoters" && n == 0:
		return "Số sói + 1"
	case d.Unit == "giờ", d.Unit == "tiếng":
		return formatKm(n) + "h"
	}
	return formatKm(n) + " " + d.Unit
}

// formatMinutes viết độ dài theo giờ: 90 → "1h30", 120 → "2h", 30 → "30 phút".
func formatMinutes(m int) string {
	switch {
	case m < 60:
		return fmt.Sprintf("%d phút", m)
	case m%60 == 0:
		return fmt.Sprintf("%dh", m/60)
	}
	return fmt.Sprintf("%dh%02d", m/60, m%60)
}

// scheduleOf là lịch ván đang dùng; nil là lịch gốc.
func scheduleOf(c werewolf.Config) werewolf.Schedule {
	if c.Schedule == nil {
		return werewolf.DefaultSchedule()
	}
	return *c.Schedule
}

// phasesOf là độ dài (phút) bốn pha; lịch không đặt pha thì bốn pha của lịch
// gốc co theo độ dài vòng.
func phasesOf(s werewolf.Schedule) []int {
	if len(s.Phases) == len(defaultPhases) {
		return s.Phases
	}
	out := make([]int, len(defaultPhases))
	for i, m := range defaultPhases {
		out[i] = m * s.RoundHours / 24
	}
	return out
}
