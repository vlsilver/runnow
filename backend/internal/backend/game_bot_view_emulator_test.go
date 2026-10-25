//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"reflect"
	"sort"
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

func sortedCopy(v []string) []string {
	out := append([]string(nil), v...)
	sort.Strings(out)
	return out
}

// botGameWithNames: ván 10 người đã Start, tên hiện là uid viết hoa.
func botGameWithNames(t *testing.T) *storeGame {
	t.Helper()
	g := newStoreGame(t)
	for uid := range storeRoles() {
		seed(t, g.db, "publicProfiles/"+uid, map[string]any{"displayName": strings.ToUpper(uid)})
	}
	return g
}

// 3i chỉ thấy phần ai cũng thấy: không vai người sống, người chết lật bài, đề cử
// và phiếu đếm như topic, ai chưa bấm, km tới giờ, dự báo mất phiếu theo R30.
func TestEmulatorBotWerewolfShowsOnlyPublicGame(t *testing.T) {
	g := botGameWithNames(t)

	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam))
	v, raw := botWerewolfAt(t, g, time.Date(2026, 10, 15, 23, 0, 0, 0, vietnam))
	noRoleExcept(t, raw)
	if v.Game == nil || v.Game.Phase != "Đêm 1, sói đang chọn" || v.Game.Deadline != "00:00 16/10" || v.Game.Now != "23:00 15/10" {
		t.Fatalf("game = %s", raw)
	}
	if len(v.Game.Alive) != 10 || len(v.Game.Dead) != 0 || v.Game.LastKm["V1"] != "5 km" || v.Game.KmSinceLast22h["V1"] != "5 km" || v.Game.KmFrameEnd != "22:00 16/10" {
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
	if got := sortedCopy(v.Game.NotChosenYet); !reflect.DeepEqual(got, []string{"GUARD", "HUNTER", "V2", "V3", "W2", "WITCH"}) {
		t.Fatalf("notChosenYet = %v", got)
	}
	if !reflect.DeepEqual(v.Game.Dead, []string{"V4: Dân, chết vòng 1"}) || len(v.Game.News) == 0 || v.Game.News[0].Title != "Bản tin đêm 1" {
		t.Fatalf("game = %s", raw)
	}

	// 20h V2 (2 đề cử) và V3 (1 đề cử) lên giàn, mỗi người một phiên. Người lên
	// giàn và người chết bấm thì không tính.
	g.advance(time.Date(2026, 10, 16, 20, 0, 0, 0, vietnam))
	at = time.Date(2026, 10, 16, 20, 30, 0, 0, vietnam)
	for uid, choice := range map[string]string{"v1": ww.ChoiceHang, "w1": ww.ChoiceSpare, "v2": ww.ChoiceHang, "v4": ww.ChoiceHang} {
		seed(t, g.db, "games/"+g.id+"/rounds/1/actions/"+uid+"_vote", map[string]any{"uid": uid, "kind": string(ww.KindVote), "choice": choice, "receivedAt": at})
	}
	// 8 người bỏ phiếu, tổng 6 km với X = 1 km: được tính 6 phiếu, mất 2. V1
	// ít nhất nên chắc mất; W1 và SEER bằng km ở ngưỡng nên bốc thăm một người.
	km := map[string]float64{"v1": 0, "w1": 500, "seer": 500}
	g.store.frameKm = func(_ context.Context, uid string, end time.Time) (FrameKm, error) {
		m, ok := km[uid]
		if !ok {
			m = 1000
		}
		return FrameKm{FrameEnd: end, Meters: m}, nil
	}
	v, raw = botWerewolfAt(t, g, at)
	noRoleExcept(t, raw, "Dân")
	if !reflect.DeepEqual(v.Game.OnTrial, []string{"V2", "V3"}) || len(v.Game.Trials) != 2 || v.Game.Nominations != nil {
		t.Fatalf("game = %s", raw)
	}
	if tr := v.Game.Trials; tr[0].Nominee != "V2" || !reflect.DeepEqual(tr[0].Votes, map[string][]string{"Treo": {"V1"}, "Tha": {"W1"}}) || tr[1].Nominee != "V3" || len(tr[1].Votes) != 0 {
		t.Fatalf("game = %s", raw)
	}
	// Chưa ai bấm ở phiên V3, nên ai sống cũng còn ít nhất một phiên chưa bấm.
	if got := sortedCopy(v.Game.NotChosenYet); !reflect.DeepEqual(got, []string{"GUARD", "HUNTER", "SEER", "V1", "V2", "V3", "W1", "W2", "WITCH"}) {
		t.Fatalf("notChosenYet = %v", got)
	}
	f := v.Game.Trials[0].VoteForecast
	if f == nil || f.Voters != 8 || f.CountedIfNow != 6 || !reflect.DeepEqual(f.LoseVote, []string{"V1"}) || !reflect.DeepEqual(sortedCopy(f.DrawAmong), []string{"SEER", "W1"}) || f.DrawLose != 1 {
		t.Fatalf("voteForecast = %+v", f)
	}
	// Tổng 6 km, mất 2: V1 và W1 cùng 0 km ở ngưỡng, cả nhóm đều mất nên không
	// phải bốc thăm.
	km["seer"] = 1000
	km["w1"] = 0
	v, _ = botWerewolfAt(t, g, at)
	if f := v.Game.Trials[0].VoteForecast; !reflect.DeepEqual(sortedCopy(f.LoseVote), []string{"V1", "W1"}) || f.DrawAmong != nil {
		t.Fatalf("voteForecast = %+v", f)
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

// get_my_werewolf trả đúng phần /me của người có Telegram id đó, và chỉ khi
// liên kết khớp cả hai chiều.
func TestEmulatorBotMyWerewolfIsTheAskersOwn(t *testing.T) {
	g := botGameWithNames(t)
	for uid, tg := range g.tg {
		seed(t, g.db, "telegramLinks/"+uid, map[string]any{"tgUserId": mustInt(tg)})
	}
	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam))
	at := time.Date(2026, 10, 15, 23, 0, 0, 0, vietnam)
	ctx := context.Background()

	seer, err := g.store.BotMyWerewolf(ctx, g.tg["seer"], at)
	if err != nil {
		t.Fatal(err)
	}
	if seer.NotPlaying != "" || seer.Role != "Tiên tri" || !seer.Alive || !reflect.DeepEqual(seer.Todo, []string{"Soi"}) || seer.KmSinceLast22h != "5 km" || seer.KmPerUnit != "1 km" {
		t.Fatalf("seer = %+v", seer)
	}

	g.act(1, ww.KindWolfBite, "w1", at, "v3")
	wolf, err := g.store.BotMyWerewolf(ctx, g.tg["w1"], at)
	if err != nil {
		t.Fatal(err)
	}
	notes := strings.Join(wolf.Notes, "\n")
	if wolf.Role != "Sói" || !strings.Contains(notes, "W2") || len(wolf.Actions) != 1 || wolf.Actions[0].Selected != "V3" || wolf.Todo != nil {
		t.Fatalf("wolf = %+v", wolf)
	}

	// tgLinks trỏ tới seer nhưng telegramLinks/seer trỏ tg khác: không nhận.
	seed(t, g.db, "tgLinks/777", map[string]any{"uid": "seer"})
	for _, tg := range []string{"777", "123", ""} {
		got, err := g.store.BotMyWerewolf(ctx, tg, at)
		if err != nil {
			t.Fatal(err)
		}
		if got.NotPlaying == "" || got.Role != "" {
			t.Fatalf("tg %q: %+v", tg, got)
		}
	}
}
