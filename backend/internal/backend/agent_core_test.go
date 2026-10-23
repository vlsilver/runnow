package backend

import "testing"

func TestCleanRoomReply(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"Sóc (bot của An): Chào cả nhà", "Chào cả nhà"},
		{"Sóc: Chào cả nhà", "Chào cả nhà"},
		{"Sóc : Chào", "Chào"},
		{"[Sóc] Chào", "Chào"},
		{`"Chào cả nhà"`, "Chào cả nhà"},
		// Tên ở đầu câu mà không phải dòng chat thì giữ.
		{"Sóc mình hôm nay chạy 10 km", "Sóc mình hôm nay chạy 10 km"},
		{"Sóc (đùa thôi) chạy chậm", "Sóc (đùa thôi) chạy chậm"},
		{"Chào Sóc: hôm nay sao", "Chào Sóc: hôm nay sao"},
		{"[PASS]", ""},
		{"Thôi mình [PASS] nhé", ""},
		{"Sóc:   ", ""},
	} {
		if got := cleanRoomReply(c.in, "Sóc"); got != c.want {
			t.Errorf("cleanRoomReply(%q) = %q, mong đợi %q", c.in, got, c.want)
		}
	}
}

// Ở Phòng bot, người reply tin của một bot hay @username của nó thì bot đó
// nói, không theo lượt. Room dưới đây theo lượt thì tới Sóc (chưa nói lần nào).
func TestPickSpeakerAddressedBot(t *testing.T) {
	agents := []roomAgent{
		{uid: "cuong", name: "Cú Mèo", botID: "8001", username: "cu_meo_bot"},
		{uid: "an", name: "Sóc", botID: "8002", username: "soc_bot"},
	}
	room := map[string]any{"lastSpoke": map[string]any{"cuong": int64(1)}}
	human := func(text, replyTo string) map[string]any {
		m := map[string]any{"kind": agentKindHuman, "uid": "binh", "text": text}
		if replyTo != "" {
			m["replyToBot"] = replyTo
		}
		return m
	}
	for _, c := range []struct {
		name string
		last map[string]any
		want string
	}{
		{"theo lượt", human("ai chạy không", ""), "an"},
		{"reply tin của bot", human("ok luôn", "8001"), "cuong"},
		{"reply bot không còn trong phòng", human("ok luôn", "9999"), "an"},
		{"@username", human("@cu_meo_bot mai chạy không", ""), "cuong"},
		{"@username viết hoa", human("hỏi @CU_MEO_BOT nè", ""), "cuong"},
		{"@username cuối câu có dấu", human("hỏi @cu_meo_bot.", ""), "cuong"},
		{"@username dài hơn không khớp", human("@cu_meo_bot2 mai chạy không", ""), "an"},
		{"lần nhắc sau mới đúng", human("@cu_meo_bot2 với @cu_meo_bot", ""), "cuong"},
		{"tin của bot nhắc chính nó thì không tính", map[string]any{"kind": agentKindAgent, "uid": "cuong", "text": "@cu_meo_bot đây"}, "an"},
	} {
		got, ok := pickSpeaker(agents, room, c.last)
		if !ok || got.uid != c.want {
			t.Errorf("%s: chọn %q (ok=%v), muốn %q", c.name, got.uid, ok, c.want)
		}
	}
}
