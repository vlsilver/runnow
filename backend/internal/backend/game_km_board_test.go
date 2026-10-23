package backend

import (
	"context"
	"errors"
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Vào đêm thì bản tin 22h chở km vừa chốt của mọi người còn sống, ai chưa có
// km là 0, để group biết ai đủ km dùng kỹ năng. Bước khác không chở.
func TestStepMessagesNightCarriesKm(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	night, evs, err := ww.Step(st, ww.Inputs{Km: map[string]float64{"w1": 1200, "seer": 300}})
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]float64{"w1": 1200, "seer": 300, "w2": 0, "guard": 0, "witch": 0, "hunter": 0, "cupid": 0, "v1": 0, "v2": 0, "v3": 0}
	if got := stepMessages(st, night, evs)[0].Data["km"]; !reflect.DeepEqual(got, want) {
		t.Fatalf("km 22h = %v", got)
	}
	dawn, evs := mustStep(t, night)
	if got, ok := stepMessages(night, dawn, evs)[0].Data["km"]; ok {
		t.Fatalf("0h mà vẫn chở km: %v", got)
	}
}

// Bản tin 22h kèm bảng km: đủ ngưỡng (2,5 km ở renderer test) và chưa đủ, nhiều
// km đứng trước, không nhắc vai. 2499 m hiện 2.4 chứ không làm tròn lên 2.5.
func TestRenderNightDigestKmBoard(t *testing.T) {
	out := renderOne(t, testRenderer(), chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/setup", "round": 1, "phase": "night", "call": "night", "wake": []string{"wolf"},
		"km": map[string]float64{"w1": 2500, "w2": 2499, "s1": 7340, "f1": 0},
	})
	want := "<b>Đêm 1 buông xuống, cả làng đi ngủ.</b>\nQuản trò gọi lần lượt:\n" +
		"1. Sói thức dậy, cả phe chọn một người để cắn, chốt lúc 0h.\n" +
		"Ai có vai thì bấm trong tin 3i nhắn riêng hoặc trong app RunNow.\n\n" +
		"<b>Km chốt 22h, dùng cho đêm 1</b>\n" +
		"Có vai đêm thì cần đủ 2.5 km mới dùng được kỹ năng. Sói tính chung cả phe: tổng km sói còn sống phải đủ 2.5 km cho mỗi sói. Cupid không cần km.\n" +
		"Đủ km: Chi 7.3 · An &lt;Sói&gt; 2.5\n" +
		"Chưa đủ: Bình &amp; Co 2.4 · Giả 0"
	if len(out.parts) != 1 || out.parts[0] != want {
		t.Fatalf("22h = %q", out.parts)
	}
}

// Sói có km riêng đủ ngưỡng mà phe chưa đủ tổng km thì nút Cắn nói rõ là thiếu
// km của cả phe, không để người chơi tưởng mình đã đủ mà app lỗi.
func TestWolfBiteDisabledReasonNamesTeamKm(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	night, _, err := ww.Step(st, ww.Inputs{Km: map[string]float64{"w1": 1200}})
	if err != nil {
		t.Fatal(err)
	}
	acts := meActions(night, "w1", nil, nil, nil, night.NightAt.Add(time.Hour), 0)
	if len(acts) != 1 || acts[0].Kind != string(ww.KindWolfBite) || acts[0].Enabled {
		t.Fatalf("w1 = %+v", acts)
	}
	want := "Phe Sói chưa đủ km: cả phe có 1.2 km, cần 2 km (1 km cho mỗi sói còn sống). " +
		"Sói tính chung cả phe nên km riêng của bạn đủ thì vẫn chưa cắn được. Km đã chốt lúc 22h, muốn cắn đêm sau thì cả phe chạy thêm trước 22h."
	if acts[0].DisabledReason != want {
		t.Fatalf("lý do = %q", acts[0].DisabledReason)
	}
}

