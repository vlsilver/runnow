package backend

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf16"

	"cloud.google.com/go/firestore"
	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Bộ gửi outbox của Ma Sói (3.4). Mỗi chat gửi tuần tự theo seq dưới một lease
// 60 giây, claim bằng transaction, nên hai bộ gửi chạy cùng lúc không gửi đôi
// và tin trong một chat không đảo thứ tự. Telegram không có idempotency key:
// crash giữa lúc gửi và lúc ghi sent thì tin được gửi lại, chấp nhận (3.4).

const (
	outboxPending = "pending"
	outboxSending = "sending"
	outboxSent    = "sent"
	outboxFailed  = "failed"
	outboxSkipped = "skipped"

	outboxLease       = 60 * time.Second
	telegramTextLimit = 4096 // tính theo UTF-16, như Telegram
)

// outboxTelegram là phần Bot API bộ gửi cần; TelegramService đáp ứng.
type outboxTelegram interface {
	SendText(ctx context.Context, m TelegramText) (int64, error)
	EditText(ctx context.Context, chatID string, messageID int64, text string, html bool, markup any) error
}

// FlushResult: RetryAt khác 0 là còn chat phải gửi sau mốc đó (429, hoặc bộ
// gửi khác đang giữ lease); người gọi hẹn game-flush lúc ấy.
type FlushResult struct {
	Sent    int       `json:"sent"`
	Failed  int       `json:"failed"`
	Skipped int       `json:"skipped"`
	RetryAt time.Time `json:"retryAt,omitzero"`
}

func (r *FlushResult) retryAt(t time.Time) {
	if r.RetryAt.IsZero() || t.Before(r.RetryAt) {
		r.RetryAt = t
	}
}

type sendOutcome int

const (
	outcomeSent   sendOutcome = iota // gồm cả 400 "message is not modified"
	outcomeFailed                    // 400 khác, 403, group đã đổi ID: bỏ tin, gửi tin sau
	outcomeLater                     // 429: giữ pending, hẹn lại theo retry_after
	outcomeRetry                     // mạng, 5xx, lỗi lạ: giữ pending, task retry
)

// classifySend phân loại lỗi gửi theo bảng ở 3.4.
func classifySend(err error) sendOutcome {
	if err == nil {
		return outcomeSent
	}
	var te *TelegramAPIError
	if !errors.As(err, &te) {
		return outcomeRetry
	}
	switch {
	case te.Status == 429 || te.Code == 429:
		return outcomeLater
	case te.Status == 400 && strings.Contains(te.Description, "message is not modified"):
		return outcomeSent
	case te.Status == 400 || te.Status == 403: // gồm cả 400 có migrate_to_chat_id
		return outcomeFailed
	}
	return outcomeRetry
}

var errLeaseLost = errors.New("outbox: mất lease của chat")

// FlushGame gửi mọi tin pending của ván. Lỗi ở một chat không chặn chat khác;
// các lỗi được gộp lại để task retry. now cho test điều khiển giờ của lease.
func (s *GameStore) FlushGame(ctx context.Context, gameID string, tg outboxTelegram, now func() time.Time) (FlushResult, error) {
	var res FlushResult
	game := s.gameRef(gameID)
	chats, err := game.Collection("outboxChats").Where("pending", "==", true).Documents(ctx).GetAll()
	if err != nil {
		return res, err
	}
	if len(chats) == 0 {
		return res, nil
	}
	g, err := game.Get(ctx)
	if err != nil {
		return res, err
	}
	r, err := s.outboxRenderer(ctx, game, g.Data())
	if err != nil {
		return res, err
	}
	r.store, r.game, r.now = s, game, now
	owner, err := leaseOwner()
	if err != nil {
		return res, err
	}
	f := chatFlusher{db: s.db, game: game, gameID: gameID, tg: tg, r: r, owner: owner, now: now, res: &res}
	var errs []error
	for _, c := range chats {
		if err := f.flush(ctx, c.Ref.ID); err != nil {
			errs = append(errs, fmt.Errorf("outboxChats/%s: %w", c.Ref.ID, err))
		}
	}
	return res, errors.Join(errs...)
}

