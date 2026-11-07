package backend

import (
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// threeShifts: 3 vòng mỗi ngày, mỗi vòng 6 tiếng, mở 6h, 12h, 18h.
var threeShifts = ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 6, RoundHours: 6, Rounds: 3}}

// Luật chung in giờ theo lịch của ván; lịch gốc giữ nguyên câu cũ.
func TestGameRulesFollowSchedule(t *testing.T) {
	if got := gameRulesFor(ww.Config{}); !strings.HasPrefix(got, "Mỗi vòng dài một ngày. 22h tới 10h là đêm: các vai có kỹ năng chọn người. 10h bản tin đêm, đề cử tới 20h; tối đa 3 người nhiều đề cử nhất lên giàn. 20h tới 22h biểu quyết Treo hay Tha từng người. 22h chốt phiếu và km.\n") {
		t.Fatalf("lịch gốc = %q", got)
	}
	want := "Mỗi ngày 3 vòng, mỗi vòng dài 6 tiếng, mở lúc 6h, 12h, 18h; ngoài khung đó không nhận lựa chọn nào. Giờ bên dưới là của vòng mở lúc 6h, vòng khác lệch giờ tương ứng. " +
		"6h tới 9h là đêm: các vai có kỹ năng chọn người. 9h bản tin đêm, đề cử tới 11h30; tối đa 3 người nhiều đề cử nhất lên giàn. 11h30 tới 12h biểu quyết Treo hay Tha từng người. 12h chốt phiếu.\n"
	if got := gameRulesFor(threeShifts); !strings.HasPrefix(got, want) {
		t.Fatalf("3 vòng = %q", got)
	}
	// Vòng 8 tiếng: một giờ của lịch gốc thành 20 phút.
	one := ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 20, RoundHours: 8, Rounds: 1}}
	want = "Mỗi ngày một vòng dài 8 tiếng, mở lúc 20h; ngoài khung đó không nhận lựa chọn nào. " +
		"20h tới 0h là đêm: các vai có kỹ năng chọn người. 0h bản tin đêm, đề cử tới 3h20;"
	if got := gameRulesFor(one); !strings.HasPrefix(got, want) {
		t.Fatalf("1 vòng = %q", got)
	}
}

// Thẻ trong app theo giờ vòng đang chạy: vòng mở 12h, sói khoá 12h30, phiên
// biểu quyết gọi theo tên chốt 18h.
func TestMeActionsHelpFollowsRound(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, threeShifts, msgRoles(), msgStart)
	st.Phase = ww.PhaseNight
	var bite *GameAction
	for _, a := range meActions(st, "w1", nil, nil, nil, st.NightAt.Add(10*time.Minute), 0) {
		if a.Kind == string(ww.KindWolfBite) {
			bite = &a
		}
	}
	if bite == nil || !strings.HasSuffix(bite.Help, "Khoá lúc 12h30.") {
		t.Fatalf("thẻ cắn = %+v", bite)
	}
	st.Phase, st.Nominees, st.Nominee = ww.PhaseTrial, []string{"v1"}, "v1"
	players := []gamePlayerInfo{{uid: "v1", name: "An"}}
	acts := meActions(st, "w1", nil, nil, players, st.NightAt.Add(5*time.Hour+45*time.Minute), 0)
	if len(acts) != 1 || acts[0].Help != "Treo hay tha An. Đổi được tới 18h." {
		t.Fatalf("thẻ biểu quyết = %+v", acts)
	}
}

// Chữ trên nút hành động theo giờ của vòng đang chạy (Start 9h → vòng mở 12h).
func TestActionHelpFollowsRound(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager, "s1": ww.Seer}
	st := ww.NewState(ww.Seed{1}, threeShifts, roles, msgStart)
	if !st.NightAt.Equal(msgStart.Add(3 * time.Hour)) {
		t.Fatalf("msgStart %s → vòng đầu %s, test giả định vòng mở sau 3 tiếng", msgStart, st.NightAt)
	}
	for kind, want := range map[ww.Kind]string{
		ww.KindWolfBite: "Khoá lúc 12h30.",
		ww.KindNominate: "Đổi được tới 17h30.",
		ww.KindVote:     "Đổi được tới 18h.",
	} {
		if got := actionHelp(st, kind); !strings.HasSuffix(got, want) {
			t.Fatalf("%s = %q, mong đợi đuôi %q", kind, got, want)
		}
	}
	if got := actionHelp(ww.NewState(ww.Seed{1}, ww.Config{}, roles, msgStart), ww.KindWolfBite); !strings.HasSuffix(got, "Khoá lúc 0h.") {
		t.Fatalf("lịch gốc = %q", got)
	}
}

// Nhãn lúc chuẩn bị báo giờ mở đêm 1 thật của ván, lấy từ deadline trong game doc.
func TestSetupLabelShowsFirstNight(t *testing.T) {
	g := map[string]any{"round": 0, "phase": string(ww.PhaseSetup), "deadline": time.Date(2026, 10, 15, 12, 0, 0, 0, vietnam)}
	if got := phaseLabelOf(g); got != "Chuẩn bị, đêm 1 bắt đầu lúc 12h" {
		t.Fatalf("nhãn = %q", got)
	}
	g["deadline"] = nil
	if got := phaseLabelOf(g); got != "Chuẩn bị" {
		t.Fatalf("thiếu deadline = %q", got)
	}
}

