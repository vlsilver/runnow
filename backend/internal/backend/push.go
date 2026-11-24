package backend

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// PushService giữ device token FCM của app và gửi thông báo đẩy. Token nằm ở
// pushTokens/{hash token}, mỗi token một chủ: máy đổi tài khoản thì app đăng ký
// lại và token sang chủ mới, nên người cũ không còn nhận push trên máy đó. Chỉ
// backend đọc ghi collection này; rules không mở cho app.
type PushService struct {
	db     *firestore.Client
	sender pushSender
	// deadToken nhận ra lỗi FCM báo token không còn dùng được. Lỗi thật là
	// kiểu internal của SDK nên test thay hàm này.
	deadToken func(error) bool
}

// pushSender là phần FCM của messaging.Client; test thay bằng bản giả.
type pushSender interface {
	SendEach(ctx context.Context, messages []*messaging.Message) (*messaging.BatchResponse, error)
}

func NewPushService(db *firestore.Client, sender pushSender) *PushService {
	return &PushService{db: db, sender: sender, deadToken: messaging.IsUnregistered}
}

// Token FCM thật dài chừng 160 ký tự; chặn trên cho doc không phình.
const pushTokenMax = 4096

var pushPlatforms = map[string]bool{"ios": true, "android": true, "web": true}

func (s *PushService) tokenRef(token string) *firestore.DocumentRef {
	sum := sha256.Sum256([]byte(token))
	return s.db.Collection("pushTokens").Doc(hex.EncodeToString(sum[:])[:40])
}

// Register ghi token của máy cho uid. Gọi lại thì chỉ cập nhật updatedAt.
func (s *PushService) Register(ctx context.Context, uid, token, platform string, now time.Time) error {
	if token == "" || len(token) > pushTokenMax || !pushPlatforms[platform] {
		return invalidRequest()
	}
	_, err := s.tokenRef(token).Set(ctx, map[string]any{"uid": uid, "token": token, "platform": platform, "updatedAt": now})
	return err
}

// Unregister gỡ token lúc đăng xuất. Token đã sang người khác thì để nguyên,
// vì máy đó giờ là của người kia.
func (s *PushService) Unregister(ctx context.Context, uid, token string) error {
	if token == "" || len(token) > pushTokenMax {
		return invalidRequest()
	}
	ref := s.tokenRef(token)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		d, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			return nil
		}
		if err != nil {
			return err
		}
		if stringValue(d.Data()["uid"]) != uid {
			return nil
		}
		return tx.Delete(ref)
	})
}

// pushNote là một thông báo, mọi người nhận thấy cùng nội dung. Data đi kèm
// để app biết chạm vào thì mở màn nào.
type pushNote struct {
	Title string
	Body  string
	Data  map[string]string
}

// Send gửi note tới mọi máy của uids. Truy vấn in nhận tối đa 30 giá trị nên
// đọc token theo từng lô 30 uid. Người đã tắt nhóm của note thì bỏ qua.
func (s *PushService) Send(ctx context.Context, uids []string, note pushNote) error {
	if len(uids) == 0 {
		return nil
	}
	var docs []*firestore.DocumentSnapshot
	for chunk := range slices.Chunk(uids, pushInMax) {
		got, err := s.db.Collection("pushTokens").Where("uid", "in", chunk).Documents(ctx).GetAll()
		if err != nil {
			return err
		}
		docs = append(docs, got...)
	}
	return s.sendDocs(ctx, docs, note)
}

// pushInMax là trần số giá trị của một truy vấn in trên Firestore.
const pushInMax = 30

// SendAll gửi note tới mọi máy đã đăng ký, trừ máy của except (người gây ra
// sự kiện). Đọc hết pushTokens nên chỉ dùng cho thông báo chung cả club.
func (s *PushService) SendAll(ctx context.Context, except string, note pushNote) error {
	all, err := s.db.Collection("pushTokens").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	docs := slices.DeleteFunc(all, func(d *firestore.DocumentSnapshot) bool {
		return stringValue(d.Data()["uid"]) == except
	})
	return s.sendDocs(ctx, docs, note)
}

// fcmBatchMax là trần số tin của một lần SendEach.
const fcmBatchMax = 500

// sendDocs gửi note tới các token trong docs, bỏ người đã tắt nhóm của note.
// Token FCM báo đã chết thì xoá. Không gửi được tới máy nào thì trả lỗi để
// Cloud Tasks gửi lại; hỏng một phần thì chỉ log, vì gửi lại cả lượt thì máy đã
// nhận sẽ nhận hai lần.
func (s *PushService) sendDocs(ctx context.Context, docs []*firestore.DocumentSnapshot, note pushNote) error {
	var uids []string
	for _, d := range docs {
		if uid := stringValue(d.Data()["uid"]); !slices.Contains(uids, uid) {
			uids = append(uids, uid)
		}
	}
	off, err := s.optedOut(ctx, uids, note.Data["kind"])
	if err != nil {
		return err
	}
	docs = slices.DeleteFunc(docs, func(d *firestore.DocumentSnapshot) bool { return off[stringValue(d.Data()["uid"])] })
	if len(docs) == 0 {
		return nil
	}
	var failed []error
	sent := 0
	for start := 0; start < len(docs); start += fcmBatchMax {
		batch := docs[start:min(start+fcmBatchMax, len(docs))]
		msgs := make([]*messaging.Message, len(batch))
		for i, d := range batch {
			msgs[i] = &messaging.Message{
				Token:        stringValue(d.Data()["token"]),
				Notification: &messaging.Notification{Title: note.Title, Body: note.Body},
				Data:         note.Data,
				APNS:         &messaging.APNSConfig{Payload: &messaging.APNSPayload{Aps: &messaging.Aps{Sound: "default"}}},
			}
		}
		res, err := s.sender.SendEach(ctx, msgs)
		if err != nil {
			if sent == 0 {
				return err
			}
			failed = append(failed, err)
			continue
		}
		sent += res.SuccessCount
		for i, r := range res.Responses {
			if r.Success {
				continue
			}
			if s.deadToken(r.Error) {
				// Xoá lỗi thì để lần gửi sau xoá; trả lỗi ở đây làm Cloud Tasks gửi
				// lại cả lượt cho những máy đã nhận.
				if _, err := batch[i].Ref.Delete(ctx); err != nil {
					slog.WarnContext(ctx, "push.dead_token_delete_failed", "token_doc", batch[i].Ref.ID, "error", err)
				}
				continue
			}
			failed = append(failed, r.Error)
		}
	}
	if len(failed) == 0 {
		return nil
	}
	if sent == 0 {
		return errors.Join(failed...)
	}
	slog.WarnContext(ctx, "push.partial_failure", "sent", sent, "failed", len(failed), "error", errors.Join(failed...))
	return nil
}
