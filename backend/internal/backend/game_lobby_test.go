package backend

import (
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Bảng 1.2: 13 người có 3 sói và đủ 5 vai đặc biệt. Bật 2 vai mở rộng thì mỗi
// vai một lá thay chỗ Dân: 13 - 3 - 5 - 2 = 3 Dân.
func TestLobbyRolesFollowDeck(t *testing.T) {
	cfg := ww.Config{KmPerUnit: 2, Extended: []ww.Role{ww.Elder, ww.Idiot}}
	got, err := gameLobbyFor(cfg, 13)
	if err != nil {
		t.Fatal(err)
	}
	want := []GameLobbyRole{
		{Label: "Sói ×3"}, {Label: "Tiên tri"}, {Label: "Bảo vệ"}, {Label: "Phù thuỷ"}, {Label: "Thợ săn"}, {Label: "Cupid"},
		{Label: "Già làng · mới", Extended: true}, {Label: "Kẻ ngốc · mới", Extended: true}, {Label: "Dân"},
	}
	if !reflect.DeepEqual(got.Roles, want) {
		t.Fatalf("roles = %+v", got.Roles)
	}
	wantFacts := []GameLobbyFact{{Value: "2 km", Label: "mốc mỗi ngày"}, {Value: "+2", Label: "vai mở rộng"}}
	if !reflect.DeepEqual(got.Facts, wantFacts) {
		t.Fatalf("facts = %+v", got.Facts)
	}
}

// Sảnh chưa đủ người thì tính bộ bài theo số tối thiểu: 3 người đăng ký vẫn ra
// bộ của 10 người (2 sói, 2 vai đặc biệt) chứ không lỗi.
func TestLobbyBelowMinimumUsesSmallestDeck(t *testing.T) {
	got, err := gameLobbyFor(ww.Config{KmOff: true}, 3)
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Roles) != 4 || got.Roles[0].Label != "Sói ×2" {
		t.Fatalf("roles = %+v", got.Roles)
	}
	if len(got.Facts) != 0 {
		t.Fatalf("tắt km và không có vai mở rộng mà có facts: %+v", got.Facts)
	}
}

// Ván nhiều vòng báo số vòng mỗi ngày ngay ở sảnh; ván một vòng không thêm ô.
func TestLobbyShowsRoundsPerDay(t *testing.T) {
	two := ww.Config{KmPerUnit: 2, Schedule: &ww.Schedule{StartHour: 10, RoundHours: 12, Rounds: 2}}
	got, err := gameLobbyFor(two, 10)
	if err != nil {
		t.Fatal(err)
	}
	want := []GameLobbyFact{{Value: "2 vòng", Label: "mỗi ngày"}, {Value: "2 km", Label: "mốc mỗi ngày"}}
	if !reflect.DeepEqual(got.Facts, want) {
		t.Fatalf("facts = %+v", got.Facts)
	}
	one := ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 6, RoundHours: 24, Rounds: 1}}
	if got, err = gameLobbyFor(one, 10); err != nil || len(got.Facts) != 0 {
		t.Fatalf("một vòng: %+v, %v", got, err)
	}
}
