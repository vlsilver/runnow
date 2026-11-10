import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart' show LatLng;

/// Split ngắn hơn mức này (đoạn lẻ cuối buổi) thì pace không đáng tin, không
/// đưa lên biểu đồ.
const runCardMinSplitMeters = 300.0;

/// Chiếu kinh/vĩ độ lên mặt phẳng rồi đặt giữa [box], giữ đúng tỉ lệ hình
/// đường chạy. Đường chỉ có một điểm hay đứng yên thì trả rỗng.
List<Offset> fitRunRoute(List<LatLng> points, Rect box) {
  if (points.length < 2) return const [];
  final lat0 =
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  final k = math.cos(lat0 * math.pi / 180);
  final xs = [for (final p in points) p.longitude * k];
  final ys = [for (final p in points) -p.latitude];
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  final spanX = maxX - minX, spanY = maxY - minY;
  if (spanX == 0 && spanY == 0) return const [];
  final scale = math.min(
    spanX == 0 ? double.infinity : box.width / spanX,
    spanY == 0 ? double.infinity : box.height / spanY,
  );
  final dx = box.left + (box.width - spanX * scale) / 2;
  final dy = box.top + (box.height - spanY * scale) / 2;
  return [
    for (var i = 0; i < xs.length; i++)
      Offset(dx + (xs[i] - minX) * scale, dy + (ys[i] - minY) * scale),
  ];
}

/// Đường cong đi qua đúng từng điểm (Catmull-Rom). Điểm điều khiển bị kẹp trong
/// khoảng cao thấp của đoạn để đường không vọt quá giá trị thật.
void curveThroughPoints(Path path, List<Offset> points) {
  double within(double y, Offset a, Offset b) =>
      y.clamp(math.min(a.dy, b.dy), math.max(a.dy, b.dy));
  for (var i = 0; i + 1 < points.length; i++) {
    final before = points[math.max(i - 1, 0)];
    final from = points[i];
    final to = points[i + 1];
    final after = points[math.min(i + 2, points.length - 1)];
    path.cubicTo(
      from.dx + (to.dx - before.dx) / 6,
      within(from.dy + (to.dy - before.dy) / 6, from, to),
      to.dx - (after.dx - from.dx) / 6,
      within(to.dy - (after.dy - from.dy) / 6, from, to),
      to.dx,
      to.dy,
    );
  }
}
