import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

enum CreatePosterKind { wolf, live, coach }

/// Ô có tranh trên trang Tạo mới: Ma Sói, Live hẹn giờ, Giáo án AI.
class CreatePosterTile extends StatelessWidget {
  const CreatePosterTile({
    super.key,
    required this.kind,
    required this.title,
    required this.onTap,
    this.height = 124,
  });

  final CreatePosterKind kind;
  final String title;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final night = palette.accentNight;
    final (bg, fg) = switch (kind) {
      CreatePosterKind.wolf => (night, Colors.white),
      CreatePosterKind.live => (
        Color.lerp(palette.accentDeep, night, 0.35)!,
        Colors.white,
      ),
      CreatePosterKind.coach => (
        dark
            ? Color.lerp(palette.glassStart, palette.accent, 0.22)!
            : Color.lerp(Colors.white, palette.accent, 0.16)!,
        palette.ink,
      ),
    };
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: bg,
        borderRadius: palette.radius(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(
                  child: CustomPaint(
                    painter: _PosterPainter(
                      kind: kind,
                      line: kind == CreatePosterKind.coach
                          ? palette.accent
                          : Colors.white,
                      warm: palette.warmMark,
                      ground: Color.lerp(bg, Colors.black, 0.35)!,
                      square: palette.isIron,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 13,
                  child: ExcludeSemantics(
                    child: Text(
                      palette.title(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: palette.heading(
                        TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterPainter extends CustomPainter {
  const _PosterPainter({
    required this.kind,
    required this.line,
    required this.warm,
    required this.ground,
    required this.square,
  });

  final bool square;

  final CreatePosterKind kind;
  final Color line;
  final Color warm;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case CreatePosterKind.wolf:
        _wolf(canvas, size);
      case CreatePosterKind.live:
        _live(canvas, size);
      case CreatePosterKind.coach:
        _coach(canvas, size);
    }
  }

  void _wolf(Canvas canvas, Size s) {
    final moon = Offset(s.width - 62, 44);
    canvas.drawCircle(moon, 46, Paint()..color = line.withValues(alpha: 0.07));
    canvas.drawCircle(moon, 26, Paint()..color = line.withValues(alpha: 0.92));
    canvas.drawCircle(
      moon.translate(-8, -6),
      5,
      Paint()..color = ground.withValues(alpha: 0.16),
    );
    final stars = Paint()..color = line.withValues(alpha: 0.55);
    for (final (x, y, r) in const [
      (0.10, 0.20, 1.4),
      (0.24, 0.42, 1.0),
      (0.38, 0.16, 1.6),
      (0.52, 0.34, 1.0),
      (0.64, 0.14, 1.2),
    ]) {
      canvas.drawCircle(Offset(s.width * x, s.height * y), r, stars);
    }
    // Rặng thông dưới chân, thấp dần về bên trái để chừa chỗ cho tên.
    final forest = Path()..moveTo(s.width * 0.42, s.height);
    var x = s.width * 0.42;
    var i = 0;
    while (x < s.width) {
      final h = 22.0 + (i % 3) * 9 + (i.isEven ? 6 : 0);
      forest
        ..lineTo(x + 9, s.height - h)
        ..lineTo(x + 18, s.height);
      x += 18;
      i++;
    }
    forest.close();
    canvas.drawPath(forest, Paint()..color = ground);
  }

  void _live(Canvas canvas, Size s) {
    final route = Path()
      ..moveTo(-6, s.height * 0.30)
      ..cubicTo(
        s.width * 0.30,
        s.height * 0.02,
        s.width * 0.34,
        s.height * 0.62,
        s.width * 0.60,
        s.height * 0.40,
      )
      ..cubicTo(
        s.width * 0.80,
        s.height * 0.22,
        s.width * 0.84,
        s.height * 0.56,
        s.width + 6,
        s.height * 0.26,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = (square ? StrokeCap.butt : StrokeCap.round)
        ..color = line.withValues(alpha: 0.42),
    );
    final metric = route.computeMetrics().first;
    for (final t in const [0.22, 0.46]) {
      final p = metric.getTangentForOffset(metric.length * t)!.position;
      canvas.drawCircle(p, 4.5, Paint()..color = line.withValues(alpha: 0.9));
    }
    final live = metric.getTangentForOffset(metric.length * 0.70)!.position;
    canvas.drawCircle(live, 11, Paint()..color = warm.withValues(alpha: 0.28));
    canvas.drawCircle(live, 5.5, Paint()..color = warm);
  }

  void _coach(Canvas canvas, Size s) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(s.width - 96, 14, 82, 50),
      Radius.circular(25),
    );
    final lane = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = line.withValues(alpha: 0.30);
    canvas.drawRRect(track, lane);
    canvas.drawRRect(track.deflate(8), lane);
    final done = Path()
      ..addArc(Rect.fromLTWH(s.width - 64, 14, 50, 50), -math.pi / 2, math.pi);
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = (square ? StrokeCap.butt : StrokeCap.round)
        ..color = line,
    );
    _sparkle(canvas, Offset(22, 26), 8, line);
    _sparkle(canvas, Offset(40, 44), 4.5, line.withValues(alpha: 0.6));
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PosterPainter old) =>
      old.kind != kind ||
      old.line != line ||
      old.warm != warm ||
      old.ground != ground;
}

/// Ô kèo nhanh vẽ như số đeo ngực: hai lỗ ghim, con số to, hạn ở dưới.
class CreateBibTile extends StatelessWidget {
  const CreateBibTile({
    super.key,
    required this.value,
    required this.unit,
    required this.caption,
    required this.onTap,
    this.warm = false,
  });

  final String value;
  final String unit;
  final String caption;
  final VoidCallback onTap;

  /// Kèo hết hạn trong hôm nay: gạch chân và hạn tô cam.
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final mark = warm ? palette.warmMark : palette.ink;
    final hole = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: palette.background,
        shape: context.runNowPalette.round,
        border: Border.all(color: palette.border),
      ),
    );
    return Semantics(
      button: true,
      label: '$value $unit $caption',
      child: Material(
        color: palette.glassStart,
        shape: RoundedRectangleBorder(
          borderRadius: palette.radius(14),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [hole, hole],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: palette.heading(
                          TextStyle(
                            fontSize: 34,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            color: palette.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        unit,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 36,
                    height: 3,
                    margin: const EdgeInsets.only(top: 5, bottom: 5),
                    decoration: BoxDecoration(
                      color: mark,
                      borderRadius: context.runNowPalette.radius(2),
                    ),
                  ),
                  Text(
                    caption,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: warm ? mark : palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút tròn ở hàng cuối trang Tạo mới.
class CreateRoundAction extends StatelessWidget {
  const CreateRoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: palette.radius(16),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: palette.glassStart,
                    shape: context.runNowPalette.round,
                    border: Border.all(color: palette.border),
                  ),
                  child: Icon(icon, size: 23, color: palette.accentDeep),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
