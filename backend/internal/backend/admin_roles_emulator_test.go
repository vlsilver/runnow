//go:build emulator

package backend

import "testing"

func TestEmulatorAdminRoles(t *testing.T) {
	e := newAgentEnv(t)
	e.cfg.TelegramChatID, e.cfg.TelegramBotUsername = "-1001", "threei_bot"
	e.srv = NewAPIServer(e.cfg, e.deps)
	roles := func(uid string) map[string][]string {
		r := e.call(uid, "GET", "/v1/admin/settings", nil, "")
		e.want(r, 200, "")
		out := map[string][]string{}
		for role, uids := range r.body["roles"].(map[string]any) {
			out[role] = toStrings(uids)
		}
		return out
	}

	// Người không phải admin: không xem, không sửa được.
	e.want(e.call("cuong", "GET", "/v1/admin/settings", nil, ""), 403, "not_admin")
	e.want(e.call("cuong", "POST", "/v1/admin/roles/admin/cuong", nil, ""), 403, "not_admin")
	e.want(e.call("cuong", "DELETE", "/v1/admin/roles/admin/an", nil, ""), 403, "not_admin")

	r := e.call("an", "GET", "/v1/admin/settings", nil, "")
	tg, _ := r.body["telegram"].(map[string]any)
	if tg["chatId"] != "-1001" || tg["botUsername"] != "threei_bot" {
		t.Fatalf("telegram: %s", r.raw)
	}
	got := roles("an")
	wantList(t, "admin", got["admin"], "an", "binh")
	wantList(t, "tester", got["tester"])
	wantList(t, "bot", got["bot"], "cuong")

	// Cấp hai lần vẫn chỉ một dòng.
	for i := 0; i < 2; i++ {
		e.want(e.call("an", "POST", "/v1/admin/roles/tester/dung", nil, ""), 200, "")
	}
	wantList(t, "tester sau cấp", toStrings(e.doc("gameState/config")["testerUids"]), "dung")
	e.want(e.call("an", "POST", "/v1/admin/roles/bot/ghost", nil, ""), 404, "user_not_found")
	e.want(e.call("an", "POST", "/v1/admin/roles/owner/dung", nil, ""), 404, "unknown_role")

	// Không tự bỏ quyền admin của mình, nên lúc nào cũng còn ít nhất một admin.
	e.want(e.call("an", "DELETE", "/v1/admin/roles/admin/an", nil, ""), 409, "cannot_remove_self")
	for i := 0; i < 2; i++ {
		e.want(e.call("an", "DELETE", "/v1/admin/roles/admin/binh", nil, ""), 200, "")
	}
	e.want(e.call("binh", "POST", "/v1/admin/roles/admin/binh", nil, ""), 403, "not_admin")
	e.want(e.call("an", "DELETE", "/v1/admin/roles/bot/cuong", nil, ""), 200, "")
	got = roles("an")
	wantList(t, "admin sau bỏ", got["admin"], "an")
	wantList(t, "bot sau bỏ", got["bot"])
	// Bỏ quyền bot là mất bot ngay, không cần deploy.
	e.want(e.call("cuong", "GET", "/v1/agents/group-facts", nil, ""), 403, "agent_disabled")
}
