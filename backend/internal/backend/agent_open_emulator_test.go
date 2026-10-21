//go:build emulator

package backend

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

func (e *agentEnv) setOpen(open bool) {
	e.t.Helper()
	if _, err := e.store.db.Doc("agentState/config").Set(context.Background(), map[string]any{"open": open}, firestore.MergeAll); err != nil {
		e.t.Fatal(err)
	}
}

// Cờ open bật thì người ngoài allowlist dùng được bot; tắt thì quay về
// allowlist, kể cả bot người đó đã tạo và đã ở phòng.
func TestEmulatorAgentOpenFlag(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")

	e.setOpen(true)
	r := e.call("dung", "GET", "/v1/agents/me", nil, "")
	agent, _ := r.body["agent"].(map[string]any)
	if r.status != 200 || r.body["enabled"] != true || agent["name"] != "Bot của Dũng" || agent["created"] != false {
		t.Fatalf("cờ bật, người ngoài allowlist: %d %s", r.status, r.raw)
	}
	e.createBot("dung", "Dế", "")
	if e.doc("agents/dung")["inRoom"] != true {
		t.Fatalf("bot mới tạo phải vào phòng: %v", e.doc("agents/dung"))
	}
	e.want(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
	e.want(e.call("dung", "GET", "/v1/agents/room", nil, ""), 200, "")
	e.want(e.call("dung", "POST", "/v1/agents/room", map[string]any{"text": "Dế ơi chạy không"}, ""), 200, "")
	// Bot được gọi tên thì nói trước: Dế nói dù uid đứng sau An.
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chạy!")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	if msgs := messages(t, e.call("dung", "GET", "/v1/agents/room?after=1", nil, "")); len(msgs) != 1 || msgs[0]["name"] != "Dế" {
		t.Fatalf("cờ bật, bot của Dũng phải nói được: %v", msgs)
	}

	e.setOpen(false)
	if r := e.call("dung", "GET", "/v1/agents/me", nil, ""); r.status != 200 || r.body["enabled"] != false || r.body["agent"] != nil {
		t.Fatalf("cờ tắt, người ngoài allowlist: %d %s", r.status, r.raw)
	}
	e.want(e.call("dung", "POST", "/v1/agents/me", map[string]any{"name": "Dế"}, ""), 403, "agent_disabled")
	e.want(e.call("dung", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 403, "agent_disabled")
	e.want(e.call("dung", "GET", "/v1/agents/room", nil, ""), 403, "agent_disabled")
	e.want(e.call("dung", "POST", "/v1/agents/room", map[string]any{"text": "a"}, ""), 403, "agent_disabled")

	// Bot của Dũng vẫn inRoom nhưng chủ hết quyền: gọi tên cũng không nói,
	// không có trong danh sách phòng.
	e.tick(time.Second)
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Dế đâu rồi"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Dế nghỉ rồi")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 3})
	msgs := messages(t, e.call("cuong", "GET", "/v1/agents/room?after=3", nil, ""))
	if len(msgs) != 1 || msgs[0]["name"] != "Sóc" {
		t.Fatalf("cờ tắt, chỉ bot trong allowlist được nói: %v", msgs)
	}
	if sys := e.llm.calls[len(e.llm.calls)-1].system; strings.Contains(sys, "Dế (bot") {
		t.Fatalf("cờ tắt mà bot của Dũng vẫn trong danh sách phòng:\n%s", sys)
	}
	for _, m := range anyList(e.call("cuong", "GET", "/v1/agents/room", nil, "").body["members"]) {
		if m.(map[string]any)["uid"] == "dung" {
			t.Fatalf("cờ tắt mà Dũng vẫn trong danh sách thành viên phòng")
		}
	}

	// Lưu lại hồ sơ không kéo bot đã ra khỏi phòng vào lại.
	if _, err := e.store.db.Doc("agents/an").Update(context.Background(), []firestore.Update{{Path: "inRoom", Value: false}}); err != nil {
		t.Fatal(err)
	}
	e.createBot("an", "Sóc", "Lắm mồm")
	if e.doc("agents/an")["inRoom"] != false {
		t.Fatalf("lưu hồ sơ đã ghi đè inRoom: %v", e.doc("agents/an"))
	}
	// Bot ra khỏi phòng thì không nói nữa, dù chủ vẫn trong allowlist: phòng
	// không còn bot nào nói được, nên không gọi model.
	e.tick(time.Second)
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Sóc ơi"}, ""), 200, "")
	calls := len(e.llm.calls)
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 5})
	if len(e.llm.calls) != calls {
		t.Fatal("bot đã ra khỏi phòng mà vẫn được gọi nói")
	}
}

