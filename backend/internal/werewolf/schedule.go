package werewolf

import "time"

// vietnam là giờ nghiệp vụ (+7, không có giờ mùa hè).
var vietnam = time.FixedZone("ICT", 7*3600)

// FirstNight là mốc 22h đầu tiên cách lúc Start ít nhất 2 giờ (R12, C1).
func FirstNight(start time.Time) time.Time {
	earliest := start.Add(2 * time.Hour).In(vietnam)
	night := time.Date(earliest.Year(), earliest.Month(), earliest.Day(), 22, 0, 0, 0, vietnam)
	if night.Before(earliest) {
		night = night.AddDate(0, 0, 1)
	}
	return night
}
