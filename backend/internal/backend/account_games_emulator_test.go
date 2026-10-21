//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// docData trả dữ liệu của doc, nil khi doc không có.
func docData(t *testing.T, accounts *AccountService, path string) map[string]any {
	t.Helper()
	snap, err := accounts.db.Doc(path).Get(context.Background())
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	return snap.Data()
}

func TestEmulatorAccountDeleteRemovesClosedAndRegisteringGameData(t *testing.T) {
	db := emulatorDB(t)
	accounts := &AccountService{db: db}
	for path, doc := range map[string]map[string]any{
		"games/reg":                                      {"status": gameRegistering, "playerCount": 2},
		"games/reg/players/uA":                           {"uid": "uA", "tgUserId": "7", "name": "An"},
		"games/reg/players/uB":                           {"uid": "uB", "tgUserId": "8", "name": "Bình"},
		"games/old":                                      {"status": gameEnded, "playerCount": 2},
		"games/old/players/uA":                           {"uid": "uA", "tgUserId": "7", "name": "An", "alive": false},
		"games/old/players/uB":                           {"uid": "uB", "tgUserId": "8", "name": "Bình", "alive": true},
		"games/old/rounds/1/km/uA":                       {"meters": 5000.0, "hourlyToday": []any{1.0, 2.0}},
		"games/old/rounds/1/km/uB":                       {"meters": 3000.0},
		"games/old/rounds/1/actions/uA_vote":             {"uid": "uA", "kind": "vote"},
		"games/old/chats/wolves":                         {"key": "wolves", "seq": 2},
		"games/old/chats/wolves/chatMessages/0000000001": {"seq": 1, "uid": "uA", "kind": "text", "text": "của An"},
		"games/old/chats/wolves/chatMessages/0000000002": {"seq": 2, "uid": "uB", "kind": "text", "text": "của Bình"},
		"games/old/chatReports/wolves_1_uB":              {"author": "uA", "reporter": "uB", "text": "của An"},
		"games/old/chatReports/wolves_2_uA":              {"author": "uB", "reporter": "uA", "text": "của Bình"},
		"games/old/chatReports/wolves_9_uB":              {"author": "uC", "reporter": "uB", "text": "của Cường"},
		"gameBlocks/uA":                                  {"uids": []any{"uB"}},
		"gameBlocks/uB":                                  {"uids": []any{"uA", "uC"}},
	} {
		seed(t, db, path, doc)
	}

	for i := 0; i < 2; i++ { // xoá tài khoản lỗi giữa chừng thì chạy lại, phải ra cùng kết quả
		if err := accounts.deleteGameData(context.Background(), "uA"); err != nil {
			t.Fatal(err)
		}
	}

	// Ván đang đăng ký: rút hẳn ra như tự huỷ đăng ký.
	if docData(t, accounts, "games/reg/players/uA") != nil {
		t.Fatal("còn đăng ký của uA trong ván đang đăng ký")
	}
	if g := docData(t, accounts, "games/reg"); g["playerCount"] != int64(1) {
		t.Fatalf("playerCount = %v, mong đợi 1", g["playerCount"])
	}
	// Ván đã xong: giữ chỗ trong ván cho lịch sử của người khác, bỏ tên và tg id.
	p := docData(t, accounts, "games/old/players/uA")
	if p == nil || p["uid"] != "uA" || p["alive"] != false {
		t.Fatalf("players/uA của ván cũ = %v, mong đợi còn uid và alive", p)
	}
	if _, ok := p["name"]; ok {
		t.Fatalf("còn tên trong ván cũ: %v", p)
	}
	if _, ok := p["tgUserId"]; ok {
		t.Fatalf("còn tg id trong ván cũ: %v", p)
	}
	for _, gone := range []string{
		"games/old/rounds/1/km/uA",
		"games/old/chats/wolves/chatMessages/0000000001",
		"games/old/chatReports/wolves_1_uB",
		"games/old/chatReports/wolves_2_uA",
		"gameBlocks/uA",
	} {
		if docData(t, accounts, gone) != nil {
			t.Fatalf("xoá tài khoản mà còn %s", gone)
		}
	}
	for _, kept := range []string{
		"games/reg/players/uB",
		"games/old/players/uB",
		"games/old/rounds/1/km/uB",
		"games/old/rounds/1/actions/uA_vote",
		"games/old/chats/wolves/chatMessages/0000000002",
		"games/old/chatReports/wolves_9_uB",
	} {
		if docData(t, accounts, kept) == nil {
			t.Fatalf("xoá nhầm %s", kept)
		}
	}
	if b := docData(t, accounts, "gameBlocks/uB"); len(anyList(b["uids"])) != 1 || anyList(b["uids"])[0] != "uC" {
		t.Fatalf("gameBlocks/uB = %v, mong đợi chỉ còn uC", b)
	}
}

// Xoá tài khoản giữa ván: ván chạy tiếp, tới mốc chốt kế tiếp người đó bị tính
// là đã rời PSC (R33), dù tgLinks của họ còn nguyên.
func TestEmulatorAccountDeleteMidGameCountsAsLeft(t *testing.T) {
	g := newStoreGame(t)
	accounts := &AccountService{db: g.db}
	ctx := context.Background()
	night := g.start.NightAt
	g.advance(night.Add(time.Minute))
	if _, err := g.ref("players/v2").Update(ctx, []firestore.Update{{Path: "name", Value: "Vy"}}); err != nil {
		t.Fatal(err)
	}
	seed(t, g.db, "games/"+g.id+"/chats/wolves/chatMessages/0000000001", map[string]any{"seq": 1, "uid": "w1", "kind": "text", "text": "cắn ai"})
	seed(t, g.db, "games/"+g.id+"/chats/wolves/chatMessages/0000000002", map[string]any{"seq": 2, "uid": "w2", "kind": "text", "text": "cắn v1"})

	for i := 0; i < 2; i++ {
		for _, uid := range []string{"v2", "w1"} {
			if err := accounts.deleteGameData(ctx, uid); err != nil {
				t.Fatal(err)
			}
		}
	}

	p := docData(t, accounts, "games/"+g.id+"/players/v2")
	if p == nil || p["alive"] != true {
		t.Fatalf("players/v2 = %v, mong đợi còn doc và còn sống tới mốc chốt", p)
	}
	if _, ok := p["name"]; ok {
		t.Fatalf("còn tên của v2: %v", p)
	}
	if _, ok := p["tgUserId"]; ok {
		t.Fatalf("còn tg id của v2: %v", p)
	}
	if docData(t, accounts, "games/"+g.id+"/chats/wolves/chatMessages/0000000001") != nil {
		t.Fatal("còn tin chat phe của w1")
	}
	if docData(t, accounts, "games/"+g.id+"/chats/wolves/chatMessages/0000000002") == nil {
		t.Fatal("xoá nhầm tin của w2")
	}
	// km của ván đang chạy để engine tự lo, không xoá chen giữa.
	if docData(t, accounts, "games/"+g.id+"/rounds/0/km/v2") == nil {
		t.Fatal("xoá km của ván đang chạy")
	}

	res := g.advance(night.Add(12*time.Hour + time.Minute))
	st := g.state()
	if res.Status != gameRunning || st.Phase != ww.PhaseDay {
		t.Fatalf("sau 10h: %+v, phase %s, mong đợi ván sang ngày 1", res, st.Phase)
	}
	for _, uid := range []string{"v2", "w1"} {
		if p := st.Players[uid]; p.Alive || p.Cause != ww.CauseLeft {
			t.Fatalf("%s = %+v, mong đợi chết vì rời PSC", uid, p)
		}
	}
}
