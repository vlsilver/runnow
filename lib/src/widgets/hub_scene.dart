import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowHubSceneTokens;

/// Cảnh vẽ làm nền thẻ nhỏ ở trang Kèo. Năm cảnh đầu theo loại kèo, [track]
/// cho giáo án, [werewolf] cho ván Ma Sói, bốn cảnh cuối là bầu trời theo giờ
/// của buổi chạy.
enum HubScene {
  road,
  sunrise,
  city,
  summit,
  map,
  track,
  werewolf,
  dawn,
  day,
  dusk,
  night;

  /// Trời theo giờ bắt đầu chạy (giờ máy): 5–9h rạng sáng, 9–16h ban ngày,
  /// 16–19h hoàng hôn, còn lại là đêm.
  static HubScene forRunAt(DateTime startedAt) {
    final hour = startedAt.toLocal().hour;
    if (hour >= 5 && hour < 9) return dawn;
    if (hour >= 9 && hour < 16) return day;
    if (hour >= 16 && hour < 19) return dusk;
    return night;
  }
}

/// Thẻ có tranh [scene] làm nền, chữ và icon sáng. Màu chữ đổi qua
/// `onSurface` nên con bên trong không cần biết mình nằm trên tranh.
class HubSceneCard extends StatelessWidget {
  const HubSceneCard({
    required this.scene,
    required this.onTap,
    required this.padding,
    required this.child,
    super.key,
  });

  final HubScene scene;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(24),
      color: _T.shade,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: _HubScenePainter(scene))),
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(onSurface: _T.ink),
            ),
            // Vệt chạm vẽ trên Material này, nằm trên tranh. Material đặt lại
            // kiểu chữ theo theme gốc, nên màu chữ phải đặt bên trong nó.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: _T.ink),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: _T.ink),
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

class _HubScenePainter extends CustomPainter {
  const _HubScenePainter(this.scene);

  final HubScene scene;

  @override
  void paint(Canvas canvas, Size size) {
    final draw = switch (scene) {
      HubScene.road => _road,
      HubScene.sunrise => _sunrise,
      HubScene.city => _city,
      HubScene.summit => _summit,
      HubScene.map => _map,
      HubScene.track => _track,
      HubScene.werewolf => _werewolf,
      HubScene.dawn => _dawn,
      HubScene.day => _day,
      HubScene.dusk => _dusk,
      HubScene.night => _night,
    };
    paintScene(canvas, size, (c, s) {
      draw(c, s);
      paintGrain(c, s, scene.index + 1, alpha: 0.04);
    });
    _scrims(canvas, size);
  }

  @override
  bool shouldRepaint(_HubScenePainter old) => old.scene != scene;
}

/// Tối dần ở mép trên (vòng tiến độ, tên) và mép dưới (số km, tiêu đề).
void _scrims(Canvas canvas, Size size) {
  void band(double from, double to, double fromAlpha, double toAlpha) {
    final rect = Rect.fromLTRB(
      0,
      size.height * from,
      size.width,
      size.height * to,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _T.shade.withValues(alpha: fromAlpha),
            _T.shade.withValues(alpha: toAlpha),
          ],
        ).createShader(rect),
    );
  }

  band(0, 0.35, 0.3, 0);
  band(0.45, 1, 0, 0.62);
}

List<(double, Color)> _stops(List<Color> colors) => [
  for (final (i, color) in colors.indexed)
    (colors.length == 1 ? 0 : i / (colors.length - 1), color),
];

/// Mặt trời: quầng sáng rồi đĩa đặc.
void _sun(Canvas canvas, Offset center, double r, Color core, Color glow) {
  canvas
    ..drawCircle(
      center,
      r * 3,
      Paint()
        ..shader = ui.Gradient.radial(center, r * 3, [
          glow,
          glow.withValues(alpha: 0),
        ]),
    )
    ..drawCircle(center, r, Paint()..color = core);
}

