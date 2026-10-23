package backend

import (
	"context"
	"testing"
	"time"
)

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

func TestNextKmFrameEnd(t *testing.T) {
	cases := map[time.Time]time.Time{
		time.Date(2026, 10, 23, 21, 59, 59, 0, vietnam): time.Date(2026, 10, 23, 22, 0, 0, 0, vietnam),
		time.Date(2026, 10, 23, 22, 0, 0, 0, vietnam):   time.Date(2026, 10, 24, 22, 0, 0, 0, vietnam),
		time.Date(2026, 10, 23, 15, 30, 0, 0, time.UTC): time.Date(2026, 10, 24, 22, 0, 0, 0, vietnam), // 22:30 VN
		time.Date(2026, 10, 23, 2, 0, 0, 0, vietnam):    time.Date(2026, 10, 23, 22, 0, 0, 0, vietnam),
	}
	for wall, want := range cases {
		if got := nextKmFrameEnd(wall); !got.Equal(want) {
			t.Errorf("nextKmFrameEnd(%s) = %s, muốn %s", wall, got, want)
		}
	}
}
