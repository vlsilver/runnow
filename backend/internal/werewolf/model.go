// Package werewolf là luật Ma Sói (features/ma_soi_plan.md, mục 1). Mọi hàm ở
// đây là hàm thuần: không đọc Firestore, không gọi đồng hồ, ngẫu nhiên lấy từ
// seed của ván. Nhờ vậy cùng đầu vào luôn ra cùng kết quả, và replay được ván.
package werewolf

import (
	"crypto/rand"
	"fmt"
)

// Role là vai của một người chơi. Giá trị chuỗi được lưu vào Firestore, đừng đổi.
type Role string

const (
	Wolf     Role = "wolf"
	Seer     Role = "seer"
	Guard    Role = "guard"
	Witch    Role = "witch"
	Hunter   Role = "hunter"
	Cupid    Role = "cupid"
	Villager Role = "villager"
)

// specialRoles theo thứ tự thêm vào khi số người tăng (bảng 1.2).
var specialRoles = []Role{Seer, Guard, Witch, Hunter, Cupid}

func isSpecial(r Role) bool {
	for _, s := range specialRoles {
		if s == r {
			return true
		}
	}
	return false
}

// Config là cấu hình của một ván, chụp vào ván lúc Start và không đổi nữa (R10).
type Config struct {
	// KmPerUnit là X: km cần cho một lượt kỹ năng hoặc một phiếu. 0 nghĩa là
	// dùng mặc định 1 km.
	KmPerUnit float64 `json:"kmPerUnit"`
	// Disabled là các vai đặc biệt admin tắt. Vai bị tắt thành Dân (R8).
	Disabled []Role `json:"disabled,omitempty"`
	TestMode bool   `json:"testMode,omitempty"`
}

// Validate từ chối cấu hình mà luật không cho: chỉ tắt được vai đặc biệt (R8).
func (c Config) Validate() error {
	if c.KmPerUnit < 0 {
		return fmt.Errorf("kmPerUnit âm: %v", c.KmPerUnit)
	}
	for _, r := range c.Disabled {
		if !isSpecial(r) {
			return fmt.Errorf("không tắt được vai %q, chỉ tắt được vai đặc biệt", r)
		}
	}
	return nil
}

func (c Config) disabled(r Role) bool {
	for _, d := range c.Disabled {
		if d == r {
			return true
		}
	}
	return false
}

// Seed là nguồn ngẫu nhiên duy nhất của một ván, sinh lúc Start, nằm trong
// secret/state. Ai có seed là đoán được vai, nên không bao giờ trả ra ngoài.
type Seed [32]byte

func NewSeed() (Seed, error) {
	var s Seed
	_, err := rand.Read(s[:])
	return s, err
}
