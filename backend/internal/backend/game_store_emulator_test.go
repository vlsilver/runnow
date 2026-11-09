//go:build emulator

package backend

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// storeRoles: 10 người, không có Cupid để bước 0h không ghép ngẫu nhiên.
func storeRoles() map[string]ww.Role {
	return map[string]ww.Role{
		"w1": ww.Wolf, "w2": ww.Wolf, "seer": ww.Seer, "guard": ww.Guard, "witch": ww.Witch, "hunter": ww.Hunter,
		"v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager, "v4": ww.Villager,
	}
}

type storeGame struct {
	t     *testing.T
	db    *firestore.Client
	store *GameStore
	id    string
	start *ww.State
	tg    map[string]string // uid → tgUserId
}

// newStoreGame tạo ván, ghi người chơi đã liên kết và đang ở PSC, rồi Start.
// km của mọi người là 5 km.
func newStoreGame(t *testing.T) *storeGame {
	t.Helper()
	return newStoreGameWith(t, ww.Config{})
}

// newStoreGameWith như newStoreGame nhưng Start với cấu hình cfg.
func newStoreGameWith(t *testing.T, cfg ww.Config) *storeGame {
	t.Helper()
	db := emulatorDB(t)
	g := &storeGame{t: t, db: db, store: NewGameStore(db, testPscChat), tg: map[string]string{}}
	g.store.frameKm = func(_ context.Context, _ string, _, end time.Time) (FrameKm, error) {
		return FrameKm{FrameEnd: end, OfficialMeters: 5000, Meters: 5000, Source: "official"}, nil
	}
	ctx := context.Background()
	id, err := g.store.CreateGame(ctx, NewGameInput{CreatedBy: "admin", ChatID: "-100"}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	g.id = id
	for i, uid := range sortedPlayers(ww.NewState(ww.Seed{}, ww.Config{}, storeRoles(), msgStart)) {
		tg := strconv.Itoa(900000 + i)
		g.tg[uid] = tg
		seed(t, db, "games/"+id+"/players/"+uid, map[string]any{"uid": uid, "tgUserId": tg})
		seed(t, db, "tgLinks/"+tg, map[string]any{"uid": uid, "inPsc": true})
	}
	g.start = ww.NewState(ww.Seed{3}, cfg, storeRoles(), msgStart)
	if err := g.store.StartGame(ctx, id, g.start, msgStart); err != nil {
		t.Fatal(err)
	}
	return g
}

func (g *storeGame) ref(path string) *firestore.DocumentRef {
	return g.db.Doc("games/" + g.id + "/" + path)
}

func (g *storeGame) count(col string) int {
	g.t.Helper()
	docs, err := g.db.Collection("games").Doc(g.id).Collection(col).Documents(context.Background()).GetAll()
	if err != nil {
		g.t.Fatal(err)
	}
	return len(docs)
}

func (g *storeGame) state() *ww.State {
	g.t.Helper()
	snap, err := g.ref("secret/state").Get(context.Background())
	if err != nil {
		g.t.Fatal(err)
	}
	st, err := decodeState(snap.Data())
	if err != nil {
		g.t.Fatal(err)
	}
	return st
}

func (g *storeGame) advance(now time.Time) AdvanceResult {
	g.t.Helper()
	res, err := g.store.AdvanceGame(context.Background(), g.id, now)
	if err != nil {
		g.t.Fatal(err)
	}
	return res
}

// act ghi action như service hành động (W0) sẽ ghi.
func (g *storeGame) act(round int, kind ww.Kind, uid string, at time.Time, targets ...string) {
	g.t.Helper()
	var ts []any
	for _, t := range targets {
		ts = append(ts, t)
	}
	seed(g.t, g.db, "games/"+g.id+"/rounds/"+strconv.Itoa(round)+"/actions/"+uid+"_"+string(kind), map[string]any{
		"uid": uid, "kind": string(kind), "targets": ts, "receivedAt": at, "source": "app",
	})
}

func TestEmulatorCreateGameWhileOneIsOpenIs409(t *testing.T) {
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	ctx := context.Background()
	first, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "admin"}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.CreateGame(ctx, NewGameInput{CreatedBy: "admin"}, msgStart)
	var he *HTTPError
	if !errors.As(err, &he) || he.Status != 409 || he.Code != "game_running" {
		t.Fatalf("lỗi = %v, mong đợi 409 game_running", err)
	}
	if _, err := db.Doc("games/"+first).Update(ctx, []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	second, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "admin"}, msgStart)
	if err != nil || second == first {
		t.Fatalf("ván cũ đã hết mà không tạo được ván mới: %v", err)
	}
	cur, err := db.Doc("gameState/current").Get(ctx)
	if err != nil || cur.Data()["gameId"] != second {
		t.Fatalf("gameState/current = %v, %v", cur.Data(), err)
	}
}

