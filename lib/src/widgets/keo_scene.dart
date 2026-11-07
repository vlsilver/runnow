import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart';

/// Hình nền thẻ kèo: mỗi loại kèo một hình, màu theo hành và sáng/tối mà
/// người dùng chọn. Hình vẽ trong khung 164×208 (thẻ đứng ở trang chủ); thẻ
/// ngang thì hình neo về bên phải, phần trái chỉ có nền.
enum KeoScene {
  distance,
  activeDays,
  activityCount,
  longestRun,
  route,
  meet,
  live,
  werewolf;

  static KeoScene forContract(RunContract contract) {
    if (contract.meetAt != null) return meet;
    return switch (contract.metric) {
      RunContractMetric.distance => distance,
      RunContractMetric.activeDays => activeDays,
      RunContractMetric.activityCount => activityCount,
      RunContractMetric.longestRun => longestRun,
      RunContractMetric.routeCompletion => route,
    };
  }
}

/// Bố cục 0–2 lấy từ id: cùng một kèo luôn ra cùng một nền, còn hai kèo cùng
/// loại nằm cạnh nhau thường khác hình. Không dùng `String.hashCode` vì Dart
/// không hứa giữ nó giữa các lần chạy.
int keoSceneVariant(String id) =>
    id.codeUnits.fold(0, (sum, unit) => (sum * 31 + unit) & 0x7fffffff) % 3;

/// Bảng màu của một hình, lấy từ dải màu của hành. Ma Sói luôn là cảnh đêm,
/// nên chữ trên nó luôn sáng dù app đang ở chế độ sáng.
@immutable
class KeoSceneColors {
  const KeoSceneColors._({
    required this.sky,
    required this.far,
    required this.mid,
    required this.near,
    required this.accent,
    required this.line,
    required this.ground,
    required this.dash,
    required this.snow,
    required this.ink,
    required this.muted,
  });

  factory KeoSceneColors.resolve(RunNowPalette palette, KeoScene scene) {
    final ramp = palette.element.ramp;
    final night = scene == KeoScene.werewolf;
    if (palette.appearance == RunNowAppearance.light && !night) {
      final tint = palette.element.tint;
      return KeoSceneColors._(
        sky: tint,
        far: _mix(tint, ramp[0], 0.38),
        mid: _mix(tint, ramp[0], 0.72),
        near: _mix(ramp[0], ramp[1], 0.55),
        accent: ramp[3],
        line: _mix(tint, RunNowThemeTokens.lightInk, 0.11),
        ground: _mix(tint, Colors.white, 0.6),
        dash: Colors.white,
        snow: Colors.white,
        ink: RunNowThemeTokens.lightInk,
        muted: RunNowThemeTokens.lightMuted,
      );
    }
    final base = palette.appearance == RunNowAppearance.dark
        ? palette.background
        : RunNowThemeTokens.darkNeutral[0];
    final sky = _mix(base, ramp[4], night ? 0.38 : 0.42);
    return KeoSceneColors._(
      sky: sky,
      far: night ? _mix(base, ramp[4], 0.16) : _mix(base, ramp[4], 0.7),
      mid: ramp[4],
      near: night
          ? _mix(base, Colors.black, 0.35)
          : _mix(ramp[4], ramp[3], 0.45),
      accent: ramp[1],
      line: _mix(sky, Colors.white, night ? 0.12 : 0.13),
      ground: _mix(base, ramp[4], 0.22),
      dash: _mix(base, Colors.white, 0.8),
      snow: _mix(ramp[0], Colors.white, night ? 0.55 : 0.6),
      ink: RunNowThemeTokens.darkInk,
      muted: RunNowKeoSceneTokens.darkMuted,
    );
  }

  final Color sky;
  final Color far;
  final Color mid;
  final Color near;
  final Color accent;
  final Color line;
  final Color ground;
  final Color dash;

  /// Tuyết trên đỉnh núi; với Ma Sói là màu trăng.
  final Color snow;
  final Color ink;
  final Color muted;

