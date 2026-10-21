import 'package:flutter/material.dart';

import 'training_plan_models.dart';

/// Glyph cường độ theo loại bài — các thanh bar (giống SVG trong design):
/// easy 2 bar thấp dần · long 4 bar bằng · tempo 3 bar tăng · interval 5 bar
/// cao–thấp xen kẽ · rest 1 thanh ngang · race cột cờ.
class WorkoutGlyph extends StatelessWidget {
  const WorkoutGlyph({super.key, required this.type, required this.color, this.size = 26});

  final WorkoutType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.56,
      child: CustomPaint(painter: _GlyphPainter(type, color)),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.type, this.color);
  final WorkoutType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final h = size.height;

    void bars(List<double> hs) {
      final n = hs.length;
      final gap = size.width * 0.14 / (n - 1).clamp(1, 99);
      final bw = (size.width - gap * (n - 1)) / n;
      for (var i = 0; i < n; i++) {
        final bh = h * hs[i];
        final x = i * (bw + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, h - bh, bw, bh),
            Radius.circular(bw * 0.4),
          ),
          p,
        );
      }
    }

    switch (type) {
      case WorkoutType.easy:
        bars([0.7, 0.45]);
      case WorkoutType.long:
        bars([0.7, 0.7, 0.7, 0.7]);
      case WorkoutType.tempo:
        bars([0.45, 0.7, 1.0]);
      case WorkoutType.interval:
        bars([0.5, 1.0, 0.5, 1.0, 0.5]);
      case WorkoutType.rest:
        final y = h * 0.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.1, y - h * 0.09, size.width * 0.8, h * 0.18),
            Radius.circular(h * 0.09),
          ),
          p,
        );
      case WorkoutType.race:
        // Cột cờ + lá cờ.
        final poleW = size.width * 0.13;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.14, 0, poleW, h),
            Radius.circular(poleW * 0.4),
          ),
          p,
        );
        final path = Path()
          ..moveTo(size.width * 0.14 + poleW, h * 0.06)
          ..lineTo(size.width * 0.86, h * 0.28)
          ..lineTo(size.width * 0.14 + poleW, h * 0.5)
          ..close();
        canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) =>
      old.type != type || old.color != color;
}
