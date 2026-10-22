package backend

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"cloud.google.com/go/firestore"
	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// MyBot trên Telegram (Pha T): mỗi MyBot là một bot Telegram thật, tạo qua
// Managed Bots với 3i là bot quản lý. Người dùng bấm link t.me/newbot/<3i>/...
// rồi tự xác nhận trên Telegram; webhook của 3i nhận update managed_bot, nối bot
// con với uid qua tgLinks, rồi task trên bot đặt webhook, tên và mô tả cho bot
// con. Mọi lời gọi Telegram chạy trên bot service, nơi có token 3i.
//
//	managedBots/{botId}                       uid, username, ownerTgId, createdAt, updatedAt,
//	                                          replacedAt, syncedName, syncedDescription, syncedAt
//	managedBots/{botId}/tgUpdates/{updateId}  update đã nhận, chống xử lý hai lần (TTL expiresAt)
//	managedBots/{botId}/tgOutbox/{key}        tin bot con gửi đi (TTL expiresAt)
//	agents/{uid}.telegram                     botId, username, linkedAt, setupAt, setupError
//
// Không lưu token bot con: lấy bằng getManagedBotToken khi cần và cache trong
// bộ nhớ của instance; Telegram trả 401 thì bỏ cache và lấy lại một lần.
// Webhook của mọi bot con về chung một route, secret của từng bot là HMAC của
// TELEGRAM_WEBHOOK_SECRET theo botId, nên cũng không phải lưu secret.

const (
	managedUpdateTTL = 7 * 24 * time.Hour
	managedOutboxTTL = 30 * 24 * time.Hour

	managedOpSend  = "send"
	managedOpLeave = "leave"

	managedMinUsername = 5
	managedMaxUsername = 32
)

// Bot con chỉ nhận tin riêng và việc bị thêm vào group (T7 bản 1).
var managedAllowedUpdates = []string{"message", "my_chat_member"}

var (
	errManagedNoLink  = errors.New("mybot: tài khoản Telegram chưa liên kết với 3i Run")
	errManagedNoAgent = errors.New("mybot: chủ chưa tạo MyBot trong app")
	errManagedBusy    = errors.New("mybot: tin đang được instance khác gửi")
)

type ManagedBotService struct {
	db *firestore.Client
	// manager là client của bot quản lý; bot con lấy client qua forBot.
	manager       *TelegramService
	username      string
	rootSecret    string
	publicBaseURL string
	publish       taskPublishFunc
	now           func() time.Time
	// chatID là group PSC, nơi có topic Phòng bot; rỗng thì bot con không gửi
	// tin phòng ra Telegram.
	chatID string

	mu     sync.Mutex
	tokens map[string]string // botId → token đang cache
}

func NewManagedBotService(db *firestore.Client, manager *TelegramService, username, rootSecret, publicBaseURL string, publish taskPublishFunc) *ManagedBotService {
	return &ManagedBotService{db: db, manager: manager, username: username, rootSecret: rootSecret,
		publicBaseURL: publicBaseURL, publish: publish, now: time.Now, tokens: map[string]string{}}
}

func (m *ManagedBotService) botRef(botID string) *firestore.DocumentRef {
	return m.db.Collection("managedBots").Doc(botID)
}

func (m *ManagedBotService) agentRef(uid string) *firestore.DocumentRef {
	return m.db.Collection("agents").Doc(uid)
}

// ---- Secret webhook ----

func webhookHMAC(root, msg string) string {
	h := hmac.New(sha256.New, []byte(root))
	h.Write([]byte(msg))
	return hex.EncodeToString(h.Sum(nil))
}

// childSecret là secret_token webhook của bot con: 64 ký tự hex, nằm trong bộ
// ký tự Telegram cho phép, và khác hẳn secret gốc mà webhook 3i dùng.
func (m *ManagedBotService) childSecret(botID string) string {
	return webhookHMAC(m.rootSecret, "managed:"+botID)
}

