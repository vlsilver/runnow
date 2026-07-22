/// Sinh key cho collection `users/{uid}/periodStats/{periodType}:{periodKey}`
/// (backend ghi, xem `backend/internal/backend/period_stats_service.go`).
/// Key phải khớp từng ký tự với phía Go: ngày `2026-07-15`, tuần ISO 8601
/// `2026-W29`, tháng `2026-07` — đều sort đúng thứ tự thời gian theo chuỗi.
///
/// Backend tính theo lịch Việt Nam; phía app dùng ngày local của thiết bị
/// (app phục vụ người dùng VN nên hai lịch trùng nhau trong thực tế).
library;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// Tuần ISO 8601 (thứ 2 là đầu tuần, tuần "thuộc" năm chứa ngày thứ 5 của
/// nó) — cùng quy tắc với `time.Time.ISOWeek` bên Go, nên qua biên năm mới
/// (vd 01/01/2027 thuộc 2026-W53) hai bên vẫn ra cùng key.
String weekKey(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstJanuary = DateTime(thursday.year, 1, 1);
  final week = 1 + thursday.difference(firstJanuary).inDays ~/ 7;
  return '${thursday.year.toString().padLeft(4, '0')}-'
      'W${week.toString().padLeft(2, '0')}';
}
