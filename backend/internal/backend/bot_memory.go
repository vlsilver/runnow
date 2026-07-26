package backend

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// MemoryService duy trì "trí nhớ dài hạn" cho từng group.
//
// Bộ nhớ làm việc (50 tin gần nhất) chỉ giữ được mạch hội thoại một hai
// ngày — không đủ để bot "nhớ mọi người". Mỗi đêm dịch vụ này đọc chat trong
// ngày rồi chưng cất thành một đoạn sự thật cô đọng về nhóm (ai đang tập
// giải gì, thói quen chạy, chuyện đùa), lưu lại và luôn nạp vào đầu context
// khi bot trả lời. Đó là thứ khiến bot như một thành viên thật thay vì một
// máy tra số liệu.
type MemoryService struct {
	genai *genai.Client
	db    *firestore.Client
	model string
}

func NewMemoryService(gc *genai.Client, db *firestore.Client, model string) *MemoryService {
	return &MemoryService{genai: gc, db: db, model: model}
}

// maxMemoryChars chặn trí nhớ phình vô hạn — nó luôn nằm trong mọi request
// nên phải gọn.
const maxMemoryChars = 3000

// consolidationTriggerCount là số tin MỚI tích lại trước khi chưng cất một
// lần. Bot ghi mọi tin trong group (Privacy Mode tắt), nên thay vì chỉ chưng
// cất mỗi đêm — dễ mất mạch nếu group chat sôi nổi — cứ đủ 100 tin chưa xử lý
// là cuốn ngay vào trí nhớ dài hạn. Job đêm vẫn chạy như lưới an toàn.
const consolidationTriggerCount = 100

// maxConsolidationBatch là trần số tin đọc mỗi lần chưng cất. Bình thường mỗi
// lần chỉ có ~100 tin mới kể từ mốc trước; trần này chỉ chặn trường hợp tồn
// đọng lớn (lần đầu, hoặc group im lâu rồi bùng) khỏi nuốt cả nghìn tin vào
// một prompt.
const maxConsolidationBatch = 600

// Load đọc trí nhớ hiện tại của một group. Rỗng nếu chưa có.
func (m *MemoryService) Load(ctx context.Context, chatID string) string {
	if m == nil {
		return ""
	}
	snap, err := m.db.Collection("botMemory").Doc(chatID).Get(ctx)
	if err != nil {
		return ""
	}
	return stringValue(snap.Data()["text"])
}

// ConsolidateAll chưng cất trí nhớ cho mọi group đang hoạt động.
//
// Lỗi ở một group không được chặn các group còn lại — một nhóm chat lỗi
// không nên làm hỏng cả mẻ.
func (m *MemoryService) ConsolidateAll(ctx context.Context) error {
	// DocumentRefs liệt kê được cả doc "ảo" chỉ có subcollection (Firestore
	// không tự tạo doc cha khi ghi vào subcollection), nên bắt được mọi
	// group đã từng có tin.
	it := m.db.Collection("botConversations").DocumentRefs(ctx)
	consolidated, failed := 0, 0
	for {
		ref, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		if err := m.consolidate(ctx, ref.ID); err != nil {
			slog.WarnContext(ctx, "memory.consolidate_failed", "chatId", ref.ID, "error", err)
			failed++
			continue
		}
		consolidated++
	}
	slog.InfoContext(ctx, "memory.consolidate_done", "consolidated", consolidated, "failed", failed)
	return nil
}

// consolidate cuốn những tin CHƯA chưng cất (createdAt sau mốc lần trước) vào
// trí nhớ dài hạn. Đọc theo mốc thời gian thay vì "N tin gần nhất" để không
// bỏ sót và không chưng cất lại phần đã xử lý.
func (m *MemoryService) consolidate(ctx context.Context, chatID string) error {
	since := m.lastConsolidatedAt(ctx, chatID)
	// Đọc cũ→mới từ ngay sau mốc trước; giới hạn trần để prompt không phình.
	docs, err := m.db.Collection("botConversations").Doc(chatID).Collection("botMessages").
		Where("createdAt", ">", since).
		OrderBy("createdAt", firestore.Asc).
		Limit(maxConsolidationBatch).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	if len(docs) == 0 {
		return nil
	}
	var transcript strings.Builder
	var newest time.Time
	for _, d := range docs {
		data := d.Data()
		if t, ok := data["createdAt"].(time.Time); ok && t.After(newest) {
			newest = t
		}
		text := stringValue(data["text"])
		if text == "" {
			continue
		}
		if stringValue(data["role"]) == genai.RoleModel {
			transcript.WriteString("Bot: ")
		} else if name := stringValue(data["name"]); name != "" {
			transcript.WriteString(name + ": ")
		}
		transcript.WriteString(text)
		transcript.WriteString("\n")
	}
	if strings.TrimSpace(transcript.String()) == "" {
		// Chỉ toàn tin rỗng: vẫn đẩy mốc lên để lần sau khỏi quét lại.
		return m.advanceWatermark(ctx, chatID, newest)
	}

	existing := m.Load(ctx, chatID)
	updated, err := m.distill(ctx, existing, transcript.String())
	if err != nil {
		return err
	}
	updated = strings.TrimSpace(updated)
	if updated == "" {
		// distill không rút ra gì mới nhưng tin ĐÃ được đọc — vẫn phải đẩy
		// mốc, nếu không sẽ chưng cất lại đúng lô này mãi.
		return m.advanceWatermark(ctx, chatID, newest)
	}
	if len([]rune(updated)) > maxMemoryChars {
		updated = string([]rune(updated)[:maxMemoryChars])
	}
	_, err = m.db.Collection("botMemory").Doc(chatID).Set(ctx, map[string]any{
		"text":               updated,
		"chatId":             chatID,
		"updatedAt":          firestore.ServerTimestamp,
		"lastConsolidatedAt": newest,
	}, firestore.MergeAll)
	return err
}