  /// Bản nhạt cho thẻ ngang: chip, số % và nút nằm kín bên phải, đè lên hình,
  /// nên mọi lớp hình pha về [sky] để chữ đọc được. Chữ giữ nguyên màu.
  KeoSceneColors get quiet {
    Color q(Color art) => _mix(sky, art, 0.34);
    return KeoSceneColors._(
      sky: sky,
      far: q(far),
      mid: q(mid),
      near: q(near),
      accent: q(accent),
      line: q(line),
      ground: q(ground),
      dash: q(dash),
      snow: q(snow),
      ink: ink,
      muted: muted,
    );
  }

  List<Color> get _all => [
    sky,
    far,
    mid,
    near,
    accent,
    line,
    ground,
    dash,
    snow,
    ink,
    muted,
  ];

  @override
  bool operator ==(Object other) =>
      other is KeoSceneColors &&
      List.generate(
        _all.length,
        (i) => i,
      ).every((i) => _all[i] == other._all[i]);

  @override
  int get hashCode => Object.hashAll(_all);
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Thẻ có hình [scene] làm nền. Chữ và icon bên trong lấy màu qua `onSurface`
/// và `surface` của theme, nên con bên trong không cần biết nó nằm trên hình.
class KeoSceneCard extends StatelessWidget {
  const KeoSceneCard({
    required this.scene,
    required this.seed,
    required this.onTap,
    required this.padding,
    required this.child,
    this.radius = 24,
    super.key,
  });

  final KeoScene scene;

