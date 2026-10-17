package backend

import "testing"

func TestMaskProfanity(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"cắn seer nhé", "cắn seer nhé"},
		{"ĐM thằng này", "** thằng này"},
		{"vãi cả lồn!", "vãi cả ***!"},
		{"đéo tin, fuck", "*** tin, ****"},
		// Chỉ che nguyên từ: "lon" (lon bia) và "dmc" không phải từ tục.
		{"mua lon bia ở dmc", "mua lon bia ở dmc"},
		{"vcl.vcl", "***.***"},
		// Dấu tách rời (NFD) vẫn bị che.
		{"lồn", "***"},
	} {
		if got := maskProfanity(c.in); got != c.want {
			t.Errorf("maskProfanity(%q) = %q, mong đợi %q", c.in, got, c.want)
		}
	}
}