// 0h phe Sói thiếu km: tin riêng của từng sói chở km cả phe và mức cần, lúc
// gửi ghi ra thành nguyên nhân. Tin cũ không có số thì giữ câu cũ.
func TestWolvesShortOfKmPrivateDMNamesNumbers(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	night, _, err := ww.Step(st, ww.Inputs{Km: map[string]float64{"w1": 1200}})
	if err != nil {
		t.Fatal(err)
	}
	dawn, evs, err := ww.Step(night, ww.Inputs{})
	if err != nil {
		t.Fatal(err)
	}
	// Đêm 1 Cupid không ghép thì bot ghép thay, nên cặp đôi cũng có tin riêng;
	// chỉ tin của sói chở km phe.
	wolfKm := map[string]any{}
	for _, m := range stepMessages(night, dawn, evs) {
		if m.Template == tplPrivate {
			wolfKm[m.ChatKey] = m.Data["wolfKm"]
		}
	}
	want := map[string]float64{"have": 1200, "need": 2000}
	if !reflect.DeepEqual(wolfKm[dmChat("w1")], want) || !reflect.DeepEqual(wolfKm[dmChat("w2")], want) {
		t.Fatalf("tin riêng của sói = %+v", wolfKm)
	}
	for key, v := range wolfKm {
		if key != dmChat("w1") && key != dmChat("w2") && v != nil {
			t.Fatalf("%s không phải sói mà nhận km phe: %v", key, v)
		}
	}

	r := testRenderer() // ngưỡng 2,5 km
	out := renderOne(t, r, dmChat("w1"), tplPrivate, map[string]any{
		"events": []ww.Event{{Kind: ww.EventWolvesTarget, Reason: ww.VoidNoKm}}, "wolfKm": map[string]float64{"have": 2499, "need": 5000},
	})
	if out.parts[0] != dmText("Phe Sói chưa đủ km nên đêm nay không cắn được ai: cả phe có 2.4 km, cần 5 km (2.5 km cho mỗi sói còn sống). Muốn cắn đêm sau thì cả phe chạy thêm trước 22h.") {
		t.Fatalf("0h = %q", out.parts[0])
	}
}

// Tin nhắc 15h, 21h kèm km đang gom cho mốc 22h tới của người còn sống, tính
// lúc gửi. Ván đã sang đêm (tin nhắc gửi trễ) hay ván thử thì chỉ còn lời nhắc.
// Đọc km lỗi thì tin lỗi chứ không gửi bảng thiếu.
func TestRenderReminderLiveKm(t *testing.T) {
	r := testRenderer()
	st := ww.NewState(ww.Seed{1}, r.cfg, map[string]ww.Role{"w1": ww.Wolf, "w2": ww.Villager, "s1": ww.Seer, "f1": ww.Villager}, msgStart)
	st.Phase = ww.PhaseDay
	st.Players["f1"].Alive = false
	live := map[string]float64{"w1": 900, "w2": 3100, "s1": 2600}
	var ends []time.Time
	var readErr error
	r.st, r.now = st, func() time.Time { return time.Date(2026, 10, 16, 15, 0, 30, 0, vietnam) }
	r.store = &GameStore{frameKm: func(_ context.Context, uid string, end time.Time) (FrameKm, error) {
		ends = append(ends, end)
		return FrameKm{Meters: live[uid]}, readErr
	}}
	render := func() (string, error) {
		out, err := r.renderReminder(context.Background(), chatGroup, `{"reason":"nominate"}`)
		return strings.Join(out.parts, "|"), err
	}

	nudge := "<b>Nhắc đề cử</b>\nĐề cử đóng lúc 17h. Ai chưa đề cử thì vào app RunNow để chọn."
	want := nudge + "\n\n<b>Km tới 15:00, chốt lúc 22h</b>\n" +
		"Có vai đêm thì cần đủ 2.5 km mới dùng được kỹ năng. Sói tính chung cả phe: tổng km sói còn sống phải đủ 2.5 km cho mỗi sói. Cupid không cần km.\n" +
		"Đủ km: Bình &amp; Co 3.1 · Chi 2.6\n" +
		"Chưa đủ: An &lt;Sói&gt; 0.9\n" +
		"Km chốt 22h dùng cho biểu quyết tối nay và kỹ năng đêm nay. Chạy xong mở app cho km kịp đồng bộ."
	if got, err := render(); err != nil || got != want {
		t.Fatalf("15h = %q, %v", got, err)
	}
	frameEnd := time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam)
	if len(ends) != 3 || !ends[0].Equal(frameEnd) || !ends[2].Equal(frameEnd) {
		t.Fatalf("khung km = %v", ends)
	}

	st.Phase = ww.PhaseNight
	if got, err := render(); err != nil || got != nudge {
		t.Fatalf("gửi trễ sang đêm = %q, %v", got, err)
	}
	st.Phase, r.gameData = ww.PhaseDay, map[string]any{"testMode": true}
	if got, err := render(); err != nil || got != nudge {
		t.Fatalf("ván thử = %q, %v", got, err)
	}
	r.gameData, readErr = nil, errors.New("firestore hỏng")
	if _, err := render(); err == nil {
		t.Fatal("đọc km lỗi mà tin vẫn gửi")
	}
}