  /// Id của kèo, phòng hay ván; chọn bố cục qua [keoSceneVariant].
  final String seed;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = KeoSceneColors.resolve(context.runNowPalette, scene);
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(radius),
      color: colors.sky,
      // passthrough: thẻ đứng có cỡ cố định thì con nhận cỡ đó; thẻ ngang thì
      // con quyết định chiều cao, hình phủ theo.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: KeoScenePainter(
                  scene: scene,
                  variant: keoSceneVariant(seed),
                  colors: colors,
                ),
              ),
            ),
          ),
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                onSurface: colors.ink,
                surface: colors.sky,
              ),
            ),
            // Vệt chạm vẽ trên Material này, nằm trên hình. Material đặt lại
            // kiểu chữ theo theme gốc, nên màu chữ phải đặt bên trong nó.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: colors.ink),
                  child: IconTheme.merge(
                    data: IconThemeData(color: colors.ink),
                    child: Padding(padding: padding, child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KeoScenePainter extends CustomPainter {
  const KeoScenePainter({
    required this.scene,
    required this.variant,
    required this.colors,
  });

  static const _width = 164.0;
  static const _height = 208.0;

  final KeoScene scene;
  final int variant;
  final KeoSceneColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.sky);
    final scale = size.height / _height;
    final dx = size.width - _width * scale;
    canvas.save();
    canvas.translate(dx, 0);
    canvas.scale(scale);
    // Cảnh sói đã tối sẵn và thẻ Ma Sói không có số % bên phải, nên giữ màu
    // đậm cho thấy rõ con sói.
    final wide = size.width > size.height * 1.25 && scene != KeoScene.werewolf;
    final draw = _SceneDraw(
      canvas,
      wide ? colors.quiet : colors,
      variant.clamp(0, 2),
      -dx / scale,
    );
    switch (scene) {
      case KeoScene.distance:
        draw.road();
      case KeoScene.activeDays:
        draw.days();
      case KeoScene.activityCount:
        draw.track();
      case KeoScene.longestRun:
        draw.summit();
      case KeoScene.route:
        draw.route();
      case KeoScene.meet:
        draw.meet();
      case KeoScene.live:
        draw.live();
      case KeoScene.werewolf:
        draw.werewolf();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(KeoScenePainter old) =>
      old.scene != scene || old.variant != variant || old.colors != colors;
}

/// Vẽ trong toạ độ khung 164×208. [left] là mép trái thật của thẻ trong toạ
/// độ đó (âm khi thẻ rộng hơn khung), để dải đất kéo hết chiều ngang thẻ.
class _SceneDraw {
  _SceneDraw(this.canvas, this.c, this.v, this.left);

  final Canvas canvas;
  final KeoSceneColors c;
  final int v;
  final double left;

  T pick<T>(List<T> options) => options[v];

  Paint fill(Color color) => Paint()..color = color;

  Paint stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void dashed(Path path, Paint paint, double on, double off) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += on + off) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + on, metric.length)),
          paint,
        );
      }
    }
  }

  void polygon(List<Offset> points, Color color) =>
      canvas.drawPath(Path()..addPolygon(points, true), fill(color));

  void band(double top, Color color) =>
      canvas.drawRect(Rect.fromLTRB(left, top, 164, 208), fill(color));

  void road() {
    final vx = pick([116.0, 90.0, 134.0]);
    final lb = pick([58.0, 30.0, 76.0]);
    final rb = pick([214.0, 168.0, 230.0]);
    final amp = pick([18.0, 26.0, 12.0]);
    final top = 112 - amp;
    canvas.drawCircle(
      Offset(vx + pick([-26.0, 26.0, -36.0]), 106),
      21,
      fill(c.accent),
    );
    canvas.drawPath(
      Path()
        ..moveTo(left, 112)
        ..lineTo(left, top)
        ..lineTo(0, top)
        ..quadraticBezierTo(42, top - 18, 84, top + 4)
        // `T` của SVG: điểm điều khiển đối xứng với điểm trước qua (84, top+4).
        ..quadraticBezierTo(126, top + 26, 164, top - 6)
        ..lineTo(164, 112)
        ..close(),
      fill(c.far),
    );
    band(112, c.ground);
    polygon([
      Offset(vx - 1.5, 112),
      Offset(vx + 1.5, 112),
      Offset(rb, 208),
      Offset(lb, 208),
    ], c.mid);
    dashed(
      Path()
        ..moveTo(vx, 118)
        ..lineTo((lb + rb) / 2, 208),
      stroke(c.dash, 3),
      10,
      9,
    );
  }

  void days() {
    final done = pick([
      '11011101111011011111011',
      '01110111111001111101111111',
      '10101111101111111011',
    ]);
    final x0 = pick([74.0, 70.0, 78.0]);
    final y0 = pick([22.0, 30.0, 20.0]);
    Offset dot(int i) => Offset(x0 + (i % 7) * 12, y0 + (i ~/ 7) * 12);
    canvas.drawCircle(
      Offset(pick([126.0, 110.0, 134.0]), pick([52.0, 60.0, 44.0])),
      50,
      fill(c.far),
    );
    canvas.drawPath(
      Path()
        ..moveTo(left, 150)
        ..lineTo(0, 150)
        ..quadraticBezierTo(54, 118, 164, 138)
        ..lineTo(164, 208)
        ..lineTo(left, 208)
        ..close(),
      fill(c.mid),
    );
    canvas.drawPath(
      Path()
        ..moveTo(left, 168)
        ..lineTo(0, 168)
        ..quadraticBezierTo(90, 140, 164, 162)
        ..lineTo(164, 208)
        ..lineTo(left, 208)
        ..close(),
      fill(c.ground),
    );
    for (var i = 0; i < 28; i++) {
      final filled = i < done.length && done[i] == '1';
      canvas.drawCircle(dot(i), 3.8, fill(filled ? c.accent : c.line));
    }
    canvas.drawCircle(dot(done.length - 1), 7.5, stroke(c.accent, 2));
  }

  void track() {
    final cx = pick([150.0, 136.0, 162.0]);
    final cy = pick([66.0, 80.0, 54.0]);
    // Sân điền kinh: đường thẳng hai bên, hai đầu là nửa vòng tròn. Path bắt
    // đầu ở giữa cạnh trên, đi theo chiều kim đồng hồ.
    Path stadium(double w, double h) {
      final r = h / 2;
      final half = (w - h) / 2;
      return Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + half, cy - r)
        ..arcToPoint(Offset(cx + half, cy + r), radius: Radius.circular(r))
        ..lineTo(cx - half, cy + r)
        ..arcToPoint(Offset(cx - half, cy - r), radius: Radius.circular(r))
        ..close();
    }

    canvas.drawPath(stadium(206, 126), fill(c.mid));
    canvas.drawPath(stadium(150, 70), fill(c.far));
    for (var i = 0; i < 5; i++) {
      canvas.drawPath(
        stadium(150 + i * 14.0, 70 + i * 14.0),
        stroke(c.line, 1.4),
      );
    }
    // Một làn tô màu, nằm ở đoạn đường thẳng dưới và khúc cua trái, phần
    // luôn lọt vào thẻ.
    final lane = stadium(178, 98).computeMetrics().first;
    final start = pick([250.0, 300.0, 330.0]);
    canvas.drawPath(lane.extractPath(start, start + 96), stroke(c.accent, 4));
  }

  void summit() {
    final px = pick([106.0, 84.0, 122.0]);
    final py = pick([34.0, 42.0, 28.0]);
    final ridge = [
      const Offset(0, 124),
      const Offset(26, 98),
      const Offset(50, 110),
      const Offset(80, 80),
      const Offset(104, 100),
      const Offset(132, 84),
      const Offset(164, 104),
    ];
    polygon([
      Offset(left, 208),
      Offset(left, 124),
      ...ridge,
      const Offset(164, 208),
    ], c.far);
    polygon([
      Offset(px - 78, 150),
      Offset(px, py),
      Offset(px + 72, 150),
    ], c.mid);
    polygon([
      Offset(px, py),
      Offset(px + 72, 150),
      Offset(px + 16, 150),
    ], c.near);
    polygon([
      Offset(px, py),
      Offset(px - 13, py + 17),
      Offset(px - 5, py + 13),
      Offset(px + 2, py + 19),
      Offset(px + 11, py + 13),
    ], c.snow);
    band(150, c.ground);
    dashed(
      Path()..addPolygon([
        Offset(px - 54, 150),
        Offset(px - 30, 126),
        Offset(px - 44, 112),
        Offset(px - 18, 88),
        Offset(px - 28, 74),
        Offset(px - 6, py + 12),
      ], false),
      stroke(c.accent, 2.4),
      5,
      5,
    );
    canvas.drawLine(Offset(px, py), Offset(px, py - 20), stroke(c.ink, 1.6));
    polygon([
      Offset(px, py - 20),
      Offset(px + 15, py - 15),
      Offset(px, py - 10),
    ], c.accent);
  }

  void route() {
    final cx = pick([104.0, 88.0, 118.0]);
    final cy = pick([80.0, 92.0, 70.0]);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(pick([-18.0, 16.0, -32.0]) * math.pi / 180);
    for (var i = 5; i >= 0; i--) {
      final ring = Rect.fromCenter(
        center: Offset.zero,
        width: 2 * (16 + i * 16.0),
        height: 2 * (10 + i * 11.0),
      );
      if (i == 0) canvas.drawOval(ring, fill(c.far));
      canvas.drawOval(ring, stroke(c.line, 1.3));
    }
    canvas.restore();
    // Ba tuyến viết lại từ path SVG của bản thiết kế, `S` đổi ra điểm điều
    // khiển đối xứng.
    final (start, pin, path) = pick([
      (
        const Offset(148, 196),
        const Offset(118, 40),
        Path()
          ..moveTo(148, 196)
          ..cubicTo(104, 176, 158, 140, 118, 120)
          ..cubicTo(78, 100, 70, 78, 118, 40),
      ),
      (
        const Offset(150, 198),
        const Offset(72, 46),
        Path()
          ..moveTo(150, 198)
          ..cubicTo(120, 160, 60, 168, 70, 128)
          ..cubicTo(80, 88, 120, 92, 72, 46),
      ),
      (
        const Offset(142, 196),
        const Offset(132, 34),
        Path()
          ..moveTo(142, 196)
          ..cubicTo(150, 150, 98, 150, 108, 112)
          ..cubicTo(118, 74, 152, 70, 132, 34),
      ),
    ]);
    dashed(path, stroke(c.accent, 3), 7, 6);
    canvas.drawCircle(start, 5, fill(c.sky));
    canvas.drawCircle(start, 5, stroke(c.accent, 2.5));
    canvas.drawCircle(pin, 8, fill(c.accent));
    canvas.drawCircle(pin, 3, fill(c.sky));
  }

  void meet() {
    final m = Offset(pick([112.0, 96.0, 124.0]), pick([66.0, 76.0, 56.0]));
    canvas.drawCircle(m, 66, stroke(c.line, 1.3));
    canvas.drawCircle(m, 46, stroke(c.line, 1.3));
    canvas.drawCircle(m, 28, fill(c.far));
    Path toMeet(Offset from, Offset control) => Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, m.dx, m.dy);
    final paths = pick([
      [
        toMeet(const Offset(0, 34), const Offset(60, 30)),
        toMeet(const Offset(164, 150), const Offset(150, 90)),
        toMeet(const Offset(150, 0), const Offset(100, 30)),
      ],
      [
        toMeet(const Offset(0, 20), const Offset(40, 70)),
        toMeet(const Offset(164, 120), const Offset(110, 120)),
        toMeet(const Offset(120, 0), const Offset(140, 50)),
      ],
      [
        toMeet(const Offset(0, 60), const Offset(70, 20)),
        toMeet(const Offset(164, 176), const Offset(170, 100)),
        toMeet(const Offset(70, 0), const Offset(130, 10)),
      ],
    ]);
    dashed(paths[0], stroke(c.mid, 3), 6, 6);
    dashed(paths[1], stroke(c.mid, 3), 6, 6);
    dashed(paths[2], stroke(c.accent, 3), 6, 6);
    canvas.drawCircle(m, 13, stroke(c.accent, 2));
    canvas.drawCircle(m, 6.5, fill(c.accent));
  }

  void live() {
    // Điểm phát sóng ở góc trên phải; góc trên trái để trống cho giờ hẹn.
    final center = pick([
      const Offset(130, 50),
      const Offset(124, 62),
      const Offset(136, 42),
    ]);
    final p0 = Offset(-8, pick([138.0, 128.0, 146.0]));
    final p1 = pick([
      const Offset(44, 104),
      const Offset(30, 150),
      const Offset(60, 120),
    ]);
    final p2 =
        center + Offset(-pick([64.0, 40.0, 76.0]), pick([86.0, 70.0, 96.0]));
    final p3 = center + const Offset(-9, 13);
    Offset at(double t) {
      final u = 1 - t;
      return p0 * (u * u * u) +
          p1 * (3 * u * u * t) +
          p2 * (3 * u * t * t) +
          p3 * (t * t * t);
    }

    canvas.drawCircle(center, 44, fill(c.far));
    band(150, c.ground);
    dashed(
      Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy),
      stroke(c.mid, 3.2),
      1,
      7,
    );
    for (final (radius, color) in [(14.0, c.accent), (25.0, c.mid)]) {
      final box = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(box, -math.pi / 4, math.pi / 2, false, stroke(color, 3));
      canvas.drawArc(
        box,
        3 * math.pi / 4,
        math.pi / 2,
        false,
        stroke(color, 3),
      );
    }
    canvas.drawCircle(center, 7, fill(c.accent));
    canvas.drawCircle(center, 2.6, fill(c.sky));
    for (final (t, radius, color) in [
      (0.34, 6.0, c.mid),
      (0.58, 6.5, c.mid),
      (0.8, 7.0, c.near),
    ]) {
      canvas.drawCircle(at(t), radius, fill(color));
      canvas.drawCircle(at(t), radius, stroke(c.sky, 2.5));
    }
  }

  void werewolf() {
    final moon = pick([
      const Offset(118, 46),
      const Offset(84, 50),
      const Offset(84, 58),
    ]);
    // Sói ngồi tru trên mỏm đá, mõm chạm trăng. Hình sói vẽ trong khung
    // 184×238, mõm chĩa lên phải; flip thì quay sang trái.
    final (wx, wy, s, flip) = pick([
      (66.0, 52.0, 0.36, false),
      (152.0, 56.0, 0.36, true),
      (22.0, 62.0, 0.34, false),
    ]);
    final wolfLeft = flip ? wx - 184 * s : wx;
    final wolfRight = flip ? wx : wx + 184 * s;
    final rockTop = wy + 238 * s;

    // Cây và sao rải theo một dãy số cố định, để bố cục không đổi giữa các
    // lần vẽ.
    var seed = 7 + v * 131;
    double rand() {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    }

    final farTrees = <List<Offset>>[];
    for (
      var x = math.min(-8.0, left - 8);
      x < 172;
      x += 13 + (rand() * 6).round()
    ) {
      final h = 26 + (rand() * 26).round();
      final w = 7 + (rand() * 3).round();
      farTrees.add([
        Offset(x, 150.0 - h),
        Offset(x + w, 150),
        Offset(x - w, 150),
      ]);
    }
    final stars = <(Offset, double)>[];
    for (var i = 0; i < 10; i++) {
      final star = Offset(
        (rand() * 160 + 2).roundToDouble(),
        (rand() * 96 + 6).roundToDouble(),
      );
      if ((star - moon).distance < 42) continue;
      stars.add((star, rand() > 0.7 ? 1.6 : 1.0));
    }

    for (final (star, radius) in stars) {
      canvas.drawCircle(star, radius, fill(RunNowKeoSceneTokens.star));
    }
    canvas.drawCircle(moon, 38, stroke(c.line, 1.2));
    canvas.drawCircle(moon, 25, fill(c.snow));
    canvas.drawCircle(
      moon + const Offset(9, -8),
      5,
      fill(_mix(c.snow, c.accent, 0.25)),
    );
    for (final tree in farTrees) {
      polygon(tree, c.far);
    }
    band(148, c.far);
    final eyes = pick([
      const [Offset(34, 142)],
      const [Offset(42, 142), Offset(64, 147)],
      const [Offset(112, 142), Offset(134, 147)],
    ]);
    for (final eye in eyes) {
      canvas.drawCircle(eye, 1.9, fill(c.accent));
      canvas.drawCircle(eye + const Offset(6, 0), 1.9, fill(c.accent));
    }
    final nearTrees = pick([
      const [(6.0, 110.0, 20.0), (-12.0, 140.0, 18.0)],
      const [(10.0, 116.0, 20.0), (-8.0, 146.0, 16.0)],
      const [(150.0, 108.0, 22.0), (178.0, 136.0, 18.0)],
    ]);
    for (final (x, top, w) in nearTrees) {
      polygon([Offset(x, top), Offset(x + w, 208), Offset(x - w, 208)], c.near);
    }
    polygon([
      Offset(wolfLeft - 12, 208),
      Offset(wolfLeft - 4, rockTop + 6),
      Offset(wolfLeft + 8, rockTop),
      Offset(wolfRight - 6, rockTop),
      Offset(wolfRight + 6, rockTop + 8),
      Offset(wolfRight + 22, 208),
    ], c.near);
    canvas.save();
    canvas.translate(wx, wy);
    canvas.scale(flip ? -s : s, s);
    canvas.drawPath(_wolf, fill(c.near));
    canvas.restore();
  }
}