// AdminRetryOutbox xếp mọi tin failed chưa gửi lại thành tin mới ở cuối chat
// của nó và trả số tin đã xếp; người gọi kick flush. Tin cũ giữ status failed
// (M1 vẫn đếm) và ghi retriedAs, nên gọi lại không xếp đôi. Tin gửi bù tới sau
// những tin mới hơn, nên bộ gửi thêm dòng giờ của tin gốc (origAt). Prompt và
// tin sửa của lượt đã qua thì bộ gửi bỏ (stale) như thường. Một transaction là
// đủ: Firestore không còn giới hạn 500 lần ghi mỗi commit.
func (s *GameStore) AdminRetryOutbox(ctx context.Context, gameID, by string, wall time.Time) (int, error) {
	if _, err := s.readStartGame(ctx, gameID); err != nil {
		return 0, err
	}
	game := s.gameRef(gameID)
	var n int
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		docs, err := tx.Documents(game.Collection("outbox").Where("status", "==", outboxFailed)).GetAll()
		if err != nil {
			return err
		}
		var failed []*firestore.DocumentSnapshot
		for _, d := range docs {
			if _, done := d.Data()["retriedAs"]; !done {
				failed = append(failed, d)
			}
		}
		// Theo seq là đủ: seq tăng dần trong từng chat, nên chat nào cũng giữ thứ tự cũ.
		sort.Slice(failed, func(i, j int) bool { return number(failed[i].Data()["seq"]) < number(failed[j].Data()["seq"]) })
		msgs := make([]gameMsg, len(failed))
		for i, d := range failed {
			msgs[i] = gameMsg{ChatKey: stringValue(d.Data()["chatKey"])}
		}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		for _, d := range failed {
			m := d.Data()
			key := stringValue(m["chatKey"])
			seq := chats[key]
			chats[key] = seq + 1
			id := key + "_" + strconv.FormatInt(seq, 10)
			origAt := m["origAt"]
			if origAt == nil {
				origAt = m["createdAt"]
			}
			if err := tx.Create(game.Collection("outbox").Doc(id), map[string]any{
				"chatKey": key, "seq": seq, "template": m["template"], "data": m["data"],
				"status": outboxPending, "eventSeq": m["eventSeq"], "createdAt": wall,
				"retryOf": d.Ref.ID, "origAt": origAt,
			}); err != nil {
				return err
			}
			if err := tx.Update(d.Ref, []firestore.Update{{Path: "retriedAs", Value: id}, {Path: "retriedAt", Value: wall}}); err != nil {
				return err
			}
		}
		n = len(failed)
		return markChatsPending(tx, game, chats, wall)
	})
	if err != nil {
		return 0, err
	}
	slog.InfoContext(ctx, "game.outbox_retried", "gameId", gameID, "by", by, "requeued", n)
	return n, nil
}

func leaseOwner() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

type chatFlusher struct {
	db     *firestore.Client
	game   *firestore.DocumentRef
	gameID string
	tg     outboxTelegram
	r      *outboxRenderer
	owner  string
	now    func() time.Time
	res    *FlushResult
}

// flush claim chat rồi gửi lần lượt từ lastSentSeq+1 tới hết.
func (f *chatFlusher) flush(ctx context.Context, key string) error {
	chat := f.game.Collection("outboxChats").Doc(key)
	seq, err := f.claim(ctx, chat)
	if err != nil || seq == 0 {
		return err
	}
	for seq > 0 {
		if seq, err = f.sendOne(ctx, chat, key, seq); err != nil {
			return err
		}
	}
	return nil
}

// claim lấy lease của chat và trả seq kế tiếp cần gửi; 0 là không có gì để
// gửi lúc này (đã hết tin, bộ gửi khác đang giữ, hoặc đang chờ 429).
func (f *chatFlusher) claim(ctx context.Context, chat *firestore.DocumentRef) (int64, error) {
	var seq int64
	err := f.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		seq = 0
		d, err := tx.Get(chat)
		if err != nil {
			return err
		}
		c, t := d.Data(), f.now()
		if c["pending"] != true {
			return nil
		}
		if until := timeValue(c["leaseUntil"]); until.After(t) && stringValue(c["leaseOwner"]) != f.owner {
			f.res.retryAt(until)
			return nil
		}
		if at := timeValue(c["retryAt"]); at.After(t) {
			f.res.retryAt(at)
			return nil
		}
		next := int64(number(c["lastSentSeq"])) + 1
		if next >= int64(number(c["nextSeq"])) {
			return tx.Update(chat, releaseLease(firestore.Update{Path: "pending", Value: false}))
		}
		seq = next
		return tx.Update(chat, []firestore.Update{
			{Path: "leaseOwner", Value: f.owner}, {Path: "leaseUntil", Value: t.Add(outboxLease)},
			{Path: "retryAt", Value: firestore.Delete},
		})
	})
	return seq, err
}

func releaseLease(extra ...firestore.Update) []firestore.Update {
	return append([]firestore.Update{{Path: "leaseOwner", Value: firestore.Delete}, {Path: "leaseUntil", Value: firestore.Delete}}, extra...)
}

// holds kiểm lease trong transaction: lease của mình hết hạn và bộ gửi khác đã
// lấy lại chat thì dừng, không gửi hay ghi gì thêm. Hết hạn mà chưa ai lấy thì
// gửi tiếp được, vì lần ghi kế tiếp gia hạn lại.
func (f *chatFlusher) holds(c map[string]any) bool {
	return stringValue(c["leaseOwner"]) == f.owner
}

