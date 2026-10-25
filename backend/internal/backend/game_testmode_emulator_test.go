//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// testPscChat là TELEGRAM_CHAT_ID của test; group test dùng chat khác.
const testPscChat = "-1001111"

func wantHTTP(t *testing.T, err error, status int, code string) {
	t.Helper()
	var he *HTTPError
	if !errors.As(err, &he) || he.Status != status || he.Code != code {
		t.Fatalf("lỗi = %v, mong đợi %d %s", err, status, code)
	}
}

// X1 "Xong khi": bật testMode với chatId của PSC thì 422, không tạo ván. Thiếu
// cấu hình PSC thì cũng không tạo được ván thử.
func TestEmulatorTestModeInPscIs422(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	store := NewGameStore(db, testPscChat)
	_, err := store.CreateGame(ctx, NewGameInput{ChatID: " " + testPscChat, Config: ww.Config{TestMode: true}}, msgStart)
	wantHTTP(t, err, 422, "test_mode_psc")
	if _, err := NewGameStore(db, "").CreateGame(ctx, NewGameInput{ChatID: "-1002222", Config: ww.Config{TestMode: true}}, msgStart); err == nil {
		t.Fatal("thiếu TELEGRAM_CHAT_ID mà vẫn tạo được ván thử")
	}
	if docs, err := db.Collection("games").Documents(ctx).GetAll(); err != nil || len(docs) != 0 {
		t.Fatalf("có %d ván, %v", len(docs), err)
	}
	if _, err := store.CreateGame(ctx, NewGameInput{ChatID: "-1002222", Config: ww.Config{TestMode: true}}, msgStart); err != nil {
		t.Fatalf("ván thử ở group test: %v", err)
	}
}

// testModeGame: ván thử ở group test, 4 người thật (r1–r4, đã liên kết, đang ở
// PSC) và 6 người giả. Vai ép: fake-01, fake-02 là sói, r1 là tiên tri, fake-03
// là bảo vệ; 6 người còn lại là dân (10 người chỉ có 2 sói, tiên tri, bảo vệ).
// wall là giờ thật, mỗi lần bấm trôi 1 phút.
type testModeGame struct {
	*storeGame
	wall    time.Time
	lastAdv AdvanceResult // kết quả lần adv() gần nhất
}

var realTesters = []string{"r1", "r2", "r3", "r4"}

func newTestModeGame(t *testing.T) *testModeGame {
	t.Helper()
	db := emulatorDB(t)
	ctx := context.Background()
	g := &testModeGame{storeGame: &storeGame{t: t, db: db, store: NewGameStore(db, testPscChat), tg: map[string]string{}}, wall: msgStart}
	g.store.frameKm = func(context.Context, string, time.Time) (FrameKm, error) {
		t.Fatal("ván thử không được đọc buổi chạy")
		return FrameKm{}, nil
	}
	id, err := g.store.CreateGame(ctx, NewGameInput{CreatedBy: "admin", ChatID: "-1002222", Config: ww.Config{TestMode: true}}, g.tick())
	if err != nil {
		t.Fatal(err)
	}
	g.id = id
	for i, uid := range realTesters {
		tg := strconv.Itoa(800000 + i)
		g.tg[uid] = tg
		seed(t, db, "games/"+id+"/players/"+uid, map[string]any{"uid": uid, "tgUserId": tg})
		seed(t, db, "tgLinks/"+tg, map[string]any{"uid": uid, "inPsc": true})
	}
	fakes, err := g.store.SetFakePlayers(ctx, id, 6, g.tick())
	if err != nil {
		t.Fatal(err)
	}
	forced := map[string]ww.Role{"fake-01": ww.Wolf, "fake-02": ww.Wolf, "r1": ww.Seer, "fake-03": ww.Guard}
	if err := g.store.SetForcedRoles(ctx, id, forced, g.tick()); err != nil {
		t.Fatal(err)
	}
	st, err := g.store.NewStartState(ctx, id, append(append([]string{}, realTesters...), fakes...), ww.Seed{7}, g.tick())
	if err != nil {
		t.Fatal(err)
	}
	for uid, p := range st.Players {
		if want, ok := forced[uid]; (ok && p.Role != want) || (!ok && p.Role != ww.Villager) {
			t.Fatalf("%s = %s, mong đợi %v", uid, p.Role, forced)
		}
	}
	if err := g.store.StartGame(ctx, id, st, g.wall); err != nil {
		t.Fatal(err)
	}
	g.start = st
	return g
}

