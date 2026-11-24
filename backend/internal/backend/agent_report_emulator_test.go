//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// hiddenSeqs là seq của các tin bị ẩn trong trang, theo thứ tự trả về; tin bị
// ẩn mà còn chữ thì fail.
func hiddenSeqs(t *testing.T, msgs []map[string]any) []float64 {
	t.Helper()
	var out []float64
	for _, m := range msgs {
		if m["hidden"] == true {
			if m["text"] != "" {
				t.Fatalf("tin ẩn mà còn chữ: %v", m)
			}
			out = append(out, m["seq"].(float64))
		}
	}
	return out
}

func seqsOf(msgs []map[string]any) []float64 {
	out := make([]float64, len(msgs))
	for i, m := range msgs {
		out[i] = m["seq"].(float64)
	}
	return out
}

func sameSeqs(a, b []float64) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// adminDMs là chữ các tin gửi tới tg id của admin.
func adminDMs(tg *fakeTelegram, chat string) []string {
	var out []string
	for _, c := range tg.Calls("sendMessage") {
		if c.Params["chat_id"] == chat {
			out = append(out, c.Params["text"].(string))
		}
	}
	return out
}

// Báo cáo tin trong phòng: DM admin, ghi đè khi bấm lại; chặn thì ẩn tin của
// người bị chặn lẫn bot của họ với riêng người chặn, cả trang lẫn poll after.
func TestEmulatorAgentRoomReportBlock(t *testing.T) {
	e := newAgentEnv(t)
	tg := newFakeTelegram(t)
	e.deps.Telegram = tg.service(testPscChat)
	seed(t, e.store.db, "telegramLinks/an", map[string]any{"tgUserId": "5000"})
	seed(t, e.store.db, "tgLinks/5000", map[string]any{"uid": "an"})
	e.createBot("an", "Sóc", "")
	e.createBot("binh", "Mèo", "")

	// Lọc từ tục ở tin người gửi vào phòng và ở câu bot nói.
	e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "đm ai chạy không"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Đéo, mình lười")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/room", map[string]any{"text": "chào cả nhà"}, ""), 200, "")
	msgs := messages(t, e.call("cuong", "GET", "/v1/agents/room", nil, ""))
	if len(msgs) != 3 || msgs[2]["text"] != "** ai chạy không" || msgs[1]["name"] != "Sóc" || msgs[1]["text"] != "***, mình lười" {
		t.Fatalf("phòng sau khi lọc: %v", msgs)
	}
	if got := hiddenSeqs(t, msgs); len(got) != 0 {
		t.Fatalf("chưa chặn mà ẩn %v", got)
	}

	// Báo cáo hai lần cùng tin: một báo cáo, mỗi lần đều DM admin.
	for i := 0; i < 2; i++ {
		e.want(e.call("cuong", "POST", "/v1/agents/room/messages/1/report", map[string]any{}, ""), 200, "")
	}
	reports, err := e.store.db.Collection("agentRooms/main/reports").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(reports) != 1 || reports[0].Ref.ID != "0000000001_cuong" || reports[0].Data()["author"] != "binh" || reports[0].Data()["block"] != false {
		t.Fatalf("báo cáo: %d doc", len(reports))
	}
	dms := adminDMs(tg, "5000")
	if len(dms) != 2 || !strings.Contains(dms[0], "Cường báo cáo tin của Bình.") || !strings.Contains(dms[0], "** ai chạy không") {
		t.Fatalf("DM admin = %q", dms)
	}
	if msgs := messages(t, e.call("cuong", "GET", "/v1/agents/room", nil, "")); len(hiddenSeqs(t, msgs)) != 0 {
		t.Fatalf("chỉ báo cáo mà đã ẩn: %v", msgs)
	}

	// Báo cáo tin của bot Sóc và chặn: người bị chặn là An, chủ bot.
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/2/report", map[string]any{"block": true}, ""), 200, "")
	if dms := adminDMs(tg, "5000"); len(dms) != 3 || !strings.Contains(dms[2], "tin của bot Sóc (của An) và chặn An") {
		t.Fatalf("DM admin khi báo cáo bot = %q", dms)
	}
	msgs = messages(t, e.call("cuong", "GET", "/v1/agents/room", nil, ""))
	if !sameSeqs(seqsOf(msgs), []float64{3, 2, 1}) || !sameSeqs(hiddenSeqs(t, msgs), []float64{3, 2}) || msgs[1]["name"] != "Sóc" {
		t.Fatalf("Cường chặn An, trang: %v", msgs)
	}
	msgs = messages(t, e.call("cuong", "GET", "/v1/agents/room?after=1", nil, ""))
	if !sameSeqs(seqsOf(msgs), []float64{3, 2}) || !sameSeqs(hiddenSeqs(t, msgs), []float64{3, 2}) {
		t.Fatalf("Cường chặn An, poll after: %v", msgs)
	}
	for _, uid := range []string{"an", "binh"} {
		if msgs := messages(t, e.call(uid, "GET", "/v1/agents/room", nil, "")); len(hiddenSeqs(t, msgs)) != 0 {
			t.Fatalf("%s không chặn ai mà thấy tin ẩn: %v", uid, msgs)
		}
	}

	// Chặn lại người đã chặn thì danh sách không nhân đôi.
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/3/report", map[string]any{"block": true}, ""), 200, "")
	r := e.call("cuong", "GET", "/v1/agents/blocks", nil, "")
	if blocks := anyList(r.body["blocks"]); r.status != 200 || len(blocks) != 1 || blocks[0].(map[string]any)["uid"] != "an" || blocks[0].(map[string]any)["name"] != "An" {
		t.Fatalf("danh sách chặn: %d %s", r.status, r.raw)
	}

	e.want(e.call("binh", "POST", "/v1/agents/room/messages/1/report", map[string]any{}, ""), 400, "invalid_request")
	e.want(e.call("an", "POST", "/v1/agents/room/messages/2/report", map[string]any{}, ""), 400, "invalid_request")
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/99/report", map[string]any{}, ""), 404, "message_not_found")
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/abc/report", map[string]any{}, ""), 400, "invalid_request")
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/0/report", map[string]any{}, ""), 400, "invalid_request")
	e.want(e.call("dung", "POST", "/v1/agents/room/messages/1/report", map[string]any{}, ""), 403, "agent_disabled")
	e.want(e.call("dung", "GET", "/v1/agents/blocks", nil, ""), 403, "agent_disabled")
	e.want(e.call("dung", "DELETE", "/v1/agents/blocks/an", nil, ""), 403, "agent_disabled")

	// Bỏ chặn thì thấy lại; bỏ lần hai, hay bỏ khi chưa chặn ai, vẫn 200.
	for i := 0; i < 2; i++ {
		e.want(e.call("cuong", "DELETE", "/v1/agents/blocks/an", nil, ""), 200, "")
	}
	e.want(e.call("binh", "DELETE", "/v1/agents/blocks/an", nil, ""), 200, "")
	if msgs := messages(t, e.call("cuong", "GET", "/v1/agents/room", nil, "")); len(hiddenSeqs(t, msgs)) != 0 || msgs[0]["text"] != "chào cả nhà" {
		t.Fatalf("bỏ chặn mà vẫn ẩn: %v", msgs)
	}
	if r := e.call("cuong", "GET", "/v1/agents/blocks", nil, ""); string(r.raw) != "{\"blocks\":[]}\n" {
		t.Fatalf("bỏ chặn xong: %s", r.raw)
	}
}

