package backend

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Chat phe kín trong app, thay cho group Telegram Phe Sói / Cặp đôi: người không
// ở group nào vẫn nói chuyện được với phe mình. Doc chat ở games/{id}/chats/{key},
// tin ở chats/{key}/chatMessages/{seq}. Ai là thành viên thì tính từ state của
// engine mỗi lần gọi, nên không có danh sách thành viên nào phải giữ cho khớp.

const (
	chatLovers    = "lovers"
	chatPageSize  = 30
	chatMaxRunes  = 1000
	chatMinGap    = time.Second
	chatPingEvery = 10 * time.Minute
	chatKeepFor   = 90 * 24 * time.Hour

	// chatKindWolfPick: tin hệ thống khi một sói chọn hay bỏ chọn cắn (C2).
	chatKindWolfPick = "wolf_pick"
)

var (
	errChatNotFound = &HTTPError{Status: http.StatusNotFound, Code: "chat_not_found", Message: "Không có chat này."}
	errChatReadOnly = &HTTPError{Status: http.StatusForbidden, Code: "chat_read_only", Message: "Bạn chỉ xem được chat này."}
	errChatTooFast  = &HTTPError{Status: http.StatusTooManyRequests, Code: "too_fast", Message: "Gửi chậm lại một chút."}
	errChatText     = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_text", Message: fmt.Sprintf("Tin nhắn trống hoặc dài quá %d ký tự.", chatMaxRunes)}
	errChatNoMsg    = &HTTPError{Status: http.StatusNotFound, Code: "message_not_found", Message: "Không còn tin nhắn này."}
)

var chatLabels = map[string]string{chatWolves: "Phe Sói", chatLovers: "Cặp đôi"}

// chatMembers là người trong chat key, nil khi ván không có chat đó. Phe chỉ có
// một người thì không có chat.
func chatMembers(st *werewolf.State, key string) []string {
	var out []string
	switch key {
	case chatWolves:
		for _, uid := range sortedPlayers(st) {
			if st.Players[uid].Role == werewolf.Wolf {
				out = append(out, uid)
			}
		}
	case chatLovers:
		out = append(out, st.Lovers...)
	}
	if len(out) < 2 {
		return nil
	}
	return out
}

// chatAccess: người đã chết, ván đã hết hay đã huỷ thì chỉ còn đọc. Huỷ ván chỉ
// đổi status của game, không đụng state, nên phải xét cả gameData.
func chatAccess(st *werewolf.State, gameData map[string]any, key, uid string) (member, canSend bool) {
	if st == nil || !slices.Contains(chatMembers(st, key), uid) {
		return false, false
	}
	return true, st.Players[uid].Alive && st.Phase != werewolf.PhaseEnded && !gameClosed(stringValue(gameData["status"]))
}

type GameChat struct {
	Key      string            `json:"key"`
	Label    string            `json:"label"`
	CanSend  bool              `json:"canSend"`
	Messages []GameChatMessage `json:"messages"`
	Cursor   string            `json:"cursor,omitempty"`
	// HasNewer: trang after còn tin mới hơn, gọi tiếp với after là seq lớn nhất.
	HasNewer bool `json:"hasNewer"`
}

type GameChatMessage struct {
	Seq    int64     `json:"seq"`
	UID    string    `json:"uid"`
	Name   string    `json:"name"`
	Text   string    `json:"text"`
	System bool      `json:"system"`
	At     time.Time `json:"at"`
	// Hidden: người xem đã chặn người gửi; Text rỗng, app không vẽ tin này.
	Hidden bool `json:"hidden,omitempty"`
}

func chatRef(game *firestore.DocumentRef, key string) *firestore.DocumentRef {
	return game.Collection("chats").Doc(key)
}

