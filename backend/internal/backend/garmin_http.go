package backend

import (
	"log/slog"
	"net/http"
)

// garminRoutes là API nối Garmin Connect của app và endpoint nhận push.
func (s *Server) garminRoutes() {
	s.route("GET /v1/garmin/status", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		connection, err := s.deps.Garmin.Status(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, connection)
	}))
	s.route("POST /v1/garmin/authorization", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			ReturnTarget string `json:"returnTarget"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		u, err := s.deps.Garmin.Authorization(r.Context(), uid, body.ReturnTarget)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"authorizationUrl": u})
	}))
	s.route("GET /v1/garmin/callback", func(w http.ResponseWriter, r *http.Request) error {
		q := r.URL.Query()
		redirect, err := s.deps.Garmin.Callback(r.Context(), q.Get("oauth_token"), q.Get("oauth_verifier"))
		if err != nil {
			return err
		}
		http.Redirect(w, r, redirect, http.StatusFound)
		return nil
	})
	s.route("POST /v1/garmin/disconnect", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Garmin.Disconnect(r.Context(), uid); err != nil {
			return err
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	}))
	// Garmin đẩy mọi loại dữ liệu đã đăng ký trên portal về đây. Sai token thì
	// trả 404 như route không tồn tại. Lỗi khi ghi thì trả 500 để Garmin gửi lại.
	s.route("POST /v1/garmin/push/{token}", func(w http.ResponseWriter, r *http.Request) error {
		if !s.deps.Garmin.ValidPushToken(r.PathValue("token")) {
			http.NotFound(w, r)
			return nil
		}
		push, err := decodeGarminPush(r.Body)
		if err != nil {
			slog.WarnContext(r.Context(), "garmin.push_invalid", "error", err)
			return invalidRequest()
		}
		if err := s.deps.Garmin.HandlePush(r.Context(), push); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"received": true})
	})
}
