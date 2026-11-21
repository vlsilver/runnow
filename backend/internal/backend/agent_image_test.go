package backend

import "testing"

// Mốc theo yêu cầu: dưới 1 km không vẽ, từ 1 km 3 ảnh, từ 5 km 5 ảnh, từ 10 km
// 10 ảnh mỗi ngày.
func TestAgentImageLimit(t *testing.T) {
	for _, c := range []struct {
		km   float64
		want int64
	}{{0, 0}, {0.99, 0}, {1, 3}, {4.99, 3}, {5, 5}, {9.99, 5}, {10, 10}, {42.2, 10}} {
		if got := agentImageLimit(c.km); got != c.want {
			t.Errorf("agentImageLimit(%v) = %d, muốn %d", c.km, got, c.want)
		}
	}
	for _, c := range []struct {
		km         float64
		nextKm     float64
		nextImages int64
		hasNext    bool
	}{{0, 1, 3, true}, {1, 5, 5, true}, {7, 10, 10, true}, {10, 0, 0, false}} {
		km, images, ok := agentImageNextTier(c.km)
		if km != c.nextKm || images != c.nextImages || ok != c.hasNext {
			t.Errorf("agentImageNextTier(%v) = %v %d %v", c.km, km, images, ok)
		}
	}
}
