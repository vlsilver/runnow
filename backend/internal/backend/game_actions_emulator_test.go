//go:build emulator

package backend

import (
	"context"
	"errors"
	"reflect"
	"sync"
	"testing"
	"time"

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
