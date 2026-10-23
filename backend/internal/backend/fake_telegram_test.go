package backend

import (
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// fakeTelegram giả Bot API cho test: ghi lại mọi call theo thứ tự, trả lỗi theo
// kịch bản từng method (429, 403, 400…), còn lại trả ok. Dùng chung cho test
// thường và test emulator (W1a), để bộ gửi outbox (T6) và nút DM (W2) cùng test
// trên một mặt Telegram.
type fakeTelegram struct {
	URL   string
	token string

	mu     sync.Mutex
	calls  []tgCall
	script map[string][]tgReply
	nextID int64
	onCall func(tgCall)
	// tokens là các token gọi được; revoked là token đã bị thay, gọi vào thì
	// 401 như Telegram. managed là token hiện tại của từng bot con theo bot id,
	// getManagedBotToken trả từ đây.
	tokens  map[string]bool
	revoked map[string]bool
	managed map[int64]string
	minted  int
}

type tgCall struct {
	Token  string
	Method string
	Params map[string]any // JSON body; multipart/form thì là giá trị chuỗi, file ghi tên file
}

type tgReply struct {
	Status int
	Body   string
}

const fakeTelegramToken = "fake-token"

func newFakeTelegram(t *testing.T) *fakeTelegram {
	t.Helper()
	f := &fakeTelegram{token: fakeTelegramToken, script: map[string][]tgReply{},
		tokens: map[string]bool{fakeTelegramToken: true}, revoked: map[string]bool{}, managed: map[int64]string{}}
	srv := httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(srv.Close)
	f.URL = srv.URL
	return f
}

// service trả TelegramService trỏ vào fake, chat mặc định chatID.
func (f *fakeTelegram) service(chatID string) *TelegramService {
	s := NewTelegramService(f.token, chatID)
	s.apiBaseURL = f.URL
	return s
}

// addManaged tạo token cho bot con botID, như lúc người dùng vừa tạo bot qua
// bot quản lý. Gọi lại với cùng botID là thay token (replaceManagedBotToken):
// token cũ từ đó trả 401.
func (f *fakeTelegram) addManaged(botID int64) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	if old, ok := f.managed[botID]; ok {
		delete(f.tokens, old)
		f.revoked[old] = true
	}
	f.minted++
	tok := fmt.Sprintf("child-%d-%d", botID, f.minted)
	f.managed[botID] = tok
	f.tokens[tok] = true
	return tok
}

// CallsBy như Calls nhưng chỉ lấy call bằng token tok.
func (f *fakeTelegram) CallsBy(tok, method string) []tgCall {
	var out []tgCall
	for _, c := range f.Calls(method) {
		if c.Token == tok {
			out = append(out, c)
		}
	}
	return out
}

// Then xếp các phản hồi cho những lần gọi method kế tiếp; hết kịch bản thì trả ok.
func (f *fakeTelegram) Then(method string, replies ...tgReply) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.script[method] = append(f.script[method], replies...)
}

// OnCall chạy fn sau khi ghi nhận mỗi call, trước khi trả lời. Test dùng nó để
// chen việc vào giữa lúc Telegram nhận tin và lúc bộ gửi ghi kết quả.
func (f *fakeTelegram) OnCall(fn func(tgCall)) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.onCall = fn
}

// Calls trả các call của method theo thứ tự; method rỗng thì trả hết.
func (f *fakeTelegram) Calls(method string) []tgCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []tgCall
	for _, c := range f.calls {
		if method == "" || c.Method == method {
			out = append(out, c)
		}
	}
	return out
}

func tgTooManyRequests(retryAfter int) tgReply {
	return tgReply{http.StatusTooManyRequests, fmt.Sprintf(`{"ok":false,"error_code":429,"description":"Too Many Requests: retry after %d","parameters":{"retry_after":%d}}`, retryAfter, retryAfter)}
}

func tgForbidden(description string) tgReply {
	return tgReply{http.StatusForbidden, tgError(403, description)}
}

func tgBadRequest(description string) tgReply {
	return tgReply{http.StatusBadRequest, tgError(400, description)}
}

