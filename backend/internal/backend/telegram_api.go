package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Client Bot API có cấu trúc cho bộ gửi outbox của Ma Sói (T6): trả message_id
// để sau này sửa tin, và trả lỗi Telegram dưới dạng TelegramAPIError để phân
// loại (429 hẹn lại, 400/403 bỏ tin, 5xx gửi lại). Các hàm Send* cũ chỉ trả
// chuỗi lỗi nên không dùng được cho việc này.

// TelegramAPIError là lỗi Bot API trả về (ok=false hoặc HTTP không phải 2xx).
type TelegramAPIError struct {
	Method      string
	Status      int // HTTP status
	Code        int // error_code; 0 nếu body không đọc được
	Description string
	RetryAfter  int   // parameters.retry_after (giây), có ở 429
	MigrateTo   int64 // parameters.migrate_to_chat_id, có khi group đã lên supergroup
}

func (e *TelegramAPIError) Error() string {
	return fmt.Sprintf("telegram %s failed: status=%d code=%d %s", e.Method, e.Status, e.Code, e.Description)
}

// TelegramText là một tin văn bản. HTML bật parse_mode HTML: người gọi phải tự
// escape phần chữ do người dùng nhập.
type TelegramText struct {
	ChatID   string
	ThreadID int64 // 0 = General / chat không có Topics
	Text     string
	HTML     bool
	Markup   any // reply_markup; nil là không có
}

// SendText gửi tin và trả message_id.
func (s *TelegramService) SendText(ctx context.Context, m TelegramText) (int64, error) {
	body := map[string]any{
		"chat_id":              m.ChatID,
		"text":                 m.Text,
		"link_preview_options": map[string]any{"is_disabled": true},
	}
	if m.ThreadID != 0 {
		body["message_thread_id"] = m.ThreadID
	}
	if m.HTML {
		body["parse_mode"] = "HTML"
	}
	if m.Markup != nil {
		body["reply_markup"] = m.Markup
	}
	var out struct {
		MessageID int64 `json:"message_id"`
	}
	if err := s.callAPI(ctx, "sendMessage", body, &out); err != nil {
		return 0, err
	}
	if out.MessageID == 0 {
		return 0, errors.New("telegram sendMessage: kết quả thiếu message_id")
	}
	return out.MessageID, nil
}

// EditText sửa chữ (và nút) của tin đã gửi. Sửa mà nội dung không đổi thì
// Telegram trả 400 "message is not modified"; người gọi tự quyết coi đó là gì.
func (s *TelegramService) EditText(ctx context.Context, chatID string, messageID int64, text string, html bool, markup any) error {
	body := map[string]any{
		"chat_id":              chatID,
		"message_id":           messageID,
		"text":                 text,
		"link_preview_options": map[string]any{"is_disabled": true},
	}
	if html {
		body["parse_mode"] = "HTML"
	}
	if markup != nil {
		body["reply_markup"] = markup
	}
	return s.callAPI(ctx, "editMessageText", body, nil)
}

// WebhookPendingCount là pending_update_count của getWebhookInfo: số update
// Telegram còn giữ vì chưa giao được tới webhook.
func (s *TelegramService) WebhookPendingCount(ctx context.Context) (int, error) {
	var out struct {
		PendingUpdateCount int `json:"pending_update_count"`
	}
	err := s.callAPI(ctx, "getWebhookInfo", map[string]any{}, &out)
	return out.PendingUpdateCount, err
}

// callAPI gọi một method JSON và đọc result vào out (nil thì bỏ result).
func (s *TelegramService) callAPI(ctx context.Context, method string, body map[string]any, out any) error {
	if s.botToken == "" {
		return errors.New("telegram chưa cấu hình token")
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiBaseURL+"/bot"+s.botToken+"/"+method, bytes.NewReader(payload))
	if err != nil {
		return s.redact(err)
	}
	req.Header.Set("Content-Type", "application/json")
	return s.doAPI(method, req, out)
}

// doAPI gửi req tới method rồi đọc kết quả như callAPI, cho cả request không
// phải JSON (multipart của sendPhoto).
func (s *TelegramService) doAPI(method string, req *http.Request, out any) error {
	resp, err := s.do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if err != nil {
		return s.redact(err)
	}
	var env struct {
		OK          bool            `json:"ok"`
		Result      json.RawMessage `json:"result"`
		ErrorCode   int             `json:"error_code"`
		Description string          `json:"description"`
		Parameters  struct {
			RetryAfter      int   `json:"retry_after"`
			MigrateToChatID int64 `json:"migrate_to_chat_id"`
		} `json:"parameters"`
	}
	parseErr := json.Unmarshal(raw, &env)
	if resp.StatusCode >= 300 || parseErr != nil || !env.OK {
		e := &TelegramAPIError{Method: method, Status: resp.StatusCode, Code: env.ErrorCode, Description: env.Description,
			RetryAfter: env.Parameters.RetryAfter, MigrateTo: env.Parameters.MigrateToChatID}
		if parseErr != nil {
			e.Description = fmt.Sprintf("body=%.512s", strings.TrimSpace(string(raw)))
		}
		return e
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(env.Result, out); err != nil {
		return fmt.Errorf("telegram %s: đọc result: %w", method, err)
	}
	return nil
}