// sendOne gửi tin seq và trả seq kế tiếp, hoặc 0 khi chat đã hết tin hay phải
// dừng (429, lỗi tạm thời).
func (f *chatFlusher) sendOne(ctx context.Context, chat *firestore.DocumentRef, key string, seq int64) (int64, error) {
	msgRef := f.game.Collection("outbox").Doc(key + "_" + strconv.FormatInt(seq, 10))
	var msg, chatData map[string]any
	err := f.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		c, err := tx.Get(chat)
		if err != nil {
			return err
		}
		m, err := tx.Get(msgRef)
		if err != nil {
			return err
		}
		if !f.holds(c.Data()) {
			return errLeaseLost
		}
		msg, chatData = m.Data(), c.Data()
		if st := stringValue(msg["status"]); st != outboxPending && st != outboxSending {
			return nil // đã ghi kết quả ở lần trước; chỉ còn dời lastSentSeq
		}
		// Lease vừa được claim hoặc vừa gia hạn ở finish của tin trước.
		return tx.Update(msgRef, []firestore.Update{
			{Path: "status", Value: outboxSending}, {Path: "attempts", Value: firestore.Increment(1)},
			{Path: "sendingAt", Value: f.now()},
		})
	})
	if err != nil {
		return 0, err
	}

	var d delivery // result nil: tin đã có kết quả từ lượt trước
	outcome := outcomeSent
	var sendErr error
	if st := stringValue(msg["status"]); st == outboxPending || st == outboxSending {
		d, outcome, sendErr = f.deliver(ctx, key, seq, msg, chatData)
	}
	switch outcome {
	case outcomeLater, outcomeRetry:
		return 0, f.keepPending(ctx, chat, msgRef, outcome, sendErr)
	}
	return f.finish(ctx, chat, msgRef, key, seq, d)
}

// delivery là kết quả ghi lên outbox/{key}_{seq}, cùng phần ghi thêm lên doc
// chat (message_id của prompt, để tin sửa tìm được).
type delivery struct {
	result  map[string]any
	chatUps []firestore.Update
}

// deliver render rồi gửi (hoặc sửa) tin.
func (f *chatFlusher) deliver(ctx context.Context, key string, seq int64, msg, chat map[string]any) (delivery, sendOutcome, error) {
	tpl := stringValue(msg["template"])
	var out outboxText
	var err error
	if tpl == tplPrompt || tpl == tplChoice || tpl == tplTally {
		out, err = f.r.renderAction(ctx, key, tpl, stringValue(msg["data"]), chat)
	} else {
		out, err = f.r.render(key, tpl, stringValue(msg["data"]))
	}
	if err != nil {
		f.logFailed(ctx, key, seq, tpl, err)
		return delivery{result: map[string]any{"status": outboxFailed, "error": err.Error(), "failedAt": f.now()}}, outcomeFailed, nil
	}
	if out.skip != "" {
		return delivery{result: map[string]any{"status": outboxSkipped, "skipReason": out.skip}}, outcomeSent, nil
	}
	if at := timeValue(msg["origAt"]); !at.IsZero() && out.editID == 0 {
		out.parts = withLateLabel(out.parts, at)
	}
	var ids []int64
	for i, part := range out.parts {
		var markup any
		if i == len(out.parts)-1 {
			markup = out.markup // nút đi cùng phần cuối
		}
		var id int64
		if out.editID != 0 {
			err = f.tg.EditText(ctx, out.chatID, out.editID, part, true, markup)
		} else {
			id, err = f.tg.SendText(ctx, TelegramText{ChatID: out.chatID, ThreadID: out.threadID, Text: part, HTML: true, Markup: markup})
		}
		switch outcome := classifySend(err); outcome {
		case outcomeSent:
			if id != 0 {
				ids = append(ids, id)
			}
		case outcomeFailed:
			f.logFailed(ctx, key, seq, tpl, err)
			res := map[string]any{"status": outboxFailed, "error": err.Error(), "failedAt": f.now()}
			var te *TelegramAPIError
			if errors.As(err, &te) {
				res["errorStatus"] = te.Status
				if te.MigrateTo != 0 {
					res["migrateTo"] = te.MigrateTo
				}
				if strings.HasPrefix(key, "dm:") {
					// 403: người chơi chặn bot; chat not found: chưa từng mở chat với bot.
					res["dmBlocked"] = te.Status == 403 || strings.Contains(te.Description, "chat not found")
				}
			}
			if len(ids) > 0 {
				res["messageIds"] = ids
			}
			return delivery{result: res}, outcome, err
		default:
			// Phần đã gửi sẽ được gửi lại cùng cả tin; tin dài quá 4096 hiếm nên chấp nhận.
			return delivery{}, outcome, err
		}
	}
	d := delivery{result: map[string]any{"status": outboxSent, "messageIds": ids, "sentAt": f.now()}}
	if out.editID != 0 {
		d.result["editedId"] = out.editID
	}
	if out.promptKind != "" && len(ids) > 0 {
		d.chatUps = []firestore.Update{{Path: "prompts." + out.promptKind, Value: map[string]any{
			"messageId": ids[len(ids)-1], "turnKey": out.turnKey,
		}}}
	}
	return d, outcomeSent, nil
}