func secretMatches(got, want string) bool {
	return want != "" && subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

func (m *ManagedBotService) childWebhookURL(botID string) string {
	return m.publicBaseURL + "/v1/telegram/managed/" + botID + "/webhook"
}

// ---- Token bot con ----

// logSetupCall ghi kết quả mỗi lời gọi Telegram khi dựng bot con, prefix
// mybot.setup để grep được trên log prod. Lần chạy thật đầu tiên là PoC của
// Managed Bots: log cho biết hàm nào Telegram nhận, hàm nào từ chối. Không
// bao giờ ghi token: TelegramAPIError chỉ có method, status và description.
func logSetupCall(ctx context.Context, botID, method string, err error) {
	if err != nil {
		slog.WarnContext(ctx, "mybot.setup", "botId", botID, "method", method, "ok", false, "error", err.Error())
		return
	}
	slog.InfoContext(ctx, "mybot.setup", "botId", botID, "method", method, "ok", true)
}

// setupCall là callAPI của bot con kèm logSetupCall.
func setupCall(ctx context.Context, tg *TelegramService, botID, method string, params map[string]any) error {
	err := tg.callAPI(ctx, method, params, nil)
	logSetupCall(ctx, botID, method, err)
	return err
}

// forBot trả client của bot con botID, token lấy từ cache hoặc từ bot quản lý.
func (m *ManagedBotService) forBot(ctx context.Context, botID string) (*TelegramService, error) {
	m.mu.Lock()
	tok := m.tokens[botID]
	m.mu.Unlock()
	if tok == "" {
		id, err := strconv.ParseInt(botID, 10, 64)
		if err != nil {
			return nil, fmt.Errorf("mybot: botId %q không phải số", botID)
		}
		err = m.manager.callAPI(ctx, "getManagedBotToken", map[string]any{"user_id": id}, &tok)
		if err == nil && tok == "" {
			err = errors.New("mybot: getManagedBotToken trả token rỗng")
		}
		logSetupCall(ctx, botID, "getManagedBotToken", err)
		if err != nil {
			return nil, err
		}
		m.mu.Lock()
		m.tokens[botID] = tok
		m.mu.Unlock()
	}
	return m.manager.withToken(tok), nil
}

// dropToken bỏ token đã cache, chỉ khi cache vẫn là token vừa bị từ chối, để
// không xoá token mới mà request khác vừa lấy về.
func (m *ManagedBotService) dropToken(botID, tok string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.tokens[botID] == tok {
		delete(m.tokens, botID)
	}
}

// callBot chạy fn bằng client của bot con. Telegram trả 401 (token đã bị thay,
// hay người dùng đổi token trong BotFather) thì bỏ cache, lấy token mới và chạy
// lại đúng một lần.
func (m *ManagedBotService) callBot(ctx context.Context, botID string, fn func(*TelegramService) error) error {
	tg, err := m.forBot(ctx, botID)
	if err != nil {
		return err
	}
	err = fn(tg)
	var te *TelegramAPIError
	if !errors.As(err, &te) || te.Status != 401 {
		return err
	}
	slog.WarnContext(ctx, "mybot.token_refetch", "botId", botID)
	m.dropToken(botID, tg.botToken)
	if tg, err = m.forBot(ctx, botID); err != nil {
		return err
	}
	return fn(tg)
}

// ---- Nối bot con với uid ----

// managedBotInfo là managedBots/{botId} đã đọc.
type managedBotInfo struct {
	ID        string
	UID       string
	OwnerTgID int64
	Retired   bool
}

func readManagedBot(d *firestore.DocumentSnapshot) managedBotInfo {
	if d == nil || !d.Exists() {
		return managedBotInfo{}
	}
	tg, _ := strconv.ParseInt(tgIDString(d.Data()["ownerTgId"]), 10, 64)
	_, retired := d.Data()["replacedAt"]
	return managedBotInfo{ID: d.Ref.ID, UID: stringValue(d.Data()["uid"]), OwnerTgID: tg, Retired: retired}
}

// bot đọc managedBots/{botId}; không có thì ok false.
func (m *ManagedBotService) bot(ctx context.Context, botID string) (managedBotInfo, bool, error) {
	d, err := m.botRef(botID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return managedBotInfo{}, false, nil
	}
	if err != nil {
		return managedBotInfo{}, false, err
	}
	return readManagedBot(d), true, nil
}

// linkResult: Retired là các bot không còn thuộc ai sau lần nối này (bot cũ của
// uid, hay chính bot này khi chủ mới chưa liên kết), cần gỡ webhook.
type linkResult struct {
	UID     string
	Changed bool
	Retired []string
	// InPsc: sau lần nối này bot vẫn đang ở PSC (cùng bot, chỉ đổi token hay
	// username).
	InPsc bool
}

// Link xử lý update managed_bot: ownerTg vừa tạo bot botID, đổi token, hoặc
// thành chủ mới của bot. Chạy lại với cùng update thì không ghi gì thêm.
//   - tg chưa liên kết uid: errManagedNoLink. Bot đang thuộc người khác thì bị
//     gỡ khỏi người đó (chủ trên Telegram đã đổi), nhưng không nối với ai.
//   - uid chưa tạo MyBot: errManagedNoAgent, không ghi gì.
//   - uid đã có bot khác: bot mới thắng, bot cũ ghi replacedAt.
//   - bot đang thuộc uid khác: chuyển sang uid mới, gỡ agents/{uid cũ}.telegram.
func (m *ManagedBotService) Link(ctx context.Context, ownerTg, botID int64, username string, links *TelegramLinkService) (linkResult, error) {
	wall := m.now()
	id := strconv.FormatInt(botID, 10)
	uid, err := links.UIDForTelegram(ctx, ownerTg)
	if err != nil {
		return linkResult{}, err
	}
	var res linkResult
	err = m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		res = linkResult{UID: uid}
		snap, err := getOptional(tx, m.botRef(id))
		if err != nil {
			return err
		}
		cur := readManagedBot(snap)
		if uid == "" {
			// Chỉ gỡ khi chủ trên Telegram thật sự đổi. Cùng chủ mà tg đã huỷ
			// liên kết trong app (update đổi token) thì giữ bot cho chủ cũ.
			if !snap.Exists() || cur.Retired || cur.OwnerTgID == ownerTg {
				return nil
			}
			if err := m.unlinkAgent(tx, cur.UID, id); err != nil {
				return err
			}
			if err := tx.Update(m.botRef(id), []firestore.Update{{Path: "replacedAt", Value: wall}, {Path: "updatedAt", Value: wall}}); err != nil {
				return err
			}
			res.Changed, res.Retired = true, []string{id}
			return nil
		}
		agent, err := getOptional(tx, m.agentRef(uid))
		if err != nil {
			return err
		}
		if !agent.Exists() {
			return errManagedNoAgent
		}
		tgField, _ := agent.Data()["telegram"].(map[string]any)
		oldBot := stringValue(tgField["botId"])
		var old *firestore.DocumentSnapshot
		if oldBot != "" && oldBot != id {
			if old, err = getOptional(tx, m.botRef(oldBot)); err != nil {
				return err
			}
		}
		var prevAgent *firestore.DocumentSnapshot
		if cur.UID != "" && cur.UID != uid {
			if prevAgent, err = getOptional(tx, m.agentRef(cur.UID)); err != nil {
				return err
			}
		}
		// Cùng chủ, cùng username, uid đang trỏ đúng bot này: update gửi lại.
		if snap.Exists() && !cur.Retired && cur.UID == uid && cur.OwnerTgID == ownerTg &&
			stringValue(snap.Data()["username"]) == username && oldBot == id && stringValue(tgField["username"]) == username {
			return nil
		}
		res.Changed = true
		// Hết đọc; từ đây chỉ ghi.
		if old != nil && old.Exists() && readManagedBot(old).UID == uid {
			if err := tx.Update(old.Ref, []firestore.Update{{Path: "replacedAt", Value: wall}, {Path: "updatedAt", Value: wall}}); err != nil {
				return err
			}
			res.Retired = append(res.Retired, oldBot)
		}
		if prevAgent != nil && prevAgent.Exists() {
			if prev, _ := prevAgent.Data()["telegram"].(map[string]any); stringValue(prev["botId"]) == id {
				if err := tx.Update(prevAgent.Ref, []firestore.Update{{Path: "telegram", Value: firestore.Delete}}); err != nil {
					return err
				}
			}
		}
		doc := map[string]any{"uid": uid, "username": username, "ownerTgId": ownerTg, "createdAt": wall, "updatedAt": wall}
		sameOwner := snap.Exists() && !cur.Retired && cur.UID == uid
		if sameOwner {
			// Giữ createdAt và các field synced*: chỉ đổi token hay username.
			if t, ok := snap.Data()["createdAt"].(time.Time); ok {
				doc["createdAt"] = t
			}
			for _, k := range []string{"syncedName", "syncedDescription", "syncedAt"} {
				if v, ok := snap.Data()[k]; ok {
					doc[k] = v
				}
			}
		}
		// Set không merge: bot đổi chủ thì bỏ replacedAt và synced* của chủ cũ,
		// để tên và mô tả được đặt lại theo MyBot của chủ mới.
		if err := tx.Set(m.botRef(id), doc); err != nil {
			return err
		}
		link := map[string]any{"botId": id, "username": username, "linkedAt": wall}
		if oldBot == id {
			if t, ok := tgField["linkedAt"].(time.Time); ok {
				link["linkedAt"] = t
			}
			// Đổi token hay username không đưa bot ra khỏi PSC.
			for _, k := range []string{"inPsc", "pscAt"} {
				if v, ok := tgField[k]; ok {
					link[k] = v
				}
			}
		}
		res.InPsc = link["inPsc"] == true
		return tx.Update(agent.Ref, []firestore.Update{{Path: "telegram", Value: link}})
	})
	if err == nil && uid == "" {
		// Trả kèm res: bot có thể vừa bị gỡ khỏi chủ cũ, cần gỡ webhook.
		err = errManagedNoLink
	}
	return res, err
}

