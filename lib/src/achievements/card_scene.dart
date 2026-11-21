import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:myrun/src/theme.dart';

typedef _T = RunNowCardSceneTokens;

/// Bộ nét vẽ chung cho tranh vẽ bằng code trên thẻ (Ma Sói, Hành trình):
/// trời, sao, trăng, rừng thông, sói, hạt nhiễu. Số đo trong các hàm là số
/// đo của bản thiết kế, thẻ rộng [sceneWidth]; [paintScene] co giãn canvas về
/// cỡ thật nên nét nào cũng giữ đúng tỉ lệ.
const sceneWidth = 232.0;

/// Vẽ [paint] trên hệ toạ độ bản thiết kế: rộng [sceneWidth], cao theo tỉ lệ
/// của [size].
void paintScene(
  Canvas canvas,
  Size size,
  void Function(Canvas canvas, Size size) paint,
) {
  final k = size.width / sceneWidth;
  canvas
    ..save()
    ..clipRect(Offset.zero & size)
    ..scale(k);
  paint(canvas, Size(sceneWidth, size.height / k));
  canvas.restore();
}

/// Số ngẫu nhiên có seed (LCG) để tranh vẽ lần nào cũng như nhau.
class SceneRandom {
  SceneRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _state / 4294967296;
  }
}

/// Trời dọc từ trên xuống, [stops] là (vị trí, màu).
void paintSky(Canvas canvas, Size size, List<(double, Color)> stops) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final (_, color) in stops) color],
        stops: [for (final (at, _) in stops) at],
      ).createShader(rect),
  );
}

/// [count] sao rải trong phần trên cao [maxY] của tranh, độ mờ khác nhau.
void paintStars(
  Canvas canvas,
  Size size, {
  required int count,
  required int seed,
  required Color color,
  double maxY = 0.6,
}) {
  final r = SceneRandom(seed);
  final paint = Paint();
  for (var i = 0; i < count; i++) {
    final x = r.next() * size.width;
    final y = r.next() * size.height * maxY;
    final radius = r.next() * 1.2 + 0.3;
    paint.color = color.withValues(alpha: 0.35 + r.next() * 0.6);
    canvas.drawCircle(Offset(x, y), radius, paint);
  }
}

/// Trăng tròn có quầng, mặt sáng lệch về góc trên trái và vài vết lõm.
void paintMoon(
  Canvas canvas,
  Offset center,
  double r, {
  required Color core,
  required Color rim,
  required Color glow,
}) {
  canvas
    ..drawCircle(
      center,
      r * 2.8,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r * 2.8,
          [glow, glow.withValues(alpha: 0)],
          [0.6 / 2.8, 1],
        ),
    )
    ..drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r,
          [core, rim],
          null,
          TileMode.clamp,
          null,
          center - Offset(r * 0.3, r * 0.3),
          r * 0.1,
        ),
    );
  final crater = Paint()..color = _T.crater;
  for (final (dx, dy, rr) in const [
    (-0.3, -0.2, 0.18),
    (0.25, 0.1, 0.13),
    (-0.05, 0.35, 0.1),
    (0.35, -0.32, 0.08),
  ]) {
    canvas.drawCircle(center + Offset(dx * r, dy * r), rr * r, crater);
  }
}

/// Dải rừng thông ba tầng tán dọc mép [base], cao chừng [height].
void paintPines(
  Canvas canvas,
  double width,
  double base,
  double height,
  int count,
  Color color,
  int seed,
) {
  final r = SceneRandom(seed);
  final path = Path()
    ..moveTo(0, base + 40)
    ..lineTo(0, base);
  for (var i = 0; i <= count; i++) {
    final x = i / count * width + (r.next() - 0.5) * 8;
    final th = height * (0.65 + r.next() * 0.55);
    final bw = width / count * (0.9 + r.next() * 0.4);
    path
      ..lineTo(x - bw / 2, base)
      ..lineTo(x - bw * 0.32, base - th * 0.38)
      ..lineTo(x - bw * 0.4, base - th * 0.38)
      ..lineTo(x - bw * 0.2, base - th * 0.7)
      ..lineTo(x - bw * 0.28, base - th * 0.7)
      ..lineTo(x, base - th)
      ..lineTo(x + bw * 0.28, base - th * 0.7)
      ..lineTo(x + bw * 0.2, base - th * 0.7)
      ..lineTo(x + bw * 0.4, base - th * 0.38)
      ..lineTo(x + bw * 0.32, base - th * 0.38)
      ..lineTo(x + bw / 2, base);
  }
  path
    ..lineTo(width, base)
    ..lineTo(width, base + 40)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

/// Dải sương ngang quanh [y], đậm ở giữa, tan về hai phía.
void paintFog(Canvas canvas, double width, double y, double half, Color color) {
  final rect = Rect.fromLTWH(0, y - half, width, half * 2);
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)],
      ).createShader(rect),
  );
}

