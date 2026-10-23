/// Km còn thiếu tới [nextKm], làm tròn lên một chữ số để "chạy thêm" không bao
/// giờ thành 0 km. Trừ epsilon vì 5 − 4,1 ra 0,9000000000000004 và ceil sẽ đẩy
/// lên 1.
double agentKmLeft(double nextKm, double runKm) =>
    ((nextKm - runKm) * 10 - 1e-9).ceil() / 10;

/// 2.4 → "2,4", 1.0 → "1".
String formatAgentKm(double km) {
  final text = km == km.roundToDouble()
      ? km.toInt().toString()
      : km.toStringAsFixed(1);
  return text.replaceAll('.', ',');
}
