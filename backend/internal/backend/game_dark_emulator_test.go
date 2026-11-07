//go:build emulator

package backend

import (
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Tiên tri soi trong đêm: kết quả theo đặc quyền phe Sói đang chờ lúc soi.
// w1 chọn Tàng Hình lên w2 thì soi w2 ra Dân; w2 đổi sang Vu Khống v1 thì soi
// v1 ra Sói. Lượt soi trả kết quả ngay và lưu lại kết quả đó.
func TestEmulatorPeekFollowsPendingDark(t *testing.T) {
	g := newStoreGameWith(t, ww.Config{KmOff: true, Dark: ww.DarkPowers()})
	g.advance(g.start.NightAt.Add(time.Minute))
	at := func(d time.Duration) time.Time { return g.start.NightAt.Add(d) }

	if r := g.submit(ActionRequest{UID: "w1", Kind: ww.KindWolfDark, Choice: string(ww.DarkCloak), Targets: []string{"w2"}, ReceivedAt: at(2 * time.Minute)}); !r.Applied {
		t.Fatalf("w1 Tàng Hình: %+v", r)
	}
	if r := g.submit(ActionRequest{UID: "seer", Kind: ww.KindSeerPeek, Targets: []string{"w2"}, ReceivedAt: at(3 * time.Minute)}); r.Peek != ww.TeamVillage {
		t.Fatalf("soi w2 đang Tàng Hình: %+v", r)
	}

	g2 := newStoreGameWith(t, ww.Config{KmOff: true, Dark: ww.DarkPowers()})
	g2.advance(g2.start.NightAt.Add(time.Minute))
	at2 := func(d time.Duration) time.Time { return g2.start.NightAt.Add(d) }
	g2.submit(ActionRequest{UID: "w1", Kind: ww.KindWolfDark, Choice: string(ww.DarkCloak), Targets: []string{"w2"}, ReceivedAt: at2(2 * time.Minute)})
	g2.submit(ActionRequest{UID: "w2", Kind: ww.KindWolfDark, Choice: string(ww.DarkFrame), Targets: []string{"v1"}, ReceivedAt: at2(3 * time.Minute)})
	if r := g2.submit(ActionRequest{UID: "seer", Kind: ww.KindSeerPeek, Targets: []string{"v1"}, ReceivedAt: at2(4 * time.Minute)}); r.Peek != ww.TeamWolves {
		t.Fatalf("soi v1 đang bị Vu Khống: %+v", r)
	}
}