// Hai bên cùng chốt mốc 22h đêm 1: đúng một event bước và một bộ outbox.
// Bộ outbox tính tay: Start ra 1 tin group + 10 lá bài; mở đêm ra 1 bản tin +
// prompt cho guard, seer, w1, w2, cùng tin đêm cho 6 người còn lại. Tổng 22;
// chat group có 2 tin nên nextSeq = 3.
func TestEmulatorConcurrentAdvanceRunsTheStepOnce(t *testing.T) {
	for round := 0; round < 5; round++ {
		g := newStoreGame(t)
		now := g.start.NightAt.Add(time.Minute)
		var wg sync.WaitGroup
		gate := make(chan struct{})
		steps := make([]int, 2)
		errs := make([]error, 2)
		for i := range steps {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				<-gate
				res, err := g.store.AdvanceGame(context.Background(), g.id, now)
				steps[i], errs[i] = res.Steps, err
			}(i)
		}
		close(gate)
		wg.Wait()
		if errs[0] != nil || errs[1] != nil {
			t.Fatalf("lỗi: %v", errs)
		}
		if steps[0]+steps[1] != 1 {
			t.Fatalf("lần %d: số bước = %v, mong đợi tổng 1", round, steps)
		}
		if n := g.count("events"); n != 2 {
			t.Fatalf("lần %d: %d event, mong đợi 2 (start + 1 bước)", round, n)
		}
		if n := g.count("outbox"); n != 22 {
			t.Fatalf("lần %d: %d tin outbox, mong đợi 22", round, n)
		}
		chat, err := g.ref("outboxChats/group").Get(context.Background())
		if err != nil || chat.Data()["nextSeq"] != int64(3) || chat.Data()["pending"] != true {
			t.Fatalf("chat group = %v, %v", chat.Data(), err)
		}
	}
}