func (g *testModeGame) tick() time.Time {
	g.wall = g.wall.Add(time.Minute)
	return g.wall
}

func (g *testModeGame) public() map[string]any {
	g.t.Helper()
	snap, err := g.db.Doc("games/" + g.id).Get(context.Background())
	if err != nil {
		g.t.Fatal(err)
	}
	return snap.Data()
}

// adv bấm admin/advance với taskKey đang thấy; phải chạy đúng một bước.
func (g *testModeGame) adv() {
	g.t.Helper()
	key := stringValue(g.public()["taskKey"])
	res, err := g.store.AdminAdvance(context.Background(), g.id, key, g.tick())
	if err != nil || res.Steps != 1 {
		g.t.Fatalf("advance %s: %+v, %v", key, res, err)
	}
	g.lastAdv = res
}

// do gửi một hành động qua W0: người giả thì admin bấm thay, người thật tự bấm.
func (g *testModeGame) do(uid string, kind ww.Kind, choice string, targets ...string) ActionResult {
	g.t.Helper()
	fake := strings.HasPrefix(uid, "fake-")
	src := "app"
	if fake {
		src = "admin"
	}
	res, err := g.store.SubmitAction(context.Background(), ActionRequest{
		GameID: g.id, UID: uid, Kind: kind, Targets: targets, Choice: choice, Source: src, ReceivedAt: g.tick(), ActAs: fake,
	})
	if err != nil || res.Reject != nil || !res.Applied {
		g.t.Fatalf("%s %s %v: %+v, %v", uid, kind, targets, res, err)
	}
	return res
}

func (g *testModeGame) setKm(round int, km float64) {
	g.t.Helper()
	for uid, p := range g.state().Players {
		if p.Alive {
			if err := g.store.AdminSetKm(context.Background(), g.id, round, uid, km, g.tick()); err != nil {
				g.t.Fatal(err)
			}
		}
	}
}

func aliveOf(st *ww.State) []string {
	var out []string
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Alive {
			out = append(out, uid)
		}
	}
	return out
}

// Một ngày: mọi người còn sống đề cử target (target đề cử người khác), lên giàn
// lúc 20h, 21h biểu quyết, ai cũng Treo trừ spare. Bấm advance: 18h, 20h, 21h, 22h.
func (g *testModeGame) hangDay(round int, target, spare, targetPick string) {
	g.t.Helper()
	for _, uid := range aliveOf(g.state()) {
		pick := target
		if uid == target {
			pick = targetPick
		}
		g.do(uid, ww.KindNominate, "", pick)
	}
	g.adv() // 18h nhắc đề cử
	g.adv() // 20h lên giàn
	if st := g.state(); st.Nominee != target {
		g.t.Fatalf("lên giàn %q, mong đợi %s", st.Nominee, target)
	}
	g.adv() // 21h nhắc biểu quyết; cửa sổ biểu quyết đã mở từ 20h
	g.setKm(round, 5)
	for _, uid := range aliveOf(g.state()) {
		if uid == target {
			continue
		}
		choice := ww.ChoiceHang
		if uid == spare {
			choice = ww.ChoiceSpare
		}
		g.do(uid, ww.KindVote, choice)
	}
	g.adv() // 22h chốt ngày
}