/// Dải đồi lượn quanh độ cao [y], phủ kín tới đáy tranh.
void _hill(
  Canvas canvas,
  Size size,
  double y,
  double amp,
  int seed,
  Color color,
) {
  final r = SceneRandom(seed);
  final w = size.width;
  final path = Path()
    ..moveTo(0, size.height)
    ..lineTo(0, y + (r.next() - 0.5) * amp);
  const bumps = 3;
  for (var i = 0; i < bumps; i++) {
    path.quadraticBezierTo(
      w * (i + 0.5) / bumps,
      y - amp * (0.4 + r.next() * 0.6),
      w * (i + 1) / bumps,
      y + (r.next() - 0.5) * amp * 0.5,
    );
  }
  path
    ..lineTo(w, size.height)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

void _hills(
  Canvas canvas,
  Size size,
  List<double> ys,
  List<Color> colors,
  int seed,
) {
  for (final (i, color) in colors.indexed) {
    _hill(canvas, size, size.height * ys[i], 22, seed + i * 7, color);
  }
}

Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

void _road(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  final hz = h * 0.55;
  paintSky(canvas, size, [
    (0, _T.roadSky[0]),
    (0.3, _T.roadSky[1]),
    (0.48, _T.roadSky[2]),
    (0.56, _T.roadSky[3]),
  ]);
  _sun(canvas, Offset(w * 0.5, hz - 4), 26, _T.roadSun, _T.roadSunGlow);
  canvas
    ..drawPath(
      _poly([
        Offset(0, hz),
        Offset(0, hz - 18),
        Offset(w * 0.12, hz - 34),
        Offset(w * 0.24, hz - 16),
        Offset(w * 0.36, hz - 30),
        Offset(w * 0.44, hz - 10),
        Offset(w * 0.6, hz - 12),
        Offset(w * 0.7, hz - 36),
        Offset(w * 0.82, hz - 14),
        Offset(w * 0.92, hz - 28),
        Offset(w, hz - 12),
        Offset(w, hz),
      ]),
      Paint()..color = _T.roadRange,
    )
    ..drawRect(Rect.fromLTRB(0, hz, w, h), Paint()..color = _T.roadGround)
    ..drawPath(
      _poly([
        Offset(w * 0.5 - 3, hz),
        Offset(w * 0.5 + 3, hz),
        Offset(w * 0.98, h),
        Offset(w * 0.02, h),
      ]),
      Paint()..color = _T.roadAsphalt,
    );
  // Vạch giữa đường: gần thì dài và to, xa thì ngắn và mảnh.
  final line = Paint()..color = _T.roadLine;
  for (final (from, to) in const [
    (0.04, 0.08),
    (0.13, 0.2),
    (0.27, 0.38),
    (0.47, 0.63),
    (0.74, 0.98),
  ]) {
    final y0 = hz + (h - hz) * from;
    final y1 = hz + (h - hz) * to;
    final half0 = 0.4 + 3 * from;
    final half1 = 0.4 + 3 * to;
    canvas.drawPath(
      _poly([
        Offset(w * 0.5 - half0, y0),
        Offset(w * 0.5 + half0, y0),
        Offset(w * 0.5 + half1, y1),
        Offset(w * 0.5 - half1, y1),
      ]),
      line,
    );
  }
}

void _sunrise(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, [
    (0, _T.sunriseSky[0]),
    (0.4, _T.sunriseSky[1]),
    (0.62, _T.sunriseSky[2]),
    (0.72, _T.sunriseSky[3]),
  ]);
  final sun = Offset(w * 0.5, h * 0.64);
  final ray = Paint()..color = _T.sunriseRay;
  for (var i = 0; i < 9; i++) {
    final a = math.pi + (i + 0.5) * math.pi / 9;
    const half = 0.06;
    canvas.drawPath(
      _poly([
        sun,
        sun + Offset(math.cos(a - half), math.sin(a - half)) * 300,
        sun + Offset(math.cos(a + half), math.sin(a + half)) * 300,
      ]),
      ray,
    );
  }
  _sun(canvas, sun, 34, _T.sunriseSun, _T.sunriseGlow);
  _hills(canvas, size, const [0.64, 0.74, 0.86], _T.sunriseHills, 3);
}

void _city(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.citySky));
  paintStars(canvas, size, count: 30, seed: 31, maxY: 0.45, color: _T.star);
  paintMoon(
    canvas,
    Offset(w * 0.76, h * 0.2),
    15,
    core: _T.cityMoon,
    rim: _T.cityMoonRim,
    glow: _T.cityMoonGlow,
  );
  final r = SceneRandom(41);
  final back = Paint()..color = _T.cityBack;
  for (var x = -6.0; x < w;) {
    final bw = 20 + r.next() * 22;
    canvas.drawRect(
      Rect.fromLTRB(x, h * (0.46 + r.next() * 0.14), x + bw, h),
      back,
    );
    x += bw + 2;
  }
  final front = Paint()..color = _T.cityFront;
  final window = Paint();
  for (var x = -4.0; x < w;) {
    final bw = 26 + r.next() * 24;
    final top = h * (0.6 + r.next() * 0.12);
    canvas.drawRect(Rect.fromLTRB(x, top, x + bw, h), front);
    for (var wy = top + 8; wy < h - 6; wy += 11) {
      for (var wx = x + 5; wx < x + bw - 6; wx += 9) {
        if (r.next() < 0.32) {
          window.color = _T.window.withValues(alpha: 0.55 + r.next() * 0.4);
          canvas.drawRect(Rect.fromLTWH(wx, wy, 4, 5), window);
        }
      }
    }
    x += bw + 3;
  }
}