// Một đêm đi qua Firestore: action đọc từ rounds/1/actions, km từ rounds/0/km,
// người rời PSC từ tgLinks. Trước 10h: guard rời nhóm (lựa chọn bảo vệ bị huỷ),
// v2 gỡ liên kết, tài khoản Telegram của v4 chuyển sang uid khác; v3 là người
// chơi giả nên không rời được. Sói cắn v1; w2 cắn v2 rồi bỏ chọn nên không tính.
// 18h có tin nhắc: thêm event và tin group, không thêm dòng feed. Cuối cùng
// replay events ra đúng state đang lưu.
func TestEmulatorNightThroughFirestoreAndReplay(t *testing.T) {
	g := newStoreGame(t)
	ctx := context.Background()
	night := g.start.NightAt
	g.advance(night.Add(time.Minute))
	for uid := range storeRoles() {
		km, err := g.ref("rounds/0/km/" + uid).Get(ctx)
		if err != nil || km.Data()["meters"] != 5000.0 || km.Data()["source"] != "auto" {
			t.Fatalf("km của %s = %v, %v", uid, km.Data(), err)
		}
	}
	g.act(1, ww.KindWolfBite, "w1", night.Add(30*time.Minute), "v1")
	g.act(1, ww.KindWolfBite, "w2", night.Add(50*time.Minute), "v2")
	if _, err := g.ref("rounds/1/actions/w2_wolf_bite").Update(ctx, []firestore.Update{{Path: "cleared", Value: true}}); err != nil {
		t.Fatal(err)
	}
	g.act(1, ww.KindGuard, "guard", night.Add(40*time.Minute), "v3")
	g.advance(night.Add(2*time.Hour + time.Minute))
	if st := g.state(); st.Bitten != "v1" {
		t.Fatalf("bitten = %q, mong đợi v1 (w2 đã bỏ chọn)", st.Bitten)
	}
	seed(t, g.db, "tgLinks/"+g.tg["guard"], map[string]any{"uid": "guard", "inPsc": false})
	seed(t, g.db, "games/"+g.id+"/players/v2", map[string]any{"uid": "v2"})
	seed(t, g.db, "tgLinks/"+g.tg["v4"], map[string]any{"uid": "nguoi-khac", "inPsc": true})
	seed(t, g.db, "games/"+g.id+"/players/v3", map[string]any{"uid": "v3", "fake": true})
	res := g.advance(night.Add(12*time.Hour + time.Minute))
	if res.Steps != 1 || res.Status != gameRunning {
		t.Fatalf("res = %+v", res)
	}

	st := g.state()
	causes := map[string]ww.Cause{}
	for uid, p := range st.Players {
		if !p.Alive {
			causes[uid] = p.Cause
		}
	}
	want := map[string]ww.Cause{"v1": ww.CauseBite, "guard": ww.CauseLeft, "v2": ww.CauseLeft, "v4": ww.CauseLeft}
	if st.Phase != ww.PhaseDay || len(causes) != len(want) {
		t.Fatalf("sau 10h: phase %s, chết %v, mong đợi %v", st.Phase, causes, want)
	}
	for uid, c := range want {
		if causes[uid] != c {
			t.Fatalf("chết %v, mong đợi %v", causes, want)
		}
	}
	for uid := range want {
		p, err := g.ref("players/" + uid).Get(ctx)
		if err != nil || p.Data()["alive"] != false || p.Data()["deathRound"] != int64(1) {
			t.Fatalf("players/%s = %v, %v", uid, p.Data(), err)
		}
	}
	void, err := g.ref("rounds/1/actions/guard_guard").Get(ctx)
	if err != nil || void.Data()["voidReason"] != ww.VoidActorDead {
		t.Fatalf("action guard = %v, %v", void.Data(), err)
	}
	pub, err := g.db.Collection("games").Doc(g.id).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	revealed, _ := pub.Data()["revealed"].(map[string]any)
	if len(revealed) != 4 || revealed["v1"] != "villager" || revealed["guard"] != "guard" || pub.Data()["phaseKey"] != "r1/day" {
		t.Fatalf("games/%s = %v", g.id, pub.Data())
	}
	if n := g.count("feed"); n != 3 {
		t.Fatalf("%d dòng feed, mong đợi 3 (22h, 0h, 10h)", n)
	}

	before := g.count("outbox")
	if res := g.advance(night.Add(20*time.Hour + time.Minute)); res.Steps != 1 {
		t.Fatalf("18h: %+v", res)
	}
	if n := g.count("feed"); n != 3 {
		t.Fatalf("tin nhắc thêm dòng feed: %d", n)
	}
	if n := g.count("outbox"); n != before+1 {
		t.Fatalf("tin nhắc ra %d tin outbox", n-before)
	}
	if g.state().Reminded != "r1/day" {
		t.Fatal("chưa ghi đã nhắc")
	}

	replayMatches(t, g)
}

// replayMatches chạy lại events qua engine, từ state lúc Start, và so hash với
// state sau từng bước.
func replayMatches(t *testing.T, g *storeGame) {
	t.Helper()
	docs, err := g.db.Collection("games").Doc(g.id).Collection("events").OrderBy("seq", firestore.Asc).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var st *ww.State
	for _, d := range docs {
		ev := d.Data()
		var err error
		switch ev["kind"] {
		case "cancel":
			continue // huỷ không đổi state
		case "start":
			st = &ww.State{}
			err = json.Unmarshal([]byte(ev["state"].(string)), st)
		case "pause":
			st, err = ww.Pause(st)
		case "resume":
			st, err = ww.Resume(st, ev["at"].(time.Time))
		case "extend":
			st, err = ww.Extend(st, time.Duration(number(ev["minutes"]))*time.Minute)
		default:
			var in ww.Inputs
			if err := json.Unmarshal([]byte(ev["inputs"].(string)), &in); err != nil {
				t.Fatal(err)
			}
			st, _, err = ww.Advance(st, in, ev["at"].(time.Time))
		}
		if err != nil {
			t.Fatalf("replay event %v (%v): %v", ev["seq"], ev["kind"], err)
		}
		b, _ := json.Marshal(st)
		sum := sha256.Sum256(b)
		if hex.EncodeToString(sum[:]) != ev["stateHash"] {
			t.Fatalf("replay lệch ở event %v", ev["seq"])
		}
	}
	b1, _ := json.Marshal(st)
	b2, _ := json.Marshal(g.state())
	if string(b1) != string(b2) {
		t.Fatal("replay không ra state đang lưu")
	}
}

