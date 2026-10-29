package backend

import (
	"context"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

// agentDMQuota là số tin bot của một người được nói hôm nay (giờ VN), gồm câu
// trả lời chat riêng mọi kênh và tin trong mọi phòng: dmBaseDaily tin sẵn, cộng
// dmPerKm tin cho mỗi km trọn chạy hay đi bộ hôm nay, không quá dmDailyMax. Km
// lấy từ todayKm, cùng chỗ với lượt vẽ ảnh.
type agentDMQuota struct {
	runKm float64
	max   int64
	// nextKm và nextMax là mốc km trọn kế tiếp và max ở mốc đó; nil khi chạy thêm
	// cũng không mở thêm câu nào (đã chạm trần hoặc dmPerKm là 0).
	nextKm  *float64
	nextMax *int64
}

func newAgentDMQuota(lim agentLimits, runKm float64) agentDMQuota {
	full := int64(math.Floor(runKm))
	at := func(km int64) int64 { return min(lim.dmDailyMax, lim.dmBase+lim.dmPerKm*km) }
	q := agentDMQuota{runKm: runKm, max: at(full)}
	if next := at(full + 1); next > q.max {
		km := float64(full + 1)
		q.nextKm, q.nextMax = &km, &next
	}
	return q
}

func (s *AgentStore) dmQuota(ctx context.Context, lim agentLimits, uid string, wall time.Time) (agentDMQuota, error) {
	runKm, err := s.todayKm(ctx, uid, wall)
	if err != nil {
		return agentDMQuota{}, err
	}
	return newAgentDMQuota(lim, runKm), nil
}

// dmUsedToday là số tin bot đã nói hôm nay (giờ VN), đếm trên doc bot.
func dmUsedToday(agent map[string]any, wall time.Time) int64 {
	if stringValue(agent["dmDay"]) != vnDay(wall) {
		return 0
	}
	return int64(number(agent["dmDayCount"]))
}

// dmLimitReply là câu bot trả khi chủ hết lượt hôm nay. Còn mốc km thì nói
// luôn cách mở thêm, vì trên Telegram chủ không thấy thẻ km của app.
func dmLimitReply(q agentDMQuota) string {
	if q.nextKm == nil {
		return agentBudgetReply
	}
	return fmt.Sprintf("Hôm nay mình hết lượt nói rồi. Bạn chạy hay đi bộ thêm %s km là mình nói tiếp được %d câu nữa, không thì qua 0h mình nói tiếp nhé.",
		viKmLeft(*q.nextKm-q.runKm), *q.nextMax-q.max)
}

// viKmLeft làm tròn lên 0,1 km cho chạy đúng số đó là đủ mốc, viết dấu phẩy
// thập phân. Trừ 1e-9 để 5 − 4,1 (ra 0,9000000000000004) không thành 1.
func viKmLeft(km float64) string {
	return strings.Replace(strconv.FormatFloat(math.Ceil(km*10-1e-9)/10, 'f', -1, 64), ".", ",", 1)
}
