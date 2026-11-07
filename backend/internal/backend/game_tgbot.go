package backend

import (
	"context"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Bot ván là managed bot riêng của chủ ván (admin Ma Sói), tạo qua 3i như
// MyBot nhưng không đụng MyBot: một chủ một bot ván, tạo bot ván mới thì bot
// cũ bị thay. Chủ tự thêm bot vào group của mình làm admin; group và topic chỉ
// được ghi nhận từ sự kiện Telegram gửi tới chính bot đó (my_chat_member, lệnh
// /van của chủ trong topic), nên ván chỉ chọn được nơi bot đang thật sự ở.
//
// Firestore:
//   - managedBots/{botId}: kind "game", uid, username, ownerTgId.
//   - managedBots/{botId}/chats/{chatId}: title, type, forum, status, addedBy,
//     topics {threadId: {name, at, by}}.
//   - gameBots/{uid}: botId, username, linkedAt, setupAt, setupError.
//   - gameBotIntents/{tgUserId}: uid, expiresAt. Có intent còn hạn thì bot mới
//     của tg đó là bot ván, không thì đi đường MyBot như cũ.

const (
	managedKindGame  = "game"
	gameBotIntentTTL = 30 * time.Minute
	gameBotName      = "Quản trò Ma Sói"
	// gameBotCommand: chủ gõ trong topic để báo bot ván đăng vào đó.
	gameBotCommand = "/van"
)

var (
	errGameBotNoLink  = &HTTPError{Status: http.StatusConflict, Code: "telegram_not_linked", Message: "Liên kết Telegram trong app trước."}
	errGameBotMissing = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "telegram_bot", Message: "Tạo bot ván trước."}
	errGameBotChat    = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "telegram_chat", Message: "Bot ván chưa ở group này hoặc chưa là admin."}
	errGameBotTopic   = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "telegram_topic", Message: "Gõ /van trong topic đó để bot nhận topic trước."}
)

func (m *ManagedBotService) gameBotRef(uid string) *firestore.DocumentRef {
	return m.db.Collection("gameBots").Doc(uid)
}

func (m *ManagedBotService) gameIntentRef(tg int64) *firestore.DocumentRef {
	return m.db.Collection("gameBotIntents").Doc(strconv.FormatInt(tg, 10))
}

func (m *ManagedBotService) gameChatRef(botID, chatID string) *firestore.DocumentRef {
	return m.botRef(botID).Collection("chats").Doc(chatID)
}

// linkedTg là tg đang liên kết với uid; 0 là chưa liên kết.
func (m *ManagedBotService) linkedTg(ctx context.Context, uid string) (int64, error) {
	link, err := getData(ctx, m.db.Collection("telegramLinks").Doc(uid))
	if err != nil {
		return 0, err
	}
	tg, _ := strconv.ParseInt(tgIDString(link["tgUserId"]), 10, 64)
	return tg, nil
}

// StartGameBot ghi intent cho tg của uid rồi trả link tạo bot của Telegram.
// Bấm lại thì gia hạn intent.
func (m *ManagedBotService) StartGameBot(ctx context.Context, uid string) (string, error) {
	tg, err := m.linkedTg(ctx, uid)
	if err != nil {
		return "", err
	}
	if tg == 0 {
		return "", errGameBotNoLink
	}
	if _, err := m.gameIntentRef(tg).Set(ctx, map[string]any{"uid": uid, "expiresAt": m.now().Add(gameBotIntentTTL)}); err != nil {
		return "", err
	}
	return managedCreateURL(m.username, suggestBotUsername("van", uid), gameBotName), nil
}

// gameBotOwner cho biết update managed_bot này có phải của bot ván không, và
// uid sẽ giữ bot. game true, uid rỗng: bot ván đã đổi chủ trên Telegram, cần
// gỡ.
func (m *ManagedBotService) gameBotOwner(ctx context.Context, ownerTg, botID int64) (uid string, game bool, err error) {
	cur, ok, err := m.bot(ctx, strconv.FormatInt(botID, 10))
	if err != nil {
		return "", false, err
	}
	if ok {
		if cur.Kind != managedKindGame {
			return "", false, nil
		}
		if cur.Retired || cur.OwnerTgID != ownerTg {
			return "", true, nil
		}
		return cur.UID, true, nil
	}
	intent, err := getData(ctx, m.gameIntentRef(ownerTg))
	if err != nil || intent == nil || !m.now().Before(timeValue(intent["expiresAt"])) {
		return "", false, err
	}
	return stringValue(intent["uid"]), true, nil
}

