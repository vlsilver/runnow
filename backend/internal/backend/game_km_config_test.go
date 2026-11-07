package backend

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// reminderAt dựng renderer có state ở phase cho sẵn và km đang gom live, để
// render tin nhắc như TestRenderReminderLiveKm.
func reminderAt(t *testing.T, cfg ww.Config, phase ww.Phase, nominee string, live map[string]float64) func() string {
	r := testRenderer()
	r.cfg = cfg
	st := ww.NewState(ww.Seed{1}, cfg, map[string]ww.Role{"w1": ww.Wolf, "w2": ww.Villager, "s1": ww.Seer, "f1": ww.Villager}, msgStart)
	st.Phase, st.Nominee = phase, nominee
	r.st, r.now = st, func() time.Time { return time.Date(2026, 10, 24, 21, 0, 0, 0, vietnam) }
	r.store = &GameStore{frameKm: func(_ context.Context, uid string, _ time.Time) (FrameKm, error) {
		if live == nil {
			return FrameKm{}, errors.New("ván tắt km mà vẫn đọc km")
		}
		return FrameKm{Meters: live[uid]}, nil
	}}
	return func() string {
		out, err := r.renderReminder(context.Background(), chatGroup, `{"reason":"vote"}`)
		if err != nil {
			t.Fatal(err)
		}
		if cfg.KmOff && out.markup != nil {
			t.Fatalf("ván tắt km mà vẫn có nút xem km: %v", out.markup)
		}
		return strings.Join(out.parts, "\n")
	}
}

const voteNudge = "<b>Nhắc biểu quyết</b>\nBiểu quyết Treo hay Tha đóng lúc 22h. Ai chưa bỏ phiếu thì vào app RunNow."

// Ván tắt km: bản tin 22h không có bảng km, tin nhắc không đọc km, không có
// nút "Xem km của tôi".
func TestKmOffHidesKmFromGroup(t *testing.T) {
	r := testRenderer()
	r.cfg, r.gameID = ww.Config{KmOff: true}, "g1"
	out := renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/setup", "round": 1, "phase": "night", "call": "night", "wake": []string{"wolf"},
		"km": map[string]float64{"w1": 2500},
	})
	if strings.Contains(out.parts[0], "km") || out.markup != nil {
		t.Fatalf("22h ván tắt km = %q, markup %v", out.parts, out.markup)
	}
	if got := reminderAt(t, ww.Config{KmOff: true}, ww.PhaseTrial, "f1", nil)(); got != voteNudge {
		t.Fatalf("nhắc ván tắt km = %q", got)
	}
}

// Ván có km từng vai: câu đầu bảng km nói km của từng kỹ năng, sói cắn tự do.
func TestKmBoardShowsPerRoleKm(t *testing.T) {
	cfg := ww.Config{KmPerUnit: 2.5, SkillKm: map[ww.Role]float64{ww.Wolf: 0, ww.Seer: 2, ww.Guard: 0}}
	got := reminderAt(t, cfg, ww.PhaseDay, "", map[string]float64{"w1": 900, "w2": 3100, "s1": 2600})()
	want := "Km cần cho kỹ năng: Tiên tri 2 km, Bảo vệ không cần km, Phù thuỷ 2.5 km, Thợ săn 2.5 km. Sói cắn không cần km. Cupid không cần km."
	if !strings.Contains(got, "\n"+want+"\n") {
		t.Fatalf("bảng km = %q", got)
	}
}

// Luật top: dự báo ai được x2 phiếu nếu chốt bây giờ. f1 lên giàn; w2 3,1 km
// và s1 2,6 km đủ 2,5 km, w1 0,9 km không đủ.
func TestReminderVoteTopForecast(t *testing.T) {
	last := func(cfg ww.Config, live map[string]float64) string {
		lines := strings.Split(reminderAt(t, cfg, ww.PhaseTrial, "f1", live)(), "\n")
		return lines[len(lines)-2]
	}
	cfg := ww.Config{KmPerUnit: 2.5, Vote: ww.VoteTop, TopVoters: 1}
	if got := last(cfg, map[string]float64{"w1": 900, "w2": 3100, "s1": 2600}); got !=
		"Biểu quyết nếu chốt bây giờ: Bình &amp; Co được tính 2 phiếu (1 người chạy nhiều nhất, mỗi người đủ 2.5 km)." {
		t.Fatalf("top = %q", got)
	}
	if got := last(cfg, map[string]float64{"w1": 900, "w2": 2600, "s1": 2600}); got !=
		"Biểu quyết nếu chốt bây giờ: bốc thăm 1 người được tính 2 phiếu trong: Chi, Bình &amp; Co (1 người chạy nhiều nhất, mỗi người đủ 2.5 km)." {
		t.Fatalf("top bằng km = %q", got)
	}
	if got := last(cfg, map[string]float64{"w1": 900}); got !=
		"Biểu quyết nếu chốt bây giờ: chưa ai đủ 2.5 km để được tính 2 phiếu." {
		t.Fatalf("top chưa ai đủ = %q", got)
	}
}

