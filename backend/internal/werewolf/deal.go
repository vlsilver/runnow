package werewolf

import (
	"errors"
	"fmt"
	"sort"
)

const (
	MinPlayers = 10
	MaxPlayers = 16
)

// ErrPlayerCount: dưới 10 hoặc trên 16 người thì không Start được (R9).
var ErrPlayerCount = errors.New("số người chơi phải từ 10 tới 16")

// composition trả bộ vai cho n người theo bảng 1.2, rồi áp công tắc (R8): vai
// bị tắt thành Dân, số sói giữ nguyên.
func composition(n int, cfg Config) ([]Role, error) {
	if n < MinPlayers || n > MaxPlayers {
		return nil, fmt.Errorf("%w (đang có %d)", ErrPlayerCount, n)
	}
	wolves, specials := 3, len(specialRoles)
	switch {
	case n == 10:
		wolves, specials = 2, 2
	case n == 11:
		specials = 3
	case n == 12:
		specials = 4
	}
	roles := make([]Role, 0, n)
	for i := 0; i < wolves; i++ {
		roles = append(roles, Wolf)
	}
	for _, r := range specialRoles[:specials] {
		if !cfg.disabled(r) {
			roles = append(roles, r)
		}
	}
	for len(roles) < n {
		roles = append(roles, Villager)
	}
	return roles, nil
}

// Deal chia vai (R8–R11). Danh sách người chơi được sort theo uid trước, nên
// thứ tự đăng ký không ảnh hưởng kết quả; ngẫu nhiên lấy từ hash(seed, "deal").
func Deal(seed Seed, players []string, cfg Config) (map[string]Role, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	sorted := append([]string(nil), players...)
	sort.Strings(sorted)
	for i := 1; i < len(sorted); i++ {
		if sorted[i] == sorted[i-1] {
			return nil, fmt.Errorf("người chơi %q bị trùng", sorted[i])
		}
	}
	roles, err := composition(len(sorted), cfg)
	if err != nil {
		return nil, err
	}
	newStream(seed, "", "deal").shuffle(len(roles), func(i, j int) { roles[i], roles[j] = roles[j], roles[i] })
	out := make(map[string]Role, len(sorted))
	for i, uid := range sorted {
		out[uid] = roles[i]
	}
	return out, nil
}