// LinkGameBot nối bot botID làm bot ván của uid; uid rỗng là gỡ bot. Bot ván
// cũ của uid bị thay. Chạy lại với cùng update thì không ghi gì.
func (m *ManagedBotService) LinkGameBot(ctx context.Context, ownerTg, botID int64, username, uid string) (linkResult, error) {
	wall := m.now()
	id := strconv.FormatInt(botID, 10)
	var res linkResult
	err := m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		res = linkResult{UID: uid}
		snap, err := getOptional(tx, m.botRef(id))
		if err != nil {
			return err
		}
		cur := readManagedBot(snap)
		if uid == "" {
			if !snap.Exists() || cur.Retired {
				return nil
			}
			ptr, err := getOptional(tx, m.gameBotRef(cur.UID))
			if err != nil {
				return err
			}
			if ptr.Exists() && stringValue(ptr.Data()["botId"]) == id {
				if err := tx.Delete(ptr.Ref); err != nil {
					return err
				}
			}
			res.Changed, res.Retired = true, []string{id}
			return tx.Update(snap.Ref, []firestore.Update{{Path: "replacedAt", Value: wall}, {Path: "updatedAt", Value: wall}})
		}
		ptr, err := getOptional(tx, m.gameBotRef(uid))
		if err != nil {
			return err
		}
		oldBot := ""
		if ptr.Exists() {
			oldBot = stringValue(ptr.Data()["botId"])
		}
		var old *firestore.DocumentSnapshot
		if oldBot != "" && oldBot != id {
			if old, err = getOptional(tx, m.botRef(oldBot)); err != nil {
				return err
			}
		}
		if snap.Exists() && !cur.Retired && cur.UID == uid && oldBot == id &&
			stringValue(snap.Data()["username"]) == username && stringValue(ptr.Data()["username"]) == username {
			return nil
		}
		res.Changed = true
		if old != nil && old.Exists() && readManagedBot(old).UID == uid {
			if err := tx.Update(old.Ref, []firestore.Update{{Path: "replacedAt", Value: wall}, {Path: "updatedAt", Value: wall}}); err != nil {
				return err
			}
			res.Retired = append(res.Retired, oldBot)
		}
		created, linked := wall, wall
		if t, ok := snap.Data()["createdAt"].(time.Time); ok && cur.UID == uid {
			created = t
		}
		if t, ok := ptr.Data()["linkedAt"].(time.Time); ok && oldBot == id {
			linked = t
		}
		if err := tx.Set(m.botRef(id), map[string]any{"kind": managedKindGame, "uid": uid, "username": username,
			"ownerTgId": ownerTg, "createdAt": created, "updatedAt": wall}); err != nil {
			return err
		}
		if err := tx.Set(m.gameBotRef(uid), map[string]any{"botId": id, "username": username, "linkedAt": linked}); err != nil {
			return err
		}
		return tx.Delete(m.gameIntentRef(ownerTg))
	})
	return res, err
}

// syncGameBot đặt webhook cho bot ván. Tên bot do chủ đặt lúc tạo trên
// Telegram nên không đặt lại.
func (m *ManagedBotService) syncGameBot(ctx context.Context, info managedBotInfo) error {
	err := m.callBot(ctx, info.ID, func(tg *TelegramService) error {
		return setupCall(ctx, tg, info.ID, "setWebhook", map[string]any{
			"url": m.childWebhookURL(info.ID), "secret_token": m.childSecret(info.ID), "allowed_updates": managedAllowedUpdates,
		})
	})
	if err != nil {
		slog.ErrorContext(ctx, "game.bot_setup_failed", "botId", info.ID, "uid", info.UID, "error", err)
	}
	if recErr := m.recordGameSetup(ctx, info, err); recErr != nil {
		return recErr
	}
	if err != nil && !permanentTelegramErr(err) {
		return err
	}
	return nil
}

func (m *ManagedBotService) recordGameSetup(ctx context.Context, info managedBotInfo, setupErr error) error {
	wall := m.now()
	return m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		ptr, err := getOptional(tx, m.gameBotRef(info.UID))
		if err != nil || !ptr.Exists() || stringValue(ptr.Data()["botId"]) != info.ID {
			return err
		}
		if setupErr != nil {
			return tx.Update(ptr.Ref, []firestore.Update{{Path: "setupError", Value: setupErrorText(setupErr)}})
		}
		return tx.Update(ptr.Ref, []firestore.Update{{Path: "setupError", Value: firestore.Delete}, {Path: "setupAt", Value: wall}})
	})
}

// GameTelegramTarget là nơi ván đăng tin: group và topic (0 là General hay
// group không chia topic).
type GameTelegramTarget struct {
	ChatID   string `json:"chatId"`
	ThreadID int64  `json:"threadId"`
}

