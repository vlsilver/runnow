//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"
)

// userText là chữ của mọi lượt user trong request thứ i gửi model, mỗi part
// một dòng.
func (f *fake3i) userText(i int) string {
	f.t.Helper()
	var b strings.Builder
	for _, c := range anyList(f.reqs[i]["contents"]) {
		content := c.(map[string]any)
		if stringValue(content["role"]) != "user" {
			continue
		}
		for _, p := range anyList(content["parts"]) {
			b.WriteString(stringValue(p.(map[string]any)["text"]))
			b.WriteString("\n")
		}
	}
	return b.String()
}

// An (tg 111) đã liên kết app và để hồ sơ công khai, tên Telegram là "Ann".
// Kín (tg 333) đã liên kết nhưng để hồ sơ riêng tư. Bình (tg 222) chỉ có trên
// Telegram.
func (f *fake3i) seedSpeakers() {
	seed(f.t, f.db, "tgLinks/111", map[string]any{"uid": "an"})
	seed(f.t, f.db, "stepLeaderboardEntries/an", map[string]any{"profileVisibility": "public", "nickname": "An Nguyễn", "displayName": "an.nguyen"})
	seed(f.t, f.db, "tgLinks/333", map[string]any{"uid": "kin"})
	seed(f.t, f.db, "stepLeaderboardEntries/kin", map[string]any{"profileVisibility": "private", "displayName": "Kín Đáo"})
	at := time.Now().Add(-time.Minute)
	seed(f.t, f.db, "botConversations/"+fake3iGroup+"/botMessages/m1", map[string]any{"role": "user", "name": "Bình", "tgUserId": "222", "text": "mai ai chạy", "createdAt": at})
	seed(f.t, f.db, "botConversations/"+fake3iGroup+"/botMessages/m2", map[string]any{"role": "user", "name": "Kin", "tgUserId": "333", "text": "mình nghỉ", "createdAt": at.Add(time.Second)})
	seed(f.t, f.db, "botConversations/"+fake3iGroup+"/botMessages/m3", map[string]any{"role": "user", "name": "Ann", "tgUserId": "111", "text": "mai mình chạy", "createdAt": at.Add(2 * time.Second)})
}

func TestEmulatorBotKnowsLinkedSpeakerAppName(t *testing.T) {
	f := newFake3i(t, false)
	f.seedSpeakers()
	f.script = []map[string]any{say("Để xem nào")}
	if err := f.bot.HandleMessage(context.Background(), fake3iGroup, 0, "111", "Ann", "@3i tuần này tôi chạy bao nhiêu", ""); err != nil {
		t.Fatal(err)
	}
	got := f.userText(0)
	// Người đã liên kết, hồ sơ công khai: model thấy tên app, đúng tên tool
	// get_member_* tìm theo, ở cả câu đang hỏi lẫn tin cũ trong lịch sử.
	for _, want := range []string{
		"Ann (tên trên app: An Nguyễn): @3i tuần này tôi chạy bao nhiêu\n",
		"Ann (tên trên app: An Nguyễn): mai mình chạy\n",
		"Bình: mai ai chạy\n",
		"Kin: mình nghỉ\n",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("thiếu %q trong:\n%s", want, got)
		}
	}
	// Hồ sơ riêng tư thì bot không được biết họ là ai trên app.
	if strings.Contains(got, "Kín Đáo") {
		t.Errorf("lộ tên app của người để hồ sơ riêng tư:\n%s", got)
	}
	if sys := f.system(0); !strings.Contains(sys, "(tên trên app: X)") {
		t.Errorf("system prompt chưa dặn cách dùng tên trên app:\n%s", sys)
	}
}