// Chat trả một trang tin, luôn mới trước. Không có tham số là trang mới nhất;
// cursor (seq cuối của trang trước) lùi về tin cũ hơn; after lấy tối đa một
// trang tin ngay sau seq đó, để poll lấp được đoạn app chưa có.
func (s *GameStore) Chat(ctx context.Context, gameID, key, cursor, after string, v GameViewer) (GameChat, error) {
	if cursor != "" && after != "" {
		return GameChat{}, invalidRequest()
	}
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return GameChat{}, err
	}
	g, registered, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return GameChat{}, err
	}
	if !registered {
		return GameChat{}, errNotGamePlayer
	}
	st, err := s.loadState(ctx, g.Ref)
	if err != nil {
		return GameChat{}, err
	}
	member, canSend := chatAccess(st, g.Data(), key, v.UID)
	if !member {
		return GameChat{}, errChatNotFound
	}
	col := chatRef(g.Ref, key).Collection("chatMessages")
	q := col.OrderBy("seq", firestore.Desc).Limit(chatPageSize)
	switch {
	case cursor != "":
		n, err := strconv.ParseInt(cursor, 10, 64)
		if err != nil || n < 1 {
			return GameChat{}, invalidRequest()
		}
		q = col.Where("seq", "<", n).OrderBy("seq", firestore.Desc).Limit(chatPageSize)
	case after != "":
		n, err := strconv.ParseInt(after, 10, 64)
		if err != nil || n < 0 {
			return GameChat{}, invalidRequest()
		}
		// Lấy dư một tin để biết còn tin mới hơn hay không.
		q = col.Where("seq", ">", n).OrderBy("seq", firestore.Asc).Limit(chatPageSize + 1)
	}
	docs, err := q.Documents(ctx).GetAll()
	if err != nil {
		return GameChat{}, err
	}
	out := GameChat{Key: key, Label: chatLabels[key], CanSend: canSend, Messages: []GameChatMessage{}}
	if after != "" {
		if len(docs) > chatPageSize {
			docs, out.HasNewer = docs[:chatPageSize], true
		}
		slices.Reverse(docs)
	}
	if len(docs) == 0 {
		return out, nil // poll không có tin mới thì khỏi đọc danh sách người chơi
	}
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return GameChat{}, err
	}
	blocked, err := s.blockedBy(ctx, v.UID)
	if err != nil {
		return GameChat{}, err
	}
	index := playerIndex(players)
	name := func(uid string) string {
		if p, ok := index[uid]; ok {
			return p.name
		}
		return "Người chơi"
	}
	for _, d := range docs {
		m := d.Data()
		msg := GameChatMessage{Seq: int64(number(m["seq"])), UID: stringValue(m["uid"]), Text: stringValue(m["text"]), At: timeValue(m["at"])}
		msg.Name = name(msg.UID)
		if kind := stringValue(m["kind"]); kind != "text" {
			msg.System = true
			msg.Text = chatSystemText(kind, msg.Name, m, name)
		} else if blocked[msg.UID] {
			msg.Hidden, msg.Text = true, ""
		}
		out.Messages = append(out.Messages, msg)
	}
	if after == "" && len(docs) == chatPageSize {
		out.Cursor = strconv.FormatInt(int64(number(docs[len(docs)-1].Data()["seq"])), 10)
	}
	return out, nil
}

// chatSystemText dựng chữ lúc đọc để tên luôn là tên hiện tại của người chơi.
func chatSystemText(kind, actor string, m map[string]any, name func(string) string) string {
	switch kind {
	case chatKindWolfPick:
		if target := stringValue(m["target"]); target != "" {
			return actor + " chọn cắn " + name(target) + "."
		}
		return actor + " bỏ chọn cắn."
	}
	return ""
}

