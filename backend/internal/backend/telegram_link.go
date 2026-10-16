package backend

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// TelegramLinkService nối uid của app với tài khoản Telegram (L1). Liên kết nằm
// ở hai doc server-only, ghi cùng một transaction: tgLinks/{tgUserId} → uid
// (bot tra người bấm nút) và telegramLinks/{uid} → tg (app hỏi trạng thái). Không
// dùng users/{uid}.telegramUserId, vì rules cho chủ doc sửa field đó: ai ghi tg
// của người khác vào là nhận được DM lá bài của người đó.
//
// Mỗi tg chỉ trỏ một uid và ngược lại. Người bấm Start trong DM chính là chủ tg,
// nên mã của uid mới thắng: liên kết cũ của tg đó, hay của uid đó, bị gỡ.
type TelegramLinkService struct {
	db          *firestore.Client
	botUsername string
	random      io.Reader
}

func NewTelegramLinkService(db *firestore.Client, botUsername string) *TelegramLinkService {
	return &TelegramLinkService{db: db, botUsername: botUsername, random: rand.Reader}
}

const linkCodeTTL = 10 * time.Minute

var (
	errLinkCodeInvalid = errors.New("mã liên kết không có hoặc sai dạng")
	errLinkCodeExpired = errors.New("mã liên kết đã hết hạn")
	errLinkCodeUsed    = errors.New("mã liên kết đã được tài khoản Telegram khác dùng")
	errLinkInGame      = &HTTPError{Status: http.StatusConflict, Code: "in_game", Message: "Bạn đang trong ván Ma Sói, đợi ván kết thúc rồi mới đổi liên kết Telegram được."}
)

