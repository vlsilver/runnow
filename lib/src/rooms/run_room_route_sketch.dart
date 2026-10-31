import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/run_contracts/run_contract_models.dart';

List<LatLng> runRoomRouteLatLngs(RunContractRoute route) => [
  for (final p in route.points) LatLng(p.latitude, p.longitude),
];

/// "6,4 km" cho quãng tuyến của phòng.
String runRoomRouteKm(RunContractRoute route) =>
    '${(route.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Hình tuyến không có nền map: thumbnail ở danh sách, thẻ phòng, sheet mở
/// phòng. Giữ tỉ lệ thật của tuyến và canh giữa trong khung.
class RunRoomRouteSketch extends StatelessWidget {
  const RunRoomRouteSketch({
    required this.route,
    required this.color,
    this.dashed = false,
    this.strokeWidth = 3,
    this.padding = const EdgeInsets.all(8),
    super.key,
  });

  final RunContractRoute route;
  final Color color;
  final bool dashed;
  final double strokeWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _SketchPainter(
      points: runRoomRouteLatLngs(route),
      color: color,
      dashed: dashed,
      strokeWidth: strokeWidth,
      padding: padding,
    ),
    child: const SizedBox.expand(),
  );
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.points,
    required this.color,
    required this.dashed,
    required this.strokeWidth,
    required this.padding,
  });

  final List<LatLng> points;
  final Color color;
  final bool dashed;
  final double strokeWidth;
  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final box = padding.deflateRect(Offset.zero & size);
    // Chiếu phẳng: kinh độ co theo cos vĩ độ để tuyến không bị bè ngang.
    final midLat =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final kx = math.cos(midLat * math.pi / 180);
    final xs = [for (final p in points) p.longitude * kx];
    final ys = [for (final p in points) -p.latitude];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final w = math.max(maxX - minX, 1e-9), h = math.max(maxY - minY, 1e-9);
    final scale = math.min(box.width / w, box.height / h);
    final dx = box.left + (box.width - w * scale) / 2;
    final dy = box.top + (box.height - h * scale) / 2;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(
        dx + (xs[i] - minX) * scale,
        dy + (ys[i] - minY) * scale,
      );
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dashed ? _dash(path, strokeWidth * 2.4) : path, paint);
  }

  static Path _dash(Path source, double length) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += length * 2) {
        out.addPath(metric.extractPath(d, d + length), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) =>
      old.points != points ||
      old.color != color ||
      old.dashed != dashed ||
      old.strokeWidth != strokeWidth;
}
