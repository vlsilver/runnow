// Tiện ích định dạng cho SỐ BƯỚC (Apple Health) — dùng chung giữa card ở Nhật
// ký và trang chi tiết, tránh lặp code.

/// Mục tiêu bước/ngày mặc định (chuẩn wellness phổ biến) — dùng cho thanh tiến độ.
const stepDailyGoal = 10000;

/// 12345 → "12.345" (dấu chấm phân cách nghìn, kiểu VN).
String stepThousands(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]}.',
);

/// Quãng đường ƯỚC LƯỢNG từ số bước (mét). Sải chân trung bình ~0.75 m — chỉ để
/// tham khảo, nên luôn hiển thị kèm dấu "≈".
double stepDistanceMeters(int steps) => steps * 0.75;

/// "≈"-label quãng đường ước lượng TỪ BƯỚC: "1,6 km" (≥10 km bỏ thập phân).
String stepDistanceKm(int steps) => _km(stepDistanceMeters(steps));

/// Quãng đường THẬT từ mét (Apple Health "Walking + Running Distance") → "6,2 km".
String stepKmFromMeters(double meters) => _km(meters);

String _km(double meters) {
  final km = meters / 1000;
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1).replaceAll('.', ',')} km';
}

const _stepWeekdays = <String>[
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

/// "YYYY-MM-DD" → "Hôm nay · 17/08" / "Hôm qua · 16/08" / "Thứ Hai · 15/08".
String stepRelativeDate(String key) {
  final date = DateTime.tryParse(key);
  if (date == null) return key;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  final dm =
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}';
  final label = switch (diff) {
    0 => 'Hôm nay',
    1 => 'Hôm qua',
    _ => _stepWeekdays[(date.weekday - 1) % 7],
  };
  return '$label · $dm';
}

/// Tháng 3 chữ (khớp rail của ActivityTile): 1→JAN … 12→DEC.
String stepMonthShort(int month) => const [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
][(month - 1) % 12];