// unlinkAgent gỡ agents/{uid}.telegram nếu nó còn trỏ botID. Gọi trong
// transaction, trước mọi lần ghi khác vì có đọc.
func (m *ManagedBotService) unlinkAgent(tx *firestore.Transaction, uid, botID string) error {
	if uid == "" {
		return nil
	}
	agent, err := getOptional(tx, m.agentRef(uid))
	if err != nil || !agent.Exists() {
		return err
	}
	if tg, _ := agent.Data()["telegram"].(map[string]any); stringValue(tg["botId"]) != botID {
		return nil
	}
	return tx.Update(agent.Ref, []firestore.Update{{Path: "telegram", Value: firestore.Delete}})
}

// ---- Đặt webhook, tên, mô tả cho bot con ----

type managedSyncTask struct {
	BotID string `json:"botId"`
}

// managedSyncTaskFor: key rỗng là không đặt TaskID, mỗi lần gọi một task (đổi
// tên trong app). Task đọc state hiện tại nên chạy thừa không sao.
func managedSyncTaskFor(botID, key string) PublishTask {
	t := PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/managed-bot-sync", Payload: managedSyncTask{BotID: botID}}
	if key != "" {
		t.TaskID = StableTaskID("mbot-sync", []any{botID, key})
	}
	return t
}

