package backend

import (
	"encoding/json"
	"fmt"
	"math"
	"net/url"
)

func jsonMarshal(v any) ([]byte, error) { return json.Marshal(v) }
func number(v any) float64 {
	switch n := v.(type) {
	case float64:
		if math.IsNaN(n) || math.IsInf(n, 0) {
			return 0
		}
		return n
	case int:
		return float64(n)
	case int64:
		return float64(n)
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}

func falseLike(value any) bool {
	return value == false || fmt.Sprint(value) == "false"
}

// activityDetailURL trỏ tới màn hình chi tiết buổi chạy trong app 3i Run.
//
// Đây là route đã có sẵn của app (`/club/:uid/activity/:id` trong
// lib/src/app.dart), nên link mở được ở cả bản web lẫn bản native khi đã
// cấu hình universal link. Người chưa đăng nhập sẽ dừng ở màn hình đăng
// nhập — đúng ý đồ, dữ liệu buổi chạy không phơi ra cho người lạ.
func activityDetailURL(webBaseURL, uid, activityID string) string {
	return webBaseURL + "/club/" + url.PathEscape(uid) + "/activity/" + url.PathEscape(activityID)
}