// Chat riêng che từ tục ở tin chủ gửi lẫn câu bot trả lời.
func TestEmulatorAgentDMFilter(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	r := e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "vl mệt quá"}, "")
	if r.status != 200 || r.body["text"] != "** mệt quá" {
		t.Fatalf("gửi tin: %d %s", r.status, r.raw)
	}
	e.llm.script = []*genai.GenerateContentResponse{llmText("Đéo sao, nghỉ đi")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1})
	msgs := messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, ""))
	if len(msgs) != 2 || msgs[0]["text"] != "*** sao, nghỉ đi" || msgs[1]["text"] != "** mệt quá" {
		t.Fatalf("chat riêng sau khi lọc: %v", msgs)
	}
}

// Xoá tài khoản gỡ báo cáo người đó gửi hay bị gửi, danh sách chặn của họ, và
// họ trong danh sách chặn của người khác. Chạy lại vẫn ra cùng kết quả.
func TestEmulatorAgentAccountDeleteReports(t *testing.T) {
	e := newAgentEnv(t)
	e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "tin của Bình"}, ""), 200, "")
	e.tick(time.Second)
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "tin của Cường"}, ""), 200, "")
	e.want(e.call("cuong", "POST", "/v1/agents/room/messages/1/report", map[string]any{"block": true}, ""), 200, "")
	e.want(e.call("binh", "POST", "/v1/agents/room/messages/2/report", map[string]any{"block": true}, ""), 200, "")
	e.want(e.call("an", "POST", "/v1/agents/room/messages/2/report", map[string]any{"block": true}, ""), 200, "")
	e.want(e.call("an", "POST", "/v1/agents/room/messages/1/report", map[string]any{"block": true}, ""), 200, "")

	accounts := &AccountService{db: e.store.db, auth: e.auth, oauth: &OAuthService{db: e.store.db}}
	for i := 0; i < 2; i++ {
		if err := accounts.Delete(context.Background(), "cuong"); err != nil {
			t.Fatal(err)
		}
	}
	reports, err := e.store.db.Collection("agentRooms/main/reports").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(reports) != 1 || reports[0].Ref.ID != "0000000001_an" {
		t.Fatalf("còn %d báo cáo, muốn chỉ báo cáo của An về Bình", len(reports))
	}
	if len(e.doc("agentBlocks/cuong")) != 0 {
		t.Fatal("xoá tài khoản mà còn danh sách chặn của Cường")
	}
	if got := anyList(e.doc("agentBlocks/binh")["uids"]); len(got) != 0 {
		t.Fatalf("Bình vẫn chặn %v", got)
	}
	if got := anyList(e.doc("agentBlocks/an")["uids"]); len(got) != 1 || got[0] != "binh" {
		t.Fatalf("An chặn %v, muốn chỉ còn Bình", got)
	}
}
