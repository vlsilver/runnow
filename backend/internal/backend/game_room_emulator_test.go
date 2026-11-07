//go:build emulator

package backend

import (
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Phòng chung có từ lúc mở đăng ký: người đã đăng ký và admin nói chuyện được
// trước khi chia bài, người chưa đăng ký thì không vào được.
func TestEmulatorGameRoomBeforeStart(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 2)
	path := "/v1/games/" + id + "/chats/room"

	e.want(e.call(userOf(1), "POST", path, map[string]any{"text": "chờ đủ người nhé"}, ""), 200, "")
	e.want(e.call("boss", "POST", path, map[string]any{"text": "tối nay mở"}, ""), 200, "")
	r := e.call(userOf(2), "GET", path, nil, "")
	e.want(r, 200, "")
	msgs := chatMessages(t, r)
	if len(msgs) != 2 || msgs[0]["text"] != "tối nay mở" || msgs[1]["uid"] != userOf(1) || r.body["label"] != "Phòng chung" || r.body["canSend"] != true {
		t.Fatalf("phòng chung = %s", r.raw)
	}
	e.want(e.call(userOf(3), "GET", path, nil, ""), 404, "not_player")
	e.want(e.call(userOf(3), "POST", path, map[string]any{"text": "cho vào"}, ""), 404, "not_player")
	// Phòng chung không nhắn riêng báo tin mới.
	if n := len(e.tasksTo("/tasks/game-flush")); n != 0 {
		t.Fatalf("phòng chung bắn %d task gửi tin", n)
	}

	d := e.call(userOf(1), "GET", "/v1/games/"+id, nil, "")
	e.want(d, 200, "")
	if room, _ := d.body["room"].(map[string]any); room["key"] != "room" || room["canSend"] != true {
		t.Fatalf("detail.room = %v", d.body["room"])
	}
	if d := e.call(userOf(3), "GET", "/v1/games/"+id, nil, ""); d.body["room"] != nil {
		t.Fatalf("người chưa đăng ký vẫn thấy phòng: %v", d.body["room"])
	}
	// Rút đăng ký thì thôi gửi.
	e.want(e.call(userOf(2), "DELETE", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	e.want(e.call(userOf(2), "POST", path, map[string]any{"text": "còn đây"}, ""), 404, "not_player")
}

// Đang chơi: người còn sống gửi được, người đã chết chỉ đọc, hết ván thì ai
// cũng chỉ đọc.
func TestEmulatorGameRoomWhilePlaying(t *testing.T) {
	g, h := runningAPIGame(t)
	path := "/v1/games/" + g.id + "/chats/room"
	h.want(h.call("v1", "POST", path, map[string]any{"text": "ai là sói"}, ""), 200, "")
	h.want(h.call("w1", "POST", path, map[string]any{"text": "không phải mình"}, ""), 200, "")

	editState(t, g, func(st *ww.State) { st.Players["v1"].Alive = false })
	h.want(h.call("v1", "POST", path, map[string]any{"text": "mình bị cắn"}, ""), 403, "chat_read_only")
	if r := h.call("v1", "GET", path, nil, ""); r.status != 200 || r.body["canSend"] != false || len(chatMessages(t, r)) != 2 {
		t.Fatalf("người chết đọc phòng = %d %s", r.status, r.raw)
	}

	editState(t, g, func(st *ww.State) { st.Phase = ww.PhaseEnded })
	h.want(h.call("w1", "POST", path, map[string]any{"text": "hết ván"}, ""), 403, "chat_read_only")
}
