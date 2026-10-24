package backend

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Giá trị sửa tay trong Firestore mà sai kiểu hay ra ngoài khoảng thì dùng mặc
// định, chứ không thành 0 (tắt bot) hay bỏ hẳn giới hạn.
func TestParseAgentLimits(t *testing.T) {
	ctx := context.Background()
	if got := parseAgentLimits(ctx, nil); got != (agentLimits{100, 300, 6, 10, 10}) {
		t.Fatalf("doc trống: %+v", got)
	}
	got := parseAgentLimits(ctx, map[string]any{"dmDailyMax": int64(20), "roomDailyMax": 50.0, "chainMax": 2.0, "dmBaseDaily": 5.0, "dmPerKm": int64(3)})
	if got != (agentLimits{20, 50, 2, 5, 3}) {
		t.Fatalf("giá trị hợp lệ: %+v", got)
	}
	got = parseAgentLimits(ctx, map[string]any{"dmDailyMax": "20", "roomDailyMax": -5.0, "chainMax": 0.0, "dmBaseDaily": 1.5, "dmPerKm": -1.0})
	if got != (agentLimits{100, 300, 6, 10, 10}) {
		t.Fatalf("giá trị sai phải về mặc định: %+v", got)
	}
}

func TestAgentModelUses(t *testing.T) {
	s := &Server{config: Config{AgentModel: "m", AgentLearnModel: "m"}}
	if uses := s.agentModelUses(); len(uses) != 1 || uses[0].Model != "m" {
		t.Fatalf("cùng model phải gộp một dòng: %+v", uses)
	}
	s.config.AgentLearnModel = "n"
	if uses := s.agentModelUses(); len(uses) != 2 || uses[1].Model != "n" {
		t.Fatalf("hai model: %+v", uses)
	}
	// Model vẽ thẻ cũng tính tiền theo bảng giá nên admin phải thấy để khai giá.
	s.config.RunCardArtModel = "img"
	if uses := s.agentModelUses(); len(uses) != 3 || uses[2] != (agentModelUse{Model: "img", Use: "Vẽ tranh thẻ buổi chạy"}) {
		t.Fatalf("có model vẽ thẻ: %+v", uses)
	}
}

// Trang Admin chạy trên web: trình duyệt hỏi preflight trước PATCH, CORS không
// cho PATCH thì không lưu được gì.
func TestCORSPreflightAllowsPatch(t *testing.T) {
	srv := NewAPIServer(Config{AllowedWebOrigins: map[string]struct{}{"https://threei.run": {}}}, &Dependencies{})
	r := httptest.NewRequest(http.MethodOptions, "/v1/admin/agent-config", nil)
	r.Header.Set("Origin", "https://threei.run")
	r.Header.Set("Access-Control-Request-Method", "PATCH")
	w := httptest.NewRecorder()
	srv.ServeHTTP(w, r)
	if w.Code != 204 || !strings.Contains(w.Header().Get("Access-Control-Allow-Methods"), "PATCH") {
		t.Fatalf("preflight: %d %v", w.Code, w.Header())
	}
}