// Hộp "Xem km của tôi" theo config: tắt km thì nói thẳng và không đọc km;
// chỉnh km từng vai thì nói mức của vai người bấm; sói cắn tự do thì không có
// dòng km phe.
func TestKmAlertFollowsConfig(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "s1": ww.Seer, "v1": ww.Villager}
	wall := time.Date(2026, 10, 24, 15, 7, 0, 0, vietnam)
	reads := 0
	s := &GameStore{frameKm: func(context.Context, string, time.Time) (FrameKm, error) {
		reads++
		return FrameKm{Meters: 1250}, nil
	}}
	alert := func(cfg ww.Config, uid string) string {
		st := ww.NewState(ww.Seed{1}, cfg, roles, msgStart)
		st.Phase = ww.PhaseDay
		got, err := s.kmAlert(context.Background(), nil, st, uid, wall)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	if got := alert(ww.Config{KmOff: true}, "s1"); got != "Ván này không dùng km." || reads != 0 {
		t.Fatalf("tắt km = %q, đọc km %d lần", got, reads)
	}
	cfg := ww.Config{KmPerUnit: 2.5, SkillKm: map[ww.Role]float64{ww.Wolf: 0, ww.Seer: 3}}
	if got := alert(cfg, "s1"); got != "Tới 15:07 bạn có 1.2 km, chốt lúc 22h. Cần đủ 3 km.\nKm chốt 22h gần nhất: 0 km." {
		t.Fatalf("tiên tri = %q", got)
	}
	if got := alert(cfg, "v1"); got != "Tới 15:07 bạn có 1.2 km, chốt lúc 22h.\nKm chốt 22h gần nhất: 0 km." {
		t.Fatalf("dân = %q", got)
	}
	if got := alert(cfg, "w1"); got != "Tới 15:07 bạn có 1.2 km, chốt lúc 22h.\nKm chốt 22h gần nhất: 0 km.\nPhe Sói cắn không cần km." {
		t.Fatalf("sói = %q", got)
	}
}

// Sói đã chết mà group biết: lật bài ra Sói, hoặc bị treo lộ phe Sói. Người lật
// bài thì không đếm lại theo phe.
func TestPublicDeadWolves(t *testing.T) {
	data := map[string]any{
		"revealed":      map[string]any{"a": "wolf", "b": "seer", "c": "wolf"},
		"revealedTeams": map[string]any{"c": "wolves", "d": "wolves", "e": "village"},
	}
	if got := publicDeadWolves(data); got != 3 {
		t.Fatalf("sói đã chết = %d, mong đợi 3 (a, c, d)", got)
	}
	if got := publicDeadWolves(map[string]any{}); got != 0 {
		t.Fatalf("chưa ai chết = %d", got)
	}
}

// Ván tắt km: luật từng vai không nhắc km, kể cả câu "không cần km".
func TestRoleRulesKmOff(t *testing.T) {
	for _, role := range []ww.Role{ww.Wolf, ww.Seer, ww.Hunter} {
		if got := roleRulesFor(role, ww.Config{KmOff: true}, "1"); strings.Contains(got, "km") {
			t.Fatalf("%s = %q", role, got)
		}
	}
}

// Ai được x2 phiếu là luật công khai như ai mất phiếu, nên vào bản tin group.
func TestVoteBonusIsPublic(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{Vote: ww.VoteTop}, msgRoles(), msgStart)
	for _, kind := range []ww.EventKind{ww.EventVoteCut, ww.EventVoteBonus} {
		if _, ok := publicEvent(st, ww.Event{Kind: kind, Targets: []string{"v1"}}); !ok {
			t.Fatalf("%s phải công khai", kind)
		}
	}
}

// Luật flat: km không tác động lên phiếu nên không dự báo phiếu, câu chân chỉ
// nói km dùng cho kỹ năng.
func TestReminderVoteFlatNoForecast(t *testing.T) {
	got := reminderAt(t, ww.Config{KmPerUnit: 2.5, Vote: ww.VoteFlat}, ww.PhaseTrial, "f1", map[string]float64{"w1": 900})()
	if strings.Contains(got, "Biểu quyết nếu chốt") || !strings.HasSuffix(got, "\nKm chốt 22h dùng cho kỹ năng đêm nay. Chạy xong mở app cho km kịp đồng bộ.") {
		t.Fatalf("flat = %q", got)
	}
}
