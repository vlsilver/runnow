package backend

import (
	"context"
	"net/http"
	"slices"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Cài đặt thông báo của từng người: tắt theo nhóm, không theo từng kind, vì
// người dùng nghĩ theo việc ("quà", "Ma Sói") chứ không theo từng sự kiện.
// Lưu ở pushPrefs/{uid}.off; chỉ backend đọc ghi, như pushTokens. Danh sách
// nhóm và nhãn do backend trả về để thêm nhóm không cần ra bản app.
type pushGroup struct {
	ID    string
	Label string
	// kinds là các tiền tố kind của push thuộc nhóm.
	kinds []string
}

var pushGroups = []pushGroup{
	{ID: "live", Label: "Người trong club bắt đầu chạy live", kinds: []string{"live_"}},
	{ID: "rank", Label: "Lọt top 3 bảng xếp hạng tuần, tháng", kinds: []string{"rank_top"}},
	{ID: "gift", Label: "Quà: trúng quà, quà đã được trao", kinds: []string{"rank_reward", "contract_gift", "gift_"}},
	{ID: "room", Label: "Phòng chạy: xin vào, được nhận, sắp tới giờ", kinds: []string{"room_"}},
	{ID: "game", Label: "Ma Sói: ván bắt đầu", kinds: []string{"game_"}},
	{ID: "territory", Label: "Lãnh địa: bị chiếm ô", kinds: []string{"territory_"}},
}

// pushGroupOf trả nhóm của một kind; rỗng khi kind không thuộc nhóm nào, tức
// người dùng không tắt được.
func pushGroupOf(kind string) string {
	for _, g := range pushGroups {
		for _, k := range g.kinds {
			if strings.HasPrefix(kind, k) {
				return g.ID
			}
		}
	}
	return ""
}

type PushPrefItem struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	On    bool   `json:"on"`
}

type PushPrefsView struct {
	Groups []PushPrefItem `json:"groups"`
}

func (s *PushService) prefsRef(uid string) *firestore.DocumentRef {
	return s.db.Collection("pushPrefs").Doc(uid)
}

// Prefs trả mọi nhóm, kèm nhóm nào người dùng đang bật.
func (s *PushService) Prefs(ctx context.Context, uid string) (PushPrefsView, error) {
	data, err := getData(ctx, s.prefsRef(uid))
	if err != nil {
		return PushPrefsView{}, err
	}
	off := stringList(data["off"])
	// Nhóm Lãnh địa chỉ hiện khi tính năng đã bật, để app chưa có màn không
	// thấy công tắc vô nghĩa.
	territory, err := loadTerritoryConfig(ctx, s.db)
	if err != nil {
		return PushPrefsView{}, err
	}
	view := PushPrefsView{Groups: make([]PushPrefItem, 0, len(pushGroups))}
	for _, g := range pushGroups {
		if g.ID == "territory" && !territory.Enabled {
			continue
		}
		view.Groups = append(view.Groups, PushPrefItem{ID: g.ID, Label: g.Label, On: !slices.Contains(off, g.ID)})
	}
	return view, nil
}

// SetPrefs thay danh sách nhóm đang tắt. Nhóm lạ thì từ chối cả lượt, để app
// gửi sai không âm thầm mất cài đặt.
func (s *PushService) SetPrefs(ctx context.Context, uid string, off []string, now time.Time) error {
	clean := []string{}
	for _, id := range off {
		if !slices.ContainsFunc(pushGroups, func(g pushGroup) bool { return g.ID == id }) {
			return invalidRequest()
		}
		if !slices.Contains(clean, id) {
			clean = append(clean, id)
		}
	}
	_, err := s.prefsRef(uid).Set(ctx, map[string]any{"off": clean, "updatedAt": now})
	return err
}

// optedOut trả những uid trong uids đã tắt nhóm của kind.
func (s *PushService) optedOut(ctx context.Context, uids []string, kind string) (map[string]bool, error) {
	group := pushGroupOf(kind)
	out := map[string]bool{}
	if group == "" || len(uids) == 0 {
		return out, nil
	}
	refs := make([]*firestore.DocumentRef, len(uids))
	for i, uid := range uids {
		refs[i] = s.prefsRef(uid)
	}
	docs, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	for i, d := range docs {
		if d.Exists() && slices.Contains(stringList(d.Data()["off"]), group) {
			out[uids[i]] = true
		}
	}
	return out, nil
}

func stringList(v any) []string {
	var out []string
	for _, x := range anyList(v) {
		if s, ok := x.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func (s *Server) pushPrefRoutes() {
	s.route("GET /v1/me/push-prefs", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		view, err := s.deps.Push.Prefs(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, view)
	}))
	s.route("PUT /v1/me/push-prefs", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Off []string `json:"off"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.Push.SetPrefs(r.Context(), uid, body.Off, s.now()); err != nil {
			return err
		}
		view, err := s.deps.Push.Prefs(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, view)
	}))
}