/// Bóng con sói ngồi tru, khung 184×238.
final Path _wolf = Path()
  ..moveTo(176, 4)
  ..cubicTo(181, 4, 183, 11, 180, 15)
  ..lineTo(158, 46)
  ..lineTo(170, 40)
  ..cubicTo(168, 48, 162, 60, 150, 72)
  ..cubicTo(146, 84, 150, 96, 154, 108)
  ..cubicTo(160, 124, 160, 146, 150, 164)
  ..lineTo(148, 230)
  ..cubicTo(148, 236, 152, 238, 158, 238)
  ..lineTo(134, 238)
  ..lineTo(130, 186)
  ..cubicTo(122, 196, 114, 210, 112, 228)
  ..cubicTo(118, 232, 122, 236, 118, 238)
  ..lineTo(40, 238)
  ..cubicTo(24, 240, 6, 236, 0, 226)
  ..cubicTo(10, 218, 24, 212, 30, 214)
  ..cubicTo(36, 210, 40, 206, 44, 200)
  ..cubicTo(40, 176, 52, 150, 72, 132)
  ..cubicTo(88, 118, 98, 100, 102, 84)
  ..cubicTo(104, 72, 104, 62, 108, 54)
  ..lineTo(98, 22)
  ..lineTo(120, 38)
  ..cubicTo(124, 32, 130, 28, 136, 28)
  ..close();