void _summit(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.summitSky));
  paintStars(canvas, size, count: 36, seed: 51, maxY: 0.5, color: _T.star);
  canvas
    ..drawPath(
      _poly([
        Offset(0, h * 0.62),
        Offset(w * 0.18, h * 0.5),
        Offset(w * 0.32, h * 0.58),
        Offset(w * 0.84, h * 0.46),
        Offset(w, h * 0.56),
        Offset(w, h),
        Offset(0, h),
      ]),
      Paint()..color = _T.summitRange,
    )
    ..drawPath(
      _poly([
        Offset(w * 0.02, h),
        Offset(w * 0.3, h * 0.6),
        Offset(w * 0.38, h * 0.56),
        Offset(w * 0.52, h * 0.3),
        Offset(w * 0.68, h * 0.5),
        Offset(w * 0.76, h * 0.54),
        Offset(w, h),
      ]),
      Paint()..color = _T.summitPeak,
    )
    ..drawPath(
      _poly([
        Offset(w * 0.52, h * 0.3),
        Offset(w * 0.6, h * 0.42),
        Offset(w * 0.56, h * 0.41),
        Offset(w * 0.52, h * 0.45),
        Offset(w * 0.48, h * 0.41),
        Offset(w * 0.44, h * 0.43),
      ]),
      Paint()..color = _T.summitSnow,
    );
  // Cờ trên đỉnh.
  final top = Offset(w * 0.52, h * 0.3);
  final pole = top - Offset(0, h * 0.1);
  canvas
    ..drawLine(
      top,
      pole,
      Paint()
        ..color = _T.summitSnow
        ..strokeWidth = 1.6,
    )
    ..drawPath(
      _poly([
        pole,
        pole + Offset(w * 0.09, h * 0.022),
        pole + Offset(0, h * 0.045),
      ]),
      Paint()..color = _T.summitFlag,
    );
}

void _map(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, [(0, _T.mapTop), (1, _T.mapBottom)]);
  final contour = Paint()
    ..color = _T.mapContour
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  void rings(Offset center, int count, double phase) {
    for (var k = 0; k < count; k++) {
      final base = 16.0 + k * 20;
      final path = Path();
      for (var i = 0; i <= 48; i++) {
        final a = i / 48 * 2 * math.pi;
        final rr =
            base *
            (1 +
                0.14 * math.sin(3 * a + phase + k * 0.6) +
                0.06 * math.cos(5 * a));
        final p = center + Offset(math.cos(a) * rr, math.sin(a) * rr * 0.8);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, contour);
    }
  }

  rings(Offset(w * 0.66, h * 0.36), 6, 0.4);
  rings(Offset(w * 0.12, h * 0.9), 4, 2.1);
  final route = Path()
    ..moveTo(w * 0.14, h * 0.92)
    ..cubicTo(w * 0.22, h * 0.6, w * 0.52, h * 0.82, w * 0.58, h * 0.52)
    ..cubicTo(w * 0.64, h * 0.26, w * 0.86, h * 0.36, w * 0.84, h * 0.17);
  canvas
    ..drawPath(
      dashPath(route, 8, 6),
      Paint()
        ..color = _T.mapRoute
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round,
    )
    ..drawCircle(Offset(w * 0.14, h * 0.92), 4.5, Paint()..color = _T.mapRoute)
    ..drawCircle(Offset(w * 0.84, h * 0.17), 8, Paint()..color = _T.mapPin)
    ..drawCircle(Offset(w * 0.84, h * 0.17), 3, Paint()..color = _T.ink);
}

void _track(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.trackSky));
  for (final x in [w * 0.12, w * 0.88]) {
    final at = Offset(x, h * 0.1);
    canvas
      ..drawCircle(
        at,
        110,
        Paint()
          ..shader = ui.Gradient.radial(at, 110, [
            _T.trackLight,
            _T.trackLight.withValues(alpha: 0),
          ]),
      )
      ..drawRect(
        Rect.fromCenter(center: at, width: 16, height: 6),
        Paint()..color = _T.trackLine,
      );
  }
  canvas
    ..drawRect(
      Rect.fromLTRB(0, h * 0.32, w, h * 0.46),
      Paint()..color = _T.trackStands,
    )
    ..drawRect(
      Rect.fromLTRB(0, h * 0.46, w, h),
      Paint()..color = _T.trackField,
    );
  final center = Offset(w * 0.5, h * 1.14);
  Rect oval(double t) => Rect.fromCenter(
    center: center,
    width: w * (1.15 + 0.55 * t),
    height: h * (0.72 + 0.4 * t),
  );
  canvas
    ..drawOval(oval(1), Paint()..color = _T.trackLane)
    ..drawOval(oval(0), Paint()..color = _T.trackField);
  final lane = Paint()
    ..color = _T.trackLine
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (var i = 0; i <= 4; i++) {
    canvas.drawOval(oval(i / 4), lane);
  }
}

