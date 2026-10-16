package backend

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func TestAppVersionOK(t *testing.T) {
	cases := []struct {
		have, min string
		want      bool
	}{
		{"", "", true},
		{"1.0.0", "", true},
		{"", "1.5.0", false}, // bản 1.4.3 chưa gửi header
		{"1.5.0", "1.5.0", true},
		{"1.5.0+42", "1.5.0", true},
		{"1.5.1-beta", "1.5.0", true},
		{"1.4.9", "1.5.0", false},
		{"1.10.0", "1.9.0", true}, // so theo số, không theo chữ
		{"1.5", "1.5.0", true},
		{"1.5.0.1", "1.5", true},
		{"2", "1.99.99", true},
		{"abc", "1.0.0", false},
		{"1.6.0", "x", false}, // cấu hình sai thì chặn, để lộ ra lúc test
	}
	for _, c := range cases {
		if got := appVersionOK(c.have, c.min); got != c.want {
			t.Errorf("appVersionOK(%q, %q) = %v, mong đợi %v", c.have, c.min, got, c.want)
		}
	}
}

func TestRequirementsFor(t *testing.T) {
	reqs := requirementsFor(viewerLink{linked: true, inPsc: false}, "1.0.0", "1.2.0")
	got := map[string]bool{}
	for _, r := range reqs {
		got[r.Key] = r.OK
	}
	if got["telegram_linked"] != true || got["in_psc"] != false || got["app_version"] != false || requirementsMet(reqs) {
		t.Fatalf("reqs = %+v", reqs)
	}
	if reqs[0].Action != nil || reqs[2].Action == nil || reqs[2].Action.Type != "update_app" || reqs[2].Label != "Bản app từ 1.2.0 trở lên" {
		t.Fatalf("action/label = %+v", reqs)
	}
	// inPsc chỉ tính khi đã liên kết.
	if requirementsFor(viewerLink{inPsc: true}, "", "")[1].OK {
		t.Fatal("chưa liên kết mà in_psc ok")
	}
	if !requirementsMet(requirementsFor(viewerLink{linked: true, inPsc: true}, "", "")) {
		t.Fatal("đủ điều kiện mà bị chặn")
	}
}

func feedDoc(t *testing.T, phaseKey string, evs ...ww.Event) map[string]any {
	t.Helper()
	raw, err := json.Marshal(evs)
	if err != nil {
		t.Fatal(err)
	}
	return map[string]any{"seq": int64(3), "phaseKey": phaseKey, "events": string(raw), "at": time.Unix(100, 0), "wallAt": time.Unix(50, 0)}
}

func TestFeedItemText(t *testing.T) {
	names := map[string]gamePlayerInfo{"a": {name: "An"}, "b": {name: "Bình"}, "c": {name: "Chi"}}
	cases := []struct {
		key   string
		evs   []ww.Event
		title string
		lines []string
	}{
		{"r2/dawn", nil, "Bản tin đêm 2", []string{"Đêm qua không ai chết."}},
		{"r1/dawn", []ww.Event{{Kind: ww.EventDeath, UID: "a", Role: ww.Hunter}, {Kind: ww.EventHunterTurn, UID: "a"}},
			"Bản tin đêm 1", []string{"An đã chết. Lá bài: Thợ săn.", "An là Thợ săn, được bắn một người."}},
		{"r1/day", []ww.Event{{Kind: ww.EventNominee, UID: "b", Counts: map[string]int{"b": 3, "c": 3}, Draw: true}},
			"Đề cử ngày 1", []string{"Bình lên giàn với 3 đề cử, bốc thăm vì hoà."}},
		{"r3/day", []ww.Event{{Kind: ww.EventNominee}}, "Đề cử ngày 3", []string{"Không ai được đề cử, hôm nay không ai lên giàn."}},
		{"r1/trial", []ww.Event{
			{Kind: ww.EventVoteCut, Targets: []string{"a", "c"}},
			{Kind: ww.EventVoteResult, UID: "b", Hang: 4, Spare: 2, Hanged: true},
			{Kind: ww.EventDeath, UID: "b", Role: ww.Wolf},
			{Kind: ww.EventWinner, Team: ww.TeamVillage},
		}, "Biểu quyết ngày 1", []string{"Tổng km chưa đủ nên An, Chi mất phiếu.", "Treo 4, Tha 2: Bình bị treo.", "Bình đã chết. Lá bài: Sói.", "Phe Dân thắng."}},
		{"r2/trial", []ww.Event{{Kind: ww.EventVoteResult, UID: "b", Hang: 2, Spare: 2}}, "Biểu quyết ngày 2", []string{"Treo 2, Tha 2: Bình được tha."}},
		{"r4/trial", []ww.Event{{Kind: ww.EventVoteResult, UID: "c", Reason: ww.ReasonNoTrial}}, "Biểu quyết ngày 4", []string{"Chi đã rời PSC, bỏ biểu quyết."}},
		{"r2/night/hunter", []ww.Event{{Kind: ww.EventDeath, UID: "c", Role: ww.Seer}}, "Thợ săn bắn", []string{"Chi đã chết. Lá bài: Tiên tri."}},
		{"r14/trial", []ww.Event{{Kind: ww.EventWinner, Team: ww.TeamVillage, Reason: ww.ReasonTimeout}}, "Biểu quyết ngày 14", []string{"Hết 14 vòng, Phe Dân thắng."}},
		{"r1/night", nil, "Đêm 1", []string{}},
		{"r1/day", []ww.Event{{Kind: ww.EventDeath, UID: "zz", Role: ww.Villager}}, "Đề cử ngày 1", []string{"Người chơi đã chết. Lá bài: Dân."}},
	}
	for _, c := range cases {
		item, err := feedItem(feedDoc(t, c.key, c.evs...), names)
		if err != nil {
			t.Fatal(err)
		}
		if item.Title != c.title || strings.Join(item.Lines, "|") != strings.Join(c.lines, "|") {
			t.Errorf("%s: %q %q, mong đợi %q %q", c.key, item.Title, item.Lines, c.title, c.lines)
		}
	}
	// Giờ của dòng feed là giờ thật (wallAt), không phải giờ ván đã bị đẩy.
	item, _ := feedItem(feedDoc(t, "r1/dawn"), names)
	if !item.At.Equal(time.Unix(50, 0)) || item.Seq != 3 {
		t.Fatalf("at = %v, seq = %d", item.At, item.Seq)
	}
	if _, err := feedItem(map[string]any{"events": "{"}, names); err == nil {
		t.Fatal("events hỏng mà không báo lỗi")
	}
}

