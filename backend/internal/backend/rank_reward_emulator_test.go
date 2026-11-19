//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"
)

// Quà tuần 26/10–1/11, bảng Chạy. Hạng mong đợi tính tay từ km: an 30, binh 20,
// chi 20 (chung hạng 2 với binh), dung 5 (hạng 4).
func TestEmulatorRankRewards(t *testing.T) {
	e := newAgentEnv(t)
	db := e.store.db
	e.deps.RankRewards = NewRankRewardService(db, NewTelegramLinkService(db, "threei_bot"))
	e.srv = NewAPIServer(e.cfg, e.deps)
	// Bình, người trao, đã liên kết Telegram từ trước khi treo quà.
	seed(t, db, "telegramLinks/binh", map[string]any{"tgUserId": "888"})
	seed(t, db, "tgLinks/888", map[string]any{"uid": "binh", "username": "binh_run"})
	const board = "week_2026-10-26_run"
	path := "/v1/admin/rank-rewards/" + board
	photo := "rankRewards/" + board + "/a1.jpg"
	ao := map[string]any{"fromRank": 1, "toRank": 1, "name": " Áo PSC ", "icon": "shirt", "photos": []string{photo}}
	tat := map[string]any{"fromRank": 2, "toRank": 3, "name": "Tất chạy", "icon": "socks"}
	put := func(uid, giver string, items ...map[string]any) apiResp {
		if items == nil {
			items = []map[string]any{}
		}
		return e.call(uid, "PUT", path, map[string]any{"giverUid": giver, "items": items}, "")
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

	// 20/10: kỳ chưa bắt đầu. Chỉ admin sửa, quà phải hợp lệ.
	e.want(put("cuong", "binh", ao), 403, "not_admin")
	e.want(put("an", "binh", ao, with(tat, "fromRank", 1)), 422, "invalid_reward")
	e.want(put("an", "binh", with(ao, "icon", "car")), 422, "invalid_reward")
	e.want(put("an", "binh", with(ao, "toRank", 11)), 422, "invalid_reward")
	e.want(put("an", "binh", with(ao, "name", strings.Repeat("á", 41))), 422, "invalid_reward")
	e.want(put("an", "binh", with(ao, "photos", []string{"rankRewards/week_2026-11-02_run/a1.jpg"})), 422, "invalid_reward")
	e.want(put("an", "binh", with(ao, "photos", []string{"rankRewards/" + board + "/../x.jpg"})), 422, "invalid_reward")
	e.want(put("an", "cuong", ao), 422, "invalid_giver")
	e.want(e.call("an", "PUT", "/v1/admin/rank-rewards/week_2026-10-27_run", map[string]any{"giverUid": "binh", "items": []any{ao}}, ""), 404, "unknown_board")

	r := put("an", "binh", tat, ao)
	e.want(r, 200, "")
	items, _ := r.body["items"].([]any)
	if len(items) != 2 || r.body["state"] != "upcoming" || r.body["giverName"] != "Bình" {
		t.Fatalf("quà sau lưu: %s", r.raw)
	}
	first, second := items[0].(map[string]any), items[1].(map[string]any)
	if first["name"] != "Áo PSC" || second["name"] != "Tất chạy" || first["id"] == "" || first["id"] == second["id"] {
		t.Fatalf("quà phải sắp theo hạng, tên bỏ khoảng trắng, có id riêng: %s", r.raw)
	}
	aoID, tatID := first["id"].(string), second["id"].(string)
	// Chưa bắt đầu thì bỏ hết được.
	e.want(put("an", "binh"), 200, "")
	if snap, _ := db.Doc("rankRewards/" + board).Get(context.Background()); snap.Exists() {
		t.Fatal("bỏ hết quà mà doc còn")
	}
	r = put("an", "binh", ao, tat)
	e.want(r, 200, "")
	items, _ = r.body["items"].([]any)
	aoID, tatID = items[0].(map[string]any)["id"].(string), items[1].(map[string]any)["id"].(string)

	// 28/10: kỳ đang chạy, chỉ thêm.
	e.clock = time.Date(2026, 10, 28, 8, 0, 0, 0, vietnam)
	aoKept, tatKept := with(ao, "id", aoID), with(tat, "id", tatID)
	e.want(put("an", "binh", aoKept), 409, "reward_shrink")
	e.want(put("an", "binh", aoKept, with(tatKept, "name", "Tất xịn")), 409, "reward_shrink")
	e.want(put("an", "binh", aoKept, with(tatKept, "toRank", 2)), 409, "reward_shrink")
	e.want(put("an", "binh", aoKept, tatKept, with(tat, "id", "ghost", "fromRank", 5, "toRank", 5)), 422, "invalid_reward")
	huy := map[string]any{"fromRank": 5, "toRank": 10, "name": "Huy chương", "icon": "medal"}
	e.want(put("an", "binh", with(aoKept, "icon", "other"), tatKept, huy), 200, "")

	// 2/11 12:30: hết kỳ, khoá.
	e.clock = time.Date(2026, 11, 2, 12, 30, 0, 0, vietnam)
	e.want(put("an", "binh", aoKept, tatKept, huy), 409, "reward_locked")

	for uid, km := range map[string]float64{"an": 30, "binh": 20, "chi": 20, "dung": 5} {
		seed(t, db, "publicProfiles/"+uid, map[string]any{"profileVisibility": "public", "displayName": map[string]string{"an": "An", "binh": "Bình", "chi": "Chi", "dung": "Dũng"}[uid]})
		seedRankActivity(t, db, uid, uid+"1", "strava", "Run", time.Date(2026, 10, 28, 6, 0, 0, 0, vietnam), km*1000)
	}
	ranks := NewRankCardService(db, nil)
	ranks.enqueue = e.publish
	for i := 0; i < 2; i++ {
		if err := ranks.Close(context.Background(), e.clock); err != nil {
			t.Fatal(err)
		}
	}
	for uid, want := range map[string]string{"an": "Áo PSC", "binh": "Tất chạy", "chi": "Tất chạy"} {
		reward, _ := rankDoc(t, db, "users/"+uid+"/rankCards/"+board)["reward"].(map[string]any)
		if reward["name"] != want || reward["giverName"] != "Bình" || reward["givenAt"] != nil || reward["receivedAt"] != nil {
			t.Fatalf("quà trên thẻ %s = %v", uid, reward)
		}
		if _, leaked := reward["giverTg"]; leaked {
			t.Fatalf("thẻ %s chép Telegram người trao", uid)
		}
	}
	if _, leaked := rankDoc(t, db, "rankRewards/"+board)["giverTg"]; leaked {
		t.Fatal("doc quà ai cũng đọc được mà chép Telegram người trao")
	}
	if reward := rankDoc(t, db, "users/dung/rankCards/"+board)["reward"]; reward != nil {
		t.Fatalf("hạng 4 không có quà mà thẻ có %v", reward)
	}
	if reward := rankDoc(t, db, "users/an/rankCards/month_2026-10-01_run")["reward"]; reward != nil {
		t.Fatalf("bảng tháng không treo quà mà thẻ có %v", reward)
	}
	b := rankDoc(t, db, "rankBoards/"+board)
	var withGift []string
	for _, raw := range b["entries"].([]any) {
		if m := raw.(map[string]any); m["reward"] != nil {
			withGift = append(withGift, m["uid"].(string))
		}
	}
	if strings.Join(withGift, " ") != "an binh chi" {
		t.Fatalf("bảng: quà ở %v", withGift)
	}
	pushes := e.tasksTo(rankRewardPushPath)
	if len(pushes) != 1 || pushes[0].Payload.(rankRewardPushTask).BoardID != board {
		t.Fatalf("chốt hai lần phải hẹn đúng một push của bảng có quà: %+v", pushes)
	}

	// Trao và nhận.
	given := path + "/winners/%s/given"
	at := func(uid string) string { return strings.Replace(given, "%s", uid, 1) }
	received := "/v1/rank-cards/" + board + "/reward/received"
	e.want(e.call("cuong", "POST", at("an"), nil, ""), 403, "not_admin")
	e.want(e.call("an", "POST", at("dung"), nil, ""), 404, "no_reward")
	r = e.call("an", "POST", at("binh"), nil, "")
	e.want(r, 200, "")
	if winners, _ := r.body["winners"].([]any); len(winners) != 3 {
		t.Fatalf("người trúng: %s", r.raw)
	}
	if rankDoc(t, db, "users/binh/rankCards/"+board)["reward"].(map[string]any)["givenAt"] == nil {
		t.Fatal("đã trao mà givenAt rỗng")
	}
	for i := 0; i < 2; i++ {
		e.want(e.call("chi", "POST", received, nil, ""), 200, "")
	}
	chi := rankDoc(t, db, "users/chi/rankCards/"+board)["reward"].(map[string]any)
	if chi["givenAt"] == nil || chi["receivedAt"] == nil {
		t.Fatalf("nhận quà phải ghi cả đã trao: %v", chi)
	}
	e.want(e.call("an", "DELETE", at("chi"), nil, ""), 409, "reward_received")
	e.want(e.call("an", "DELETE", at("binh"), nil, ""), 200, "")
	if rankDoc(t, db, "users/binh/rankCards/"+board)["reward"].(map[string]any)["givenAt"] != nil {
		t.Fatal("bỏ đánh dấu mà givenAt còn")
	}
	// Trao đủ 14 ngày thì coi như đã nhận, không bỏ đánh dấu được nữa.
	e.want(e.call("an", "POST", at("binh"), nil, ""), 200, "")
	e.tick(14*24*time.Hour - time.Second)
	e.want(e.call("an", "DELETE", at("binh"), nil, ""), 200, "")
	e.want(e.call("an", "POST", at("binh"), nil, ""), 200, "")
	e.tick(14 * 24 * time.Hour)
	e.want(e.call("an", "DELETE", at("binh"), nil, ""), 409, "reward_received")
	e.want(e.call("dung", "POST", received, nil, ""), 404, "no_reward")

	// Telegram người trao chỉ người trúng hỏi được, đọc lúc hỏi.
	contact := "/v1/rank-cards/" + board + "/reward/contact"
	e.want(e.call("dung", "GET", contact, nil, ""), 404, "no_reward")
	e.want(e.call("chi", "GET", "/v1/rank-cards/week_x/reward/contact", nil, ""), 404, "unknown_board")
	if r := e.call("chi", "GET", contact, nil, ""); r.status != 200 || r.body["giverTg"] != "binh_run" {
		t.Fatalf("người trúng hỏi liên hệ: %d %s", r.status, r.raw)
	}
}