// gameBotTarget kiểm nơi uid chọn cho ván: bot ván của uid đang là admin ở
// group đó và chủ đã /van trong topic đó. Trả botId. Chỉ đọc Firestore, vì
// api không giữ token bot; state đã ghi từ chính sự kiện Telegram gửi bot.
func gameBotTarget(ctx context.Context, db *firestore.Client, uid string, t GameTelegramTarget) (string, error) {
	ptr, err := getData(ctx, db.Collection("gameBots").Doc(uid))
	if err != nil {
		return "", err
	}
	botID := stringValue(ptr["botId"])
	if botID == "" {
		return "", errGameBotMissing
	}
	if _, err := strconv.ParseInt(t.ChatID, 10, 64); err != nil {
		return "", errGameBotChat
	}
	chat, err := getData(ctx, db.Collection("managedBots").Doc(botID).Collection("chats").Doc(t.ChatID))
	if err != nil {
		return "", err
	}
	if stringValue(chat["status"]) != "administrator" {
		return "", errGameBotChat
	}
	topics, _ := chat["topics"].(map[string]any)
	if _, ok := topics[strconv.FormatInt(t.ThreadID, 10)]; !ok {
		return "", errGameBotTopic
	}
	return botID, nil
}

// gameInPsc: ván đăng vào PSC bằng 3i, nên người chơi phải ở PSC. Ván của bot
// ván không xét PSC: lúc Start bot ván hỏi group của ván.
func gameInPsc(g map[string]any, cfg werewolf.Config) bool {
	return !cfg.NoTelegram && stringValue(g["botId"]) == ""
}

// gameRequirements là điều kiện đăng ký của ván g: như requirementsFor, bỏ
// điều kiện ở PSC với ván của bot ván.
func gameRequirements(link viewerLink, appVersion string, cfg gameConfig, g map[string]any, gc werewolf.Config) []GameRequirement {
	reqs := requirementsFor(link, appVersion, cfg, !gc.NoTelegram)
	if gc.NoTelegram || gameInPsc(g, gc) {
		return reqs
	}
	out := make([]GameRequirement, 0, len(reqs))
	for _, r := range reqs {
		if r.Key != "in_psc" {
			out = append(out, r)
		}
	}
	return out
}

// gameMemberCheck hỏi bot ván botID một tg có đang ở chatID không.
func (m *ManagedBotService) gameMemberCheck(botID, chatID string) pscMembership {
	return func(ctx context.Context, tg int64) (bool, error) {
		var in bool
		err := m.callBot(ctx, botID, func(t *TelegramService) error {
			mem, err := t.GetChatMember(ctx, chatID, tg)
			in = mem.InChat()
			return err
		})
		return in, err
	}
}

// managedOutbox là outboxTelegram của bot ván: gọi qua callBot để token đổi
// trên Telegram thì lấy lại token mới.
type managedOutbox struct {
	m     *ManagedBotService
	botID string
}

func (m *ManagedBotService) gameOutbox(botID string) outboxTelegram {
	return managedOutbox{m: m, botID: botID}
}

func (o managedOutbox) SendText(ctx context.Context, t TelegramText) (int64, error) {
	var id int64
	err := o.m.callBot(ctx, o.botID, func(tg *TelegramService) error {
		var err error
		id, err = tg.SendText(ctx, t)
		return err
	})
	return id, err
}

func (o managedOutbox) EditText(ctx context.Context, chatID string, messageID int64, text string, html bool, markup any) error {
	return o.m.callBot(ctx, o.botID, func(tg *TelegramService) error {
		return tg.EditText(ctx, chatID, messageID, text, html, markup)
	})
}

// ---- Trạng thái cho app ----

// GameTelegram là GET /v1/games/telegram: bot ván của người gọi và các group
// bot đang ở, kèm topic chủ đã xác nhận bằng /van.
type GameTelegram struct {
	TelegramLinked bool          `json:"telegramLinked"`
	Bot            *GameBot      `json:"bot"`
	Chats          []GameBotChat `json:"chats"`
}

type GameBot struct {
	Username   string `json:"username"`
	SetupError string `json:"setupError,omitempty"`
	// AddURL mở màn chọn group của Telegram, xin sẵn quyền admin cho bot.
	AddURL string `json:"addUrl"`
}

type GameBotChat struct {
	ChatID string `json:"chatId"`
	Title  string `json:"title"`
	Admin  bool   `json:"admin"`
	Forum  bool   `json:"forum"`
	// Topics là nơi chủ đã gõ /van, mới nhất trước; threadId 0 là General hay
	// group không chia topic.
	Topics []GameBotTopic `json:"topics"`
}