func TestRejectHTTPNeverServerError(t *testing.T) {
	cases := map[ww.Reject]int{
		ww.ErrPhaseClosed: 409, ww.ErrPaused: 409, ww.ErrNotAlive: 422, ww.ErrNotYourRole: 422,
		ww.ErrKmInsufficient: 422, ww.ErrInvalidTarget: 422, ww.ErrLoverTarget: 422, ww.ErrGuardRepeat: 422, ww.ErrAlreadyUsed: 422,
	}
	for r, want := range cases {
		he := rejectHTTP(ww.KindGuard, r)
		if he.Status != want || he.Code != string(r) || he.Message == "" || he.Message == "Chưa làm được lúc này." {
			t.Errorf("%s: %+v", r, he)
		}
	}
	if got := rejectHTTP(ww.KindWitchSave, ww.ErrInvalidTarget).Message; got != "Đêm nay không có ai để cứu." {
		t.Fatalf("bình cứu: %q", got)
	}
}

// Bug của L1: preflight của DELETE /v1/telegram/link bị chặn vì CORS chỉ cho
// GET, POST; header X-App-Version (3.8) cũng phải được cho qua.
func TestCORSPreflightAllowsDeleteAndAppHeaders(t *testing.T) {
	srv := NewAPIServer(Config{AllowedWebOrigins: map[string]struct{}{"https://threei.run": {}}}, &Dependencies{})
	r := httptest.NewRequest(http.MethodOptions, "/v1/telegram/link", nil)
	r.Header.Set("Origin", "https://threei.run")
	r.Header.Set("Access-Control-Request-Method", "DELETE")
	w := httptest.NewRecorder()
	srv.ServeHTTP(w, r)
	if w.Code != 204 || !strings.Contains(w.Header().Get("Access-Control-Allow-Methods"), "DELETE") {
		t.Fatalf("preflight: %d %v", w.Code, w.Header())
	}
	for _, h := range []string{"Authorization", "X-App-Version", "X-App-Platform"} {
		if !strings.Contains(w.Header().Get("Access-Control-Allow-Headers"), h) {
			t.Fatalf("thiếu %s trong Allow-Headers: %v", h, w.Header())
		}
	}
}

func TestWriteErrorMergesExtra(t *testing.T) {
	s := &Server{}
	w := httptest.NewRecorder()
	s.writeError(w, httptest.NewRequest("POST", "/x", nil), &HTTPError{Status: 422, Code: "requirements_unmet", Message: "m", Extra: map[string]any{"requirements": []string{"a"}}})
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	if w.Code != 422 || body["error"] != "requirements_unmet" || body["requirements"] == nil {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
}

func TestAPIStatusMapsPause(t *testing.T) {
	g := map[string]any{"status": gameRunning, "paused": true, "deadline": time.Unix(100, 0), "phaseKey": "r1/night"}
	if apiStatus(g) != "paused" || statusLabel(g) != "Tạm dừng" || nextDeadline(g) != nil {
		t.Fatalf("%s %s %v", apiStatus(g), statusLabel(g), nextDeadline(g))
	}
	if g := map[string]any{"status": gameEnded, "paused": true}; apiStatus(g) != gameEnded {
		t.Fatal("ván đã kết thúc vẫn ra paused")
	}
}

func TestBalanceScoreByHand(t *testing.T) {
	cases := []struct {
		n    int
		cfg  ww.Config
		want int
	}{
		{10, ww.Config{}, -12 + 7 + 3 + 6},                                       // 2 sói, Tiên tri, Bảo vệ, 6 dân
		{16, ww.Config{}, -18 + 7 + 3 + 4 + 3 - 3 + 8},                           // đủ 5 vai đặc biệt, 8 dân
		{13, ww.Config{Disabled: []ww.Role{ww.Cupid}}, -18 + 7 + 3 + 4 + 3 + 6},  // Cupid thành dân
		{12, ww.Config{Disabled: []ww.Role{ww.Seer, ww.Witch}}, -18 + 3 + 3 + 7}, // Bảo vệ, Thợ săn, 7 dân
	}
	for _, c := range cases {
		roles, err := ww.Composition(c.n, c.cfg)
		if err != nil {
			t.Fatal(err)
		}
		if got := balanceScore(roles); got != c.want {
			t.Errorf("n=%d %v: %d, mong đợi %d", c.n, c.cfg.Disabled, got, c.want)
		}
	}
}
