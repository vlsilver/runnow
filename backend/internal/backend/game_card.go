package backend

import (
	"crypto/sha256"
	"encoding/binary"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Thẻ Ma Sói: mỗi người bốc một bậc thẻ lúc phát vai; ván kết thúc thì người
// phe thắng (kể cả đã chết) giữ thẻ ở users/{uid}/gameCards/{gameId}, phe thua
// thì không. Chỉ backend ghi.

// gameCardOdds là phần triệu của từng bậc, theo thứ tự runCardTiers: 45/30/16/
// 7/2 %, như thẻ buổi chạy 5 km. Mọi vai chung một bảng, để bậc thẻ không gợi
// ý vai lúc ván còn chạy.
var gameCardOdds = [5]int64{450000, 300000, 160000, 70000, 20000}

// gameCardTier bốc bậc từ seed của ván (bí mật, sinh lúc Start) và uid: không
// phải lưu gì lúc phát vai, transaction chạy lại vẫn ra cùng bậc. Đổi
// gameCardOdds thì bậc của các ván đang chạy cũng đổi theo; thẻ đã ghi lúc kết
// thúc thì giữ nguyên.
func gameCardTier(seed werewolf.Seed, uid string) runCardTier {
	h := sha256.New()
	h.Write(seed[:])
	h.Write([]byte("card:" + uid))
	r := binary.BigEndian.Uint64(h.Sum(nil)[:8]) % runCardPpm
	return runCardPick(gameCardOdds, int64(r))
}

// gameCardVariant bốc bản Ẩn như gameCardTier, với tiền tố riêng để trúng Ẩn
// không dính tới bậc.
func gameCardVariant(seed werewolf.Seed, uid string) string {
	h := sha256.New()
	h.Write(seed[:])
	h.Write([]byte("secret:" + uid))
	r := binary.BigEndian.Uint64(h.Sum(nil)[:8]) % runCardPpm
	return runCardVariant(int64(r))
}

// gameCardDoc chép đủ những gì in trên thẻ, nên xoá ván thì thẻ vẫn còn.
func gameCardDoc(gameID, uid string, st *werewolf.State, endedAt time.Time) map[string]any {
	p := st.Players[uid]
	doc := map[string]any{
		"gameId":      gameID,
		"tier":        string(gameCardTier(st.Seed, uid)),
		"role":        string(p.Role),
		"team":        string(st.TeamOf(uid)),
		"winner":      string(st.Winner),
		"alive":       p.Alive,
		"rounds":      st.Round,
		"playerCount": len(st.Players),
		"endedAt":     endedAt,
	}
	if !p.Alive {
		doc["deathRound"] = p.DeathRound
	}
	if v := gameCardVariant(st.Seed, uid); v != "" {
		doc["variant"] = v
	}
	if st.Config.TestMode {
		doc["testMode"] = true
	}
	return doc
}
