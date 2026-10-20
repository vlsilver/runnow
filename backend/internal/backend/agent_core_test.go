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
