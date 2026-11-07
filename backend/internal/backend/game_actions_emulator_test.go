//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// nightGame là ván đã qua mốc 22h đêm 1; at(d) là 22h + d.
func nightGame(t *testing.T) (*storeGame, func(time.Duration) time.Time) {
	g := newStoreGame(t)
	g.advance(g.start.NightAt.Add(time.Minute))
	return g, func(d time.Duration) time.Time { return g.start.NightAt.Add(d) }
}

func (g *storeGame) submit(req ActionRequest) ActionResult {
	g.t.Helper()
	req.GameID = g.id
	if req.Source == "" {
		req.Source = "app"
		if req.TgUpdateID > 0 {
			req.Source = "telegram"
		}
	}
	res, err := g.store.SubmitAction(context.Background(), req)
	if err != nil {
		g.t.Fatal(err)
	}
	return res
}

func bite(target string, at time.Time, update int64) ActionRequest {
	return ActionRequest{UID: "w1", Kind: ww.KindWolfBite, Targets: []string{target}, ReceivedAt: at, TgUpdateID: update}
}

func (g *storeGame) storedTargets(uid string, kind ww.Kind) []any {
	g.t.Helper()
	d, err := g.ref("rounds/1/actions/" + uid + "_" + string(kind)).Get(context.Background())
	if err != nil {
		g.t.Fatal(err)
	}
	ts, _ := d.Data()["targets"].([]any)
	return ts
}

// Chọn qua app rồi qua Telegram cách nhau 0.5 giây: bản sau thắng, và bước 0h
// dùng bản đó.
func TestEmulatorActionAppThenTelegramLaterWins(t *testing.T) {
	g, at := nightGame(t)
	if r := g.submit(bite("v1", at(30*time.Minute), 0)); !r.Applied || r.Reject != nil {
		t.Fatalf("app: %+v", r)
	}
	if r := g.submit(bite("v2", at(30*time.Minute+500*time.Millisecond), 100)); !r.Applied {
		t.Fatalf("telegram: %+v", r)
	}
	if got := g.storedTargets("w1", ww.KindWolfBite); !reflect.DeepEqual(got, []any{"v2"}) {
		t.Fatalf("đang lưu %v", got)
	}
	g.advance(at(2*time.Hour + time.Minute))
	if b := g.state().Bitten; b != "v2" {
		t.Fatalf("bitten = %q", b)
	}
}

// Telegram gửi lại u=100 sau khi đã đổi trong app: bỏ qua, trả lựa chọn đang lưu.
func TestEmulatorActionTelegramResendAfterAppChangeIsIgnored(t *testing.T) {
	g, at := nightGame(t)
	g.submit(bite("v1", at(10*time.Minute), 100))
	g.submit(bite("v2", at(11*time.Minute), 0))
	r := g.submit(bite("v1", at(12*time.Minute), 100))
	if r.Applied || r.Reject != nil || r.Current == nil || r.Current.Targets[0] != "v2" {
		t.Fatalf("gửi lại: %+v", r)
	}
	if got := g.storedTargets("w1", ww.KindWolfBite); !reflect.DeepEqual(got, []any{"v2"}) {
		t.Fatalf("đang lưu %v", got)
	}
}

// u=101 tới trước u=100 (webhook song song): giữ 101.
func TestEmulatorActionOlderUpdateArrivingLateIsIgnored(t *testing.T) {
	g, at := nightGame(t)
	g.submit(bite("v2", at(10*time.Minute), 101))
	if r := g.submit(bite("v1", at(10*time.Minute+time.Second), 100)); r.Applied {
		t.Fatalf("u=100 tới sau mà vẫn ghi: %+v", r)
	}
	if got := g.storedTargets("w1", ww.KindWolfBite); !reflect.DeepEqual(got, []any{"v2"}) {
		t.Fatalf("đang lưu %v", got)
	}
}

