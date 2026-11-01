import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Đặt các điểm của routeSketch (0..1000, xem ActivitySummary.routeSketch) vào
/// giữa [box], giữ tỉ lệ ngang dọc.
List<Offset> fitRouteSketch(List<int> sketch, Rect box) {
  var width = 0;
  var height = 0;
  for (var i = 0; i + 1 < sketch.length; i += 2) {
    width = math.max(width, sketch[i]);
    height = math.max(height, sketch[i + 1]);
  }
  final span = math.max(width, height);
  if (span == 0) return const [];
  final scale = math.min(box.width, box.height) / span;
  final left = box.left + (box.width - width * scale) / 2;
  final top = box.top + (box.height - height * scale) / 2;
  return [
    for (var i = 0; i + 1 < sketch.length; i += 2)
      Offset(left + sketch[i] * scale, top + sketch[i + 1] * scale),
  ];
}

/// Màu của nền tuyến trên thẻ, lấy từ hành đang chọn. Buổi đi bộ vẽ nét nhạt
/// hơn để buổi chạy nổi lên khi lướt.
class RouteArtColors {
  const RouteArtColors({
    required this.surface,
    required this.art,
    required this.contour,
    required this.halo,
    required this.stroke,
  });

  factory RouteArtColors.of(RunNowPalette palette, {required bool walk}) {
    final ramp = palette.element.ramp;
    final surface = palette.glassStart;
    if (palette.appearance == RunNowAppearance.light) {
      final art = palette.tint;
      return RouteArtColors(
        surface: surface,
        art: art,
        contour: Color.lerp(art, palette.ink, 0.08)!,
        halo: Color.lerp(art, ramp[0], 0.7)!,
        stroke: walk ? Color.lerp(ramp[3], palette.textMuted, 0.5)! : ramp[3],
      );
    }
    final art = Color.lerp(surface, ramp[4], 0.42)!;
    return RouteArtColors(
      surface: surface,
      art: art,
      contour: Color.lerp(art, palette.ink, 0.1)!,
      halo: Color.lerp(art, ramp[2], 0.35)!,
      stroke: walk ? Color.lerp(ramp[1], palette.ink, 0.45)! : ramp[1],
    );
  }

  final Color surface;
  final Color art;
  final Color contour;
  final Color halo;
  final Color stroke;
}

/// Nền tuyến của một thẻ: mấy đường đồng mức trang trí, rồi dáng tuyến có
/// viền sáng, chấm rỗng ở điểm xuất phát, chấm đặc ở điểm về.
class RouteSketchArt extends StatelessWidget {
  const RouteSketchArt({required this.sketch, required this.colors, super.key});

  final List<int> sketch;
  final RouteArtColors colors;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RouteSketchPainter(sketch, colors),
      child: const SizedBox.expand(),
    );
  }
}

class _RouteSketchPainter extends CustomPainter {
  _RouteSketchPainter(this.sketch, this.colors);

  final List<int> sketch;
  final RouteArtColors colors;

  // Phần bên trái khung bị dải mờ của thẻ che, nên tuyến nằm lệch phải.
  static const _fadeInset = 60.0;
  static const _pad = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.art);
    _paintContours(canvas, size);
    final points = fitRouteSketch(
      sketch,
      Rect.fromLTRB(_fadeInset, _pad, size.width - _pad, size.height - _pad),
    );
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    Paint line(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, line(colors.halo, 9))
      ..drawPath(path, line(colors.stroke, 3.2))
      ..drawCircle(points.first, 4.5, Paint()..color = colors.surface)
      ..drawCircle(points.first, 4.5, line(colors.stroke, 2.4))
      ..drawCircle(points.last, 5, Paint()..color = colors.stroke);
  }

  // Bốn đường đồng mức vẽ trên lưới 220x128 rồi giãn theo khung thật.
  void _paintContours(Canvas canvas, Size size) {
    final sx = size.width / 220;
    final sy = size.height / 128;
    final paint = Paint()
      ..color = colors.contour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final c in const [
      [
        -10.0,
        30.0,
        40.0,
        10.0,
        90.0,
        40.0,
        140.0,
        20.0,
        190.0,
        0.0,
        220.0,
        10.0,
        240.0,
        30.0,
      ],
      [
        -10.0,
        64.0,
        30.0,
        50.0,
        80.0,
        76.0,
        130.0,
        58.0,
        180.0,
        40.0,
        210.0,
        44.0,
        240.0,
        66.0,
      ],
      [
        -10.0,
        98.0,
        40.0,
        84.0,
        90.0,
        112.0,
        140.0,
        94.0,
        190.0,
        76.0,
        210.0,
        80.0,
        240.0,
        104.0,
      ],
      [
        -10.0,
        126.0,
        50.0,
        112.0,
        100.0,
        136.0,
        150.0,
        122.0,
        200.0,
        108.0,
        220.0,
        110.0,
        240.0,
        128.0,
      ],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0] * sx, c[1] * sy)
          ..cubicTo(
            c[2] * sx,
            c[3] * sy,
            c[4] * sx,
            c[5] * sy,
            c[6] * sx,
            c[7] * sy,
          )
          ..cubicTo(
            c[8] * sx,
            c[9] * sy,
            c[10] * sx,
            c[11] * sy,
            c[12] * sx,
            c[13] * sy,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RouteSketchPainter old) =>
      old.sketch != sketch || old.colors != colors;
}
