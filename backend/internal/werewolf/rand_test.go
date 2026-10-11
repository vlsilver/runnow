package werewolf

import "testing"

func TestStreamLabelsDoNotCollide(t *testing.T) {
	a := newStream(Seed{1}, "a", "bc").uint64()
	b := newStream(Seed{1}, "ab", "c").uint64()
	if a == b {
		t.Fatal(`("a","bc") và ("ab","c") phải là hai stream khác nhau`)
	}
	if newStream(Seed{1}, "n1", "deal").uint64() == newStream(Seed{1}, "n1", "vote-cut").uint64() {
		t.Fatal("mục đích khác nhau phải ra stream khác nhau")
	}
}

func TestIntnStaysInRange(t *testing.T) {
	s := newStream(Seed{3}, "", "x")
	seen := map[int]bool{}
	for i := 0; i < 1000; i++ {
		v := s.intn(5)
		if v < 0 || v >= 5 {
			t.Fatalf("intn(5) = %d", v)
		}
		seen[v] = true
	}
	if len(seen) != 5 {
		t.Fatalf("1000 lần rút mà chỉ thấy %v", seen)
	}
}