// receivedAt cũ hơn bản đang lưu (request chậm của kênh kia) thì thua.
func TestEmulatorActionOlderReceivedAtLoses(t *testing.T) {
	g, at := nightGame(t)
	g.submit(bite("v2", at(10*time.Minute), 0))
	if r := g.submit(bite("v1", at(9*time.Minute), 0)); r.Applied || r.Current.Targets[0] != "v2" {
		t.Fatalf("%+v", r)
	}
}

// Hành động bấm 1ms trước 0h chạy song song với bước chốt 0h: hoặc có mặt trong
// kết quả chốt, hoặc bị từ chối phase_closed. Không có trường hợp nhận rồi mất.
func TestEmulatorActionAtDeadlineIsCountedOrRejected(t *testing.T) {
	counted, rejected := 0, 0
	for i := 0; i < 6; i++ {
		g, at := nightGame(t)
		var wg sync.WaitGroup
		gate := make(chan struct{})
		var res ActionResult
		var actErr, advErr error
		wg.Add(2)
		go func() {
			defer wg.Done()
			<-gate
			req := bite("v1", at(2*time.Hour-time.Millisecond), 0)
			req.GameID, req.Source = g.id, "app"
			res, actErr = g.store.SubmitAction(context.Background(), req)
		}()
		go func() {
			defer wg.Done()
			<-gate
			_, advErr = g.store.AdvanceGame(context.Background(), g.id, at(2*time.Hour+time.Second))
		}()
		close(gate)
		wg.Wait()
		if actErr != nil || advErr != nil {
			t.Fatalf("lỗi: %v, %v", actErr, advErr)
		}
		st := g.state()
		if st.Phase != ww.PhaseDawn {
			t.Fatalf("chưa chốt 0h: %s", st.PhaseKey())
		}
		switch {
		case res.Applied && st.Bitten == "v1":
			counted++
		case errors.Is(res.Reject, ww.ErrPhaseClosed) && st.Bitten == "":
			rejected++
		default:
			t.Fatalf("lần %d: kết quả %+v nhưng bitten = %q", i, res, st.Bitten)
		}
	}
	t.Logf("vào kịp %d, bị từ chối %d", counted, rejected)
}

// Luật từ chối thì không ghi gì; tiên tri có kết quả ngay và không soi lại được;
// bỏ chọn thì bước chốt không tính; mỗi lần ghi có một tin sửa DM hoặc đếm phiếu,
// lựa chọn cắn có thêm một tin trong chat Phe Sói (C2).
func TestEmulatorActionRulesPeekClearAndOutbox(t *testing.T) {
	g, at := nightGame(t)
	if r := g.submit(ActionRequest{UID: "v1", Kind: ww.KindWolfBite, Targets: []string{"v2"}, ReceivedAt: at(time.Minute)}); !errors.Is(r.Reject, ww.ErrNotYourRole) || r.Applied {
		t.Fatalf("dân cắn: %+v", r)
	}
	peek := ActionRequest{UID: "seer", Kind: ww.KindSeerPeek, Targets: []string{"w2"}, ReceivedAt: at(2 * time.Minute)}
	if r := g.submit(peek); !r.Applied || r.Peek != ww.TeamWolves {
		t.Fatalf("soi: %+v", r)
	}
	peek.Targets, peek.ReceivedAt = []string{"v1"}, at(3*time.Minute)
	if r := g.submit(peek); !errors.Is(r.Reject, ww.ErrAlreadyUsed) {
		t.Fatalf("soi lần hai: %+v", r)
	}
	before := g.count("outbox")
	g.submit(bite("v1", at(4*time.Minute), 0))
	if r := g.submit(ActionRequest{UID: "w1", Kind: ww.KindWolfBite, Clear: true, ReceivedAt: at(5 * time.Minute)}); !r.Applied || r.Current != nil {
		t.Fatalf("bỏ chọn: %+v", r)
	}
	if n := g.count("outbox") - before; n != 3 {
		t.Fatalf("%d tin outbox cho 2 lần cắn, mong đợi 2 tin DM và 1 tin báo w2 có tin trong chat Phe Sói", n)
	}
	if docs, err := g.ref("chats/wolves").Collection("chatMessages").Documents(context.Background()).GetAll(); err != nil || len(docs) != 2 {
		t.Fatalf("chat Phe Sói có %d tin, mong đợi 2: %v", len(docs), err)
	}
	chat, err := g.ref("outboxChats/dm:w1").Get(context.Background())
	if err != nil || chat.Data()["pending"] != true {
		t.Fatalf("chat dm:w1 = %v, %v", chat.Data(), err)
	}
	g.advance(at(2*time.Hour + time.Minute))
	if b := g.state().Bitten; b != "" {
		t.Fatalf("sói đã bỏ chọn mà vẫn cắn %q", b)
	}
	seen, err := g.ref("rounds/1/actions/seer_seer_peek").Get(context.Background())
	if err != nil || seen.Data()["peek"] != string(ww.TeamWolves) {
		t.Fatalf("doc soi = %v, %v", seen.Data(), err)
	}
}

