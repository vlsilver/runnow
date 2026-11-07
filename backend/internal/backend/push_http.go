package backend

import "net/http"

// App đăng ký token FCM sau khi đăng nhập và mỗi lần FCM đổi token, gỡ lúc
// đăng xuất.
func (s *Server) pushRoutes() {
	s.route("PUT /v1/push-token", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Token    string `json:"token"`
			Platform string `json:"platform"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		if err := s.deps.Push.Register(r.Context(), uid, body.Token, body.Platform, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("DELETE /v1/push-token", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Token string `json:"token"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		if err := s.deps.Push.Unregister(r.Context(), uid, body.Token); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
}