// X1 "Xong khi": ván thử 10 người (4 thật, 6 giả) chạy tới kết thúc chỉ bằng
// admin/advance. Kịch bản tính tay:
//   - đêm 1: hai sói giả cắn r2, tiên tri r1 soi fake-01 ra Sói; 10h r2 chết;
//   - ngày 1: treo fake-01 (7 Treo, 1 Tha, đủ km nên đủ 8 phiếu);
//   - đêm 2: fake-02 cắn r3; ngày 2: treo fake-02, hết sói, Dân thắng lúc 22h.
//
// Không tin DM nào ghi cho người giả; replay events ra đúng state.
func TestEmulatorTestModeGameRunsToEndByAdvance(t *testing.T) {
	g := newTestModeGame(t)
	g.setKm(0, 5)
	g.adv() // 22h đêm 1
	if st := g.state(); st.Phase != ww.PhaseNight || st.Round != 1 {
		t.Fatalf("sau advance đầu: %s", st.PhaseKey())
	}
	// Bậc thẻ có từ lúc chia bài; ván chưa xong thì chưa ai sở hữu.
	if me, err := g.store.Me(context.Background(), g.id, GameViewer{UID: "r1"}, g.wall); err != nil || me.CardOwned || me.CardTier != wantTier(g.state(), "r1") {
		t.Fatalf("/me của r1 giữa ván: owned %v, tier %q, err %v", me.CardOwned, me.CardTier, err)
	}
	if res := g.do("r1", ww.KindSeerPeek, "", "fake-01"); res.Peek != ww.TeamWolves {
		t.Fatalf("soi fake-01 = %s", res.Peek)
	}
	g.do("fake-01", ww.KindWolfBite, "", "r2")
	g.do("fake-02", ww.KindWolfBite, "", "r2")
	g.adv() // 0h
	g.adv() // 10h
	if st := g.state(); st.Players["r2"].Alive || st.Phase != ww.PhaseDay {
		t.Fatalf("10h ngày 1: %s, r2 sống = %v", st.PhaseKey(), st.Players["r2"].Alive)
	}
	g.hangDay(1, "fake-01", "fake-02", "r3")
	if st := g.state(); st.Players["fake-01"].Alive || st.Players["fake-01"].Cause != ww.CauseHang || st.PhaseKey() != "r2/night" {
		t.Fatalf("22h ngày 1: %s, fake-01 = %+v", st.PhaseKey(), st.Players["fake-01"])
	}
	g.do("fake-02", ww.KindWolfBite, "", "r3")
	g.adv() // 0h
	g.adv() // 10h
	g.hangDay(2, "fake-02", "", "r4")

	st := g.state()
	pub := g.public()
	if st.Phase != ww.PhaseEnded || st.Winner != ww.TeamVillage || pub["status"] != gameEnded || pub["winner"] != "village" {
		t.Fatalf("kết thúc: %s thắng %q, status %v", st.PhaseKey(), st.Winner, pub["status"])
	}
	// Bước kết thúc ván không còn mốc nào để hẹn game-advance.
	if res := g.lastAdv; res.Status != gameEnded || !res.NextAt.IsZero() || res.TaskKey != "" {
		t.Fatalf("bước cuối = %+v", res)
	}
	dead := map[string]ww.Cause{}
	for uid, p := range st.Players {
		if !p.Alive {
			dead[uid] = p.Cause
		}
	}
	want := map[string]ww.Cause{"r2": ww.CauseBite, "fake-01": ww.CauseHang, "r3": ww.CauseBite, "fake-02": ww.CauseHang}
	if len(dead) != len(want) {
		t.Fatalf("chết %v, mong đợi %v", dead, want)
	}
	for uid, c := range want {
		if dead[uid] != c {
			t.Fatalf("chết %v, mong đợi %v", dead, want)
		}
	}
	// Giờ ván đã đi gần 2 ngày trong khi giờ thật chỉ trôi vài chục phút.
	if off := clockOffset(pub); off < 24*time.Hour {
		t.Fatalf("độ lệch giờ ván = %v", off)
	}

	outbox, err := g.db.Collection("games").Doc(g.id).Collection("outbox").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	dms := map[string]int{}
	for _, d := range outbox {
		dms[stringValue(d.Data()["chatKey"])]++
		// Outbox mang giờ thật: cảnh báo tin pending quá lâu (M1) so với giờ thật.
		if at := d.Data()["createdAt"].(time.Time); at.After(g.wall) {
			t.Fatalf("outbox %s createdAt %v là giờ ván", d.Ref.ID, at)
		}
	}
	for key := range dms {
		if strings.HasPrefix(key, "dm:fake-") {
			t.Fatalf("có tin %s cho người giả", key)
		}
	}
	if dms["dm:r1"] == 0 || dms[chatGroup] == 0 {
		t.Fatalf("thiếu tin cho người thật hoặc group: %v", dms)
	}
	chats, err := g.db.Collection("games").Doc(g.id).Collection("outboxChats").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range chats {
		if strings.HasPrefix(c.Ref.ID, "dm:fake-") {
			t.Fatalf("có outboxChats %s", c.Ref.ID)
		}
	}
	// Phe Dân thắng: người thật r1–r4 đều phe Dân nên đều giữ thẻ, kể cả r2, r3
	// đã chết. Người giả không có tài khoản nên không có thẻ dù cùng phe.
	ctx := context.Background()
	for _, uid := range []string{"r1", "r2", "r3", "r4", "fake-01", "fake-03"} {
		snap, err := g.db.Collection("users").Doc(uid).Collection("gameCards").Doc(g.id).Get(ctx)
		if strings.HasPrefix(uid, "fake-") {
			if status.Code(err) != codes.NotFound {
				t.Fatalf("thẻ của %s: err = %v", uid, err)
			}
			continue
		}
		if err != nil {
			t.Fatalf("thẻ của %s: %v", uid, err)
		}
		card := snap.Data()
		if card["tier"] != wantTier(st, uid) || card["team"] != "village" || card["winner"] != "village" ||
			card["role"] != string(st.Players[uid].Role) || card["alive"] != st.Players[uid].Alive ||
			card["playerCount"] != int64(10) || card["testMode"] != true {
			t.Fatalf("thẻ của %s = %v", uid, card)
		}
		if _, died := card["deathRound"]; died == st.Players[uid].Alive {
			t.Fatalf("thẻ của %s: deathRound khi alive = %v", uid, st.Players[uid].Alive)
		}
	}
	if me, err := g.store.Me(ctx, g.id, GameViewer{UID: "r2"}, g.wall); err != nil || !me.CardOwned || me.CardTier != wantTier(st, "r2") || me.CardRounds != st.Round {
		t.Fatalf("/me của r2 lúc kết thúc: owned %v, tier %q, rounds %d (muốn %d), err %v", me.CardOwned, me.CardTier, me.CardRounds, st.Round, err)
	}
	replayMatches(t, g.storeGame)

	// T6: gửi hết outbox của cả ván bằng chữ render từ event thật. Không tin nào
	// lỗi; group nhận bản tin cuối có bên thắng và lá bài của mọi người; DM chỉ
	// tới tg của người thật.
	tg := newFakeTelegram(t)
	res, err := g.store.FlushGame(context.Background(), g.id, tg.service(testPscChat), time.Now)
	if err != nil || res.Failed != 0 || res.Sent == 0 {
		t.Fatalf("flush = %+v, %v", res, err)
	}
	real := map[string]bool{}
	for _, tgID := range g.tg {
		real[tgID] = true
	}
	var lastGroup string
	for _, c := range tg.Calls("sendMessage") {
		switch chat := c.Params["chat_id"].(string); {
		case chat == "-1002222":
			lastGroup = c.Params["text"].(string)
		case !real[chat]:
			t.Fatalf("tin gửi tới %s", chat)
		}
	}
	head, roles, ok := strings.Cut(lastGroup, "\n\nLá bài:\n")
	if !ok || !strings.HasSuffix(head, "Phe Dân thắng.") || len(strings.Split(roles, "\n")) != 10 ||
		strings.Count(roles, ": Dân") != 6 || strings.Count(roles, ": Sói") != 2 {
		t.Fatalf("bản tin cuối = %q", lastGroup)
	}
}