type GameBotTopic struct {
	ThreadID int64  `json:"threadId"`
	Name     string `json:"name,omitempty"`
}

func gameBotAddURL(username string) string {
	return "https://t.me/" + username + "?startgroup=van&admin=manage_topics"
}

func (m *ManagedBotService) GameStatus(ctx context.Context, uid string) (*GameTelegram, error) {
	tg, err := m.linkedTg(ctx, uid)
	if err != nil {
		return nil, err
	}
	out := &GameTelegram{TelegramLinked: tg != 0, Chats: []GameBotChat{}}
	ptr, err := getData(ctx, m.gameBotRef(uid))
	if err != nil || ptr == nil {
		return out, err
	}
	botID, username := stringValue(ptr["botId"]), stringValue(ptr["username"])
	out.Bot = &GameBot{Username: username, SetupError: stringValue(ptr["setupError"]), AddURL: gameBotAddURL(username)}
	docs, err := m.botRef(botID).Collection("chats").Where("status", "in", []string{"member", "administrator"}).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		out.Chats = append(out.Chats, readGameChat(d.Ref.ID, d.Data()))
	}
	sort.Slice(out.Chats, func(i, j int) bool { return out.Chats[i].Title < out.Chats[j].Title })
	return out, nil
}

func readGameChat(chatID string, data map[string]any) GameBotChat {
	c := GameBotChat{ChatID: chatID, Title: stringValue(data["title"]), Admin: stringValue(data["status"]) == "administrator",
		Forum: data["forum"] == true, Topics: []GameBotTopic{}}
	topics, _ := data["topics"].(map[string]any)
	at := map[int64]time.Time{}
	for k, v := range topics {
		thread, err := strconv.ParseInt(k, 10, 64)
		if err != nil {
			continue
		}
		t, _ := v.(map[string]any)
		c.Topics = append(c.Topics, GameBotTopic{ThreadID: thread, Name: stringValue(t["name"])})
		at[thread] = timeValue(t["at"])
	}
	sort.Slice(c.Topics, func(i, j int) bool { return at[c.Topics[i].ThreadID].After(at[c.Topics[j].ThreadID]) })
	return c
}

// ---- Webhook ----

// linkGameBot là nhánh bot ván của update managed_bot: nối (hay gỡ) rồi hẹn
// Sync. Bot cũ hẹn gỡ webhook trước, như nhánh MyBot.
func (s *Server) linkGameBot(ctx context.Context, m *ManagedBotService, updateID, ownerTg, botID int64, username, uid string) error {
	res, err := m.LinkGameBot(ctx, ownerTg, botID, username, uid)
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "game.bot_linked", "uid", uid, "botId", botID, "changed", res.Changed, "retired", res.Retired)
	for _, old := range res.Retired {
		if _, err := m.publish(ctx, managedSyncTaskFor(old, "retired")); err != nil {
			return err
		}
	}
	if uid == "" {
		return nil
	}
	_, err = m.publish(ctx, managedSyncTaskFor(strconv.FormatInt(botID, 10), strconv.FormatInt(updateID, 10)))
	return err
}

// gameBotChildUpdate là update tới webhook của bot ván.
func (s *Server) gameBotChildUpdate(ctx context.Context, m *ManagedBotService, info managedBotInfo, u childUpdate) error {
	if mc := u.MyChatMember; mc != nil && mc.Chat.Type != "private" {
		return m.gameMembership(ctx, info, u.UpdateID, strconv.FormatInt(mc.Chat.ID, 10), mc.Chat.Type, mc.Chat.Title, mc.Chat.IsForum, mc.From.ID, mc.NewChatMember.Status)
	}
	msg := u.Message
	if msg == nil || msg.From == nil || msg.From.ID != info.OwnerTgID || msg.Chat.Type == "private" || !gameBotCommandFor(msg.Text, info.Username) {
		return nil
	}
	var thread int64
	if msg.IsTopicMessage {
		thread = msg.MessageThreadID
	}
	name := ""
	if msg.ReplyTo != nil && msg.ReplyTo.ForumTopicCreated != nil {
		name = msg.ReplyTo.ForumTopicCreated.Name
	}
	if err := m.confirmGameTopic(ctx, info, u.UpdateID, strconv.FormatInt(msg.Chat.ID, 10), thread, name); err != nil {
		return &mybotRetryErr{err}
	}
	return nil
}

