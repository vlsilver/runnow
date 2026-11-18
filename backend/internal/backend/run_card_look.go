package backend

import (
	"context"
	"maps"
	"regexp"
	"strings"

	"cloud.google.com/go/firestore"
)

// Vẻ ngoài chủ thẻ chọn cho thẻ buổi chạy nằm ở field look của doc thẻ:
// style là kiểu thẻ ("blueprint.top", "city.top.map"), skin là bộ màu
// ("dark.fire"), layout là chỗ, cỡ, màu từng phần chủ thẻ đã chỉnh ở mặt
// trước. Thẻ khoe chép cả look để người khác thấy thẻ đúng như chủ
// thẻ chọn. Backend không biết tên bộ nào, chỉ giữ chuỗi đúng dạng: app thêm
// bộ mới không cần deploy backend, app gặp tên lạ thì vẽ kiểu gốc.

const maxRunCardLooks = 100

var (
	runCardStylePattern = regexp.MustCompile(`^[A-Za-z0-9]{1,24}(\.[A-Za-z0-9]{1,24}){1,2}$`)
	runCardSkinPattern  = regexp.MustCompile(`^[A-Za-z0-9]{1,24}\.[A-Za-z0-9]{1,24}$`)
	// Backend không đọc layout, chỉ chặn chuỗi lạ và chuỗi phình to.
	runCardLayoutPattern = regexp.MustCompile(`^[a-z0-9:,;]{1,200}$`)
)

// RunCardLook là vẻ ngoài của một thẻ. Field vắng thì giữ giá trị đang có;
// skin rỗng là bỏ bộ màu riêng, thẻ về theo theme của người xem; layout
// rỗng là bỏ.
type RunCardLook struct {
	ActivityID string  `json:"activityId"`
	Style      *string `json:"style"`
	Skin       *string `json:"skin"`
	Layout     *string `json:"layout"`
}

// RunCardLooksRequest đặt vẻ ngoài cho nhiều thẻ một lần. Fill thì chỉ điền
// field thẻ chưa có, để máy đẩy bù lựa chọn cũ không đè lựa chọn mới hơn đặt
// từ máy khác.
type RunCardLooksRequest struct {
	Looks []RunCardLook `json:"looks"`
	Fill  bool          `json:"fill"`
}

func (r RunCardLooksRequest) valid() bool {
	if len(r.Looks) == 0 || len(r.Looks) > maxRunCardLooks {
		return false
	}
	seen := map[string]bool{}
	for _, l := range r.Looks {
		id := l.ActivityID
		if id == "" || len(id) > 128 || strings.Contains(id, "/") || id == "." || id == ".." || (strings.HasPrefix(id, "__") && strings.HasSuffix(id, "__")) || seen[id] {
			return false
		}
		seen[id] = true
		if l.Style == nil && l.Skin == nil && l.Layout == nil {
			return false
		}
		if l.Style != nil && !runCardStylePattern.MatchString(*l.Style) {
			return false
		}
		if l.Skin != nil && *l.Skin != "" && !runCardSkinPattern.MatchString(*l.Skin) {
			return false
		}
		if l.Layout != nil && *l.Layout != "" && !runCardLayoutPattern.MatchString(*l.Layout) {
			return false
		}
	}
	return true
}

// mergeRunCardLook trả look sau khi áp set lên cur, và có đổi gì không.
func mergeRunCardLook(cur map[string]any, set RunCardLook, fill bool) (map[string]any, bool) {
	next := maps.Clone(cur)
	if next == nil {
		next = map[string]any{}
	}
	changed := false
	put := func(key string, value *string) {
		if value == nil {
			return
		}
		old, has := cur[key]
		if fill && has {
			return
		}
		if *value == "" {
			if has {
				delete(next, key)
				changed = true
			}
			return
		}
		if old != *value {
			next[key] = *value
			changed = true
		}
	}
	put("style", set.Style)
	put("skin", set.Skin)
	put("layout", set.Layout)
	return next, changed
}

// SetLooks đặt vẻ ngoài cho các thẻ buổi chạy của uid, và cho thẻ khoe của
// chúng nếu đang khoe. Thẻ không có (chưa lật, đã xoá) thì bỏ qua: máy đẩy bù
// có thể còn giữ id của thẻ không còn. Gọi lại cùng nội dung không ghi gì.
func (s *RunCardStore) SetLooks(ctx context.Context, uid string, req RunCardLooksRequest) error {
	if !req.valid() {
		return invalidRequest()
	}
	refs := make([]*firestore.DocumentRef, 0, 2*len(req.Looks))
	for _, l := range req.Looks {
		refs = append(refs, s.cardRef(uid, l.ActivityID), s.clubCardRef(uid, l.ActivityID))
	}
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snaps, err := tx.GetAll(refs)
		if err != nil {
			return err
		}
		for i, l := range req.Looks {
			card, shared := snaps[2*i], snaps[2*i+1]
			if !card.Exists() {
				continue
			}
			cur, _ := card.Data()["look"].(map[string]any)
			next, changed := mergeRunCardLook(cur, l, req.Fill)
			if !changed {
				continue
			}
			update := []firestore.Update{{Path: "look", Value: next}}
			if err := tx.Update(card.Ref, update); err != nil {
				return err
			}
			if shared.Exists() {
				if err := tx.Update(shared.Ref, update); err != nil {
					return err
				}
			}
		}
		return nil
	})
}