// wantTier là bậc thẻ mong đợi, để so với cái backend ghi và trả.
func wantTier(st *ww.State, uid string) string { return string(gameCardTier(st.Seed, uid)) }

func (g *testModeGame) actionCount(round int) int {
	g.t.Helper()
	docs, err := roundRef(g.db.Collection("games").Doc(g.id), round).Collection("actions").Documents(context.Background()).GetAll()
	if err != nil {
		g.t.Fatal(err)
	}
	return len(docs)
}

// Admin chỉ bấm thay được người giả của ván thử: bấm thay người thật hay bấm
// thay ở ván thật thì 422 và không ghi gì. Lệnh admin khác ở ván thật cũng 422.
func TestEmulatorActAsOnlyForFakePlayersOfTestGame(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	g.setKm(0, 5)
	g.adv()
	_, err := g.store.SubmitAction(ctx, ActionRequest{GameID: g.id, UID: "r1", Kind: ww.KindSeerPeek, Targets: []string{"fake-01"}, Source: "admin", ReceivedAt: g.tick(), ActAs: true})
	wantHTTP(t, err, 422, "not_fake_player")
	if n := g.actionCount(1); n != 0 {
		t.Fatalf("bấm thay người thật mà ghi %d action", n)
	}

	real := newStoreGame(t)
	_, err = real.store.SubmitAction(ctx, ActionRequest{GameID: real.id, UID: "w1", Kind: ww.KindWolfBite, Targets: []string{"v1"}, Source: "admin", ReceivedAt: real.start.NightAt.Add(time.Minute), ActAs: true})
	wantHTTP(t, err, 422, "not_test_mode")
	_, err = real.store.AdminAdvance(ctx, real.id, real.start.TaskKey(), msgStart)
	wantHTTP(t, err, 422, "not_test_mode")
	wantHTTP(t, real.store.AdminSetKm(ctx, real.id, 0, "w1", 5, msgStart), 422, "not_test_mode")
	if n := real.count("events"); n != 1 {
		t.Fatalf("ván thật có %d event sau lệnh admin bị từ chối", n)
	}
}