// Sync đưa bot con về đúng state trong Firestore. Bot còn chủ: setWebhook về
// route chung, rồi setMyName và setMyDescription nếu khác lần đặt trước. Bot đã
// bị thay hay không còn bản ghi: deleteWebhook. Lỗi Telegram 4xx (bot bị xoá,
// tên không hợp lệ) thì ghi setupError rồi thôi; lỗi mạng, 429, 5xx thì trả
// lỗi để task chạy lại.
func (m *ManagedBotService) Sync(ctx context.Context, botID string) error {
	info, ok, err := m.bot(ctx, botID)
	if err != nil {
		return err
	}
	if !ok || info.Retired {
		err := m.callBot(ctx, botID, func(tg *TelegramService) error {
			return setupCall(ctx, tg, botID, "deleteWebhook", map[string]any{})
		})
		if err != nil && !permanentTelegramErr(err) {
			return err
		}
		slog.InfoContext(ctx, "mybot.webhook_removed", "botId", botID, "error", errString(err))
		return nil
	}
	agent, err := getData(ctx, m.agentRef(info.UID))
	if err != nil {
		return err
	}
	if agent == nil {
		return nil // chủ đã xoá tài khoản
	}
	profile, err := getData(ctx, m.db.Collection("publicProfiles").Doc(info.UID))
	if err != nil {
		return err
	}
	snap, err := m.botRef(botID).Get(ctx)
	if err != nil {
		return err
	}
	name := stringValue(agent["name"])
	desc := managedBotDescription(stringValue(profile["displayName"]))
	var synced []firestore.Update
	err = m.callBot(ctx, botID, func(tg *TelegramService) error {
		synced = synced[:0]
		if err := setupCall(ctx, tg, botID, "setWebhook", map[string]any{
			"url": m.childWebhookURL(botID), "secret_token": m.childSecret(botID), "allowed_updates": managedAllowedUpdates,
		}); err != nil {
			return err
		}
		if name != "" && name != stringValue(snap.Data()["syncedName"]) {
			if err := setupCall(ctx, tg, botID, "setMyName", map[string]any{"name": name}); err != nil {
				return err
			}
			synced = append(synced, firestore.Update{Path: "syncedName", Value: name})
		}
		if desc != stringValue(snap.Data()["syncedDescription"]) {
			if err := setupCall(ctx, tg, botID, "setMyDescription", map[string]any{"description": desc}); err != nil {
				return err
			}
			synced = append(synced, firestore.Update{Path: "syncedDescription", Value: desc})
		}
		return nil
	})
	if err != nil {
		slog.ErrorContext(ctx, "mybot.setup_failed", "botId", botID, "uid", info.UID, "error", err)
		if recErr := m.recordSetup(ctx, info.UID, botID, synced, err); recErr != nil {
			return recErr
		}
		if permanentTelegramErr(err) {
			return nil
		}
		return err
	}
	return m.recordSetup(ctx, info.UID, botID, synced, nil)
}

// recordSetup ghi kết quả Sync: phần đã đặt xong lên managedBots, setupError
// lên agents/{uid}.telegram (chỉ khi uid vẫn trỏ bot này).
func (m *ManagedBotService) recordSetup(ctx context.Context, uid, botID string, synced []firestore.Update, setupErr error) error {
	wall := m.now()
	return m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		agent, err := getOptional(tx, m.agentRef(uid))
		if err != nil {
			return err
		}
		b, err := getOptional(tx, m.botRef(botID))
		if err != nil {
			return err
		}
		if b.Exists() && readManagedBot(b).UID == uid && len(synced) > 0 {
			if err := tx.Update(b.Ref, append(synced, firestore.Update{Path: "syncedAt", Value: wall})); err != nil {
				return err
			}
		}
		if !agent.Exists() {
			return nil
		}
		if tg, _ := agent.Data()["telegram"].(map[string]any); stringValue(tg["botId"]) != botID {
			return nil
		}
		if setupErr != nil {
			return tx.Update(agent.Ref, []firestore.Update{{FieldPath: firestore.FieldPath{"telegram", "setupError"}, Value: setupErrorText(setupErr)}})
		}
		return tx.Update(agent.Ref, []firestore.Update{
			{FieldPath: firestore.FieldPath{"telegram", "setupError"}, Value: firestore.Delete},
			{FieldPath: firestore.FieldPath{"telegram", "setupAt"}, Value: wall},
		})
	})
}

