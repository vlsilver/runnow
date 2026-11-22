//go:build emulator

package backend

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// standInGame là ván đêm 1 có MyBot của seer và guard (allowlist, không cần
// đồng ý AI), bot trả reply.
func standInGame(t *testing.T, reply string) (*storeGame, *GameStandIn, *fakeLearn) {
	t.Helper()
	g, _ := nightGame(t)
	seed(t, g.db, "agentState/config", map[string]any{"memberUids": []any{"seer", "guard"}})
	seed(t, g.db, "agents/seer", map[string]any{"name": "Cú", "persona": "điềm tĩnh"})
	seed(t, g.db, "agents/guard", map[string]any{"name": "Khiên"})
	llm := &fakeLearn{reply: func(_, _ string) (string, error) { return reply, nil }}
	return g, NewGameStandIn(g.store, NewAgentStore(g.db), llm), llm
}

func (g *storeGame) closesAt(kind ww.Kind) time.Time {
	g.t.Helper()
	_, closes := g.state().Window(kind)
	if closes.IsZero() {
		g.t.Fatalf("%s chưa có giờ đóng", kind)
	}
	return closes
}

func (g *storeGame) setStandIn(uid string, on bool) {
	g.t.Helper()
	if err := g.store.SetStandIn(context.Background(), g.id, uid, on, time.Now()); err != nil {
		g.t.Fatal(err)
	}
}

func (g *storeGame) meAction(uid string, kind ww.Kind, wall time.Time) (GameMe, GameAction) {
	g.t.Helper()
	me, err := g.store.Me(context.Background(), g.id, GameViewer{UID: uid}, wall)
	if err != nil {
		g.t.Fatal(err)
	}
	for _, a := range me.Actions {
		if a.Kind == string(kind) {
			return me, a
		}
	}
	g.t.Fatalf("%s không có lượt %s", uid, kind)
	return me, GameAction{}
}

func dueKinds(t *testing.T, g *storeGame, wall time.Time) []string {
	t.Helper()
	due, err := g.store.StandInsDue(context.Background(), g.id, wall)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, d := range due {
		out = append(out, d.UID+"/"+d.Kind)
	}
	slices.Sort(out)
	return out
}

// Chỉ người đã bật mới được đỡ, và chỉ trong 15 phút trước giờ đóng. Bot soi
// thay seer, Me của seer cho thấy bot chọn và lý do; lượt sau không gọi lại model.
func TestEmulatorStandInPicksNearClose(t *testing.T) {
	g, bot, llm := standInGame(t, `{"targets":["w1"],"choice":"","reason":"w1 im lặng cả ngày"}`)
	g.setStandIn("seer", true)
	g.setStandIn("w1", true) // ván luật cũ: sói bấm sau cùng thắng, bot không cắn thay
	if bite := g.closesAt(ww.KindWolfBite); true {
		g.advance(bite.Add(-10 * time.Minute))
		if got := dueKinds(t, g, bite.Add(-10*time.Minute)); slices.Contains(got, "w1/wolf_bite") {
			t.Fatalf("hẹn cắn thay ở ván luật cũ: %v", got)
		}
	}
	closes := g.closesAt(ww.KindSeerPeek)

	g.advance(closes.Add(-20 * time.Minute))
	if got := dueKinds(t, g, closes.Add(-20*time.Minute)); len(got) != 0 {
		t.Fatalf("20 phút trước giờ đóng đã hẹn %v", got)
	}
	wall := closes.Add(-10 * time.Minute)
	g.advance(wall)
	if got := dueKinds(t, g, wall); !slices.Equal(got, []string{"seer/seer_peek"}) {
		t.Fatalf("hẹn %v, muốn chỉ seer/seer_peek", got)
	}

	task := standInTask{GameID: g.id, UID: "seer", Kind: string(ww.KindSeerPeek), TurnKey: "r1"}
	if out, err := bot.Turn(context.Background(), task, wall); err != nil || out != "applied" {
		t.Fatalf("Turn = %q, %v", out, err)
	}
	me, a := g.meAction("seer", ww.KindSeerPeek, wall)
	if !me.StandIn {
		t.Fatal("Me.standIn = false")
	}
	if a.Selected == nil || !slices.Equal(a.Selected.Targets, []string{"w1"}) || a.Selected.By != "agent" || a.Selected.Reason != "w1 im lặng cả ngày" {
		t.Fatalf("selected = %+v", a.Selected)
	}
	if in := llm.calls[0].input; !strings.Contains(in, "id=w1") || !strings.Contains(in, "VAI CỦA CHỦ: "+roleLabels[ww.Seer]) {
		t.Fatalf("input thiếu vai của chủ hoặc lựa chọn:\n%s", in)
	}

	if out, _ := bot.Turn(context.Background(), task, wall.Add(time.Minute)); out != "skipped_not_needed" {
		t.Fatalf("lần hai = %q", out)
	}
	if len(llm.calls) != 1 {
		t.Fatalf("gọi model %d lần", len(llm.calls))
	}
}