// CAS theo taskKey: key cũ thì 409, không chạy gì. Tin nhắc 18h không đổi
// phaseKey nhưng đổi taskKey, nên bấm lại với key trước tin nhắc cũng bị chặn,
// không nhảy luôn qua 20h.
func TestEmulatorAdminAdvanceStaleKeyIs409(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	g.setKm(0, 5)
	stale := stringValue(g.public()["taskKey"])
	g.adv() // 22h
	off := clockOffset(g.public())
	_, err := g.store.AdminAdvance(ctx, g.id, stale, g.tick())
	wantHTTP(t, err, 409, "phase_moved")
	// Bị từ chối thì cũng không được đẩy giờ: đẩy rồi là cửa sổ của người thật đóng sớm.
	if got := clockOffset(g.public()); got != off {
		t.Fatalf("key cũ bị từ chối mà giờ ván vẫn bị đẩy: %v → %v", off, got)
	}
	g.adv() // 0h
	g.adv() // 10h
	beforeReminder := stringValue(g.public()["taskKey"])
	g.adv() // 18h nhắc
	if st := g.state(); st.PhaseKey() != "r1/day" || st.Reminded != "r1/day" {
		t.Fatalf("sau tin nhắc: %s, reminded %q", st.PhaseKey(), st.Reminded)
	}
	events := g.count("events")
	_, err = g.store.AdminAdvance(ctx, g.id, beforeReminder, g.tick())
	wantHTTP(t, err, 409, "phase_moved")
	if n := g.count("events"); n != events || g.state().Phase != ww.PhaseDay {
		t.Fatalf("bấm lại với key cũ mà vẫn chạy: %d event, %s", n, g.state().PhaseKey())
	}
}

// Khe giữa fastForward và bước chốt: bên khác chốt xen vào thì key admin đang
// cầm đã cũ. Bước chốt phải tự kiểm lại key, kể cả khi đang có việc tới hạn,
// không thì một cú bấm chạy luôn bước kế của người khác.
func TestEmulatorAdvanceOnceChecksKeyInsideTransaction(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	g.setKm(0, 5)
	key := stringValue(g.public()["taskKey"])
	wall := g.tick()
	if err := g.store.fastForward(ctx, g.id, key, wall); err != nil {
		t.Fatal(err)
	}
	if err := g.store.snapshotKmIfDue(ctx, g.id, wall); err != nil {
		t.Fatal(err)
	}
	var res AdvanceResult
	stepped, err := g.store.advanceOnce(ctx, g.id, wall, "r1/setup@1", &res)
	wantHTTP(t, err, 409, "phase_moved")
	if stepped || g.state().Phase != ww.PhaseSetup {
		t.Fatalf("key cũ mà vẫn chốt: %s", g.state().PhaseKey())
	}
}