func managedBotDescription(owner string) string {
	owner = strings.TrimSpace(owner)
	if owner == "" {
		owner = "một thành viên"
	}
	return fmt.Sprintf("Bot cá nhân của %s trên 3i Run. Chỉ chủ bot nhắn riêng được với bot.", owner)
}

// setupErrorText là chữ hiện cho app: mô tả lỗi của Telegram, không có token.
func setupErrorText(err error) string {
	var te *TelegramAPIError
	if errors.As(err, &te) {
		return fmt.Sprintf("%s: %s", te.Method, te.Description)
	}
	return "Telegram chưa trả lời, đang thử lại"
}

// permanentTelegramErr: Telegram từ chối hẳn (4xx trừ 429), gọi lại cũng vậy.
func permanentTelegramErr(err error) bool {
	var te *TelegramAPIError
	return errors.As(err, &te) && te.Status >= 400 && te.Status < 500 && te.Status != 429
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// ProfileChanged: chủ vừa sửa hồ sơ MyBot trong app. Bot đã nối Telegram thì
// hẹn Sync để đổi tên bot con theo. Lỗi chỉ log, không chặn việc lưu hồ sơ.
func (m *ManagedBotService) ProfileChanged(ctx context.Context, uid string) {
	agent, err := getData(ctx, m.agentRef(uid))
	if err != nil {
		slog.WarnContext(ctx, "mybot.rename_sync_failed", "uid", uid, "error", err)
		return
	}
	tg, _ := agent["telegram"].(map[string]any)
	botID := stringValue(tg["botId"])
	if botID == "" {
		return
	}
	if _, err := m.publish(ctx, managedSyncTaskFor(botID, "")); err != nil {
		slog.WarnContext(ctx, "mybot.rename_sync_failed", "uid", uid, "botId", botID, "error", err)
	}
}

// ---- Outbox gửi tin của bot con ----

// Mỗi tin là một doc với ID cố định theo key của người gọi, và một task
// managed-send cùng TaskID. Gọi lại với cùng key thì không tạo tin mới, nên
// webhook nhận lại update hay task trả lời chạy lại đều không gửi đôi. Claim
// bằng lease 60 giây như outbox Ma Sói; crash giữa lúc gửi và lúc ghi sent thì
// tin được gửi lại, chấp nhận như ở đó. Không giữ thứ tự giữa các tin: chat
// riêng mỗi lượt chỉ có một câu trả lời.

type managedSendTask struct {
	BotID string `json:"botId"`
	Key   string `json:"key"`
}

func managedSendTaskFor(botID, key string) PublishTask {
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/managed-send", Payload: managedSendTask{BotID: botID, Key: key}, TaskID: StableTaskID("mbot-send", []any{botID, key})}
}

func (m *ManagedBotService) outboxRef(botID, key string) *firestore.DocumentRef {
	return m.botRef(botID).Collection("tgOutbox").Doc(strings.ReplaceAll(key, "/", "_"))
}

// enqueueManagedSend xếp tin text gửi từ bot con botID tới chatID. key khoá
// chống gửi đôi: cùng key thì chỉ một tin.
func (m *ManagedBotService) enqueueManagedSend(ctx context.Context, botID, chatID, text, key string) error {
	return m.enqueueOp(ctx, botID, chatID, 0, managedOpSend, text, key)
}

// enqueueManagedLeave xếp việc cho bot con rời chatID.
func (m *ManagedBotService) enqueueManagedLeave(ctx context.Context, botID, chatID, key string) error {
	return m.enqueueOp(ctx, botID, chatID, 0, managedOpLeave, "", key)
}

// enqueueOp ghi một việc vào outbox của bot con. threadID là topic của group
// (0 là General hay chat không có topic).
func (m *ManagedBotService) enqueueOp(ctx context.Context, botID, chatID string, threadID int64, op, text, key string) error {
	wall := m.now()
	ref := m.outboxRef(botID, key)
	doc := map[string]any{
		"chatId": chatID, "op": op, "text": text, "status": outboxPending,
		"createdAt": wall, "expiresAt": wall.Add(managedOutboxTTL),
	}
	if threadID != 0 {
		doc["threadId"] = threadID
	}
	_, err := ref.Create(ctx, doc)
	if status.Code(err) == codes.AlreadyExists {
		// Lần trước có thể đã ghi doc mà enqueue lỗi: còn pending thì enqueue
		// lại, TaskID cố định nên không ra task thứ hai.
		d, getErr := ref.Get(ctx)
		if getErr != nil {
			return getErr
		}
		if stringValue(d.Data()["status"]) != outboxPending {
			return nil
		}
	} else if err != nil {
		return err
	}
	_, err = m.publish(ctx, managedSendTaskFor(botID, key))
	return err
}

// Deliver gửi tin key của bot con botID. Đã gửi hay đã bỏ thì thôi; instance
// khác đang giữ lease thì trả lỗi để task chạy lại sau.
func (m *ManagedBotService) Deliver(ctx context.Context, botID, key string) error {
	ref := m.outboxRef(botID, key)
	owner, err := leaseOwner()
	if err != nil {
		return err
	}
	var msg map[string]any
	err = m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		msg = nil
		d, err := getOptional(tx, ref)
		if err != nil || !d.Exists() {
			return err
		}
		data := d.Data()
		switch stringValue(data["status"]) {
		case outboxSent, outboxFailed:
			return nil
		case outboxSending:
			if m.now().Before(timeValue(data["leaseUntil"])) {
				return errManagedBusy
			}
		}
		msg = data
		return tx.Update(ref, []firestore.Update{
			{Path: "status", Value: outboxSending}, {Path: "lease", Value: owner},
			{Path: "leaseUntil", Value: m.now().Add(outboxLease)}, {Path: "attempts", Value: firestore.Increment(1)},
		})
	})
	if err != nil || msg == nil {
		return err
	}
	chatID := stringValue(msg["chatId"])
	var messageID int64
	sendErr := m.callBot(ctx, botID, func(tg *TelegramService) error {
		if stringValue(msg["op"]) == managedOpLeave {
			return tg.callAPI(ctx, "leaveChat", map[string]any{"chat_id": chatID}, nil)
		}
		id, err := tg.SendText(ctx, TelegramText{ChatID: chatID, ThreadID: int64(number(msg["threadId"])), Text: stringValue(msg["text"])})
		messageID = id
		return err
	})
	outcome := classifySend(sendErr)
	updates := []firestore.Update{{Path: "lease", Value: firestore.Delete}, {Path: "leaseUntil", Value: firestore.Delete}}
	switch outcome {
	case outcomeSent:
		updates = append(updates, firestore.Update{Path: "status", Value: outboxSent}, firestore.Update{Path: "sentAt", Value: m.now()})
		if messageID != 0 {
			updates = append(updates, firestore.Update{Path: "messageId", Value: messageID})
		}
	case outcomeFailed:
		// 400/403: người dùng chặn bot, xoá bot, chat không còn. Gửi lại vẫn hỏng.
		slog.WarnContext(ctx, "mybot.send_failed", "botId", botID, "key", key, "error", sendErr)
		updates = append(updates, firestore.Update{Path: "status", Value: outboxFailed}, firestore.Update{Path: "error", Value: sendErr.Error()})
	default:
		updates = append(updates, firestore.Update{Path: "status", Value: outboxPending}, firestore.Update{Path: "error", Value: errString(sendErr)})
	}
	if _, err := ref.Update(ctx, updates); err != nil {
		return err
	}
	if outcome == outcomeLater || outcome == outcomeRetry {
		return sendErr
	}
	return nil
}