// tgMigrated là lỗi Telegram trả khi group đã lên supergroup có ID mới.
func tgMigrated(newChatID int64) tgReply {
	return tgReply{http.StatusBadRequest, fmt.Sprintf(`{"ok":false,"error_code":400,"description":"Bad Request: group chat was upgraded to a supergroup chat","parameters":{"migrate_to_chat_id":%d}}`, newChatID)}
}

func tgError(code int, description string) string {
	b, _ := json.Marshal(map[string]any{"ok": false, "error_code": code, "description": description})
	return string(b)
}

func (f *fakeTelegram) serve(w http.ResponseWriter, r *http.Request) {
	rest, _ := strings.CutPrefix(r.URL.Path, "/bot")
	tok, method, _ := strings.Cut(rest, "/")
	f.mu.Lock()
	known, revoked := f.tokens[tok], f.revoked[tok]
	f.mu.Unlock()
	if revoked {
		params, _ := readTelegramParams(r)
		f.mu.Lock()
		f.calls = append(f.calls, tgCall{Token: tok, Method: method, Params: params})
		f.mu.Unlock()
		writeTelegram(w, tgReply{http.StatusUnauthorized, tgError(401, "Unauthorized")})
		return
	}
	if !known || method == "" {
		// Telegram trả 404 cho token sai; giữ đúng để test bắt được URL ghép sai.
		writeTelegram(w, tgReply{http.StatusNotFound, tgError(404, "Not Found")})
		return
	}
	params, err := readTelegramParams(r)
	if err != nil {
		writeTelegram(w, tgBadRequest("fake: "+err.Error()))
		return
	}

	f.mu.Lock()
	f.calls = append(f.calls, tgCall{Token: tok, Method: method, Params: params})
	reply, scripted := tgReply{}, false
	if q := f.script[method]; len(q) > 0 {
		reply, scripted = q[0], true
		f.script[method] = q[1:]
	}
	if !scripted {
		reply = f.okReply(method, params)
	}
	hook := f.onCall
	f.mu.Unlock()
	if hook != nil {
		hook(tgCall{Method: method, Params: params})
	}
	writeTelegram(w, reply)
}

// okReply: send* trả Message có message_id tăng dần, getManagedBotToken trả
// token hiện tại của bot con (chưa có thì 400), method khác trả true.
func (f *fakeTelegram) okReply(method string, params map[string]any) tgReply {
	if method == "getManagedBotToken" {
		tok, ok := f.managed[int64(number(params["user_id"]))]
		if !ok {
			return tgBadRequest("Bad Request: bot not found")
		}
		b, _ := json.Marshal(map[string]any{"ok": true, "result": tok})
		return tgReply{http.StatusOK, string(b)}
	}
	if !strings.HasPrefix(method, "send") {
		return tgReply{http.StatusOK, `{"ok":true,"result":true}`}
	}
	f.nextID++
	b, _ := json.Marshal(map[string]any{"ok": true, "result": map[string]any{
		"message_id": f.nextID,
		"chat":       map[string]any{"id": params["chat_id"]},
	}})
	return tgReply{http.StatusOK, string(b)}
}

func readTelegramParams(r *http.Request) (map[string]any, error) {
	params := map[string]any{}
	for k, v := range r.URL.Query() {
		params[k] = v[0]
	}
	mediaType, mp, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
	switch mediaType {
	case "application/json":
		body, err := io.ReadAll(r.Body)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(body, &params); err != nil {
			return nil, err
		}
	case "multipart/form-data":
		mr := multipart.NewReader(r.Body, mp["boundary"])
		for {
			part, err := mr.NextPart()
			if err == io.EOF {
				break
			}
			if err != nil {
				return nil, err
			}
			if part.FileName() != "" {
				params[part.FormName()] = "file:" + part.FileName()
				continue
			}
			v, err := io.ReadAll(part)
			if err != nil {
				return nil, err
			}
			params[part.FormName()] = string(v)
		}
	case "application/x-www-form-urlencoded":
		if err := r.ParseForm(); err != nil {
			return nil, err
		}
		for k, v := range r.PostForm {
			params[k] = v[0]
		}
	}
	return params, nil
}

func writeTelegram(w http.ResponseWriter, reply tgReply) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(reply.Status)
	_, _ = io.WriteString(w, reply.Body)
}