// Ghi đè lựa chọn thì voidReason cũ mất; ván chưa chạy thì từ chối.
func TestEmulatorActionOverwriteDropsVoidAndNeedsRunningGame(t *testing.T) {
	g, at := nightGame(t)
	g.submit(bite("v1", at(time.Minute), 0))
	seed(t, g.db, "games/"+g.id+"/rounds/1/actions/w1_wolf_bite", map[string]any{
		"uid": "w1", "kind": "wolf_bite", "targets": []any{"v1"}, "receivedAt": at(time.Minute), "voidReason": "x",
	})
	g.submit(bite("v2", at(2*time.Minute), 0))
	d, err := g.ref("rounds/1/actions/w1_wolf_bite").Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := d.Data()["voidReason"]; ok {
		t.Fatalf("voidReason còn: %v", d.Data())
	}

	id, err := g.store.CreateGame(context.Background(), NewGameInput{}, msgStart)
	if err == nil {
		t.Fatalf("tạo được ván %s", id)
	}
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	id, err = store.CreateGame(context.Background(), NewGameInput{}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	res, err := store.SubmitAction(context.Background(), ActionRequest{GameID: id, UID: "w1", Kind: ww.KindWolfBite, Targets: []string{"v1"}, ReceivedAt: at(3 * time.Minute)})
	if err != nil || !errors.Is(res.Reject, ww.ErrPhaseClosed) {
		t.Fatalf("ván đang đăng ký: %+v, %v", res, err)
	}
}

// Soi dân ra Dân (kết quả lấy từ vai thật, không cố định).
func TestEmulatorActionPeekVillagerIsVillage(t *testing.T) {
	g, at := nightGame(t)
	if r := g.submit(ActionRequest{UID: "seer", Kind: ww.KindSeerPeek, Targets: []string{"v1"}, ReceivedAt: at(time.Minute)}); r.Peek != ww.TeamVillage {
		t.Fatalf("soi v1: %+v", r)
	}
}

// Mỗi lần đề cử hay biểu quyết đổi lựa chọn, bấm ở app hay Telegram, đều ra
// một tin mới trong topic và một dòng trong mục diễn biến của pha. Bấm lại
// đúng lựa chọn đang lưu thì không ra gì; rút khi chưa chọn cũng vậy.
func TestEmulatorActionPickPostsToGroupAndFeed(t *testing.T) {
	g, at := nightGame(t)
	day := func(d time.Duration) time.Time { return at(12*time.Hour + d) } // 10h ngày 1
	g.advance(day(time.Minute))
	nominate := func(uid string, d time.Duration, update int64, clear bool, targets ...string) {
		t.Helper()
		r := g.submit(ActionRequest{UID: uid, Kind: ww.KindNominate, Targets: targets, Clear: clear, ReceivedAt: day(d), TgUpdateID: update})
		if !r.Applied {
			t.Fatalf("%s đề cử %v lúc +%v: %+v", uid, targets, d, r)
		}
	}
	nominate("v1", 5*time.Minute, 0, false, "v2")
	nominate("v1", 6*time.Minute, 200, false, "v2") // Telegram, không đổi gì
	nominate("v1", 7*time.Minute, 201, false, "w1")
	nominate("v1", 8*time.Minute, 0, true)
	nominate("v2", 9*time.Minute, 0, true) // chưa chọn mà rút
	nominate("v3", 10*time.Minute, 202, false, "v2")

	g.advance(at(22*time.Hour + time.Minute)) // 20h: v2 lên giàn
	vote := func(d time.Duration, update int64, choice string, clear bool) {
		t.Helper()
		r := g.submit(ActionRequest{UID: "v1", Kind: ww.KindVote, Choice: choice, Clear: clear, ReceivedAt: at(22*time.Hour + d), TgUpdateID: update})
		if !r.Applied {
			t.Fatalf("v1 bỏ phiếu %q lúc 20h+%v: %+v", choice, d, r)
		}
	}
	vote(5*time.Minute, 300, ww.ChoiceHang, false)
	vote(6*time.Minute, 0, "", true)

	names := map[string]string{"v1": "An", "v2": "Bình", "v3": "Dũng", "w1": "Chi"}
	players := map[string]gamePlayerInfo{}
	for uid, name := range names {
		players[uid] = gamePlayerInfo{uid: uid, name: name}
	}
	name := func(uid string) string { return names[uid] }

	docs, err := g.db.Collection("games").Doc(g.id).Collection("outbox").Where("template", "==", tplPick).OrderBy("seq", firestore.Asc).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var posted []string
	for _, d := range docs {
		var p pick
		if err := json.Unmarshal([]byte(d.Data()["data"].(string)), &p); err != nil {
			t.Fatal(err)
		}
		if d.Data()["chatKey"] != chatGroup {
			t.Fatalf("tin pick vào %v, mong đợi group", d.Data()["chatKey"])
		}
		posted = append(posted, p.text(name))
	}
	want := []string{"An đề cử Bình.", "An đề cử Chi.", "An rút đề cử.", "Dũng đề cử Bình.", "An bỏ phiếu Treo Bình.", "An rút phiếu ở phiên Bình."}
	if !reflect.DeepEqual(posted, want) {
		t.Fatalf("tin trong topic:\n%q\nmong đợi\n%q", posted, want)
	}

	// Nhật ký: mục diễn biến biểu quyết mới nhất ở đầu, rồi kết quả đề cử lúc
	// 20h, rồi mục diễn biến đề cử.
	feed, err := g.store.loadFeed(context.Background(), g.db.Collection("games").Doc(g.id), "", players)
	if err != nil {
		t.Fatal(err)
	}
	var titles []string
	for _, item := range feed.Items {
		titles = append(titles, item.Title)
	}
	if len(feed.Items) < 3 || !reflect.DeepEqual(titles[:3], []string{"Diễn biến biểu quyết ngày 1", "Đề cử ngày 1", "Diễn biến đề cử ngày 1"}) {
		t.Fatalf("nhật ký = %q", titles)
	}
	if got, want := feed.Items[0].Lines, []string{"20:05 An bỏ phiếu Treo Bình.", "20:06 An rút phiếu ở phiên Bình."}; !reflect.DeepEqual(got, want) {
		t.Fatalf("diễn biến biểu quyết = %q", got)
	}
	if got, want := feed.Items[2].Lines, []string{"10:05 An đề cử Bình.", "10:07 An đề cử Chi.", "10:08 An rút đề cử.", "10:10 Dũng đề cử Bình."}; !reflect.DeepEqual(got, want) {
		t.Fatalf("diễn biến đề cử = %q", got)
	}
}
