//go:build emulator

package backend

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"testing"
	"time"
)

// Emulator nạp firestore.rules qua firebase.json; client Admin bỏ qua rules,
// nên phần này gọi REST với token chưa ký mà emulator chấp nhận để rules chạy
// như với app.
const rankRulesDocs = "projects/" + emulatorProject + "/databases/(default)/documents"

func rulesToken(uid string) string {
	enc := base64.RawURLEncoding
	header, _ := json.Marshal(map[string]any{"alg": "none", "typ": "JWT"})
	now := time.Now().Unix()
	payload, _ := json.Marshal(map[string]any{
		"iss": "https://securetoken.google.com/" + emulatorProject, "aud": emulatorProject,
		"sub": uid, "user_id": uid, "iat": now, "exp": now + 3600, "auth_time": now,
		"firebase": map[string]any{"sign_in_provider": "custom", "identities": map[string]any{}},
	})
	return enc.EncodeToString(header) + "." + enc.EncodeToString(payload) + "."
}

// rulesCall trả status HTTP; uid rỗng là chưa đăng nhập.
func rulesCall(t *testing.T, uid, method, path string, body any) int {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, _ := json.Marshal(body)
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req, err := http.NewRequest(method, "http://"+os.Getenv("FIRESTORE_EMULATOR_HOST")+"/v1/"+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if uid != "" {
		req.Header.Set("Authorization", "Bearer "+rulesToken(uid))
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

// rulesCommit ghi một doc có sẵn: fields đổi theo mask, revealedAt có thể lấy giờ server.
func rulesCommit(t *testing.T, uid, doc string, fields map[string]any, serverTimeField string) int {
	t.Helper()
	mask := []string{}
	for k := range fields {
		mask = append(mask, k)
	}
	write := map[string]any{
		"update":          map[string]any{"name": rankRulesDocs + "/" + doc, "fields": fields},
		"updateMask":      map[string]any{"fieldPaths": mask},
		"currentDocument": map[string]any{"exists": true},
	}
	if serverTimeField != "" {
		write["updateTransforms"] = []any{map[string]any{"fieldPath": serverTimeField, "setToServerValue": "REQUEST_TIME"}}
	}
	return rulesCall(t, uid, "POST", rankRulesDocs+":commit", map[string]any{"writes": []any{write}})
}

func TestEmulatorRankCardRules(t *testing.T) {
	db := emulatorDB(t)
	card := map[string]any{"rank": 2, "tier": "epic", "revealedAt": nil}
	seed(t, db, "users/an/rankCards/week_2026-10-26_run", card)
	seed(t, db, "users/an/rankCards/week_2026-10-26_steps", card)
	seed(t, db, "rankBoards/week_2026-10-26_run", map[string]any{"entries": []any{}})
	runCard := "users/an/rankCards/week_2026-10-26_run"

	cases := []struct {
		name string
		got  func() int
		want int
	}{
		{"người khác đọc thẻ", func() int { return rulesCall(t, "binh", "GET", rankRulesDocs+"/"+runCard, nil) }, 200},
		{"chưa đăng nhập đọc thẻ", func() int { return rulesCall(t, "", "GET", rankRulesDocs+"/"+runCard, nil) }, 403},
		{"đọc bảng", func() int { return rulesCall(t, "binh", "GET", rankRulesDocs+"/rankBoards/week_2026-10-26_run", nil) }, 200},
		{"ghi bảng", func() int {
			return rulesCommit(t, "an", "rankBoards/week_2026-10-26_run", map[string]any{"entries": map[string]any{"nullValue": nil}}, "")
		}, 403},
		{"người khác lật hộ", func() int { return rulesCommit(t, "binh", runCard, map[string]any{}, "revealedAt") }, 403},
		{"chủ lật bằng giờ tự đặt", func() int {
			return rulesCommit(t, "an", runCard, map[string]any{"revealedAt": map[string]any{"timestampValue": "2026-10-01T00:00:00Z"}}, "")
		}, 403},
		{"chủ lật kèm sửa hạng", func() int {
			return rulesCommit(t, "an", "users/an/rankCards/week_2026-10-26_steps", map[string]any{"rank": map[string]any{"integerValue": "1"}}, "revealedAt")
		}, 403},
		{"chủ lật", func() int { return rulesCommit(t, "an", runCard, map[string]any{}, "revealedAt") }, 200},
		{"chủ lật lần hai", func() int { return rulesCommit(t, "an", runCard, map[string]any{}, "revealedAt") }, 403},
		{"chủ tự tạo thẻ", func() int {
			return rulesCall(t, "an", "POST", rankRulesDocs+"/users/an/rankCards?documentId=month_2026-10-01_run", map[string]any{"fields": map[string]any{"rank": map[string]any{"integerValue": "1"}}})
		}, 403},
	}
	for _, c := range cases {
		if got := c.got(); got != c.want {
			t.Errorf("%s: %d, mong đợi %d", c.name, got, c.want)
		}
	}
}
