package backend

import (
	"net/http"
)

func (s *Server) runRoomRoutes() {
	s.route("POST /v1/run-rooms", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body CreateRunRoomRequest
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		id, err := s.deps.RunRooms.Create(r.Context(), uid, body, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 201, map[string]any{"id": id})
	}))
	s.route("POST /v1/run-rooms/{id}/join", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Password string `json:"password"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		res, err := s.deps.RunRooms.Join(r.Context(), r.PathValue("id"), uid, body.Password, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, res)
	}))
	s.route("POST /v1/run-rooms/{id}/leave", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.RunRooms.Leave(r.Context(), r.PathValue("id"), uid, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/run-rooms/{id}/end", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.RunRooms.End(r.Context(), r.PathValue("id"), uid, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/run-rooms/{id}/voice", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		voice := s.deps.Voice
		if !voice.Enabled() {
			return errVoiceOff
		}
		roomID := r.PathValue("id")
		name, err := s.deps.RunRooms.VoiceMember(r.Context(), roomID, uid, s.now())
		if err != nil {
			return err
		}
		token, err := voice.Token(roomID, uid, name, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"url": voice.URL, "token": token})
	}))
	for _, action := range []string{roomApprove, roomDeny, roomKick} {
		s.route("POST /v1/run-rooms/{id}/members/{uid}/"+action, s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
			if err := s.deps.RunRooms.Moderate(r.Context(), r.PathValue("id"), uid, r.PathValue("uid"), action, s.now()); err != nil {
				return err
			}
			return writeJSON(w, 200, map[string]any{"ok": true})
		}))
	}
}
