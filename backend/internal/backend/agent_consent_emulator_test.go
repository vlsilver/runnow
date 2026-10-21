//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// consent: người vào bằng cờ open bấm đồng ý AI.
func (e *agentEnv) consent(uid string) {
	e.t.Helper()
	e.want(e.call(uid, "POST", "/v1/agents/me/consent", map[string]any{"version": 1}, ""), 200, "")
}

// wantConsentRequired: API trả consent_required kèm bản cần đồng ý.
func (e *agentEnv) wantConsentRequired(r apiResp) {
	e.t.Helper()
	e.want(r, 403, "consent_required")
	if r.body["consentVersion"] != float64(1) {
		e.t.Fatalf("consent_required thiếu consentVersion: %s", r.raw)
	}
}

func (e *agentEnv) wantConsentState(uid string, required bool) {
	e.t.Helper()
	r := e.call(uid, "GET", "/v1/agents/me", nil, "")
	if r.status != 200 || r.body["consentRequired"] != required || r.body["consentVersion"] != float64(1) {
		e.t.Fatalf("GET me của %s: muốn consentRequired=%v, được %d %s", uid, required, r.status, r.raw)
	}
}

// Người vào bằng cờ open: chưa đồng ý thì mọi API đưa dữ liệu của họ tới model
// đều bị chặn, không ghi gì, không hẹn task nào, không gọi model. Đồng ý rồi
// thì dùng như thường, bấm đồng ý lần hai không đổi lần đồng ý đầu.
func TestEmulatorAgentConsentOpenUser(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.setOpen(true)

	e.wantConsentState("dung", true)
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/me", map[string]any{"name": "Dế"}, ""))
	if len(e.doc("agents/dung")) != 0 {
		t.Fatalf("chưa đồng ý mà đã tạo bot: %v", e.doc("agents/dung"))
	}
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""))
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/room", map[string]any{"text": "Sóc ơi"}, ""))
	if len(e.tasks) != 0 || len(e.llm.calls) != 0 {
		t.Fatalf("chưa đồng ý mà vẫn hẹn %d task, gọi model %d lần", len(e.tasks), len(e.llm.calls))
	}
	if msgs := messages(t, e.call("an", "GET", "/v1/agents/room", nil, "")); len(msgs) != 0 {
		t.Fatalf("chưa đồng ý mà tin đã vào phòng: %v", msgs)
	}
	// Đọc và xoá dữ liệu của mình thì không cần đồng ý.
	e.want(e.call("dung", "GET", "/v1/agents/room", nil, ""), 200, "")
	e.want(e.call("dung", "DELETE", "/v1/agents/me/learned/x", nil, ""), 200, "")

	e.want(e.call("dung", "POST", "/v1/agents/me/consent", map[string]any{"version": 2}, ""), 409, "consent_version_mismatch")
	e.want(e.call("dung", "POST", "/v1/agents/me/consent", map[string]any{}, ""), 409, "consent_version_mismatch")
	r := e.call("dung", "POST", "/v1/agents/me/consent", map[string]any{"version": 1}, "")
	if r.status != 200 || r.body["consentRequired"] != false || r.body["consentVersion"] != float64(1) {
		t.Fatalf("đồng ý: %d %s", r.status, r.raw)
	}
	consent := e.doc("agents/dung/consent/ai")
	if consent["version"] != int64(1) || consent["source"] != "app" || !consent["at"].(time.Time).Equal(agentClock) {
		t.Fatalf("bản ghi đồng ý: %v", consent)
	}
	// Đồng ý mà chưa tạo bot thì không được đẻ ra bot rỗng.
	if len(e.doc("agents/dung")) != 0 {
		t.Fatalf("đồng ý làm agents/dung tồn tại: %v", e.doc("agents/dung"))
	}
	r = e.call("dung", "GET", "/v1/agents/me", nil, "")
	if agent, _ := r.body["agent"].(map[string]any); r.body["consentRequired"] != false || agent["created"] != false {
		t.Fatalf("GET me sau khi đồng ý, chưa tạo bot: %s", r.raw)
	}
	e.tick(time.Hour)
	e.consent("dung")
	if at := e.doc("agents/dung/consent/ai")["at"].(time.Time); !at.Equal(agentClock) {
		t.Fatalf("đồng ý lần hai ghi đè lần đầu: %v", at)
	}

	e.createBot("dung", "Dế", "")
	e.want(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chào chủ")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "dung", Seq: 1})
	if len(e.llm.calls) != 1 {
		t.Fatalf("đồng ý rồi mà chat riêng không gọi model: %d", len(e.llm.calls))
	}
	e.want(e.call("dung", "POST", "/v1/agents/room", map[string]any{"text": "Sóc ơi"}, ""), 200, "")
	if n := len(roomTurnTasks(e)); n != 1 {
		t.Fatalf("đồng ý rồi mà tin phòng không hẹn lượt bot: %d", n)
	}
}