type LinkCode struct {
	Code      string    `json:"code"`
	DeepLink  string    `json:"deepLink"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type LinkStatus struct {
	Linked      bool   `json:"linked"`
	TgUsername  string `json:"tgUsername"`
	DisplayName string `json:"displayName"`
	InPsc       bool   `json:"inPsc"`
}

// TelegramUser là người gửi /start, lấy từ message.from.
type TelegramUser struct {
	ID        int64
	Username  string
	FirstName string
}

func (s *TelegramLinkService) tgLinkRef(tg string) *firestore.DocumentRef {
	return s.db.Collection("tgLinks").Doc(tg)
}

func (s *TelegramLinkService) uidLinkRef(uid string) *firestore.DocumentRef {
	return s.db.Collection("telegramLinks").Doc(uid)
}

// linkCodeRef: doc lưu theo sha256 của mã, nên đọc được Firestore cũng không
// dựng lại được deep link.
func (s *TelegramLinkService) linkCodeRef(code string) *firestore.DocumentRef {
	sum := sha256.Sum256([]byte(code))
	return s.db.Collection("linkCodes").Doc(hex.EncodeToString(sum[:]))
}

// validLinkCode: tham số start của deep link Telegram chỉ nhận tối đa 64 ký tự
// [A-Za-z0-9_-].
func validLinkCode(code string) bool {
	if code == "" || len(code) > 64 {
		return false
	}
	for _, c := range code {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

// CreateLinkCode tạo mã 256 bit (43 ký tự base64url), sống 10 phút. Mã cũ chưa
// dùng của uid vẫn còn hạn tới lúc hết giờ; TTL của linkCodes dọn sau.
func (s *TelegramLinkService) CreateLinkCode(ctx context.Context, uid string, now time.Time) (LinkCode, error) {
	if s.botUsername == "" {
		return LinkCode{}, errors.New("thiếu TELEGRAM_BOT_USERNAME, không dựng được deep link")
	}
	b := make([]byte, 32)
	if _, err := io.ReadFull(s.random, b); err != nil {
		return LinkCode{}, err
	}
	code := base64.RawURLEncoding.EncodeToString(b)
	expiresAt := now.Add(linkCodeTTL)
	if _, err := s.linkCodeRef(code).Create(ctx, map[string]any{"uid": uid, "createdAt": now, "expiresAt": expiresAt}); err != nil {
		return LinkCode{}, err
	}
	return LinkCode{Code: code, DeepLink: "https://t.me/" + s.botUsername + "?start=" + code, ExpiresAt: expiresAt}, nil
}

// ConsumeLinkCode tiêu mã khi người dùng bấm Start trong DM và trả tên app của
// uid vừa liên kết. Telegram gửi lại đúng update đó (cùng tg) thì trả lại kết
// quả cũ mà không ghi gì; tg khác dùng lại mã thì từ chối. Đổi liên kết mà một
// bên đang trong ván thì từ chối và giữ mã, vì players/{uid}.tgUserId đã chốt
// lúc đăng ký: đổi giữa ván là người đó bị tính đã rời PSC.
func (s *TelegramLinkService) ConsumeLinkCode(ctx context.Context, code string, tg TelegramUser, now time.Time) (string, error) {
	if !validLinkCode(code) {
		return "", errLinkCodeInvalid
	}
	tgKey := strconv.FormatInt(tg.ID, 10)
	var displayName string
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		c, err := tx.Get(s.linkCodeRef(code))
		if status.Code(err) == codes.NotFound {
			return errLinkCodeInvalid
		}
		if err != nil {
			return err
		}
		uid := stringValue(c.Data()["uid"])
		user, err := getOptional(tx, s.db.Collection("users").Doc(uid))
		if err != nil {
			return err
		}
		displayName = ""
		if user.Exists() {
			displayName = stringValue(user.Data()["displayName"])
		}
		if used := tgIDString(c.Data()["usedBy"]); used != "" {
			if used != tgKey {
				return errLinkCodeUsed
			}
			return nil
		}
		if expiresAt, _ := c.Data()["expiresAt"].(time.Time); !now.Before(expiresAt) {
			return errLinkCodeExpired
		}
		byTG, err := getOptional(tx, s.tgLinkRef(tgKey))
		if err != nil {
			return err
		}
		byUID, err := getOptional(tx, s.uidLinkRef(uid))
		if err != nil {
			return err
		}
		var oldUID, oldTG string
		if byTG.Exists() && stringValue(byTG.Data()["uid"]) != uid {
			oldUID = stringValue(byTG.Data()["uid"])
		}
		if byUID.Exists() && tgIDString(byUID.Data()["tgUserId"]) != tgKey {
			oldTG = tgIDString(byUID.Data()["tgUserId"])
		}
		var moving []string
		var oldUIDLink, oldTGLink *firestore.DocumentSnapshot
		if oldUID != "" {
			moving = append(moving, oldUID)
			if oldUIDLink, err = getOptional(tx, s.uidLinkRef(oldUID)); err != nil {
				return err
			}
		}
		if oldTG != "" {
			moving = append(moving, uid)
			if oldTGLink, err = getOptional(tx, s.tgLinkRef(oldTG)); err != nil {
				return err
			}
		}
		if len(moving) > 0 {
			inGame, err := inActiveGame(tx, s.db, moving...)
			if err != nil {
				return err
			}
			if inGame {
				return errLinkInGame
			}
		}
		// Chỉ gỡ đầu kia khi nó còn trỏ về đúng chỗ, để liên kết khác không bị xoá nhầm.
		if oldUIDLink != nil && oldUIDLink.Exists() && tgIDString(oldUIDLink.Data()["tgUserId"]) == tgKey {
			if err := tx.Delete(oldUIDLink.Ref); err != nil {
				return err
			}
		}
		if oldTGLink != nil && oldTGLink.Exists() && stringValue(oldTGLink.Data()["uid"]) == uid {
			if err := tx.Delete(oldTGLink.Ref); err != nil {
				return err
			}
		}
		// Merge để giữ inPsc: cờ đó thuộc về tg, không đổi theo uid.
		if err := tx.Set(s.tgLinkRef(tgKey), map[string]any{
			"uid": uid, "username": tg.Username, "displayName": tg.FirstName, "linkedAt": now, "updatedAt": now,
		}, firestore.MergeAll); err != nil {
			return err
		}
		if err := tx.Set(s.uidLinkRef(uid), map[string]any{"tgUserId": tg.ID, "linkedAt": now}); err != nil {
			return err
		}
		return tx.Update(c.Ref, []firestore.Update{{Path: "usedBy", Value: tg.ID}, {Path: "usedAt", Value: now}})
	})
	if err != nil {
		return "", err
	}
	return displayName, nil
}

// Link trả trạng thái liên kết cho app.
func (s *TelegramLinkService) Link(ctx context.Context, uid string) (LinkStatus, error) {
	byUID, err := s.uidLinkRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return LinkStatus{}, nil
	}
	if err != nil {
		return LinkStatus{}, err
	}
	tg := tgIDString(byUID.Data()["tgUserId"])
	link, err := s.tgLinkRef(tg).Get(ctx)
	if err != nil {
		return LinkStatus{}, fmt.Errorf("telegramLinks/%s trỏ tg %s nhưng đọc tgLinks lỗi: %w", uid, tg, err)
	}
	if got := stringValue(link.Data()["uid"]); got != uid {
		return LinkStatus{}, fmt.Errorf("telegramLinks/%s trỏ tg %s nhưng tgLinks/%s trỏ uid %q", uid, tg, tg, got)
	}
	return LinkStatus{
		Linked:      true,
		TgUsername:  stringValue(link.Data()["username"]),
		DisplayName: stringValue(link.Data()["displayName"]),
		InPsc:       link.Data()["inPsc"] == true,
	}, nil
}

// Unlink gỡ liên kết của uid. Chưa liên kết thì coi như xong. Đang trong ván thì
// 409 in_game.
func (s *TelegramLinkService) Unlink(ctx context.Context, uid string) error {
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		byUID, err := getOptional(tx, s.uidLinkRef(uid))
		if err != nil || !byUID.Exists() {
			return err
		}
		link, err := getOptional(tx, s.tgLinkRef(tgIDString(byUID.Data()["tgUserId"])))
		if err != nil {
			return err
		}
		inGame, err := inActiveGame(tx, s.db, uid)
		if err != nil {
			return err
		}
		if inGame {
			return errLinkInGame
		}
		if link.Exists() && stringValue(link.Data()["uid"]) == uid {
			if err := tx.Delete(link.Ref); err != nil {
				return err
			}
		}
		return tx.Delete(byUID.Ref)
	})
}

// RecordMembership ghi inPsc của một tg theo kết quả getChatMember lấy lúc
// checkedAt. tg chưa liên kết thì bỏ qua. Hai task chạy lệch thứ tự thì kết quả
// lấy sau thắng, nên tin "rời nhóm" đến muộn không ghi đè được lần kiểm mới hơn.
func (s *TelegramLinkService) RecordMembership(ctx context.Context, tgID int64, m TelegramChatMember, checkedAt time.Time) error {
	ref := s.tgLinkRef(strconv.FormatInt(tgID, 10))
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		link, err := getOptional(tx, ref)
		if err != nil || !link.Exists() {
			return err
		}
		if prev, ok := link.Data()["inPscCheckedAt"].(time.Time); ok && prev.After(checkedAt) {
			return nil
		}
		updates := []firestore.Update{{Path: "inPsc", Value: m.InChat()}, {Path: "inPscCheckedAt", Value: checkedAt}}
		if m.User.Username != "" {
			updates = append(updates, firestore.Update{Path: "username", Value: m.User.Username})
		}
		return tx.Update(ref, updates)
	})
}

// inActiveGame: có uid nào là người chơi của ván đang starting/running không.
// Ván đang đăng ký thì chưa tính: lúc Start bot kiểm lại liên kết của từng người.
func inActiveGame(tx *firestore.Transaction, db *firestore.Client, uids ...string) (bool, error) {
	cur, err := getOptional(tx, db.Collection("gameState").Doc("current"))
	if err != nil || !cur.Exists() {
		return false, err
	}
	id := stringValue(cur.Data()["gameId"])
	if id == "" {
		return false, nil
	}
	game := db.Collection("games").Doc(id)
	g, err := getOptional(tx, game)
	if err != nil || !g.Exists() {
		return false, err
	}
	if st := stringValue(g.Data()["status"]); st != gameStarting && st != gameRunning {
		return false, nil
	}
	refs := make([]*firestore.DocumentRef, len(uids))
	for i, uid := range uids {
		refs[i] = game.Collection("players").Doc(uid)
	}
	players, err := tx.GetAll(refs)
	if err != nil {
		return false, err
	}
	for _, p := range players {
		if p.Exists() {
			return true, nil
		}
	}
	return false, nil
}

// getOptional đọc doc trong transaction; không có thì trả snapshot với
// Exists() = false thay vì lỗi.
func getOptional(tx *firestore.Transaction, ref *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) {
	snap, err := tx.Get(ref)
	if status.Code(err) == codes.NotFound {
		return snap, nil
	}
	return snap, err
}