// Chủ đã bấm thì bot không gọi model; chủ bấm giữa lúc bot đọc Me và lúc bot
// ghi thì OnlyIfEmpty giữ lựa chọn của chủ.
func TestEmulatorStandInOwnerWins(t *testing.T) {
	g, bot, llm := standInGame(t, `{"targets":["v1"],"choice":"","reason":"x"}`)
	g.setStandIn("guard", true)
	wall := g.closesAt(ww.KindGuard).Add(-10 * time.Minute)
	g.advance(wall)

	if r := g.submit(ActionRequest{UID: "guard", Kind: ww.KindGuard, Targets: []string{"v2"}, ReceivedAt: wall.Add(-time.Minute)}); !r.Applied {
		t.Fatalf("chủ bấm: %+v", r)
	}
	out, err := bot.Turn(context.Background(), standInTask{GameID: g.id, UID: "guard", Kind: string(ww.KindGuard), TurnKey: "r1"}, wall)
	if err != nil || out != "skipped_not_needed" || len(llm.calls) != 0 {
		t.Fatalf("Turn = %q, %v, %d lần gọi model", out, err, len(llm.calls))
	}

	r := g.submit(ActionRequest{UID: "guard", Kind: ww.KindGuard, Targets: []string{"v1"}, ReceivedAt: wall, Source: "agent", OnlyIfEmpty: true})
	if r.Applied || r.Current == nil || !slices.Equal(r.Current.Targets, []string{"v2"}) {
		t.Fatalf("bot ghi đè chủ: %+v", r)
	}
	if got := g.storedTargets("guard", ww.KindGuard); len(got) != 1 || got[0] != "v2" {
		t.Fatalf("đang lưu %v", got)
	}
}

// Model chọn id không có trong danh sách thì bỏ lượt, không ghi gì.
func TestEmulatorStandInBadPickWritesNothing(t *testing.T) {
	g, bot, _ := standInGame(t, `{"targets":["không-có"],"choice":"","reason":"x"}`)
	g.setStandIn("seer", true)
	wall := g.closesAt(ww.KindSeerPeek).Add(-5 * time.Minute)
	g.advance(wall)
	out, err := bot.Turn(context.Background(), standInTask{GameID: g.id, UID: "seer", Kind: string(ww.KindSeerPeek), TurnKey: "r1"}, wall)
	if err != nil || out != "skipped_bad_pick" {
		t.Fatalf("Turn = %q, %v", out, err)
	}
	if _, a := g.meAction("seer", ww.KindSeerPeek, wall); a.Selected != nil {
		t.Fatalf("đã ghi %+v", a.Selected)
	}
}

// Chưa bật, đã tắt, hay chưa đồng ý AI thì bot không đọc gì gửi model.
func TestEmulatorStandInNeedsOptInAndConsent(t *testing.T) {
	g, bot, llm := standInGame(t, `{"targets":["w1"],"choice":"","reason":"x"}`)
	wall := g.closesAt(ww.KindSeerPeek).Add(-5 * time.Minute)
	task := standInTask{GameID: g.id, UID: "seer", Kind: string(ww.KindSeerPeek), TurnKey: "r1"}
	if out, _ := bot.Turn(context.Background(), task, wall); out != "skipped_off" {
		t.Fatalf("chưa bật = %q", out)
	}
	g.setStandIn("seer", true)
	g.setStandIn("seer", false)
	if out, _ := bot.Turn(context.Background(), task, wall); out != "skipped_off" {
		t.Fatalf("đã tắt = %q", out)
	}
	// Mở cho mọi người, seer ra khỏi allowlist và chưa đồng ý bản hiện hành.
	seed(t, g.db, "agentState/config", map[string]any{"open": true})
	g.setStandIn("seer", true)
	if out, _ := bot.Turn(context.Background(), task, wall); out != "skipped_no_consent" {
		t.Fatalf("chưa đồng ý = %q", out)
	}
	if len(llm.calls) != 0 {
		t.Fatalf("gọi model %d lần", len(llm.calls))
	}
}

// Người ngoài ván không bật được; ván kết thúc thì không bật được nữa, tắt vẫn được.
func TestEmulatorStandInSetRules(t *testing.T) {
	g, _, _ := standInGame(t, "")
	ctx := context.Background()
	if err := g.store.SetStandIn(ctx, g.id, "người-lạ", true, time.Now()); !errors.Is(err, errNotGamePlayer) {
		t.Fatalf("người lạ: %v", err)
	}
	g.setStandIn("v1", true)
	seedMerge(t, g, map[string]any{"status": gameCancelled})
	if err := g.store.SetStandIn(ctx, g.id, "v1", true, time.Now()); !errors.Is(err, errGameClosed) {
		t.Fatalf("ván đã huỷ: %v", err)
	}
	g.setStandIn("v1", false)
}