// Không tính được km thì không chốt và trả lỗi; mất km là mất phiếu.
func TestEmulatorAdvanceStopsWhenKmFails(t *testing.T) {
	g := newStoreGame(t)
	g.store.frameKm = func(context.Context, string, time.Time, time.Time) (FrameKm, error) {
		return FrameKm{}, errors.New("firestore unavailable")
	}
	if _, err := g.store.AdvanceGame(context.Background(), g.id, g.start.NightAt.Add(time.Minute)); err == nil {
		t.Fatal("km lỗi mà vẫn không báo lỗi")
	}
	if n := g.count("events"); n != 1 {
		t.Fatalf("%d event, mong đợi chỉ có start", n)
	}
	if g.state().Phase != ww.PhaseSetup {
		t.Fatal("km lỗi mà vẫn chốt")
	}
}

// Ván tắt km: tới 22h vẫn chốt, không đọc buổi chạy của ai, mốc km ghi 0 m
// với nguồn "off".
func TestEmulatorKmOffSnapshotSkipsRuns(t *testing.T) {
	g := newStoreGameWith(t, ww.Config{KmOff: true})
	g.store.frameKm = func(context.Context, string, time.Time, time.Time) (FrameKm, error) {
		return FrameKm{}, errors.New("ván tắt km mà vẫn đọc buổi chạy")
	}
	g.advance(g.start.NightAt.Add(time.Minute))
	if g.state().Phase == ww.PhaseSetup {
		t.Fatal("ván tắt km mà không chốt đêm 1")
	}
	snap, err := g.ref("rounds/0/km/seer").Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if d := snap.Data(); d["source"] != "off" || d["meters"] != 0.0 {
		t.Fatalf("mốc km = %v", d)
	}
}

// Chưa tới hạn hoặc ván chưa Start thì không ghi gì.
func TestEmulatorAdvanceNothingDue(t *testing.T) {
	g := newStoreGame(t)
	res := g.advance(g.start.NightAt.Add(-time.Minute))
	if res.Steps != 0 || res.Status != gameRunning || !res.NextAt.Equal(g.start.NightAt) {
		t.Fatalf("res = %+v", res)
	}
	if n := g.count("events"); n != 1 {
		t.Fatalf("%d event", n)
	}
	id, err := g.store.CreateGame(context.Background(), NewGameInput{CreatedBy: "admin"}, msgStart)
	if err == nil {
		t.Fatalf("chủ ván tạo được ván %s khi ván của mình đang chạy", id)
	}
}

// Transaction thấy mốc 22h mà snapshot km chưa có (bước khác chốt xen vào) thì
// không chốt với km rỗng, mà báo để vòng ngoài chạy lại snapshot.
func TestEmulatorStepWithoutKmSnapshotIsRetriedNotRun(t *testing.T) {
	g := newStoreGame(t)
	var res AdvanceResult
	stepped, err := g.store.advanceOnce(context.Background(), g.id, g.start.NightAt.Add(time.Minute), "", &res)
	if !errors.Is(err, errKmNotReady) || stepped {
		t.Fatalf("stepped = %v, err = %v; mong đợi errKmNotReady", stepped, err)
	}
	if g.state().Phase != ww.PhaseSetup {
		t.Fatal("chốt khi chưa có km")
	}
}

func TestEmulatorStartGameNeedsRegisteredPlayers(t *testing.T) {
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	ctx := context.Background()
	id, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "admin"}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	st := ww.NewState(ww.Seed{3}, ww.Config{}, storeRoles(), msgStart)
	if err := store.StartGame(ctx, id, st, msgStart); err == nil {
		t.Fatal("Start khi chưa ai có players/{uid} mà không lỗi")
	}
	if snap, _ := db.Doc("games/" + id).Get(ctx); snap.Data()["status"] != gameRegistering {
		t.Fatalf("status = %v", snap.Data()["status"])
	}
	g := newStoreGame(t) // đủ người: Start lần hai thì 409
	if err := g.store.StartGame(ctx, g.id, g.start, msgStart); err == nil {
		t.Fatal("Start hai lần mà không lỗi")
	}
}

