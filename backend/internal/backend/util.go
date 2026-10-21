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

// activityDetailURL trỏ tới trang chi tiết hoạt động CÔNG KHAI của app 3i Run.
//
// Route `/s/:uid/:id` (lib/src/app.dart) được _AuthGate cho đi thẳng, không
// cần đăng nhập, và tự đọc dữ liệu từ endpoint public
// `/v1/public/activities/{uid}/{id}/summary`. Nhờ vậy link chia sẻ (Telegram)
// mở được cho BẤT KỲ ai trong web app — kể cả người chưa đăng nhập.
func activityDetailURL(webBaseURL, uid, activityID string) string {
	return webBaseURL + "/s/" + url.PathEscape(uid) + "/" + url.PathEscape(activityID)
}