// ---- Câu trả lời chat riêng ra Telegram ----

// channelReply gắn vào AgentService.SetChannelReply: gửi câu trả lời chat riêng
// kênh telegram bằng bot con của chủ. Doc outbox có ID theo seq của câu trả
// lời, nên ReplyDM gọi lại bao nhiêu lần cũng chỉ một tin. Chủ chưa nối bot hay
// bot đã bị thay thì log rồi thôi, không để task chạy lại mãi.
func (m *ManagedBotService) channelReply(ctx context.Context, uid, channel string, reply AgentMessage) error {
	if channel != agentChannelTelegram {
		slog.WarnContext(ctx, "mybot.reply_unknown_channel", "uid", uid, "channel", channel)
		return nil
	}
	agent, err := getData(ctx, m.agentRef(uid))
	if err != nil {
		return err
	}
	tg, _ := agent["telegram"].(map[string]any)
	botID := stringValue(tg["botId"])
	if botID == "" {
		slog.WarnContext(ctx, "mybot.reply_no_bot", "uid", uid, "seq", reply.Seq)
		return nil
	}
	info, ok, err := m.bot(ctx, botID)
	if err != nil {
		return err
	}
	if !ok || info.Retired || info.UID != uid || info.OwnerTgID == 0 {
		slog.WarnContext(ctx, "mybot.reply_bot_gone", "uid", uid, "botId", botID, "seq", reply.Seq)
		return nil
	}
	// Chat riêng với một người có chat id bằng user id của người đó. Key có uid:
	// bot đổi chủ thì giữ outbox cũ, seq của chủ mới lại đếm từ 1.
	return m.enqueueManagedSend(ctx, botID, strconv.FormatInt(info.OwnerTgID, 10), reply.Text, "dm-"+uid+"-"+strconv.FormatInt(reply.Seq, 10))
}