// gameBotCommandFor: text là lệnh /van, gõ trống hay kèm @username của bot
// này. Bot ván là admin nên nhận cả lệnh gửi cho bot khác trong group.
func gameBotCommandFor(text, username string) bool {
	cmd, _, _ := strings.Cut(strings.TrimSpace(text), " ")
	return cmd == gameBotCommand || (username != "" && strings.EqualFold(cmd, gameBotCommand+"@"+username))
}

const gameTopicConfirmed = "Ván Ma Sói sẽ đăng vào đây. Mở app 3i Run, chọn chỗ này khi tạo ván."

// confirmGameTopic ghi topic chủ vừa gõ /van vào group đã ghi của bot, rồi
// trả lời ngay trong topic đó. Group chưa ghi (bot không ở đó, hay người lạ
// thêm) thì bỏ qua.
func (m *ManagedBotService) confirmGameTopic(ctx context.Context, info managedBotInfo, updateID int64, chatID string, thread int64, name string) error {
	ref := m.gameChatRef(info.ID, chatID)
	cur, err := getData(ctx, ref)
	if err != nil {
		return err
	}
	if st := stringValue(cur["status"]); st != "member" && st != "administrator" {
		slog.InfoContext(ctx, "game.bot_topic_unknown_chat", "botId", info.ID, "chatId", chatID)
		return nil
	}
	// Telegram gửi lại update thì ghi lại cùng topic; tin trả lời có key cố
	// định theo update nên không gửi đôi.
	key := strconv.FormatInt(thread, 10)
	ups := []firestore.Update{
		{FieldPath: firestore.FieldPath{"topics", key, "at"}, Value: m.now()},
		{FieldPath: firestore.FieldPath{"topics", key, "by"}, Value: info.OwnerTgID},
	}
	if name != "" {
		// Tin reply một tin khác trong topic thì không mang tên topic: giữ tên cũ.
		ups = append(ups, firestore.Update{FieldPath: firestore.FieldPath{"topics", key, "name"}, Value: name})
	}
	if _, err = ref.Update(ctx, ups); err != nil {
		return err
	}
	if err := m.enqueueReply(ctx, info.ID, "van-"+strconv.FormatInt(updateID, 10), managedOut{chatID: chatID, threadID: thread, text: gameTopicConfirmed}); err != nil {
		return err
	}
	slog.InfoContext(ctx, "game.bot_topic_confirmed", "botId", info.ID, "uid", info.UID, "chatId", chatID, "threadId", thread)
	return nil
}

// gameMembership ghi bot ván vào hay ra một group. Group chỉ được ghi khi
// chính chủ thêm bot; người khác thêm thì bot rời, để ván không đăng được vào
// group chủ không chọn. Bot đã ở group thì đổi quyền do ai làm cũng ghi. Bot
// ra khỏi group thì bỏ các topic đã xác nhận: vào lại phải /van lại.
func (m *ManagedBotService) gameMembership(ctx context.Context, info managedBotInfo, updateID int64, chatID, chatType, title string, forum bool, by int64, newStatus string) error {
	ref := m.gameChatRef(info.ID, chatID)
	cur, err := getData(ctx, ref)
	if err != nil {
		return err
	}
	joined := newStatus == "member" || newStatus == "administrator"
	if cur == nil {
		if !joined {
			return nil
		}
		if by != info.OwnerTgID {
			slog.WarnContext(ctx, "game.bot_added_by_stranger", "botId", info.ID, "chatId", chatID, "addedBy", by)
			return m.enqueueManagedLeave(ctx, info.ID, chatID, "leave-"+chatID+"-"+strconv.FormatInt(updateID, 10))
		}
	}
	doc := map[string]any{"title": title, "type": chatType, "forum": forum, "status": newStatus, "at": m.now()}
	if cur == nil {
		doc["addedBy"] = by
	}
	if !joined {
		doc["topics"] = firestore.Delete
	}
	slog.InfoContext(ctx, "game.bot_membership", "botId", info.ID, "uid", info.UID, "chatId", chatID, "status", newStatus, "by", by)
	_, err = ref.Set(ctx, doc, firestore.MergeAll)
	return err
}

// ---- Route ----

func (s *Server) gameTgBotRoutes() {
	s.route("GET /v1/games/telegram", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		if s.deps.ManagedBots == nil {
			return errMybotOff
		}
		out, err := s.deps.ManagedBots.GameStatus(r.Context(), v.UID)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, out)
	}))
	s.route("POST /v1/games/telegram/bot", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		if s.deps.ManagedBots == nil {
			return errMybotOff
		}
		u, err := s.deps.ManagedBots.StartGameBot(r.Context(), v.UID)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"createUrl": u})
	}))
}