// Lời quản trò ghi giờ của vòng đang chạy, suy từ deadline trong bản tin.
func TestGameMasterCallsFollowRound(t *testing.T) {
	r := testRenderer()
	r.cfg = threeShifts
	out := renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/trial", "round": 2, "phase": "night", "deadline": "2026-10-15T11:30:00Z",
		"call": "night", "wake": []string{"wolf", "seer", "witch"},
	})
	for _, want := range []string{
		"1. Sói thức dậy, cả phe chọn một người để cắn, chốt lúc 18h30.\n",
		"2. Tiên tri thức dậy, chọn một người để soi, tới 21h.\n",
		"3. Phù thuỷ: 18h30 sói chốt xong thì quản trò gọi.\n",
	} {
		if !strings.Contains(out.parts[0], want) {
			t.Fatalf("vòng 18h = %q, thiếu %q", out.parts[0], want)
		}
	}
	out = renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r3/night", "round": 3, "phase": "dawn", "deadline": "2026-10-16T02:00:00Z",
		"call": "witch", "wake": []string{"witch"},
	})
	if want := "Phù thuỷ thức dậy, chọn cứu người hay dùng bình độc, tới 9h sáng.\n"; !strings.Contains(out.parts[0], want) {
		t.Fatalf("vòng 6h = %q, thiếu %q", out.parts[0], want)
	}
	// Tin bắt đầu: đêm 1 mở 12h (05:00Z) thì Cupid ghép tới 12h30.
	out = renderOne(t, r, chatGroup, tplStart, map[string]any{"nightAt": "2026-10-15T05:00:00Z", "wake": []string{"cupid"}})
	if want := "Cupid thức dậy, chọn hai người để ghép đôi, chốt lúc 12h30 đêm 1."; !strings.Contains(out.parts[0], want) {
		t.Fatalf("tin bắt đầu = %q, thiếu %q", out.parts[0], want)
	}
}

// Tin nhắc chở hạn của lượt đang mở và in đúng giờ đó; tin cũ trong hàng đợi
// chưa có hạn thì giữ chữ của lịch gốc.
func TestReminderShowsRoundClose(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager, "s1": ww.Seer}
	st := ww.NewState(ww.Seed{1}, threeShifts, roles, msgStart)
	st.Phase = ww.PhaseDay
	msgs := stepMessages(st, st, []ww.Event{{Kind: ww.EventReminder, Reason: ww.ReminderNominate}})
	if got := msgs[0].Data["deadline"]; got != "2026-10-15T10:30:00Z" {
		t.Fatalf("hạn trong tin nhắc = %v", got)
	}
	r := testRenderer()
	for _, c := range []struct{ reason, deadline, want string }{
		{ww.ReminderNominate, "2026-10-15T10:30:00Z", "Đề cử đóng lúc 17h30."},
		{ww.ReminderVote, "2026-10-15T11:00:00Z", "Biểu quyết Treo hay Tha đóng lúc 18h."},
		{ww.ReminderNominate, "", "Đề cử đóng lúc 20h."},
		{ww.ReminderVote, "", "Biểu quyết Treo hay Tha đóng lúc 22h."},
	} {
		data := map[string]any{"reason": c.reason}
		if c.deadline != "" {
			data["deadline"] = c.deadline
		}
		if out := renderOne(t, r, chatGroup, tplReminder, data); !strings.Contains(out.parts[0], c.want) {
			t.Fatalf("%s hạn %q = %q, thiếu %q", c.reason, c.deadline, out.parts[0], c.want)
		}
	}
}

// Tuỳ chọn lịch: ô nào không gửi thì lấy của lịch gốc (22h, 24 tiếng, 1 vòng);
// ván còn dùng km thì lịch không tác dụng nên bị bỏ qua, không thành lỗi.
func TestScheduleSettingsApplied(t *testing.T) {
	for _, c := range []struct {
		in   map[string]any
		want *ww.Schedule
	}{
		{map[string]any{"kmOff": true, "startHour": 6.0, "roundHours": 6.0, "roundsPerDay": 3.0}, &ww.Schedule{StartHour: 6, RoundHours: 6, Rounds: 3}},
		{map[string]any{"kmOff": true, "roundHours": 8.0}, &ww.Schedule{StartHour: 22, RoundHours: 8, Rounds: 1}},
		{map[string]any{"kmOff": true}, nil},
		{map[string]any{"startHour": 6.0, "roundHours": 6.0}, nil},
	} {
		var gc ww.Config
		if err := applyGameSettings(&gc, c.in); err != nil {
			t.Fatalf("%v: %v", c.in, err)
		}
		if !reflect.DeepEqual(gc.Schedule, c.want) {
			t.Fatalf("%v → lịch %+v, mong đợi %+v", c.in, gc.Schedule, c.want)
		}
		if err := gc.Validate(); err != nil {
			t.Fatalf("%v → %v", c.in, err)
		}
	}
}

// Luật vai và luật phiếu của bot cũng theo giờ của vòng mở đầu ngày.
func TestRoleAndVoteRulesFollowSchedule(t *testing.T) {
	for _, c := range []struct {
		cfg  ww.Config
		role ww.Role
		want string
	}{
		{ww.Config{}, ww.Wolf, "từ 22h tới 0h."},
		{threeShifts, ww.Wolf, "từ 6h tới 6h30."},
		{threeShifts, ww.Witch, "dùng từ 6h30 tới 9h."},
		{threeShifts, ww.Cupid, "Quá 6h30 chưa ghép"},
	} {
		if got := roleRulesFor(c.role, c.cfg, "1"); !strings.Contains(got, c.want) {
			t.Fatalf("%s = %q, thiếu %q", c.role, got, c.want)
		}
	}
	got := botVoteRulesFor(threeShifts, "1")
	if !strings.HasPrefix(got, "Đề cử: 11h30 tối đa 3 người") || !strings.Contains(got, "mọi phiên chốt cùng lúc 12h") {
		t.Fatalf("luật phiếu = %q", got)
	}
}