// Ép vai lạ thì 422 ngay, không đợi tới Start mới biết.
func TestEmulatorSetForcedRolesRejectsUnknownRole(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	store := NewGameStore(db, testPscChat)
	id, err := store.CreateGame(ctx, NewGameInput{ChatID: "-1002222", Config: ww.Config{TestMode: true}}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	wantHTTP(t, store.SetForcedRoles(ctx, id, map[string]ww.Role{"r1": "king"}, msgStart), 422, "invalid_role")
	if _, err := db.Doc("games/" + id + "/secret/roles").Get(ctx); err == nil {
		t.Fatal("vai lạ mà vẫn ghi")
	}
}

// Hai admin bấm cùng lúc với cùng key: đúng một bước chạy, bên kia nhận 409.
func TestEmulatorConcurrentAdminAdvanceRunsOnce(t *testing.T) {
	for round := 0; round < 5; round++ {
		g := newTestModeGame(t)
		g.setKm(0, 5)
		key := stringValue(g.public()["taskKey"])
		wall := g.tick()
		var wg sync.WaitGroup
		gate := make(chan struct{})
		steps := make([]int, 2)
		errs := make([]error, 2)
		for i := range steps {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				<-gate
				res, err := g.store.AdminAdvance(context.Background(), g.id, key, wall.Add(time.Duration(i)*time.Millisecond))
				steps[i], errs[i] = res.Steps, err
			}(i)
		}
		close(gate)
		wg.Wait()
		if steps[0]+steps[1] != 1 {
			t.Fatalf("lần %d: số bước %v, lỗi %v", round, steps, errs)
		}
		for i, err := range errs {
			if steps[i] == 0 {
				wantHTTP(t, err, 409, "phase_moved")
			}
		}
		if n := g.count("events"); n != 2 || g.state().PhaseKey() != "r1/night" {
			t.Fatalf("lần %d: %d event, %s", round, n, g.state().PhaseKey())
		}
	}
}

// km ở ván thử: không đọc buổi chạy, ai không được sửa thì 0 (tiên tri thiếu
// km); chỉ sửa được snapshot của mốc 22h sắp tới.
func TestEmulatorTestModeKm(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	wantHTTP(t, g.store.AdminSetKm(ctx, g.id, 1, "r1", 5, g.tick()), 409, "phase_closed")
	wantHTTP(t, g.store.AdminSetKm(ctx, g.id, 0, "x-ngoai", 5, g.tick()), 422, "invalid_target")
	wantHTTP(t, g.store.AdminSetKm(ctx, g.id, 0, "r1", -1, g.tick()), 422, "invalid_km")
	if err := g.store.AdminSetKm(ctx, g.id, 0, "fake-01", 3, g.tick()); err != nil {
		t.Fatal(err)
	}
	g.adv() // 22h: snapshot rounds/0
	st := g.state()
	if st.Km["fake-01"] != 3000 || st.Km["r1"] != 0 || len(st.Km) != 10 {
		t.Fatalf("km = %v", st.Km)
	}
	res, err := g.store.SubmitAction(ctx, ActionRequest{GameID: g.id, UID: "r1", Kind: ww.KindSeerPeek, Targets: []string{"fake-01"}, Source: "app", ReceivedAt: g.tick()})
	if err != nil || res.Reject != ww.ErrKmInsufficient {
		t.Fatalf("tiên tri 0 km: %+v, %v", res, err)
	}
	wantHTTP(t, g.store.AdminSetKm(ctx, g.id, 0, "r1", 5, g.tick()), 409, "phase_closed")
}