// Đổi điều khoản (bản đã đồng ý nhỏ hơn bản hiện hành) thì phải đồng ý lại.
func TestEmulatorAgentConsentOutdated(t *testing.T) {
	e := newAgentEnv(t)
	e.setOpen(true)
	seed(t, e.store.db, "agents/dung", map[string]any{"name": "Dế", "inRoom": true})
	seed(t, e.store.db, "agents/dung/consent/ai", map[string]any{"version": 0, "at": agentClock, "source": "app"})

	e.wantConsentState("dung", true)
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/me", map[string]any{"name": "Dế"}, ""))
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""))
	e.wantConsentRequired(e.call("dung", "POST", "/v1/agents/room", map[string]any{"text": "a"}, ""))
	if len(e.tasks) != 0 {
		t.Fatalf("bản cũ mà vẫn hẹn task: %v", e.tasks)
	}

	e.tick(time.Minute)
	e.want(e.call("dung", "POST", "/v1/agents/me/consent", map[string]any{"version": 1}, ""), 200, "")
	if c := e.doc("agents/dung/consent/ai"); c["version"] != int64(1) || !c["at"].(time.Time).Equal(agentClock.Add(time.Minute)) {
		t.Fatalf("đồng ý bản mới không ghi đè bản cũ: %v", c)
	}
	e.wantConsentState("dung", false)
	e.want(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
}

// Allowlist (tester trên app 1.5.0) không bao giờ bị đòi đồng ý, cờ bật hay
// tắt cũng vậy, và không ai ghi bản ghi đồng ý hộ họ.
func TestEmulatorAgentConsentAllowlistExempt(t *testing.T) {
	e := newAgentEnv(t)
	for _, open := range []bool{false, true} {
		e.setOpen(open)
		e.tick(time.Second)
		e.wantConsentState("cuong", false)
		e.createBot("cuong", "Cú", "")
		e.want(e.call("cuong", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
		e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "a"}, ""), 200, "")
	}
	if len(e.doc("agents/cuong/consent/ai")) != 0 {
		t.Fatalf("tự ghi đồng ý cho allowlist: %v", e.doc("agents/cuong/consent/ai"))
	}
	// Cờ tắt thì người ngoài allowlist vẫn agent_disabled như cũ, không phải
	// consent_required, kể cả khi gửi đồng ý.
	e.setOpen(false)
	e.want(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 403, "agent_disabled")
	e.want(e.call("dung", "POST", "/v1/agents/me/consent", map[string]any{"version": 1}, ""), 403, "agent_disabled")
	if r := e.call("dung", "GET", "/v1/agents/me", nil, ""); r.body["enabled"] != false || r.body["consentRequired"] != false {
		t.Fatalf("GET me người không có quyền: %s", r.raw)
	}
}

// Backfill ghi đồng ý cho allowlist, không đụng người đã tự đồng ý, không tạo
// bot cho ai, chạy lại không đổi gì.
func TestEmulatorAgentBackfillAIConsent(t *testing.T) {
	e := newAgentEnv(t)
	e.setOpen(true)
	e.createBot("an", "Sóc", "")
	seed(t, e.store.db, "agents/binh/consent/ai", map[string]any{"version": 1, "at": agentClock.Add(-time.Hour), "source": "app"})
	wall := agentClock.Add(time.Hour)

	for run, want := range []string{"an,cuong", ""} {
		set, err := e.deps.Agents.BackfillAIConsent(context.Background(), wall)
		if err != nil || strings.Join(set, ",") != want {
			t.Fatalf("lần %d: ghi %v %v, muốn %q", run+1, set, err, want)
		}
		for _, uid := range []string{"an", "cuong"} {
			c := e.doc("agents/" + uid + "/consent/ai")
			if c["version"] != int64(1) || c["source"] != "backfill" || !c["at"].(time.Time).Equal(wall) {
				t.Fatalf("lần %d: đồng ý của %s: %v", run+1, uid, c)
			}
		}
		if c := e.doc("agents/binh/consent/ai"); c["source"] != "app" {
			t.Fatalf("lần %d: ghi đè đồng ý Bình tự bấm: %v", run+1, c)
		}
		if len(e.doc("agents/dung/consent/ai")) != 0 {
			t.Fatalf("lần %d: ghi đồng ý cho người ngoài allowlist", run+1)
		}
		if len(e.doc("agents/cuong")) != 0 {
			t.Fatalf("lần %d: tạo bot cho Cường: %v", run+1, e.doc("agents/cuong"))
		}
	}
}

// Xoá tài khoản gỡ luôn bản ghi đồng ý, kể cả khi người đó chưa tạo bot (doc
// cha agents/{uid} không tồn tại).
func TestEmulatorAccountDeleteRemovesAIConsent(t *testing.T) {
	e := newAgentEnv(t)
	e.setOpen(true)
	e.consent("dung")
	e.consent("binh")
	e.createBot("binh", "Mèo", "")
	db := e.store.db
	accounts := &AccountService{db: db, auth: e.auth, oauth: &OAuthService{db: db}}
	for _, uid := range []string{"dung", "binh"} {
		if err := accounts.Delete(context.Background(), uid); err != nil {
			t.Fatal(err)
		}
		if len(e.doc("agents/"+uid+"/consent/ai")) != 0 {
			t.Fatalf("xoá tài khoản %s mà còn bản ghi đồng ý", uid)
		}
	}
	if len(e.doc("agents/binh")) != 0 {
		t.Fatal("xoá tài khoản mà còn bot")
	}
}
