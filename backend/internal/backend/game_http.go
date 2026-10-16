package backend

import (
	"net/http"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// gameRoutes là API Ma Sói của app (3.8). Handler chỉ đọc request và gọi
// GameStore; kiểm quyền, luật và lỗi đều nằm ở store.
func (s *Server) gameRoutes() {
	s.route("GET /v1/games", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		list, err := s.deps.Games.List(r.Context(), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, list)
	}))
	s.route("POST /v1/games", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body CreateGameRequest
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		id, err := s.deps.Games.Create(r.Context(), body, v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 201, map[string]any{"id": id})
	}))
	s.route("GET /v1/games/{id}", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		d, err := s.deps.Games.Detail(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, d)
	}))
	s.route("GET /v1/games/{id}/feed", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		feed, err := s.deps.Games.Feed(r.Context(), r.PathValue("id"), r.URL.Query().Get("cursor"), v)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, feed)
	}))
	s.route("GET /v1/games/{id}/me", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		me, err := s.deps.Games.Me(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, me)
	}))
	s.route("POST /v1/games/{id}/registration", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		res, err := s.deps.Games.Register(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, res)
	}))
	s.route("DELETE /v1/games/{id}/registration", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		res, err := s.deps.Games.Unregister(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, res)
	}))
	s.route("POST /v1/games/{id}/actions", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		received := time.Now()
		var body gameActionBody
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		id := r.PathValue("id")
		if err := s.submitGameAction(r, ActionRequest{GameID: id, UID: v.UID, Source: "app", ReceivedAt: received}, body); err != nil {
			return err
		}
		me, err := s.deps.Games.Me(r.Context(), id, v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, me)
	}))

	// Lệnh admin của ván thử (X1). Store từ chối nếu ván không phải ván thử.
	s.route("POST /v1/games/{id}/admin/advance", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			ExpectedKey string `json:"expectedKey"`
		}
		if err := decodeJSON(r, &body); err != nil || body.ExpectedKey == "" {
			return invalidRequest()
		}
		res, err := s.deps.Games.AdminAdvance(r.Context(), r.PathValue("id"), body.ExpectedKey, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"steps": res.Steps, "status": res.Status, "taskKey": res.TaskKey, "nextAt": res.NextAt})
	}))
	s.route("POST /v1/games/{id}/admin/act-as", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		received := time.Now()
		var body struct {
			UID string `json:"uid"`
			gameActionBody
		}
		if err := decodeJSON(r, &body); err != nil || body.UID == "" {
			return invalidRequest()
		}
		req := ActionRequest{GameID: r.PathValue("id"), UID: body.UID, Source: "admin", ReceivedAt: received, ActAs: true}
		if err := s.submitGameAction(r, req, body.gameActionBody); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/km", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Round int     `json:"round"`
			UID   string  `json:"uid"`
			Km    float64 `json:"km"`
		}
		if err := decodeJSON(r, &body); err != nil || body.UID == "" {
			return invalidRequest()
		}
		if err := s.deps.Games.AdminSetKm(r.Context(), r.PathValue("id"), body.Round, body.UID, body.Km, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/roles", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Roles map[string]werewolf.Role `json:"roles"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		if err := s.deps.Games.SetForcedRoles(r.Context(), r.PathValue("id"), body.Roles, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/fake-players", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Count int `json:"count"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		uids, err := s.deps.Games.SetFakePlayers(r.Context(), r.PathValue("id"), body.Count, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"uids": uids})
	}))
}

type gameActionBody struct {
	Kind    werewolf.Kind `json:"kind"`
	Targets []string      `json:"targets"`
	Choice  string        `json:"choice"`
	Clear   bool          `json:"clear"`
}

// submitGameAction gửi một hành động qua W0; luật từ chối thì trả 409/422.
func (s *Server) submitGameAction(r *http.Request, req ActionRequest, body gameActionBody) error {
	if body.Kind == "" || len(body.Targets) > 2 {
		return invalidRequest()
	}
	req.Kind, req.Targets, req.Choice, req.Clear = body.Kind, body.Targets, body.Choice, body.Clear
	res, err := s.deps.Games.SubmitAction(r.Context(), req)
	if err != nil {
		return err
	}
	if res.Reject != nil {
		return rejectHTTP(req.Kind, res.Reject)
	}
	return nil
}

func (s *Server) gameHandler(next func(http.ResponseWriter, *http.Request, GameViewer) error) handler {
	return s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		return next(w, r, GameViewer{UID: uid, AppVersion: r.Header.Get("X-App-Version")})
	})
}

func (s *Server) gameAdmin(next func(http.ResponseWriter, *http.Request, GameViewer) error) handler {
	return s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), v.UID); err != nil {
			return err
		}
		return next(w, r, v)
	})
}