func (f *chatFlusher) logFailed(ctx context.Context, key string, seq int64, tpl string, err error) {
	// M1 đếm log này để báo admin.
	slog.ErrorContext(ctx, "game.outbox_failed", "gameId", f.gameID, "chatKey", key, "seq", seq, "template", tpl, "error", err)
}

// finish ghi kết quả của tin seq, dời lastSentSeq và trả seq kế tiếp; hết tin
// thì nhả lease và tắt pending trong cùng transaction, nên tin ghi xen vào lúc
// này (nextSeq tăng) vẫn được gửi.
func (f *chatFlusher) finish(ctx context.Context, chat, msgRef *firestore.DocumentRef, key string, seq int64, d delivery) (int64, error) {
	result := d.result
	uid, isDM := strings.CutPrefix(key, "dm:")
	dmOk, writeDM := false, false
	if isDM && result != nil {
		dmOk, writeDM = f.dmChange(uid, result)
	}
	next := int64(0)
	err := f.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		next = 0
		c, err := tx.Get(chat)
		if err != nil {
			return err
		}
		if !f.holds(c.Data()) {
			return errLeaseLost
		}
		if result != nil {
			var ups []firestore.Update
			for k, v := range result {
				ups = append(ups, firestore.Update{Path: k, Value: v})
			}
			if err := tx.Update(msgRef, ups); err != nil {
				return err
			}
		}
		if writeDM {
			if err := tx.Update(f.game.Collection("players").Doc(uid), []firestore.Update{{Path: "dmOk", Value: dmOk}}); err != nil {
				return err
			}
		}
		if seq+1 >= int64(number(c.Data()["nextSeq"])) {
			return tx.Update(chat, append(releaseLease(firestore.Update{Path: "lastSentSeq", Value: seq}, firestore.Update{Path: "pending", Value: false}), d.chatUps...))
		}
		next = seq + 1
		return tx.Update(chat, append([]firestore.Update{{Path: "lastSentSeq", Value: seq}, {Path: "leaseUntil", Value: f.now().Add(outboxLease)}}, d.chatUps...))
	})
	if err != nil {
		return 0, err
	}
	if writeDM {
		f.r.dmOk[uid] = dmOk
	}
	switch result["status"] {
	case outboxSent:
		f.res.Sent++
	case outboxFailed:
		f.res.Failed++
	case outboxSkipped:
		f.res.Skipped++
	}
	return next, nil
}

// dmChange: players/{uid}.dmOk cho M1 phải thành giá trị nào, và có cần ghi
// không. false khi Telegram từ chối DM (người chơi chặn bot), true lại khi DM
// tới được. Chỉ đọc cache; finish cập nhật cache sau khi commit, vì hàm
// transaction có thể chạy lại.
func (f *chatFlusher) dmChange(uid string, result map[string]any) (bool, bool) {
	ok, known := f.r.dmOk[uid]
	switch {
	case result["status"] == outboxSent && known && !ok:
		return true, true
	case result["dmBlocked"] == true && (!known || ok):
		return false, true
	}
	return false, false
}

// keepPending trả tin về pending và nhả lease. 429 thì ghi retryAt lên chat để
// không bộ gửi nào gửi trước mốc đó.
func (f *chatFlusher) keepPending(ctx context.Context, chat, msgRef *firestore.DocumentRef, outcome sendOutcome, sendErr error) error {
	var retryAt time.Time
	if outcome == outcomeLater {
		var te *TelegramAPIError
		wait := 1
		if errors.As(sendErr, &te) && te.RetryAfter > 0 {
			wait = te.RetryAfter
		}
		retryAt = f.now().Add(time.Duration(wait) * time.Second)
	}
	err := f.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		c, err := tx.Get(chat)
		if err != nil {
			return err
		}
		if !f.holds(c.Data()) {
			return errLeaseLost
		}
		if err := tx.Update(msgRef, []firestore.Update{{Path: "status", Value: outboxPending}, {Path: "lastError", Value: sendErr.Error()}}); err != nil {
			return err
		}
		ups := releaseLease()
		if !retryAt.IsZero() {
			ups = append(ups, firestore.Update{Path: "retryAt", Value: retryAt})
		}
		return tx.Update(chat, ups)
	})
	if err != nil {
		return errors.Join(sendErr, err)
	}
	if outcome == outcomeLater {
		f.res.retryAt(retryAt)
		return nil
	}
	return sendErr
}

// ---- Render ----

// outboxRenderer giữ những gì render cần, đọc một lần cho cả lượt gửi.
type outboxRenderer struct {
	gameID   string
	gameData map[string]any
	chatID   string
	threadID int64
	cfg      werewolf.Config
	players  []gamePlayerInfo // theo thứ tự đăng ký
	byUID    map[string]gamePlayerInfo
	dmOk     map[string]bool // chỉ có uid đã từng ghi dmOk

	// Cho prompt và tin sửa: đọc state và lựa chọn đang lưu lúc gửi (3.4).
	store *GameStore
	game  *firestore.DocumentRef
	now   func() time.Time
	st    *werewolf.State
}