void _werewolf(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.wolfSky));
  paintStars(canvas, size, count: 34, seed: 81, maxY: 0.5, color: _T.star);
  paintMoon(
    canvas,
    Offset(w * 0.6, h * 0.24),
    24,
    core: _T.wolfMoon,
    rim: _T.wolfMoonRim,
    glow: _T.wolfMoonGlow,
  );
  _hills(canvas, size, const [0.62, 0.72], _T.wolfHills, 51);
  paintFog(canvas, w, h * 0.68, 18, _T.wolfFog);
  // Mấy mái nhà của làng, đèn còn sáng.
  final hut = Paint()..color = _T.wolfPines;
  final window = Paint()..color = _T.window;
  final ground = h * 0.84;
  paintPines(canvas, w, ground, h * 0.2, 8, _T.wolfPines, 91);
  for (final (x, s) in const [(0.3, 1.0), (0.46, 0.8), (0.74, 0.9)]) {
    final left = w * x;
    final width = 30 * s;
    final wall = 18 * s;
    canvas
      ..drawRect(Rect.fromLTWH(left, ground - wall, width, wall + 2), hut)
      ..drawPath(
        _poly([
          Offset(left - 4 * s, ground - wall),
          Offset(left + width / 2, ground - wall - 16 * s),
          Offset(left + width + 4 * s, ground - wall),
        ]),
        hut,
      )
      ..drawRect(
        Rect.fromLTWH(left + width * 0.38, ground - wall * 0.7, 6 * s, 7 * s),
        window,
      );
  }
  canvas.drawRect(Rect.fromLTRB(0, ground, w, h), hut);
}

void _dawn(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, [
    (0, _T.dawnSky[0]),
    (0.38, _T.dawnSky[1]),
    (0.58, _T.dawnSky[2]),
    (0.68, _T.dawnSky[3]),
  ]);
  _sun(canvas, Offset(w * 0.32, h * 0.6), 22, _T.dawnSun, _T.dawnGlow);
  _hills(canvas, size, const [0.62, 0.7], _T.dawnHills, 11);
  paintFog(canvas, w, h * 0.7, 16, _T.dawnFog);
  final base = h * 0.8;
  paintPines(canvas, w, base, h * 0.16, 9, _T.dawnPines, 61);
  canvas.drawRect(Rect.fromLTRB(0, base, w, h), Paint()..color = _T.dawnPines);
}

void _day(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.daySky));
  _sun(canvas, Offset(w * 0.78, h * 0.15), 17, _T.daySun, _T.dayGlow);
  final cloud = Paint()..color = _T.dayCloud;
  for (final (x, y, s) in const [(0.22, 0.3, 1.0), (0.66, 0.42, 0.75)]) {
    final at = Offset(w * x, h * y);
    canvas
      ..drawCircle(at, 11 * s, cloud)
      ..drawCircle(at + Offset(13 * s, -5 * s), 14 * s, cloud)
      ..drawCircle(at + Offset(28 * s, 0), 10 * s, cloud)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(at.dx - 6 * s, at.dy - 2 * s, 42 * s, 12 * s),
          Radius.circular(6 * s),
        ),
        cloud,
      );
  }
  _hills(canvas, size, const [0.58, 0.7, 0.82], _T.dayHills, 21);
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.62, h)
      ..quadraticBezierTo(w * 0.2, h * 0.86, w * 0.42, h * 0.76)
      ..quadraticBezierTo(w * 0.6, h * 0.69, w * 0.48, h * 0.62),
    Paint()
      ..color = _T.dayTrail
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round,
  );
}

void _dusk(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, [
    (0, _T.duskSky[0]),
    (0.35, _T.duskSky[1]),
    (0.56, _T.duskSky[2]),
    (0.66, _T.duskSky[3]),
  ]);
  _sun(canvas, Offset(w * 0.62, h * 0.6), 26, _T.duskSun, _T.duskGlow);
  _hills(canvas, size, const [0.6, 0.7, 0.82], _T.duskHills, 31);
}

void _night(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, _stops(_T.nightSky));
  paintStars(canvas, size, count: 40, seed: 71, maxY: 0.55, color: _T.star);
  paintMoon(
    canvas,
    Offset(w * 0.5, h * 0.14),
    15,
    core: _T.cityMoon,
    rim: _T.cityMoonRim,
    glow: _T.cityMoonGlow,
  );
  _hills(canvas, size, const [0.6, 0.72, 0.84], _T.nightHills, 41);
  final window = Paint()..color = _T.window;
  for (final (x, y) in const [
    (0.2, 0.78),
    (0.26, 0.79),
    (0.7, 0.76),
    (0.82, 0.8),
  ]) {
    canvas.drawRect(Rect.fromLTWH(w * x, h * y, 3.5, 4.5), window);
  }
}