// Ván km hai vòng 12 tiếng: chốt phiếu và chốt cắn (hết Đêm, sau 1 tiếng) mỗi lần
// đọc đúng 24 tiếng trước giờ chốt, các khung chồng nhau.
func TestEmulatorMultiRoundKmFramesAre24Hours(t *testing.T) {
	g := newStoreGameWith(t, ww.Config{Schedule: &ww.Schedule{StartHour: 22, RoundHours: 12, Rounds: 2}})
	type frame struct{ start, end time.Time }
	var seen []frame
	g.store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
		if uid == "seer" {
			seen = append(seen, frame{start, end})
		}
		return FrameKm{FrameEnd: end, OfficialMeters: 5000, Meters: 5000, Source: "official"}, nil
	}
	night := g.start.NightAt
	for _, at := range []time.Duration{0, 12 * time.Hour, 24 * time.Hour} {
		g.advance(night.Add(at + time.Minute))
	}
	want := []frame{
		{night.Add(-24 * time.Hour), night},
		{night.Add(-23 * time.Hour), night.Add(time.Hour)},
		{night.Add(-12 * time.Hour), night.Add(12 * time.Hour)},
		{night.Add(-11 * time.Hour), night.Add(13 * time.Hour)},
		{night, night.Add(24 * time.Hour)},
	}
	if len(seen) != len(want) {
		t.Fatalf("%d lần đọc km, muốn %d: %v", len(seen), len(want), seen)
	}
	for i := range want {
		if !seen[i].start.Equal(want[i].start) || !seen[i].end.Equal(want[i].end) {
			t.Fatalf("lần chốt %d: %v, muốn %v", i, seen[i], want[i])
		}
	}
}

// Ván không km nhiều vòng: lần chốt nào cũng tới hạn, không đọc buổi chạy.
func TestEmulatorNoKmRoundsCloseWithoutReadingRuns(t *testing.T) {
	g := newStoreGameWith(t, ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 6, RoundHours: 6, Rounds: 3}})
	g.store.frameKm = func(context.Context, string, time.Time, time.Time) (FrameKm, error) {
		return FrameKm{}, errors.New("ván tắt km mà vẫn đọc buổi chạy")
	}
	night := g.start.NightAt
	g.advance(night.Add(time.Minute))
	g.advance(night.Add(6*time.Hour + time.Minute))
	for _, round := range []string{"0", "1"} {
		snap, err := g.ref("rounds/" + round + "/km/seer").Get(context.Background())
		if err != nil {
			t.Fatalf("vòng %s: %v", round, err)
		}
		if d := snap.Data(); d["source"] != "off" {
			t.Fatalf("vòng %s: mốc km = %v", round, d)
		}
	}
	if st := g.state(); st.Round != 2 || st.Phase != ww.PhaseNight {
		t.Fatalf("round %d phase %s, muốn vòng 2 pha Đêm", st.Round, st.Phase)
	}
}