// SetFakePlayers đặt đúng số người giả, gọi lại không sinh thêm; sau Start thì 409.
func TestEmulatorSetFakePlayersIsIdempotent(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	store := NewGameStore(db, testPscChat)
	id, err := store.CreateGame(ctx, NewGameInput{ChatID: "-1002222", Config: ww.Config{TestMode: true}}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	players := func() int {
		docs, err := db.Collection("games").Doc(id).Collection("players").Documents(ctx).GetAll()
		if err != nil {
			t.Fatal(err)
		}
		return len(docs)
	}
	for _, n := range []int{6, 6, 3} {
		uids, err := store.SetFakePlayers(ctx, id, n, msgStart)
		if err != nil || len(uids) != n || players() != n {
			t.Fatalf("n=%d: %v, %d doc, %v", n, uids, players(), err)
		}
	}
	snap, _ := db.Doc("games/" + id).Get(ctx)
	if got := fakeUIDs(snap.Data()); len(got) != 3 || !got["fake-03"] || got["fake-04"] {
		t.Fatalf("fakeUids = %v", got)
	}
	g := newTestModeGame(t)
	_, err = g.store.SetFakePlayers(ctx, g.id, 6, g.tick())
	wantHTTP(t, err, 409, "game_running")
	wantHTTP(t, g.store.SetForcedRoles(ctx, g.id, nil, g.tick()), 409, "game_running")
}

// Giờ ván không lùi: giờ thật đã qua mốc mà tick chưa chạy, admin bấm thì bước
// chạy ở giờ ván hiện tại, độ lệch giữ nguyên. Ván đang pause thì 409 và không
// đẩy giờ.
func TestEmulatorAdminAdvanceNeverMovesClockBack(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	g.setKm(0, 5)
	g.adv() // 22h
	off := clockOffset(g.public())
	g.wall = g.wall.Add(3 * time.Hour) // giờ ván 1h sáng, mốc 0h đã qua
	g.adv()
	if got := clockOffset(g.public()); got != off {
		t.Fatalf("độ lệch %v → %v", off, got)
	}
	last, err := g.ref("events/3").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if at := last.Data()["at"].(time.Time); !at.Equal(g.wall.Add(off)) {
		t.Fatalf("bước chạy lúc %v, mong đợi giờ ván %v", at, g.wall.Add(off))
	}

	st := g.state()
	st.Paused = true
	raw, _ := json.Marshal(st)
	seed(t, g.db, "games/"+g.id+"/secret/state", map[string]any{"state": string(raw), "phaseKey": st.PhaseKey()})
	_, err = g.store.AdminAdvance(ctx, g.id, st.TaskKey(), g.tick())
	wantHTTP(t, err, 409, "paused")
	if got := clockOffset(g.public()); got != off {
		t.Fatalf("pause mà vẫn đẩy giờ: %v → %v", off, got)
	}
}

// Giờ ván đẩy xong thì lần hẹn trả về là giờ thật, và tick chạy theo giờ thật
// vẫn chốt được ván thử đúng mốc của giờ ván.
func TestEmulatorTestModeNextAtIsWallClock(t *testing.T) {
	g := newTestModeGame(t)
	ctx := context.Background()
	g.setKm(0, 5)
	key := stringValue(g.public()["taskKey"])
	wall := g.tick()
	res, err := g.store.AdminAdvance(ctx, g.id, key, wall)
	if err != nil || res.Steps != 1 {
		t.Fatal(res, err)
	}
	// Giờ ván lúc wall là 22:00 đêm 1; mốc kế là 0h, tức 2 giờ sau theo giờ thật.
	if want := wall.Add(2 * time.Hour); !res.NextAt.Equal(want) {
		t.Fatalf("NextAt = %v, mong đợi %v", res.NextAt, want)
	}
	if res := g.advance(wall.Add(2*time.Hour - time.Second)); res.Steps != 0 {
		t.Fatalf("tick trước mốc mà chạy %d bước", res.Steps)
	}
	if res := g.advance(wall.Add(2 * time.Hour)); res.Steps != 1 || g.state().Phase != ww.PhaseDawn {
		t.Fatalf("tick đúng mốc: %+v, %s", res, g.state().PhaseKey())
	}
}
