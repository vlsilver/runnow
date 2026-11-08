package backend

import (
	"fmt"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameLobby là phần tóm tắt luật ở sảnh đăng ký. Chữ do backend dựng; app cũ
// bỏ qua.
type GameLobby struct {
	Facts []GameLobbyFact `json:"facts"`
	Roles []GameLobbyRole `json:"roles"`
}

// GameLobbyFact là một ô số: Value to, Label nhỏ bên dưới.
type GameLobbyFact struct {
	Value string `json:"value"`
	Label string `json:"label"`
}

// GameLobbyRole là một vai trong bộ bài; Extended là vai mở rộng ván này bật.
type GameLobbyRole struct {
	Label    string `json:"label"`
	Extended bool   `json:"extended,omitempty"`
}

// gameLobbyFor tính bộ bài theo số người đang có. Sảnh chưa đủ người thì lấy
// bộ của số tối thiểu, nên số sói có thể đổi khi thêm người.
func gameLobbyFor(cfg werewolf.Config, players int) (*GameLobby, error) {
	deck, err := werewolf.Composition(min(max(players, werewolf.MinPlayers), werewolf.MaxPlayers), cfg)
	if err != nil {
		return nil, err
	}
	out := &GameLobby{Facts: []GameLobbyFact{}, Roles: []GameLobbyRole{}}
	if !cfg.KmOff {
		out.Facts = append(out.Facts, GameLobbyFact{Value: formatKm(kmPerUnit(cfg)) + " km", Label: "mốc mỗi ngày"})
	}
	if n := len(cfg.Extended); n > 0 {
		out.Facts = append(out.Facts, GameLobbyFact{Value: fmt.Sprintf("+%d", n), Label: "vai mở rộng"})
	}
	extended := map[werewolf.Role]bool{}
	for _, role := range werewolf.ExtendedRoles() {
		extended[role] = true
	}
	// Composition xếp cùng vai cạnh nhau: sói, vai đặc biệt, vai mở rộng, Dân.
	for i := 0; i < len(deck); {
		role, n := deck[i], 1
		for i+n < len(deck) && deck[i+n] == role {
			n++
		}
		i += n
		label := roleLabels[role]
		switch {
		case extended[role]:
			label += " · mới"
		case n > 1 && role != werewolf.Villager:
			label += fmt.Sprintf(" ×%d", n)
		}
		out.Roles = append(out.Roles, GameLobbyRole{Label: label, Extended: extended[role]})
	}
	return out, nil
}