func (s *GameStore) outboxRenderer(ctx context.Context, game *firestore.DocumentRef, g map[string]any) (*outboxRenderer, error) {
	cfg, err := gameConfigOf(g)
	if err != nil {
		return nil, err
	}
	players, err := s.loadPlayers(ctx, game)
	if err != nil {
		return nil, err
	}
	r := &outboxRenderer{gameID: game.ID, gameData: g, chatID: stringValue(g["chatId"]), threadID: int64(number(g["threadId"])), cfg: cfg,
		players: players, byUID: playerIndex(players), dmOk: map[string]bool{}}
	for _, p := range players {
		if v, ok := p.data["dmOk"].(bool); ok {
			r.dmOk[p.uid] = v
		}
	}
	return r, nil
}

type outboxText struct {
	chatID   string
	threadID int64
	parts    []string
	skip     string // khác rỗng: không gửi, ghi lý do
	markup   any    // reply_markup của phần cuối
	editID   int64  // khác 0: sửa tin này thay vì gửi mới

	// promptKind khác rỗng: tin là prompt, gửi xong thì ghi message_id lên
	// outboxChats/{key}.prompts.{kind} cho tin sửa sau này.
	promptKind, turnKey string
}

func (r *outboxRenderer) name(uid string) string {
	if p, ok := r.byUID[uid]; ok {
		return html.EscapeString(p.name)
	}
	return "Người chơi"
}

// target chọn chat của key: DM tới tgUserId của người chơi, topic Ma Sói của
// group ván, hoặc group Phe Sói. Key lạ thì lỗi, không rơi về group chung, vì
// tin của phe kín mà vào group chung là lộ. skip khác rỗng là không gửi được.
func (r *outboxRenderer) target(key string) (outboxText, error) {
	var out outboxText
	if uid, ok := strings.CutPrefix(key, "dm:"); ok {
		p, known := r.byUID[uid]
		tg := tgIDString(p.data["tgUserId"])
		if !known || tg == "" {
			return outboxText{skip: "no_telegram"}, nil
		}
		out.chatID = tg
		return out, nil
	}
	switch key {
	case chatGroup:
		out.chatID, out.threadID = r.chatID, r.threadID
		if out.chatID == "" {
			return out, errors.New("ván không có chatId")
		}
	case chatWolves:
		// W3 ghi wolfChatId lúc tạo group; chưa có thì bỏ tin.
		if out.chatID = tgIDString(r.gameData["wolfChatId"]); out.chatID == "" {
			return outboxText{skip: "no_chat"}, nil
		}
	default:
		return out, fmt.Errorf("chat lạ %q", key)
	}
	return out, nil
}