/// Nét đứt dọc [path]: liền [on], hở [off], như setLineDash của canvas web.
Path dashPath(Path path, double on, double off) {
  final out = Path();
  for (final metric in path.computeMetrics()) {
    for (var at = 0.0; at < metric.length; at += on + off) {
      out.addPath(
        metric.extractPath(at, math.min(at + on, metric.length)),
        Offset.zero,
      );
    }
  }
  return out;
}

/// Sói ngồi hú, quay sang phải; toạ độ trong hộp 1x1.
const _wolf = [
  (0.06, 1.0), (0.0, 0.84), (0.04, 0.72), (0.14, 0.74), (0.24, 0.62), //
  (0.36, 0.5), (0.46, 0.38), (0.5, 0.26), (0.52, 0.14), (0.5, 0.02),
  (0.58, 0.1), (0.64, 0.08), (0.76, 0.0), (0.9, -0.06), (0.93, -0.02),
  (0.84, 0.06), (0.9, 0.08), (0.8, 0.14), (0.74, 0.2), (0.7, 0.3),
  (0.72, 0.46), (0.76, 0.98), (0.67, 0.98), (0.63, 0.66), (0.52, 0.7),
  (0.42, 0.76), (0.44, 0.98), (0.3, 0.98), (0.26, 0.86), (0.14, 0.92),
];

/// Bóng sói hú, góc trên trái hộp ở [origin], cạnh hộp [size].
void paintWolf(Canvas canvas, Offset origin, double size, Color color) {
  final path = Path();
  for (final (i, (x, y)) in _wolf.indexed) {
    final point = origin + Offset(x * size, y * size);
    i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
  }
  canvas.drawPath(path..close(), Paint()..color = color);
}

/// Hạt nhiễu như giấy in: chấm sáng và chấm tối rải đều, độ mờ [alpha].
void paintGrain(Canvas canvas, Size size, int seed, {double alpha = 0.05}) {
  final r = SceneRandom(seed);
  final light = <Offset>[];
  final dark = <Offset>[];
  final count = size.width * size.height ~/ 26;
  for (var i = 0; i < count; i++) {
    final bright = r.next() > 0.5;
    (bright ? light : dark).add(
      Offset(r.next() * size.width, r.next() * size.height),
    );
  }
  Paint dot(Color color) => Paint()
    ..color = color
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.square;
  canvas
    ..drawPoints(
      ui.PointMode.points,
      light,
      dot(_T.grainLight.withValues(alpha: alpha)),
    )
    ..drawPoints(
      ui.PointMode.points,
      dark,
      dot(_T.grainDark.withValues(alpha: math.min(1, alpha * 1.4))),
    );
}

/// [text] lặp quanh vòng bán kính [r], đọc xuôi chiều kim đồng hồ từ đỉnh.
/// Lặp đủ số lần cho kín vòng rồi giãn đều; một lần đã dài hơn vòng thì thu
/// nhỏ chữ.
void paintRingText(
  Canvas canvas,
  Offset c,
  double r,
  String text,
  Color color,
) {
  final around = 2 * math.pi * r;
  List<TextPainter> lay(String s, double size) => [
    for (final ch in s.characters)
      TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontFamily: 'Barlow Condensed',
            fontWeight: FontWeight.w800,
            fontSize: size,
            letterSpacing: size * 0.16,
            height: 1,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
  ];
  double width(List<TextPainter> glyphs) =>
      glyphs.fold(0.0, (sum, g) => sum + g.width);
  void dispose(List<TextPainter> glyphs) {
    for (final g in glyphs) {
      g.dispose();
    }
  }

  var size = 9.5;
  final probe = lay(text, size);
  final once = width(probe);
  dispose(probe);
  if (once > around) size *= around / once * 0.95;
  final times = math.max(1, (around / (once * size / 9.5)).floor());
  final glyphs = lay(text * times, size);
  final gap = (around - width(glyphs)) / glyphs.length;
  var angle = -math.pi / 2;
  for (final g in glyphs) {
    final step = (g.width + gap) / r;
    final mid = angle + step / 2;
    canvas
      ..save()
      ..translate(c.dx + r * math.cos(mid), c.dy + r * math.sin(mid))
      ..rotate(mid + math.pi / 2);
    g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
    canvas.restore();
    angle += step;
  }
  dispose(glyphs);
}