// PostChat ghi một tin của người chơi. Transaction đọc state để kiểm người gửi
// còn trong phe và còn sống ngay lúc ghi, đọc doc chat để cấp seq và chặn gửi
// dồn. Trả true khi có DM báo tin mới cần bot gửi.
func (s *GameStore) PostChat(ctx context.Context, gameID, key, text string, v GameViewer, wall time.Time) (bool, error) {
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > chatMaxRunes {
		return false, errChatText
	}
	text = maskProfanity(text)
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return false, err
	}
	g, registered, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return false, err
	}
	if !registered {
		return false, errNotGamePlayer
	}
	game := g.Ref
	var pinged bool
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		pinged = false
		gd, err := tx.Get(game)
		if err != nil {
			return err
		}
		sec, err := tx.Get(secretRef(game))
		if status.Code(err) == codes.NotFound {
			return errChatNotFound // chưa chia bài
		}
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		member, canSend := chatAccess(st, gd.Data(), key, v.UID)
		if !member {
			return errChatNotFound
		}
		if !canSend {
			return errChatReadOnly
		}
		c, err := readChat(tx, game, key)
		if err != nil {
			return err
		}
		if last := timeValue(nested(c.data, "lastSentAt", v.UID)); !last.IsZero() && wall.Sub(last) < chatMinGap {
			return errChatTooFast
		}
		msgs := c.pings(st, key, v.UID, gd.Data(), wall)
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		if err := c.write(tx, map[string]any{"uid": v.UID, "kind": "text", "text": text}, v.UID, msgs, wall); err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, gameData: gd.Data(), msgs: msgs, chats: chats, wall: wall}
		pinged = len(msgs) > 0
		return w.writeOutbox(int64(number(gd.Data()["eventSeq"])))
	})
	return pinged, err
}

// chatPost là doc chat đã đọc trong transaction, chờ ghi tin kế tiếp.
type chatPost struct {
	key  string
	ref  *firestore.DocumentRef
	data map[string]any
}

func readChat(tx *firestore.Transaction, game *firestore.DocumentRef, key string) (chatPost, error) {
	ref := chatRef(game, key)
	d, err := tx.Get(ref)
	if status.Code(err) == codes.NotFound {
		return chatPost{key: key, ref: ref, data: map[string]any{}}, nil
	}
	if err != nil {
		return chatPost{}, err
	}
	return chatPost{key: key, ref: ref, data: d.Data()}, nil
}

// pings là DM báo có tin mới cho thành viên còn sống khác người gửi. Mỗi người
// nhận tối đa một DM mỗi chatPingEvery, và không nhận nếu chính họ vừa gửi
// trong khoảng đó, vì như vậy là họ đang mở chat. Người chơi giả không có
// Telegram nên bỏ.
func (c chatPost) pings(st *werewolf.State, key, sender string, gameData map[string]any, wall time.Time) []gameMsg {
	fake := fakeUIDs(gameData)
	var out []gameMsg
	for _, uid := range chatMembers(st, key) {
		if uid == sender || fake[uid] || !st.Players[uid].Alive {
			continue
		}
		recent := timeValue(nested(c.data, "pingedAt", uid))
		if sent := timeValue(nested(c.data, "lastSentAt", uid)); sent.After(recent) {
			recent = sent
		}
		if !recent.IsZero() && wall.Sub(recent) < chatPingEvery {
			continue
		}
		out = append(out, gameMsg{ChatKey: dmChat(uid), Template: tplChatPing, Data: map[string]any{"chat": key}})
	}
	return out
}

// write ghi tin với seq kế tiếp và cập nhật doc chat. Gọi sau mọi lần đọc của
// transaction. sender rỗng là tin hệ thống, không tính vào lastSentAt.
func (c chatPost) write(tx *firestore.Transaction, msg map[string]any, sender string, pings []gameMsg, wall time.Time) error {
	seq := int64(number(c.data["seq"])) + 1
	msg["seq"], msg["at"], msg["expiresAt"] = seq, wall, wall.Add(chatKeepFor)
	if err := tx.Create(c.ref.Collection("chatMessages").Doc(fmt.Sprintf("%010d", seq)), msg); err != nil {
		return err
	}
	update := map[string]any{"key": c.key, "seq": seq, "updatedAt": wall}
	if sender != "" {
		update["lastSentAt"] = map[string]any{sender: wall}
	}
	if len(pings) > 0 {
		pinged := map[string]any{}
		for _, m := range pings {
			pinged[strings.TrimPrefix(m.ChatKey, "dm:")] = wall
		}
		update["pingedAt"] = pinged
	}
	return tx.Set(c.ref, update, firestore.MergeAll)
}

func nested(d map[string]any, field, key string) any {
	m, _ := d[field].(map[string]any)
	return m[key]
}