func (r *outboxRenderer) render(key, tpl, raw string) (outboxText, error) {
	out, err := r.target(key)
	if err != nil || out.skip != "" {
		return out, err
	}
	var text string
	switch tpl {
	case tplStart:
		var d struct {
			NightAt time.Time `json:"nightAt"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text = r.startText(d.NightAt)
		}
	case tplCard:
		var d struct {
			Role   werewolf.Role `json:"role"`
			Wolves []string      `json:"wolves"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text, err = r.cardText(strings.TrimPrefix(key, "dm:"), d.Role, d.Wolves)
		}
		if err == nil && r.gameID != "" {
			var data string
			if data, err = (gameButton{GameID: r.gameID, Op: opCard}).data(); err == nil {
				out.markup = inlineKeyboard([][]map[string]any{{{"text": "Xem lại lá bài", "callback_data": data}}})
			}
		}
	case tplDigest:
		text, err = r.digestText(raw)
	case tplReminder:
		var d struct {
			Reason string `json:"reason"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text, err = reminderText(d.Reason)
		}
	case tplPrivate:
		var d struct {
			Events []werewolf.Event `json:"events"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text = r.privateText(d.Events)
		}
	case tplAdmin:
		var d struct {
			Action   string    `json:"action"`
			Deadline time.Time `json:"deadline"`
			Minutes  int       `json:"minutes"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text, err = adminText(d.Action, d.Deadline, d.Minutes)
		}
	case tplWolfPick:
		var d struct {
			UID     string `json:"uid"`
			Target  string `json:"target"`
			Cleared bool   `json:"cleared"`
		}
		if err = json.Unmarshal([]byte(raw), &d); err == nil {
			text = "<b>" + r.name(d.UID) + "</b> chọn cắn <b>" + r.name(d.Target) + "</b>."
			if d.Cleared {
				text = "<b>" + r.name(d.UID) + "</b> bỏ chọn cắn."
			}
		}
	default:
		err = fmt.Errorf("template lạ %q", tpl)
	}
	if err != nil {
		return out, fmt.Errorf("render %s: %w", tpl, err)
	}
	if text == "" {
		return outboxText{skip: "empty"}, nil
	}
	out.parts = splitTelegramText(text, telegramTextLimit)
	return out, nil
}

func vnTime(t time.Time) string { return t.In(vietnam).Format("15:04 02/01") }

func (r *outboxRenderer) startText(nightAt time.Time) string {
	names := make([]string, 0, len(r.players))
	for _, p := range r.players {
		names = append(names, html.EscapeString(p.name))
	}
	return fmt.Sprintf("<b>Ma Sói bắt đầu</b>\n%d người chơi: %s.\nĐêm 1 bắt đầu lúc %s. Bot đã nhắn riêng lá bài cho từng người.",
		len(names), strings.Join(names, ", "), vnTime(nightAt))
}

// cardText: dòng đầu không lộ vai, vì Telegram hiện dòng đầu trên màn hình khoá.
func (r *outboxRenderer) cardText(uid string, role werewolf.Role, wolves []string) (string, error) {
	label, ok := roleLabels[role]
	if !ok {
		return "", fmt.Errorf("vai lạ %q", role)
	}
	rules := strings.ReplaceAll(roleRules[role], "X km", formatKm(kmPerUnit(r.cfg))+" km")
	lines := []string{"Lá bài của bạn trong ván Ma Sói:", "<b>" + label + "</b>", html.EscapeString(rules)}
	var mates []string
	for _, w := range wolves {
		if w != uid {
			mates = append(mates, r.name(w))
		}
	}
	if len(mates) > 0 {
		lines = append(lines, "Đồng đội: "+strings.Join(mates, ", ")+".")
	}
	return strings.Join(lines, "\n"), nil
}

// digestText dùng lại chữ của feed để group và app đọc cùng một bản tin. Bước
// không có gì công khai (feed cũng bỏ) thì không gửi.
func (r *outboxRenderer) digestText(raw string) (string, error) {
	var d struct {
		PhaseKey string            `json:"phaseKey"`
		Round    int               `json:"round"`
		Phase    werewolf.Phase    `json:"phase"`
		Events   []werewolf.Event  `json:"events"`
		Deadline time.Time         `json:"deadline"`
		Roles    map[string]string `json:"roles"`
	}
	if err := json.Unmarshal([]byte(raw), &d); err != nil {
		return "", err
	}
	evs, err := json.Marshal(d.Events)
	if err != nil {
		return "", err
	}
	item, err := feedItem(map[string]any{"events": string(evs), "phaseKey": d.PhaseKey}, r.byUID)
	if err != nil {
		return "", err
	}
	if len(item.Lines) == 0 {
		return "", nil
	}
	lines := []string{"<b>" + html.EscapeString(item.Title) + "</b>"}
	for _, l := range item.Lines {
		lines = append(lines, html.EscapeString(l))
	}
	switch {
	case d.Roles != nil:
		lines = append(lines, "", "Lá bài:")
		for _, p := range r.players {
			if role, ok := d.Roles[p.uid]; ok {
				lines = append(lines, r.name(p.uid)+": "+roleLabels[werewolf.Role(role)])
			}
		}
	case !d.Deadline.IsZero():
		lines = append(lines, "", fmt.Sprintf("Tiếp theo: %s, tới %s.", phaseLabel(d.Round, d.Phase), vnTime(d.Deadline)))
	}
	return strings.Join(lines, "\n"), nil
}

func reminderText(reason string) (string, error) {
	switch reason {
	case werewolf.ReminderNominate:
		return "<b>Nhắc đề cử</b>\nĐề cử đóng lúc 17h. Ai chưa đề cử thì vào app RunNow để chọn.", nil
	case werewolf.ReminderVote:
		return "<b>Nhắc biểu quyết</b>\nBiểu quyết Treo hay Tha đóng lúc 22h. Ai chưa bỏ phiếu thì vào app RunNow.", nil
	}
	return "", fmt.Errorf("lý do nhắc lạ %q", reason)
}

var voidTexts = map[string]string{
	werewolf.VoidActorDead:   "bạn đã chết trước lúc chốt",
	werewolf.VoidTargetDead:  "người được chọn đã chết",
	werewolf.VoidLoverTarget: "không chọn được người yêu của mình",
	werewolf.VoidNoKm:        "chưa đủ km",
	werewolf.VoidRepeat:      "không bảo vệ lại người của đêm trước",
	werewolf.VoidInvalid:     "người được chọn không hợp lệ",
	werewolf.VoidNoPotion:    "đã dùng hết bình",
	werewolf.VoidVoteCut:     "tổng km chưa đủ nên mất phiếu",
	werewolf.VoidGameOver:    "ván đã kết thúc",
}

var causeTexts = map[werewolf.Cause]string{
	werewolf.CauseBite: "bị sói cắn", werewolf.CausePoison: "bị đầu độc", werewolf.CauseHang: "bị treo",
	werewolf.CauseShot: "bị Thợ săn bắn", werewolf.CauseLover: "chết theo người yêu", werewolf.CauseLeft: "đã rời PSC",
}

// privateText: việc riêng của một người sau một lần chốt (stepMessages).
func (r *outboxRenderer) privateText(evs []werewolf.Event) string {
	lines := []string{"<b>Ma Sói: tin riêng</b>"}
	for _, e := range evs {
		switch e.Kind {
		case werewolf.EventVoid:
			reason := voidTexts[e.Reason]
			if reason == "" {
				reason = "không hợp lệ"
			}
			lines = append(lines, fmt.Sprintf("Lựa chọn %s của bạn không được tính: %s.", actionTexts[e.Action].label, reason))
		case werewolf.EventDeath:
			line := "Bạn đã chết"
			if c := causeTexts[e.Cause]; c != "" {
				line += ", " + c
			}
			lines = append(lines, line+".")
		case werewolf.EventLovers:
			line := fmt.Sprintf("Bạn được ghép đôi với %s, lá bài %s. Một người chết thì người kia chết theo.", r.name(e.UID), roleLabels[e.Role])
			if e.Draw {
				line = "Cupid không ghép nên bot ghép thay. " + line
			}
			lines = append(lines, line)
		case werewolf.EventWolvesTarget:
			switch {
			case e.UID != "":
				lines = append(lines, fmt.Sprintf("Phe Sói chốt cắn %s.", r.name(e.UID)))
			case e.Reason == werewolf.VoidNoKm:
				lines = append(lines, "Phe Sói chưa đủ km nên đêm nay không cắn được ai.")
			default:
				lines = append(lines, "Phe Sói không chọn ai nên đêm nay không cắn.")
			}
		}
	}
	if len(lines) == 1 {
		return ""
	}
	return strings.Join(lines, "\n")
}

// renderAction vẽ prompt (gửi mới) hoặc tin sửa prompt (choice) từ state và
// lựa chọn đang lưu lúc gửi, nên gửi lại bao nhiêu lần cũng ra cùng kết quả.
// Tin sửa cần message_id của prompt cùng lượt; prompt chưa gửi được (không có
// Telegram, bị chặn) hay đã sang lượt khác thì bỏ.
func (r *outboxRenderer) renderAction(ctx context.Context, key, tpl, raw string, chat map[string]any) (outboxText, error) {
	out, err := r.target(key)
	if err != nil || out.skip != "" {
		return out, err
	}
	var d struct {
		Kind    werewolf.Kind `json:"kind"`
		TurnKey string        `json:"turnKey"`
		Pick    []string      `json:"pick"`
	}
	if err := json.Unmarshal([]byte(raw), &d); err != nil {
		return out, fmt.Errorf("render %s: %w", tpl, err)
	}
	st, err := r.state(ctx)
	if err != nil {
		return out, err
	}
	turn := turnKey(st)
	if tpl == tplPrompt && d.TurnKey != turn {
		return outboxText{skip: "stale"}, nil
	}
	if tpl == tplChoice || tpl == tplTally {
		prompt := anyMap(anyMap(chat["prompts"])[string(d.Kind)])
		id := int64(number(prompt["messageId"]))
		switch {
		case id == 0:
			return outboxText{skip: "no_prompt"}, nil
		case stringValue(prompt["turnKey"]) != turn:
			return outboxText{skip: "stale"}, nil
		}
		out.editID = id
	}
	if key == chatGroup {
		return r.renderTally(ctx, out, tpl, st, d.Kind, turn)
	}
	uid := strings.TrimPrefix(key, "dm:")
	mine, raws, err := r.store.loadMine(ctx, r.game, st.Round, uid)
	if err != nil {
		return out, err
	}
	acts := meActions(st, uid, mine, raws, r.players, gameNow(r.gameData, r.now()), clockOffset(r.gameData))
	a := findAction(acts, d.Kind)
	if tpl == tplPrompt && a == nil {
		return outboxText{skip: "closed"}, nil
	}
	v := promptView{gameID: r.gameID, turnKey: turn, st: st, kind: d.Kind, a: a, pick: d.Pick,
		name: func(uid string) string { return playerName(r.byUID, uid) }}
	text, markup, err := v.render()
	if err != nil {
		return out, fmt.Errorf("render %s: %w", tpl, err)
	}
	out.parts, out.markup = splitTelegramText(text, telegramTextLimit), markup
	if tpl == tplPrompt {
		out.promptKind, out.turnKey = string(d.Kind), turn
	}
	return out, nil
}

// renderTally vẽ prompt đề cử hay biểu quyết trong topic từ mọi lựa chọn đang
// lưu của vòng. Hết phase thì prompt chưa gửi bị bỏ, còn tin sửa vẫn vẽ số đếm
// cuối cùng nhưng không còn nút.
func (r *outboxRenderer) renderTally(ctx context.Context, out outboxText, tpl string, st *werewolf.State, kind werewolf.Kind, turn string) (outboxText, error) {
	open := st.Phase == werewolf.PhaseDay && kind == werewolf.KindNominate ||
		st.Phase == werewolf.PhaseTrial && kind == werewolf.KindVote
	if tpl == tplPrompt && !open {
		return outboxText{skip: "closed"}, nil
	}
	docs, err := roundRef(r.game, st.Round).Collection("actions").Where("kind", "==", string(kind)).Documents(ctx).GetAll()
	if err != nil {
		return out, err
	}
	var acts []werewolf.Action
	for _, d := range docs {
		if a, ok := decodeAction(d.Data()); ok {
			acts = append(acts, a)
		}
	}
	offset := clockOffset(r.gameData)
	opens, closes := st.Window(kind)
	v := tallyView{gameID: r.gameID, turnKey: turn, st: st, kind: kind, acts: acts, players: r.players, open: open,
		opens: opens.Add(-offset), closes: closes.Add(-offset), notYet: gameNow(r.gameData, r.now()).Before(opens)}
	text, markup, err := v.render()
	if err != nil {
		return out, fmt.Errorf("render %s: %w", tpl, err)
	}
	out.parts, out.markup = splitTelegramText(text, telegramTextLimit), markup
	if tpl == tplPrompt {
		out.promptKind, out.turnKey = string(kind), turn
	}
	return out, nil
}

// state đọc secret/state một lần cho cả lượt gửi.
func (r *outboxRenderer) state(ctx context.Context) (*werewolf.State, error) {
	if r.st != nil {
		return r.st, nil
	}
	st, err := r.store.loadState(ctx, r.game)
	if err != nil {
		return nil, err
	}
	if st == nil {
		return nil, errors.New("ván chưa có state")
	}
	r.st = st
	return st, nil
}

func anyMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func adminText(action string, deadline time.Time, minutes int) (string, error) {
	switch action {
	case "pause":
		return "<b>Ván tạm dừng</b>\nAdmin đã tạm dừng ván. Mọi hạn đứng yên tới khi chạy tiếp.", nil
	case "resume":
		text := "<b>Ván chạy tiếp</b>"
		if !deadline.IsZero() {
			text += "\nHạn kế tiếp: " + vnTime(deadline) + "."
		}
		return text, nil
	case "cancel":
		return "<b>Ván đã huỷ</b>\nAdmin đã huỷ ván Ma Sói này.", nil
	case "extend":
		return fmt.Sprintf("<b>Dời hạn</b>\nAdmin dời hạn lượt này thêm %d phút. Hạn mới: %s.", minutes, vnTime(deadline)), nil
	}
	return "", fmt.Errorf("lệnh admin lạ %q", action)
}

// withLateLabel thêm dòng báo tin gửi bù vào đầu phần đầu, hoặc thành phần
// riêng nếu phần đầu đã sát giới hạn.
func withLateLabel(parts []string, at time.Time) []string {
	label := "<i>Gửi bù tin lúc " + vnTime(at) + "</i>"
	if len(parts) > 0 && utf16Len(label)+1+utf16Len(parts[0]) <= telegramTextLimit {
		return append([]string{label + "\n" + parts[0]}, parts[1:]...)
	}
	return append([]string{label}, parts...)
}

// splitTelegramText tách theo dòng cho mỗi phần không quá limit đơn vị UTF-16.
// Dòng dài quá limit thì cắt cứng theo rune. Thẻ HTML chỉ nằm trong một dòng,
// nên tách theo dòng không làm hở thẻ.
func splitTelegramText(text string, limit int) []string {
	if utf16Len(text) <= limit {
		return []string{text}
	}
	var parts []string
	var cur strings.Builder
	curLen := 0
	flush := func() {
		if cur.Len() > 0 {
			parts = append(parts, cur.String())
			cur.Reset()
			curLen = 0
		}
	}
	for _, line := range strings.Split(text, "\n") {
		for utf16Len(line) > limit {
			flush()
			head, rest := cutUTF16(line, limit)
			parts = append(parts, head)
			line = rest
		}
		n := utf16Len(line)
		if curLen > 0 && curLen+1+n > limit {
			flush()
		}
		if curLen > 0 {
			cur.WriteByte('\n')
			curLen++
		}
		cur.WriteString(line)
		curLen += n
	}
	flush()
	return parts
}

func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		n += utf16.RuneLen(r)
	}
	return n
}

func cutUTF16(s string, limit int) (string, string) {
	n := 0
	for i, r := range s {
		l := utf16.RuneLen(r)
		if n+l > limit {
			return s[:i], s[i:]
		}
		n += l
	}
	return s, ""
}

// gameFlushTask là payload của /tasks/game-flush. Bot decode chặt, nên thêm
// field thì deploy bot trước.
type gameFlushTask struct {
	GameID string `json:"gameId"`
}

// gameFlushTaskFor: gửi ngay thì không đặt TaskID (3.2 bước 5), để mỗi lần ghi
// đều có một lượt gửi. Hẹn giờ thì TaskID theo mốc, nhiều lượt gặp cùng một
// 429 chỉ tạo một task.
func gameFlushTaskFor(gameID string, at time.Time) PublishTask {
	t := PublishTask{Queue: QueueGameInbound, HandlerPath: "/tasks/game-flush", Payload: gameFlushTask{GameID: gameID}}
	if !at.IsZero() {
		t.ScheduleTime = &at
		t.TaskID = StableTaskID("gameflush", []any{gameID, at.Unix()})
	}
	return t
}