// ---- Phòng bot trên Telegram ----

// setInPsc ghi bot con botID đang ở PSC hay không (agents/{uid}.telegram.inPsc),
// theo my_chat_member của chính bot đó. Chỉ ghi khi bot vẫn là bot hiện tại của
// uid, để bot cũ đã bị thay không kéo MyBot vào hay ra khỏi Phòng bot.
func (m *ManagedBotService) setInPsc(ctx context.Context, uid, botID string, in bool) error {
	ref := m.agentRef(uid)
	wall := m.now()
	return m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		d, err := getOptional(tx, ref)
		if err != nil || !d.Exists() {
			return err
		}
		tg, _ := d.Data()["telegram"].(map[string]any)
		if stringValue(tg["botId"]) != botID || (tg["inPsc"] == true) == in {
			return nil
		}
		return tx.Update(ref, []firestore.Update{
			{FieldPath: firestore.FieldPath{"telegram", "inPsc"}, Value: in},
			{FieldPath: firestore.FieldPath{"telegram", "pscAt"}, Value: wall},
		})
	})
}

// roomOut gắn vào AgentService.SetRoomOut: gửi tin của bot trong phòng tg-psc ra
// topic Phòng bot của PSC bằng chính bot con của chủ. Doc outbox có ID theo seq
// của phòng, nên RoomTurn gọi lại bao nhiêu lần cũng chỉ một tin. Topic đã tắt,
// bot đã rời PSC hay bị thay thì log rồi thôi: tin vẫn nằm trong phòng, chỉ
// không hiện trên Telegram, và task không chạy lại mãi.
func (m *ManagedBotService) roomOut(ctx context.Context, roomID string, seq int64, uid, text string) error {
	if roomID != agentTelegramRoom {
		slog.WarnContext(ctx, "mybot.room_unknown", "room", roomID, "seq", seq)
		return nil
	}
	cfg, err := getData(ctx, m.db.Collection("agentState").Doc("config"))
	if err != nil {
		return err
	}
	thread := telegramRoomThread(cfg)
	if thread == 0 || m.chatID == "" {
		slog.WarnContext(ctx, "mybot.room_no_topic", "seq", seq)
		return nil
	}
	agent, err := getData(ctx, m.agentRef(uid))
	if err != nil {
		return err
	}
	tg, _ := agent["telegram"].(map[string]any)
	botID := stringValue(tg["botId"])
	if botID == "" || tg["inPsc"] != true {
		slog.WarnContext(ctx, "mybot.room_bot_not_in_psc", "uid", uid, "botId", botID, "seq", seq)
		return nil
	}
	info, ok, err := m.bot(ctx, botID)
	if err != nil {
		return err
	}
	if !ok || info.Retired || info.UID != uid {
		slog.WarnContext(ctx, "mybot.room_bot_gone", "uid", uid, "botId", botID, "seq", seq)
		return nil
	}
	return m.enqueueOp(ctx, botID, m.chatID, thread, managedOpSend, text, "room-"+roomID+"-"+strconv.FormatInt(seq, 10))
}

// ---- Chống xử lý trùng update của bot con ----

func (m *ManagedBotService) updateRef(botID string, updateID int64) *firestore.DocumentRef {
	return m.botRef(botID).Collection("tgUpdates").Doc(strconv.FormatInt(updateID, 10))
}

// claimUpdate ghi update đã nhận; false là đã nhận trước đó (Telegram gửi lại).
func (m *ManagedBotService) claimUpdate(ctx context.Context, botID string, updateID int64) (bool, error) {
	wall := m.now()
	_, err := m.updateRef(botID, updateID).Create(ctx, map[string]any{"at": wall, "expiresAt": wall.Add(managedUpdateTTL)})
	if status.Code(err) == codes.AlreadyExists {
		return false, nil
	}
	return err == nil, err
}

// releaseUpdate bỏ khoá khi xử lý lỗi, để lần Telegram gửi lại được xử lý.
func (m *ManagedBotService) releaseUpdate(ctx context.Context, botID string, updateID int64) {
	if _, err := m.updateRef(botID, updateID).Delete(ctx); err != nil {
		slog.ErrorContext(ctx, "mybot.release_update_failed", "botId", botID, "updateId", updateID, "error", err)
	}
}

