//go:build emulator

package backend

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"
)

// Ba kèo công khai tuần 2–8/11, mục tiêu 10 km, chốt 06:00 9/11. Kết quả mong
// đợi tính tay từ km:
//   - k1 (bốc thăm, Áo 1 suất + Tất 2 suất) của an: cuong 10 km xong 4/11, binh
//     6+5 km xong 5/11, dung 4 km chưa đạt. 2 người đạt ≤ 3 suất nên khỏi bốc:
//     cuong (đạt trước) nhận Áo, binh nhận Tất. an tự chạy 12 km nhưng là chủ kèo.
//   - k2 (theo hạng, Huy chương 2 suất) của lan: em 15 km, hoa 12 km xong 3/11,
//     giang 12 km xong 4/11. Hạng: em 1, hoa 2 (bằng km nhưng đạt trước giang).
//   - k3 (bốc thăm) của minh: khoa không chạy, không ai có quà.
func TestEmulatorContractGifts(t *testing.T) {
	e := newAgentEnv(t)
	db := e.store.db
	ctx := context.Background()
	e.deps.ContractGifts = NewContractGiftService(db, NewTelegramLinkService(db, "threei_bot"))
	e.srv = NewAPIServer(e.cfg, e.deps)
	for uid, name := range map[string]string{"lan": "Lan", "minh": "Minh", "em": "Em", "giang": "Giang", "hoa": "Hoà", "khoa": "Khoa"} {
		seed(t, db, "publicProfiles/"+uid, map[string]any{"displayName": name})
	}
	seed(t, db, "tgLinks/777", map[string]any{"uid": "an", "username": "an_run"})
	seed(t, db, "telegramLinks/an", map[string]any{"tgUserId": "777"})
	day := func(d, h int) time.Time { return time.Date(2026, 11, d, h, 0, 0, 0, vietnam) }
	contract := func(id, creator, visibility string, uids ...string) {
		parts := map[string]any{}
		for i, uid := range append([]string{creator}, uids...) {
			parts[uid] = map[string]any{"uid": uid, "progressValue": 0, "countedActivityIds": []any{}, "joinedAt": day(2, 8+i)}
		}
		seed(t, db, "runContracts/"+id, map[string]any{
			"creatorUid": creator, "title": "Kèo " + id, "metric": "distance", "targetValue": 10,
			"visibility": visibility, "status": "active", "progressValue": 0,
			"startAt": day(2, 0), "endAtExclusive": day(9, 0), "finalizeAt": day(9, 6),
			"participants": parts, "participantUids": append([]string{creator}, uids...),
		})
	}
	put := func(uid, id, kind string, items ...map[string]any) apiResp {
		return e.call(uid, "PUT", "/v1/contracts/"+id+"/gifts", map[string]any{"kind": kind, "items": items}, "")
	}
	with := func(m map[string]any, kv ...any) map[string]any {
		out := map[string]any{}
		for k, v := range m {
			out[k] = v
		}
		for i := 0; i < len(kv); i += 2 {
			out[kv[i].(string)] = kv[i+1]
		}
		return out
	}
	ao := map[string]any{"name": " Áo PSC ", "icon": "shirt", "slots": 1, "photos": []string{"contractGifts/an/k1/a1.jpg"}}
	tat := map[string]any{"name": "Tất chạy", "icon": "socks", "slots": 2}

	// 3/11: chưa ai tham gia ngoài chủ kèo.
	e.clock = day(3, 8)
	contract("k1", "an", "club")
	contract("k0", "an", "private")
	e.want(put("binh", "k1", "draw", ao), 403, "not_creator")
	e.want(put("an", "k0", "draw", ao), 422, "gift_unsupported")
	// Bỏ k0 để buổi chạy của an tính vào k1 (một buổi chỉ gán một kèo).
	if _, err := db.Doc("runContracts/k0").Delete(ctx); err != nil {
		t.Fatal(err)
	}
	e.want(put("an", "nope", "draw", ao), 404, "contract_not_found")
	e.want(put("an", "k1", "lottery", ao), 422, "invalid_gift")
	e.want(put("an", "k1", "draw", with(ao, "slots", 0)), 422, "invalid_gift")
	e.want(put("an", "k1", "draw", with(ao, "photos", []string{"contractGifts/binh/k1/a1.jpg"})), 422, "invalid_gift")
	e.want(put("an", "k1", "draw", with(ao, "photos", []string{"contractGifts/an/k2/a1.jpg"})), 422, "invalid_gift")
	e.want(put("an", "k1", "draw", with(ao, "id", "ghost")), 422, "invalid_gift")
	e.want(put("an", "k1", "rank", tat), 200, "")
	e.want(put("an", "k1", "draw"), 200, "") // bỏ hết khi chưa ai tham gia
	if snap, _ := db.Doc("contractGifts/k1").Get(ctx); snap.Exists() {
		t.Fatal("bỏ hết quà mà doc còn")
	}
	e.want(put("an", "k1", "draw", ao, tat), 200, "")
	gift := rankDoc(t, db, "contractGifts/k1")
	items := contractGiftItemsFrom(gift["items"])
	if _, leaked := gift["giverTg"]; leaked {
		t.Fatalf("doc quà ai cũng đọc mà có Telegram người trao: %v", gift)
	}
	if len(items) != 2 || items[0].Name != "Áo PSC" || items[0].ID == "" || items[0].ID == items[1].ID || gift["giverName"] != "An" {
		t.Fatalf("quà sau lưu: %v", gift)
	}
	aoKept, tatKept := with(ao, "id", items[0].ID), with(tat, "id", items[1].ID)

	// Có người tham gia: chỉ thêm, không đổi kiểu.
	contract("k1", "an", "club", "binh", "cuong", "dung")
	e.want(put("an", "k1", "draw", tatKept, aoKept), 409, "gift_shrink")
	e.want(put("an", "k1", "draw", aoKept), 409, "gift_shrink")
	e.want(put("an", "k1", "draw", aoKept, with(tatKept, "slots", 1)), 409, "gift_shrink")
	e.want(put("an", "k1", "rank", aoKept, tatKept), 409, "gift_shrink")
	e.want(put("an", "k1", "draw"), 409, "gift_shrink")
	e.want(put("an", "k1", "draw", with(aoKept, "icon", "other"), tatKept), 200, "")

	contract("k2", "lan", "club", "em", "giang", "hoa")
	e.want(put("lan", "k2", "rank", map[string]any{"name": "Huy chương", "icon": "medal", "slots": 2}), 200, "")
	contract("k3", "minh", "club", "khoa")
	e.want(put("minh", "k3", "draw", tat), 200, "")

	for _, a := range []struct {
		uid  string
		at   time.Time
		km   float64
		name string
	}{
		{"an", day(3, 6), 12, "an1"},
		{"binh", day(3, 6), 6, "binh1"}, {"binh", day(5, 6), 5, "binh2"},
		{"cuong", day(4, 6), 10, "cuong1"},
		{"dung", day(4, 6), 4, "dung1"},
		{"em", day(4, 6), 15, "em1"},
		{"hoa", day(3, 6), 12, "hoa1"},
		{"giang", day(4, 6), 12, "giang1"},
	} {
		seedRankActivity(t, db, a.uid, a.name, "strava", "Run", a.at, a.km*1000)
	}

	tick := func() {
		t.Helper()
		recalced, err := RecalcActiveContracts(ctx, db, false)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := FinalizeDueContracts(ctx, db, e.publish, recalced, e.clock, false); err != nil {
			t.Fatal(err)
		}
		if err := SendContractGiftResults(ctx, db, e.publish, false); err != nil {
			t.Fatal(err)
		}
		if err := NotifyContractTickets(ctx, db, e.publish, recalced, false); err != nil {
			t.Fatal(err)
		}
	}
	pushes := func(event string) []contractGiftPushTask {
		var out []contractGiftPushTask
		for _, task := range e.tasksTo(contractGiftPushPath) {
			if p := task.Payload.(contractGiftPushTask); p.Event == event {
				out = append(out, p)
			}
		}
		return out
	}

	// 6/11: kèo còn chạy. Người đạt kèo bốc thăm có vé, báo một lần.
	e.clock = day(6, 8)
	// Hẹn vé lỗi: trả lỗi và chưa đánh dấu, lượt sau báo lại.
	recalced, err := RecalcActiveContracts(ctx, db, false)
	if err != nil {
		t.Fatal(err)
	}
	failing := func(context.Context, PublishTask) (string, error) { return "", errors.New("cloud tasks down") }
	if err := NotifyContractTickets(ctx, db, failing, recalced, false); err == nil {
		t.Fatal("hẹn vé lỗi mà không trả lỗi")
	}
	if k1, _ := getData(ctx, db.Collection("contractGifts").Doc("k1")); k1["ticketNotified"] != nil {
		t.Fatalf("hẹn vé lỗi mà đã đánh dấu: %v", k1["ticketNotified"])
	}
	tick()
	tick()
	tickets := pushes("ticket")
	if len(tickets) != 1 || tickets[0].ContractID != "k1" || !slices.Equal(tickets[0].UIDs, []string{"binh", "cuong"}) {
		t.Fatalf("vé: %+v", tickets)
	}
	e.want(put("an", "k1", "draw", aoKept, tatKept), 200, "") // còn sửa được trước khi hết kỳ

	// 9/11 03:00: hết kỳ, khoá dù chưa chốt.
	e.clock = day(9, 3)
	e.want(put("an", "k1", "draw", aoKept, tatKept), 409, "gift_locked")

	// 9/11 07:00: chốt; Cloud Tasks hỏng lúc hẹn push kết quả thì lượt sau hẹn
	// lại. Chốt hai lần, kết quả chỉ tính một lần.
	e.clock = day(9, 7)
	recalced, err = RecalcActiveContracts(ctx, db, false)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := FinalizeDueContracts(ctx, db, e.publish, recalced, e.clock, false); err != nil {
		t.Fatal(err)
	}
	down := func(context.Context, PublishTask) (string, error) { return "", errors.New("cloud tasks down") }
	if err := SendContractGiftResults(ctx, db, down, false); err == nil || len(pushes("result")) != 0 {
		t.Fatalf("hẹn lỗi mà err=%v, đã có %d push", err, len(pushes("result")))
	}
	tick()
	tick()
	for _, id := range []string{"k1", "k2", "k3"} {
		if _, pending := rankDoc(t, db, "contractGifts/"+id)["resultPushPending"]; pending {
			t.Fatalf("%s đã hẹn push mà còn cờ", id)
		}
	}
	type won struct {
		uid, item string
		rank      int
	}
	winners := func(id string) ([]won, []string) {
		g := rankDoc(t, db, "contractGifts/"+id)
		if g["resolvedAt"] == nil {
			t.Fatalf("%s chưa chốt quà: %v", id, g)
		}
		names := map[string]string{}
		for _, it := range contractGiftItemsFrom(g["items"]) {
			names[it.ID] = it.Name
		}
		var out []won
		for _, v := range anyList(g["winners"]) {
			m := v.(map[string]any)
			out = append(out, won{stringValue(m["uid"]), names[stringValue(m["itemId"])], int(number(m["rank"]))})
		}
		var entrants []string
		for _, v := range anyList(g["entrants"]) {
			entrants = append(entrants, stringValue(v))
		}
		slices.Sort(entrants)
		return out, entrants
	}
	if w, es := winners("k1"); !slices.Equal(w, []won{{"cuong", "Áo PSC", 0}, {"binh", "Tất chạy", 0}}) || !slices.Equal(es, []string{"binh", "cuong"}) {
		t.Fatalf("k1: %v, người đạt %v", w, es)
	}
	if w, es := winners("k2"); !slices.Equal(w, []won{{"em", "Huy chương", 1}, {"hoa", "Huy chương", 2}}) || !slices.Equal(es, []string{"em", "giang", "hoa"}) {
		t.Fatalf("k2: %v, người đạt %v", w, es)
	}
	if w, es := winners("k3"); len(w) != 0 || len(es) != 0 {
		t.Fatalf("k3 không ai đạt mà có %v, %v", w, es)
	}
	if c := rankDoc(t, db, "runContracts/k1"); c["status"] != "completed" || c["finalizedBy"] != "scheduler" {
		t.Fatalf("k1 sau chốt: %v %v", c["status"], c["finalizedBy"])
	}
	var results []string
	for _, p := range pushes("result") {
		results = append(results, p.ContractID)
	}
	slices.Sort(results)
	if !slices.Equal(results, []string{"k1", "k2"}) || len(pushes("ticket")) != 1 {
		t.Fatalf("push kết quả %v, vé %d", results, len(pushes("ticket")))
	}

	// Trao và nhận.
	given := func(uid string) string { return "/v1/contracts/k1/gifts/winners/" + uid + "/given" }
	received := "/v1/contracts/k1/gifts/received"
	winner := func(uid string) map[string]any {
		for _, v := range anyList(rankDoc(t, db, "contractGifts/k1")["winners"]) {
			if m := v.(map[string]any); m["uid"] == uid {
				return m
			}
		}
		t.Fatalf("không thấy %s trong người trúng", uid)
		return nil
	}
	e.want(e.call("dung", "POST", received, nil, ""), 404, "no_gift")
	e.want(e.call("binh", "POST", given("cuong"), nil, ""), 403, "not_creator")
	e.want(e.call("an", "POST", given("dung"), nil, ""), 404, "not_winner")
	contact := "/v1/contracts/k1/gifts/contact"
	e.want(e.call("dung", "GET", contact, nil, ""), 404, "no_gift")
	if r := e.call("cuong", "GET", contact, nil, ""); r.status != 200 || r.body["giverTg"] != "an_run" {
		t.Fatalf("người trúng hỏi liên hệ: %d %v", r.status, r.body)
	}
	e.want(e.call("an", "POST", given("cuong"), nil, ""), 200, "")
	if winner("cuong")["givenAt"] == nil {
		t.Fatal("đã trao mà givenAt rỗng")
	}
	e.want(e.call("an", "DELETE", given("cuong"), nil, ""), 200, "")
	if winner("cuong")["givenAt"] != nil {
		t.Fatal("bỏ đánh dấu mà givenAt còn")
	}
	for i := 0; i < 2; i++ {
		e.want(e.call("cuong", "POST", received, nil, ""), 200, "")
	}
	if w := winner("cuong"); w["receivedAt"] == nil || w["givenAt"] == nil {
		t.Fatalf("đã nhận: %v", w)
	}
	e.want(e.call("an", "DELETE", given("cuong"), nil, ""), 409, "gift_received")
	if w := winner("binh"); w["givenAt"] != nil || w["receivedAt"] != nil {
		t.Fatalf("binh chưa trao chưa nhận mà %v", w)
	}

	// Chủ kèo xoá tài khoản: quà mang tên họ cũng đi.
	if err := (&AccountService{db: db}).deleteContractGifts(ctx, "minh"); err != nil {
		t.Fatal(err)
	}
	if snap, _ := db.Doc("contractGifts/k3").Get(ctx); snap.Exists() {
		t.Fatal("xoá tài khoản mà quà kèo còn")
	}
	if snap, _ := db.Doc("contractGifts/k1").Get(ctx); !snap.Exists() {
		t.Fatal("xoá nhầm quà của người khác")
	}
}
