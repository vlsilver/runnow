package backend

import (
	"regexp"
	"strings"
	"testing"
)

// Username gợi ý phải qua được luật của Telegram (5–32 ký tự [a-z0-9_], bắt
// đầu bằng chữ, kết thúc bằng "bot"), không thì link tạo bot mở ra đã báo lỗi.
// Đuôi 4a49 là 4 ký tự đầu sha256("uid-1"), tính bằng shasum.
func TestSuggestBotUsername(t *testing.T) {
	valid := regexp.MustCompile(`^[a-z][a-z0-9_]{4,31}$`)
	for _, c := range []struct{ name, want string }{
		{"Cú Mèo", "cu_meo_4a49_bot"},
		{"Đức Anh", "duc_anh_4a49_bot"},
		{"Ngô Văn Ất", "ngo_van_at_4a49_bot"},
		{"Nguyễn Thị Hương Giang Siêu Tốc", "nguyen_thi_huong_giang_4a49_bot"},
		{"A", "a_4a49_bot"},
		{"", "mybot_4a49_bot"},
		{"🏃‍♂️", "mybot_4a49_bot"},
		{"123 Chạy", "chay_4a49_bot"},
		{"Cú Bot", "cu_4a49_bot"},
		{"Bot", "mybot_4a49_bot"},
		{"  __Ổi--Xanh__  ", "oi_xanh_4a49_bot"},
	} {
		got := suggestBotUsername(c.name, "uid-1")
		if got != c.want {
			t.Errorf("suggestBotUsername(%q) = %q, mong đợi %q", c.name, got, c.want)
		}
		if !valid.MatchString(got) || !strings.HasSuffix(got, "bot") {
			t.Errorf("suggestBotUsername(%q) = %q sai luật Telegram", c.name, got)
		}
	}
	if a, b := suggestBotUsername("Cú", "uid-1"), suggestBotUsername("Cú", "uid-2"); a == b {
		t.Fatalf("hai uid cùng tên ra cùng username %q", a)
	}
}

func TestManagedCreateURL(t *testing.T) {
	got := managedCreateURL("threei_mybot", "cu_meo_4a49_bot", "Cú Mèo & bạn")
	want := "https://t.me/newbot/threei_mybot/cu_meo_4a49_bot?name=C%C3%BA%20M%C3%A8o%20%26%20b%E1%BA%A1n"
	if got != want {
		t.Fatalf("createUrl = %s\nmong đợi    %s", got, want)
	}
}

// Secret webhook bot con là HMAC-SHA256(TELEGRAM_WEBHOOK_SECRET, "managed:"+botId).
// Giá trị mong đợi tính bằng openssl dgst -hmac.
func TestManagedWebhookSecrets(t *testing.T) {
	m := &ManagedBotService{rootSecret: "root-secret"}
	if got := m.childSecret("8001"); got != "8c49238a72580152488545e18236c50b48a5d0a8a55fcb9ecaca109c416692ce" {
		t.Fatalf("childSecret = %s", got)
	}
	if secretMatches("", "") || secretMatches("x", m.childSecret("8001")) || !secretMatches(m.childSecret("8001"), m.childSecret("8001")) {
		t.Fatal("secretMatches sai")
	}
}
