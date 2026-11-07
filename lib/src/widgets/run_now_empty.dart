import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Trạng thái rỗng chung của app: một đường chạy trống, giữa sân là biểu
/// tượng hành của theme đang dùng, kèm lời nhắn. Tĩnh, không animation, để
/// list rỗng không tốn frame.
///
/// [compact] cho chỗ hẹp trong một thẻ/section; mặc định cho cả màn/list.
class RunNowEmpty extends StatelessWidget {
  const RunNowEmpty({
    required this.message,
    this.hint,
    this.action,
    this.compact = false,
    super.key,
  });

  final String message;
  final String? hint;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final iconHeight = compact ? 60.0 : 92.0;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 12 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RunNowEmptyIcon(height: iconHeight),
            SizedBox(height: compact ? 10 : 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.foreground,
                fontSize: compact ? 13.5 : 15,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: compact ? 12.5 : 13.5,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 10 : 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Riêng phần hình của [RunNowEmpty]: vòng sân điền kinh vẽ nét, làn giữa
/// đứt khúc, vạch đích, biểu tượng hành ở giữa sân.
class RunNowEmptyIcon extends StatelessWidget {
  const RunNowEmptyIcon({this.height = 92, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    // Nền sáng thì nét nhỏ dùng sắc đậm, như quy ước của palette.
    final line = palette.appearance == RunNowAppearance.light
        ? palette.accentDeep
        : palette.accent;
    final width = height * 1.5;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _EmptyTrackPainter(line),
          child: Center(
            child: Icon(
              palette.element.icon,
              size: height * 0.36,
              color: line.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTrackPainter extends CustomPainter {
  const _EmptyTrackPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.height * 0.035;
    final lane = size.height * 0.15;
    final outer = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final inner = outer.deflate(lane);
    final middle = outer.deflate(lane / 2);

    RRect stadium(Rect r) =>
        RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));

    final infield = stadium(inner.deflate(stroke));
    canvas.drawRRect(infield, Paint()..color = color.withValues(alpha: 0.1));

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.55);
    canvas
      ..drawRRect(stadium(outer), edge)
      ..drawRRect(stadium(inner), edge);

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.35);
    final laneLine = Path()..addRRect(stadium(middle));
    for (final PathMetric metric in laneLine.computeMetrics()) {
      final step = size.height * 0.11;
      for (var d = 0.0; d < metric.length; d += step * 2) {
        canvas.drawPath(metric.extractPath(d, d + step), dash);
      }
    }

    // Vạch đích cắt ngang làn ở cạnh dưới, lệch phải.
    final finishX = outer.left + outer.width * 0.62;
    canvas.drawLine(
      Offset(finishX, inner.bottom),
      Offset(finishX, outer.bottom),
      Paint()
        ..strokeWidth = stroke * 1.4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_EmptyTrackPainter oldDelegate) =>
      oldDelegate.color != color;
}