// Mọi kiểu ván, 1–4 vòng: ván km đọc đúng 24 tiếng trước mỗi lần chốt, ván
// không km không đọc buổi chạy; lần chốt nào cũng có mốc và ván sang vòng sau.
func TestEmulatorEveryPresetCloseFrames(t *testing.T) {
	for _, preset := range []string{"std", "hard", "classic"} {
		for _, c := range presetRounds {
			t.Run(fmt.Sprintf("%s/%d vòng", preset, c.rounds), func(t *testing.T) {
				var cfg ww.Config
				if err := applyGameSettings(&cfg, formSettings(preset, c.rounds, c.phases)); err != nil {
					t.Fatal(err)
				}
				g := newStoreGameWith(t, cfg)
				var seen [][2]time.Time
				g.store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
					if uid == "seer" {
						seen = append(seen, [2]time.Time{start, end})
					}
					return FrameKm{FrameEnd: end, OfficialMeters: 5000, Meters: 5000, Source: "official"}, nil
				}
				round := 24 * time.Hour / time.Duration(c.rounds)
				night := g.start.NightAt
				var want [][2]time.Time
				for k := range c.rounds + 1 {
					closeAt := night.Add(time.Duration(k) * round)
					g.advance(closeAt.Add(time.Minute))
					want = append(want, [2]time.Time{closeAt.Add(-24 * time.Hour), closeAt})
				}
				if preset == "classic" {
					want = nil
				}
				// Giữa hai lần chốt phiếu có đúng một lần đọc km cho chốt cắn.
				wantReads := len(want)*2 - 1
				if preset == "classic" {
					wantReads = 0
				}
				if len(seen) != wantReads {
					t.Fatalf("đọc km %d lần, muốn %d: %v", len(seen), wantReads, seen)
				}
				for i, frame := range seen {
					if i%2 == 0 {
						w := want[i/2]
						if !frame[0].Equal(w[0]) || !frame[1].Equal(w[1]) {
							t.Fatalf("lần chốt phiếu %d: %v, muốn %v", i/2, frame, w)
						}
						continue
					}
					if frame[1].Sub(frame[0]) != 24*time.Hour || !frame[1].After(want[i/2][1]) || !frame[1].Before(want[i/2+1][1]) {
						t.Fatalf("lần chốt cắn sau phiếu %d: %v", i/2, frame)
					}
				}
				for k := range c.rounds + 1 {
					snap, err := g.ref(fmt.Sprintf("rounds/%d/km/seer", k)).Get(context.Background())
					if err != nil {
						t.Fatalf("mốc km vòng %d: %v", k, err)
					}
					if off := snap.Data()["source"] == "off"; off != (preset == "classic") {
						t.Fatalf("mốc km vòng %d = %v", k, snap.Data())
					}
				}
				if st := g.state(); st.Round != c.rounds+1 || st.Phase != ww.PhaseNight {
					t.Fatalf("round %d phase %s, muốn vòng %d pha Đêm", st.Round, st.Phase, c.rounds+1)
				}
			})
		}
	}
}

// Chạy bung 2 vòng: km Riêng lấy đúng buổi chạy nằm trong 24 tiếng trước mỗi
// lần chốt. Khung chồng nên một buổi có thể tính ở hai lần chốt liên tiếp, và
// ai hụt 2 km thì lần đó không đủ kỹ năng. Số mong đợi cộng tay từ các buổi.
func TestEmulatorHardGameKmFromOverlappingFrames(t *testing.T) {
	var cfg ww.Config
	if err := applyGameSettings(&cfg, formSettings("hard", 2, [4]float64{60, 300, 300, 60})); err != nil {
		t.Fatal(err)
	}
	g := newStoreGameWith(t, cfg)
	night := g.start.NightAt
	h := func(n int) time.Time { return night.Add(time.Duration(n) * time.Hour) }
	runs := map[string][]struct {
		at     time.Time
		meters float64
	}{
		"seer": {{h(-13), 1000}, {h(1), 1500}, {h(13), 1000}},
		"v1":   {{h(-1), 1500}},
	}
	g.store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
		sum := 0.0
		for _, r := range runs[uid] {
			if !r.at.Before(start) && r.at.Before(end) {
				sum += r.meters
			}
		}
		return FrameKm{FrameEnd: end, OfficialMeters: sum, Meters: sum, Source: "official"}, nil
	}
	for k, want := range []struct{ seer, v1 float64 }{
		{1000, 1500}, // [-24h, 0): seer buổi -13h, v1 buổi -1h
		{1500, 1500}, // [-12h, 12h): seer buổi 1h, v1 buổi -1h lần nữa
		{2500, 0},    // [0, 24h): seer buổi 1h và 13h, v1 không còn buổi nào
	} {
		g.advance(h(12 * k).Add(time.Minute))
		for uid, meters := range map[string]float64{"seer": want.seer, "v1": want.v1} {
			snap, err := g.ref(fmt.Sprintf("rounds/%d/km/%s", k, uid)).Get(context.Background())
			if err != nil {
				t.Fatalf("lần chốt %d, %s: %v", k, uid, err)
			}
			if got := snap.Data()["meters"]; got != meters {
				t.Fatalf("lần chốt %d, %s: %v m, muốn %v", k, uid, got, meters)
			}
		}
		if got := g.state().Km["seer"]; got != want.seer {
			t.Fatalf("lần chốt %d: Km seer trong ván = %v, muốn %v", k, got, want.seer)
		}
	}
}
