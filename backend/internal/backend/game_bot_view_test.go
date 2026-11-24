package backend

import (
	"context"
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// 3i phải biết bộ vai của ván (bảng 1.2) thay vì đoán: 13 người là 3 sói, đủ
// 5 vai đặc biệt; vai bị tắt thành Dân, số sói giữ nguyên.
func TestBotDeck(t *testing.T) {
	want := map[string]int{"Sói": 3, "Tiên tri": 1, "Bảo vệ": 1, "Phù thuỷ": 1, "Thợ săn": 1, "Cupid": 1, "Dân": 5}
	if got := botDeck(13, ww.Config{}); !reflect.DeepEqual(got, want) {
		t.Fatalf("13 người = %v", got)
	}
	want = map[string]int{"Sói": 3, "Tiên tri": 1, "Bảo vệ": 1, "Phù thuỷ": 1, "Thợ săn": 1, "Dân": 6}
	if got := botDeck(13, ww.Config{Disabled: []ww.Role{ww.Cupid}}); !reflect.DeepEqual(got, want) {
		t.Fatalf("13 người tắt Cupid = %v", got)
	}
	if got := botDeck(9, ww.Config{}); got != nil {
		t.Fatalf("9 người chưa chia được bài mà có bộ vai %v", got)
	}
}

// Phần riêng của người chơi chỉ có trong chat riêng: group không thấy tool, và
// gọi thẳng tên tool từ group cũng không chạy.
func TestMyWerewolfOnlyInPrivateChat(t *testing.T) {
	s := &BotService{games: &GameStore{}}
	has := func(private bool) bool {
		for _, d := range s.toolDeclarations(private)[0].FunctionDeclarations {
			if d.Name == botMyWerewolfDecl.Name {
				return true
			}
		}
		return false
	}
	if has(false) || !has(true) {
		t.Fatalf("group có tool = %v, DM có tool = %v", has(false), has(true))
	}
	if _, err := s.dispatch(context.Background(), botMyWerewolfDecl.Name, nil, false); err == nil {
		t.Fatal("gọi get_my_werewolf từ group phải lỗi")
	}
}
