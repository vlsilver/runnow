package werewolf

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
)

// stream là chuỗi số tất định sinh từ hash(seed, phaseKey, purpose) (mục 3.3).
// Mỗi mục đích (chia vai, bốc thăm, Cupid ghép ngẫu nhiên…) có stream riêng, để
// thêm một lần rút ở chỗ này không làm đổi kết quả ở chỗ khác.
type stream struct {
	mac []byte // HMAC key = seed; label = phaseKey + purpose
	lbl []byte
	ctr uint64
}

func newStream(seed Seed, phaseKey, purpose string) *stream {
	// Ghi độ dài trước mỗi phần, để ("a", "bc") và ("ab", "c") ra hai stream khác nhau.
	lbl := make([]byte, 0, 16+len(phaseKey)+len(purpose))
	lbl = binary.BigEndian.AppendUint64(lbl, uint64(len(phaseKey)))
	lbl = append(lbl, phaseKey...)
	lbl = binary.BigEndian.AppendUint64(lbl, uint64(len(purpose)))
	lbl = append(lbl, purpose...)
	return &stream{mac: seed[:], lbl: lbl}
}

func (s *stream) uint64() uint64 {
	h := hmac.New(sha256.New, s.mac)
	h.Write(s.lbl)
	var ctr [8]byte
	binary.BigEndian.PutUint64(ctr[:], s.ctr)
	s.ctr++
	h.Write(ctr[:])
	return binary.BigEndian.Uint64(h.Sum(nil))
}

// intn trả số đều trong [0, n). Loại các giá trị rơi vào phần dư để không lệch
// về số nhỏ như phép % thường.
func (s *stream) intn(n int) int {
	if n <= 0 {
		panic("intn: n phải dương")
	}
	bound := uint64(n)
	limit := ^uint64(0) - (^uint64(0) % bound)
	for {
		if v := s.uint64(); v < limit {
			return int(v % bound)
		}
	}
}

// shuffle là Fisher–Yates trên n phần tử.
func (s *stream) shuffle(n int, swap func(i, j int)) {
	for i := n - 1; i > 0; i-- {
		swap(i, s.intn(i+1))
	}
}