// lastConsolidatedAt là mốc tin cuối cùng đã được cuốn vào trí nhớ. Zero nếu
// chưa từng chưng cất — khi đó query "> zero" lấy toàn bộ lịch sử.
func (m *MemoryService) lastConsolidatedAt(ctx context.Context, chatID string) time.Time {
	snap, err := m.db.Collection("botMemory").Doc(chatID).Get(ctx)
	if err != nil {
		return time.Time{}
	}
	if t, ok := snap.Data()["lastConsolidatedAt"].(time.Time); ok {
		return t
	}
	return time.Time{}
}

// advanceWatermark chỉ đẩy mốc mà không đụng nội dung trí nhớ — dùng khi lô
// vừa đọc không sinh ra gì đáng nhớ nhưng vẫn phải đánh dấu là đã xử lý.
func (m *MemoryService) advanceWatermark(ctx context.Context, chatID string, newest time.Time) error {
	if newest.IsZero() {
		return nil
	}
	_, err := m.db.Collection("botMemory").Doc(chatID).Set(ctx, map[string]any{
		"chatId":             chatID,
		"lastConsolidatedAt": newest,
	}, firestore.MergeAll)
	return err
}

const memoryDistillPrompt = `Bạn đang duy trì "trí nhớ" về một nhóm chạy bộ, để một trợ lý AI trong
group Telegram nhớ về mọi người như một thành viên thật đã ở trong nhóm lâu.

TRÍ NHỚ HIỆN TẠI:
%s

HỘI THOẠI GẦN ĐÂY:
%s

Hãy CẬP NHẬT trí nhớ, gộp cái cũ còn đúng với cái mới. Giữ những sự thật đáng
nhớ LÂU DÀI:
- Từng thành viên: đang tập giải gì, thói quen chạy (giờ giấc, cự ly ưa
  thích), chấn thương hay tình trạng sức khoẻ, tính cách, biệt danh.
- Mục tiêu, kèo đang theo đuổi.
- Chuyện đùa, văn hoá riêng của nhóm.

BỎ đi: tán gẫu vụn vặt; số liệu nhất thời như số km tuần này (cái đó tra
realtime được, không cần nhớ); thông tin đã cũ không còn đúng.

Viết cô đọng, tối đa 350 từ, gạch đầu dòng theo từng người. CHỈ ghi điều thực
sự xuất hiện trong hội thoại — tuyệt đối không bịa. Nếu chưa có gì đáng nhớ
thì trả về đúng trí nhớ cũ.

Chỉ trả về nội dung trí nhớ, KHÔNG kèm tiêu đề hay lời dẫn như "TRÍ NHỚ:" —
bắt đầu thẳng bằng các gạch đầu dòng.`

func (m *MemoryService) distill(ctx context.Context, existing, transcript string) (string, error) {
	if existing == "" {
		existing = "(chưa có)"
	}
	prompt := fmt.Sprintf(memoryDistillPrompt, existing, transcript)
	resp, err := m.genai.Models.GenerateContent(ctx, m.model,
		[]*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: prompt}}}}, nil)
	if err != nil {
		return "", err
	}
	if resp == nil || len(resp.Candidates) == 0 {
		return "", fmt.Errorf("model trả về rỗng khi chưng cất")
	}
	return resp.Text(), nil
}

// AfterMessages gọi sau khi đã lưu `added` tin vào lịch sử một group. Nó cộng
// dồn bộ đếm "tin chưa chưng cất"; khi vượt ngưỡng thì chưng cất ngay (cuốn
// chiếu) thay vì đợi job đêm. Cũng đánh dấu group còn hoạt động và đảm bảo
// botConversations/{chatID} tồn tại như doc thật cho job đêm quét tới.
//
// Không trả lỗi ra ngoài: đây là việc phụ trợ, hỏng thì chỉ log — không nên
// làm hỏng luồng trả lời / ghi tin.
func (m *MemoryService) AfterMessages(ctx context.Context, chatID string, added int) {
	if m == nil {
		return
	}
	should, err := m.noteAndCheck(ctx, chatID, added)
	if err != nil {
		slog.WarnContext(ctx, "memory.note_failed", "chatId", chatID, "error", err)
		return
	}
	if should {
		if err := m.consolidate(ctx, chatID); err != nil {
			slog.WarnContext(ctx, "memory.rolling_consolidate_failed", "chatId", chatID, "error", err)
		}
	}
}

// noteAndCheck cộng bộ đếm tin chưa chưng cất trong một transaction và trả về
// true đúng MỘT lần khi bộ đếm chạm ngưỡng (đồng thời reset về 0). Transaction
// để nhiều tin đến cùng lúc trên nhiều instance Cloud Run không cùng vượt
// ngưỡng rồi cùng kích hoạt chưng cất trùng nhau.
func (m *MemoryService) noteAndCheck(ctx context.Context, chatID string, added int) (bool, error) {
	ref := m.db.Collection("botConversations").Doc(chatID)
	should := false
	err := m.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		count := 0
		snap, err := tx.Get(ref)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if err == nil {
			count = int(number(snap.Data()["pendingCount"]))
		}
		count += added
		if count >= consolidationTriggerCount {
			should = true
			count = 0
		}
		return tx.Set(ref, map[string]any{
			"chatId":       chatID,
			"lastActiveAt": firestore.ServerTimestamp,
			"pendingCount": count,
		}, firestore.MergeAll)
	})
	if err != nil {
		return false, err
	}
	return should, nil
}