// ---- Trạng thái cho app ----

// AgentTelegram là mục telegram của GET /v1/agents/me, chỉ có khi tính năng bật
// và chủ đã tạo MyBot.
type AgentTelegram struct {
	// CreateURL mở màn tạo bot của Telegram, điền sẵn username và tên.
	CreateURL   string `json:"createUrl"`
	BotUsername string `json:"botUsername,omitempty"`
	Linked      bool   `json:"linked"`
	SetupError  string `json:"setupError,omitempty"`
	// PscJoinURL mở màn chọn group của Telegram để chủ thêm bot con vào PSC: Bot
	// API không có hàm nào cho 3i tự thêm bot. Chỉ có khi Phòng bot đang bật.
	// InPsc: bot đang ở PSC, nên được nói trong topic Phòng bot.
	PscJoinURL string `json:"pscJoinUrl,omitempty"`
	InPsc      bool   `json:"inPsc"`
}

func (m *ManagedBotService) Status(ctx context.Context, uid, agentName string) (*AgentTelegram, error) {
	agent, err := getData(ctx, m.agentRef(uid))
	if err != nil {
		return nil, err
	}
	tg, _ := agent["telegram"].(map[string]any)
	out := &AgentTelegram{
		CreateURL:   managedCreateURL(m.username, suggestBotUsername(agentName, uid), agentName),
		BotUsername: stringValue(tg["username"]),
		Linked:      stringValue(tg["botId"]) != "",
		SetupError:  stringValue(tg["setupError"]),
		InPsc:       tg["inPsc"] == true,
	}
	if out.BotUsername == "" || m.chatID == "" {
		return out, nil
	}
	// Link chỉ có khi Phòng bot đang bật: app thấy link thì hiện nút, nên admin
	// bật tắt /phongbot là đủ, không phải ra bản app mới.
	cfg, err := getData(ctx, m.db.Collection("agentState").Doc("config"))
	if err != nil {
		return nil, err
	}
	if telegramRoomThread(cfg) != 0 {
		out.PscJoinURL = pscJoinURL(out.BotUsername)
	}
	return out, nil
}

// pscJoinURL mở màn chọn group của Telegram để thêm bot vào; bot nhận
// "/start@<bot> psc" trong group, webhook bot con bỏ qua tin group đó.
func pscJoinURL(username string) string {
	return "https://t.me/" + username + "?startgroup=psc"
}

// managedCreateURL là link tạo bot con của Telegram. Tên đi qua query nên
// escape; dấu cách thành %20 chứ không thành "+", vì chưa chắc Telegram đọc "+"
// là dấu cách.
func managedCreateURL(manager, username, name string) string {
	return "https://t.me/newbot/" + manager + "/" + username + "?name=" + strings.ReplaceAll(url.QueryEscape(name), "+", "%20")
}

// suggestBotUsername gợi ý username cho bot con từ tên MyBot. Telegram cho
// 5–32 ký tự [A-Za-z0-9_], bắt đầu bằng chữ, kết thúc bằng "bot". Bỏ dấu tiếng
// Việt, thêm 4 ký tự hex từ uid cho đỡ trùng với người khác cùng tên. Người
// dùng vẫn sửa được trên Telegram trước khi tạo.
func suggestBotUsername(name, uid string) string {
	sum := sha256.Sum256([]byte(uid))
	suffix := "_" + hex.EncodeToString(sum[:2]) + "_bot"
	base := asciiSlug(name)
	base = strings.TrimSuffix(base, "_bot")
	if base == "bot" {
		base = ""
	}
	if max := managedMaxUsername - len(suffix); len(base) > max {
		base = strings.TrimRight(base[:max], "_")
	}
	if base == "" {
		base = "mybot"
	}
	out := base + suffix
	for len(out) < managedMinUsername {
		out = "my" + out
	}
	return out
}

var foldMarks = transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC)

// asciiSlug: bỏ dấu, chữ thường, ký tự khác [a-z0-9] thành "_", gộp "_", và
// bỏ phần đầu cho tới chữ cái đầu tiên.
func asciiSlug(s string) string {
	s = strings.NewReplacer("đ", "d", "Đ", "d").Replace(s)
	folded, _, err := transform.String(foldMarks, s)
	if err != nil {
		folded = s
	}
	var b strings.Builder
	underscore := false
	for _, r := range strings.ToLower(folded) {
		switch {
		case r >= 'a' && r <= 'z':
			b.WriteRune(r)
			underscore = false
		case r >= '0' && r <= '9':
			if b.Len() == 0 {
				continue // username phải bắt đầu bằng chữ
			}
			b.WriteRune(r)
			underscore = false
		default:
			if b.Len() > 0 && !underscore {
				b.WriteByte('_')
				underscore = true
			}
		}
	}
	return strings.Trim(b.String(), "_")
}
