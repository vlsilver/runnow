package backend

import (
	"context"
	"log/slog"
	"net/http"
	"slices"

	"cloud.google.com/go/firestore"
)

// Mỗi quyền là một mảng uid trong doc config sẵn có. Admin sửa trên web thì
// ghi đúng mảng đó, nên RequireAdmin, isTester và AgentStore.access vẫn đọc
// như cũ, đổi xong có hiệu lực ngay ở request kế.
type adminRole struct{ col, doc, field string }

var adminRoles = map[string]adminRole{
	"admin":  {"gameState", "config", "adminUids"},
	"tester": {"gameState", "config", "testerUids"},
	"bot":    {"agentState", "config", "memberUids"},
}

var (
	errUnknownRole     = &HTTPError{Status: http.StatusNotFound, Code: "unknown_role", Message: "Không có quyền này."}
	errUserNotFound    = &HTTPError{Status: http.StatusNotFound, Code: "user_not_found", Message: "Không tìm thấy thành viên này."}
	errRemoveSelfAdmin = &HTTPError{Status: http.StatusConflict, Code: "cannot_remove_self", Message: "Không tự bỏ quyền admin của mình được."}
)

// AdminRoles trả uid theo từng quyền, sort để thứ tự tất định. Doc chưa có
// thì quyền đó rỗng.
func (s *GameStore) AdminRoles(ctx context.Context) (map[string][]string, error) {
	out := map[string][]string{}
	for name, role := range adminRoles {
		doc, err := getData(ctx, s.db.Collection(role.col).Doc(role.doc))
		if err != nil {
			return nil, err
		}
		uids := []string{}
		for _, v := range anyList(doc[role.field]) {
			if uid := stringValue(v); uid != "" {
				uids = append(uids, uid)
			}
		}
		slices.Sort(uids)
		out[name] = uids
	}
	return out, nil
}

// SetRole cấp hoặc bỏ một quyền, gọi lại bao nhiêu lần cũng vậy. Quyền admin
// của người gọi được kiểm lại trong transaction: hai admin bỏ quyền nhau cùng
// lúc thì chỉ một người thành công, nên không bao giờ hết admin.
func (s *GameStore) SetRole(ctx context.Context, by, name, uid string, grant bool) error {
	role, ok := adminRoles[name]
	if !ok {
		return errUnknownRole
	}
	if name == "admin" && !grant && uid == by {
		return errRemoveSelfAdmin
	}
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		cfg, err := getOptional(tx, s.db.Collection("gameState").Doc("config"))
		if err != nil {
			return err
		}
		admin := false
		if cfg.Exists() {
			admin = slices.ContainsFunc(anyList(cfg.Data()["adminUids"]), func(v any) bool { return stringValue(v) == by })
		}
		if !admin {
			return errNotAdmin
		}
		var op any = firestore.ArrayRemove(uid)
		if grant {
			// Chỉ cấp cho người đã đăng nhập app, để gõ sai uid không thành quyền ma.
			prof, err := getOptional(tx, s.db.Collection("publicProfiles").Doc(uid))
			if err != nil {
				return err
			}
			if !prof.Exists() {
				return errUserNotFound
			}
			op = firestore.ArrayUnion(uid)
		}
		return tx.Set(s.db.Collection(role.col).Doc(role.doc), map[string]any{role.field: op}, firestore.MergeAll)
	})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "admin.role_changed", "by", by, "role", name, "uid", uid, "grant", grant)
	return nil
}

// Trang admin trên web. Token Telegram và Strava không đi qua đây: chúng nằm ở
// Secret Manager, chỉ service cần mới được gắn (api không có token bot).
func (s *Server) adminRoutes() {
	s.route("GET /v1/admin/settings", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		roles, err := s.deps.Games.AdminRoles(r.Context())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{
			"roles":    roles,
			"telegram": map[string]any{"chatId": s.config.TelegramChatID, "botUsername": s.config.TelegramBotUsername},
		})
	}))
	for method, grant := range map[string]bool{"POST": true, "DELETE": false} {
		s.route(method+" /v1/admin/roles/{role}/{uid}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
			if err := s.deps.Games.SetRole(r.Context(), uid, r.PathValue("role"), r.PathValue("uid"), grant); err != nil {
				return err
			}
			return writeJSON(w, 200, map[string]any{"ok": true})
		}))
	}
}