// Cờ bật: mỗi lượt chỉ đọc tối đa agentRoomMax bot đang ở phòng, dù có bao
// nhiêu người tạo bot; bot của người vừa nhắn luôn có mặt.
func TestEmulatorAgentRoomBounded(t *testing.T) {
	e := newAgentEnv(t)
	e.setOpen(true)
	// 30 người đã tạo bot, 5 người đầu cho bot ra khỏi phòng.
	for i := 0; i < 30; i++ {
		seed(t, e.store.db, fmt.Sprintf("agents/u%02d", i), map[string]any{"name": fmt.Sprintf("Bot%02d", i), "inRoom": i >= 5})
	}
	// Người nhắn có uid đứng sau cả 30 bot kia.
	e.createBot("zz", "Ngựa Vằn", "")

	agents, err := e.deps.Agents.roomAgents(context.Background(), agentAccess{open: true}, "zz")
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, a := range agents {
		got = append(got, a.uid)
	}
	want := []string{"u05", "u06", "u07", "u08", "u09", "u10", "u11", "u12", "u13", "u14", "u15", "u16", "u17", "u18", "u19", "u20", "u21", "u22", "u23", "zz"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("bot trong phòng:\n got %v\nwant %v", got, want)
	}

	e.want(e.call("zz", "POST", "/v1/agents/room", map[string]any{"text": "Ngựa Vằn ơi"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Có mình")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	sys := e.llm.calls[0].system
	if n := strings.Count(sys, "(bot của"); n != agentRoomMax {
		t.Fatalf("danh sách phòng có %d bot, muốn %d:\n%s", n, agentRoomMax, sys)
	}
	for _, off := range []string{"Bot00", "Bot04", "Bot24", "Bot29"} {
		if strings.Contains(sys, off) {
			t.Fatalf("danh sách phòng có %s:\n%s", off, sys)
		}
	}
	if msgs := messages(t, e.call("zz", "GET", "/v1/agents/room?after=1", nil, "")); len(msgs) != 1 || msgs[0]["name"] != "Ngựa Vằn" {
		t.Fatalf("bot của người vừa nhắn phải nói được: %v", msgs)
	}
	members := anyList(e.call("zz", "GET", "/v1/agents/room", nil, "").body["members"])
	if len(members) != agentRoomMax || members[agentRoomMax-1].(map[string]any)["botName"] != "Ngựa Vằn" {
		t.Fatalf("thành viên phòng: %v", members)
	}
}

// Backfill cho bot đã tạo của allowlist vào phòng, chạy lại không đổi gì.
func TestEmulatorAgentBackfillInRoom(t *testing.T) {
	e := newAgentEnv(t)
	// Allowlist là an, binh (admin) và cuong. Bot tạo bằng bản cũ chưa có inRoom.
	seed(t, e.store.db, "agents/an", map[string]any{"name": "Sóc"})
	seed(t, e.store.db, "agents/binh", map[string]any{"name": "Mèo", "inRoom": false})
	seed(t, e.store.db, "agents/dung", map[string]any{"name": "Dế"})

	for run, want := range []string{"an", ""} {
		set, err := e.deps.Agents.BackfillInRoom(context.Background())
		if err != nil || strings.Join(set, ",") != want {
			t.Fatalf("lần %d: ghi %v %v, muốn %q", run+1, set, err, want)
		}
		if e.doc("agents/an")["inRoom"] != true {
			t.Fatalf("lần %d: bot của An chưa vào phòng", run+1)
		}
		if e.doc("agents/binh")["inRoom"] != false {
			t.Fatalf("lần %d: ghi đè inRoom chủ đã tắt", run+1)
		}
		if _, ok := e.doc("agents/dung")["inRoom"]; ok {
			t.Fatalf("lần %d: bot ngoài allowlist bị cho vào phòng", run+1)
		}
		if len(e.doc("agents/cuong")) != 0 {
			t.Fatalf("lần %d: tạo bot cho người chưa tạo", run+1)
		}
	}
}
