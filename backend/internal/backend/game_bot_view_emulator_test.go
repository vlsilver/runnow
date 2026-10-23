//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// botWerewolfAt gọi tool của 3i và trả kèm JSON phần ván để soi lộ vai.
func botWerewolfAt(t *testing.T, g *storeGame, wall time.Time) (BotWerewolf, string) {
	t.Helper()
	v, err := g.store.BotWerewolf(context.Background(), wall)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(v.Game)
	if err != nil {
		t.Fatal(err)
	}
	return v, string(raw)
}

// noRoleExcept: phần ván không có nhãn vai nào ngoài vai đã lật.
func noRoleExcept(t *testing.T, raw string, revealed ...string) {
	t.Helper()
	ok := map[string]bool{}
	for _, r := range revealed {
		ok[r] = true
	}
	for _, label := range []string{"Sói", "Tiên tri", "Bảo vệ", "Phù thuỷ", "Thợ săn", "Cupid", "Dân", `"wolf"`, `"seer"`, `"villager"`} {
		if !ok[label] && strings.Contains(raw, label) {
			t.Fatalf("phần ván lộ %s: %s", label, raw)
		}
	}
}

// 3i chỉ thấy phần ai cũng thấy: không vai người sống, người chết lật bài, đề cử
// và phiếu đếm như topic, luật có X của ván.
func TestEmulatorBotWerewolfShowsOnlyPublicGame(t *testing.T) {
	g := newStoreGame(t)
	for uid := range storeRoles() {
		seed(t, g.db, "publicProfiles/"+uid, map[string]any{"displayName": strings.ToUpper(uid)})
	}

	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam))
	v, raw := botWerewolfAt(t, g, time.Date(2026, 10, 15, 23, 0, 0, 0, vietnam))
	noRoleExcept(t, raw)
	if v.Game == nil || v.Game.Phase != "Đêm 1, sói đang chọn" || v.Game.Deadline != "00:00 16/10" || v.Game.Now != "23:00 15/10" {
		t.Fatalf("game = %s", raw)
	}
	if len(v.Game.Alive) != 10 || len(v.Game.Dead) != 0 || v.Game.LastKm["V1"] != "5 km" {
		t.Fatalf("game = %s", raw)
	}
	if v.Rules != gameRulesText || !strings.Contains(v.Roles["Tiên tri"], "Cần đủ 1 km") || strings.Contains(v.VoteRules, "X km") {
		t.Fatalf("luật = %+v", v)
	}

	// Sói cắn V4, 10h lật bài. Đề cử: người chết đề cử và đề cử người chết không tính.
	g.act(1, ww.KindWolfBite, "w1", time.Date(2026, 10, 15, 22, 30, 0, 0, vietnam), "v4")
	g.advance(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam))
	at := time.Date(2026, 10, 16, 11, 0, 0, 0, vietnam)
	g.act(1, ww.KindNominate, "v1", at, "v2")
	g.act(1, ww.KindNominate, "w1", at, "v2")
	g.act(1, ww.KindNominate, "seer", at, "v3")
	g.act(1, ww.KindNominate, "v4", at, "v1")
	g.act(1, ww.KindNominate, "v3", at, "v4")
	v, raw = botWerewolfAt(t, g, at)
	noRoleExcept(t, raw, "Dân")
	want := map[string][]string{"V2": {"V1", "W1"}, "V3": {"SEER"}}
	if v.Game.Phase != "Ngày 1, đề cử" || !reflect.DeepEqual(v.Game.Nominations, want) {
		t.Fatalf("game = %s", raw)
	}
	if !reflect.DeepEqual(v.Game.Dead, []string{"V4: Dân, chết vòng 1"}) || len(v.Game.RecentNews) == 0 || v.Game.RecentNews[0].Title != "Bản tin đêm 1" {
		t.Fatalf("game = %s", raw)
	}

	// 17h V2 lên giàn. Người lên giàn và người chết bấm thì không tính.
	g.advance(time.Date(2026, 10, 16, 17, 0, 0, 0, vietnam))
	at = time.Date(2026, 10, 16, 20, 30, 0, 0, vietnam)
	for uid, choice := range map[string]string{"v1": ww.ChoiceHang, "w1": ww.ChoiceSpare, "v2": ww.ChoiceHang, "v4": ww.ChoiceHang} {
		seed(t, g.db, "games/"+g.id+"/rounds/1/actions/"+uid+"_vote", map[string]any{"uid": uid, "kind": string(ww.KindVote), "choice": choice, "receivedAt": at})
	}
	v, raw = botWerewolfAt(t, g, at)
	noRoleExcept(t, raw, "Dân")
	if v.Game.OnTrial != "V2" || !reflect.DeepEqual(v.Game.Votes, map[string][]string{"Treo": {"V1"}, "Tha": {"W1"}}) || v.Game.Nominations != nil {
		t.Fatalf("game = %s", raw)
	}

	// Ván thử không phải ván của group.
	seedMerge(t, g, map[string]any{"testMode": true})
	if v, _ = botWerewolfAt(t, g, at); v.Game != nil || v.NoGame == "" {
		t.Fatalf("ván thử: %+v", v)
	}
}

func TestEmulatorBotWerewolfWithoutGameStillHasRules(t *testing.T) {
	store := NewGameStore(emulatorDB(t), testPscChat)
	v, err := store.BotWerewolf(context.Background(), time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if v.Game != nil || v.NoGame == "" || v.Rules != gameRulesText || len(v.Roles) != len(roleRules) || !strings.Contains(v.VoteRules, "chia X km") {
		t.Fatalf("%+v", v)
	}
}