// Route bật cần MyBot đã tạo; Me trả standIn.
func TestEmulatorStandInRoute(t *testing.T) {
	g, h := runningAPIGame(t)
	h.deps.Agents = NewAgentStore(g.db)
	seed(t, g.db, "agentState/config", map[string]any{"memberUids": []any{"seer", "v1"}})
	seed(t, g.db, "agents/seer", map[string]any{"name": "Cú"})
	path := "/v1/games/" + g.id + "/me/stand-in"

	h.want(h.call("v1", "PUT", path, map[string]any{"on": true}, ""), 404, "agent_not_found")
	// Chưa tạo MyBot thì báo thế trước, chưa đòi đồng ý AI.
	h.want(h.call("v2", "PUT", path, map[string]any{"on": true}, ""), 404, "agent_not_found")
	h.want(h.call("seer", "PUT", path, map[string]any{}, ""), 400, "invalid_request")
	h.want(h.call("seer", "PUT", path, map[string]any{"on": true}, ""), 200, "")
	r := h.call("seer", "GET", "/v1/games/"+g.id+"/me", nil, "")
	h.want(r, 200, "")
	if !strings.Contains(string(r.raw), `"standIn":true`) {
		t.Fatalf("me = %s", r.raw)
	}
	// Tắt không cần MyBot.
	h.want(h.call("v1", "PUT", path, map[string]any{"on": false}, ""), 200, "")
}

// Thợ săn chết có phát bắn, nhưng bắn hay không là của chủ: bot không đỡ.
func TestEmulatorStandInSkipsHunterShot(t *testing.T) {
	g, _, _ := standInGame(t, "")
	g.setStandIn("hunter", true)
	bite := g.closesAt(ww.KindWolfBite).Add(-time.Hour)
	g.advance(bite)
	if r := g.submit(ActionRequest{UID: "w1", Kind: ww.KindWolfBite, Targets: []string{"hunter"}, ReceivedAt: bite}); !r.Applied {
		t.Fatalf("cắn: %+v", r)
	}
	// Người bị cắn chết lúc trời sáng (10h), lượt bắn mở 10h–12h.
	g.advance(g.closesAt(ww.KindWolfBite).Add(11 * time.Hour))
	if g.state().Hunter == nil {
		t.Fatal("thợ săn chưa có lượt bắn")
	}
	wall := g.closesAt(ww.KindHunterShoot).Add(-10 * time.Minute)
	g.advance(wall)
	if !slices.Contains(g.state().Available("hunter"), ww.KindHunterShoot) {
		t.Fatal("lượt bắn chưa mở")
	}
	if got := dueKinds(t, g, wall); slices.Contains(got, "hunter/hunter_shoot") {
		t.Fatalf("bot bắn thay: %v", got)
	}
}

// Chủ bấm mang giờ sớm hơn giờ bot ghi (bot lấy giờ trước khi gọi model) vẫn
// đè được lựa chọn của bot.
func TestEmulatorStandInOwnerBeatsEarlierAgentClock(t *testing.T) {
	g, _, _ := standInGame(t, "")
	wall := g.closesAt(ww.KindGuard).Add(-10 * time.Minute)
	g.advance(wall)
	if r := g.submit(ActionRequest{UID: "guard", Kind: ww.KindGuard, Targets: []string{"v1"}, ReceivedAt: wall, Source: "agent", OnlyIfEmpty: true}); !r.Applied {
		t.Fatalf("bot ghi: %+v", r)
	}
	if r := g.submit(ActionRequest{UID: "guard", Kind: ww.KindGuard, Targets: []string{"v2"}, ReceivedAt: wall.Add(-time.Second)}); !r.Applied {
		t.Fatalf("chủ không đè được bot: %+v", r)
	}
	if got := g.storedTargets("guard", ww.KindGuard); len(got) != 1 || got[0] != "v2" {
		t.Fatalf("đang lưu %v", got)
	}
}

// Task tới trễ sang vòng khác thì bỏ, không gọi model.
func TestEmulatorStandInStaleTurnSkipsModel(t *testing.T) {
	g, bot, llm := standInGame(t, `{"targets":["w1"],"choice":"","reason":"x"}`)
	g.setStandIn("seer", true)
	wall := g.closesAt(ww.KindSeerPeek).Add(-10 * time.Minute)
	g.advance(wall)
	out, err := bot.Turn(context.Background(), standInTask{GameID: g.id, UID: "seer", Kind: string(ww.KindSeerPeek), TurnKey: "r0"}, wall)
	if err != nil || out != "skipped_stale" || len(llm.calls) != 0 {
		t.Fatalf("Turn = %q, %v, %d lần gọi model", out, err, len(llm.calls))
	}
}
