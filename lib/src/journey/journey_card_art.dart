import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowCardSceneTokens;

typedef _Scene = void Function(Canvas canvas, Size size);

/// Poster mặt trước thẻ Hành trình theo chặng. Chặng lạ vẽ như Marathon.
class JourneyPosterArt extends StatelessWidget {
  const JourneyPosterArt({super.key, required this.campaign});

  /// Khoá chặng của backend: marathon, mont_blanc, xuyen_viet, dong_nam_a.
  final String campaign;

  @override
  Widget build(BuildContext context) {
    // Thẻ vẽ lại mỗi khung hình khi nghiêng; tranh đứng yên nên tách lớp.
    return RepaintBoundary(
      child: CustomPaint(painter: _PosterPainter(campaign)),
    );
  }
}

class _PosterPainter extends CustomPainter {
  const _PosterPainter(this.campaign);

  final String campaign;

  @override
  void paint(Canvas canvas, Size size) {
    final (scene, floor) = _posters[campaign] ?? _posters['marathon']!;
    paintScene(canvas, size, (canvas, size) {
      // Cảnh gói trong phần trên; phần dưới là nền của chính cảnh đó tối dần
      // xuống đáy, để tên và số liệu nằm trên chỗ yên.
      final top = size.height * _sceneShare;
      final rest = Rect.fromLTWH(0, top, size.width, size.height - top);
      canvas
        ..drawRect(
          rest,
          Paint()
            ..shader = ui.Gradient.linear(rest.topLeft, rest.bottomLeft, [
              floor,
              Color.lerp(floor, _T.posterFloorShade, 0.5)!,
            ]),
        )
        ..save()
        ..translate(0, rest.top);
      paintGrain(canvas, rest.size, 505, alpha: 0.045);
      canvas
        ..restore()
        ..save()
        // Mép cắt không làm mờ: hàng điểm ảnh ở mép mờ để lọt trời của cảnh
        // thành một vạch sáng.
        ..clipRect(Offset.zero & Size(size.width, top), doAntiAlias: false);
      scene(canvas, Size(size.width, top));
      canvas.restore();
    });
  }

  @override
  bool shouldRepaint(_PosterPainter old) => old.campaign != campaign;
}

/// Phần chiều cao tranh dành cho cảnh, tính từ trên xuống.
const _sceneShare = 0.57;

/// Mỗi chặng: cảnh, và màu lớp sát đáy cảnh để nền bên dưới nối liền.
const _posters = <String, (_Scene, Color)>{
  'marathon': (_marathon, _T.marathonHillFront),
  'mont_blanc': (_montBlanc, _T.montBlancPines),
  'xuyen_viet': (_xuyenViet, _T.xuyenVietSky3),
  'dong_nam_a': (_dongNamA, _T.dongNamAInk),
};

Paint _fill(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width;

void _poster(Canvas canvas, Size size, List<(double, Color)> sky, int seed) {
  paintSky(canvas, size, sky);
  paintGrain(canvas, size, seed, alpha: 0.045);
}

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
    ..drawCircle(center, r, _fill(core));
}

void _ellipse(
  Canvas canvas,
  Offset center,
  double rx,
  double ry,
  double angle,
  Paint paint,
) {
  canvas
    ..save()
    ..translate(center.dx, center.dy)
    ..rotate(angle)
    ..drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      paint,
    )
    ..restore();
}

/// Mặt đất kín từ độ cao [startY], qua các đường cong, xuống tới đáy tranh.
Path _ground(Size size, double startY, void Function(Path path) curve) {
  final path = Path()..moveTo(0, startY);
  curve(path);
  return path
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
}

void _marathon(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  _poster(canvas, size, const [
    (0, _T.marathonSky1),
    (0.5, _T.marathonSky2),
    (1, _T.marathonSky3),
  ], 101);
  _sun(
    canvas,
    Offset(w * 0.5, h * 0.3),
    w * 0.12,
    _T.marathonSun,
    _T.marathonSunGlow,
  );
  canvas.drawPath(
    _ground(
      size,
      h * 0.66,
      (p) => p
        ..quadraticBezierTo(w * 0.35, h * 0.54, w * 0.62, h * 0.62)
        ..quadraticBezierTo(w * 0.85, h * 0.66, w, h * 0.58),
    ),
    _fill(_T.marathonHill),
  );
  // Đền cột trên đồi.
  final bx = w * 0.28, by = h * 0.58, bw = w * 0.44;
  final temple = _fill(_T.marathonTemple);
  canvas
    ..drawPath(
      Path()
        ..moveTo(bx - 4, by - 34)
        ..lineTo(bx + bw / 2, by - 50)
        ..lineTo(bx + bw + 4, by - 34)
        ..close(),
      temple,
    )
    ..drawRect(Rect.fromLTWH(bx - 4, by - 34, bw + 8, 5), temple);
  for (var i = 0; i < 7; i++) {
    canvas.drawRect(Rect.fromLTWH(bx + i * bw / 6.6, by - 29, 5, 27), temple);
  }
  canvas
    ..drawRect(Rect.fromLTWH(bx - 6, by - 3, bw + 12, 5), temple)
    ..drawPath(
      _ground(
        size,
        h * 0.8,
        (p) => p.quadraticBezierTo(w * 0.5, h * 0.72, w, h * 0.82),
      ),
      _fill(_T.marathonHillFront),
    )
    ..drawPath(
      dashPath(
        Path()
          ..moveTo(w * 0.08, h)
          ..quadraticBezierTo(w * 0.4, h * 0.86, w * 0.62, h * 0.78),
        8,
        7,
      ),
      _stroke(_T.marathonPath, 3),
    )
    // Cành ô liu.
    ..drawPath(
      Path()
        ..moveTo(w * 0.98, h * 0.12)
        ..quadraticBezierTo(w * 0.8, h * 0.16, w * 0.72, h * 0.08),
      _stroke(_T.marathonBranch, 1.6),
    );
  final leaf = _fill(_T.marathonLeaf);
  for (var i = 0; i < 5; i++) {
    _ellipse(
      canvas,
      Offset(w * (0.95 - i * 0.05), h * (0.125 + (i.isOdd ? 0.02 : -0.015))),
      6,
      2.4,
      i.isOdd ? 0.5 : -0.5,
      leaf,
    );
  }
}

void _montBlanc(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  _poster(canvas, size, const [
    (0, _T.montBlancSky1),
    (0.55, _T.montBlancSky2),
    (1, _T.montBlancSky3),
  ], 202);
  _sun(
    canvas,
    Offset(w * 0.2, h * 0.2),
    w * 0.07,
    _T.montBlancSun,
    _T.montBlancSunGlow,
  );
  void range(List<(double, double)> points, Color color) {
    final path = Path()..moveTo(0, h);
    for (final (x, y) in points) {
      path.lineTo(w * x, h * y);
    }
    canvas.drawPath(
      path
        ..lineTo(w, h)
        ..close(),
      _fill(color),
    );
  }

  range(const [
    (0, 0.56),
    (0.18, 0.4),
    (0.3, 0.48),
    (0.52, 0.22),
    (0.68, 0.44),
    (0.82, 0.34),
    (1, 0.5),
  ], _T.montBlancPeakFar);
  final snow = _fill(_T.montBlancSnow);
  canvas
    ..drawPath(
      Path()
        ..moveTo(w * 0.52, h * 0.22)
        ..lineTo(w * 0.45, h * 0.31)
        ..lineTo(w * 0.49, h * 0.3)
        ..lineTo(w * 0.52, h * 0.33)
        ..lineTo(w * 0.56, h * 0.3)
        ..lineTo(w * 0.6, h * 0.32)
        ..close(),
      snow,
    )
    ..drawPath(
      Path()
        ..moveTo(w * 0.18, h * 0.4)
        ..lineTo(w * 0.13, h * 0.46)
        ..lineTo(w * 0.18, h * 0.45)
        ..lineTo(w * 0.22, h * 0.455)
        ..close(),
      snow,
    );
  range(const [
    (0, 0.68),
    (0.2, 0.56),
    (0.38, 0.64),
    (0.6, 0.54),
    (0.78, 0.64),
    (1, 0.58),
  ], _T.montBlancPeakMid);
  range(const [
    (0, 0.82),
    (0.3, 0.74),
    (0.55, 0.8),
    (0.8, 0.72),
    (1, 0.78),
  ], _T.montBlancPeakNear);
  paintPines(canvas, w, h * 0.96, h * 0.12, 11, _T.montBlancPines, 77);
  canvas.drawPath(
    dashPath(
      Path()
        ..moveTo(w * 0.1, h)
        ..lineTo(w * 0.35, h * 0.82)
        ..lineTo(w * 0.2, h * 0.74)
        ..lineTo(w * 0.46, h * 0.62),
      6,
      6,
    ),
    _stroke(_T.montBlancPath, 2.4),
  );
}

void _xuyenViet(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  _poster(canvas, size, const [
    (0, _T.xuyenVietSky1),
    (0.5, _T.xuyenVietSky2),
    (1, _T.xuyenVietSky3),
  ], 303);
  _sun(
    canvas,
    Offset(w * 0.8, h * 0.16),
    w * 0.08,
    _T.xuyenVietSun,
    _T.xuyenVietSunGlow,
  );
  // Dải đất chữ S cách điệu, biển Đông bên phải.
  canvas
    ..drawPath(
      Path()
        ..moveTo(w * 0.3, h * 0.06)
        ..cubicTo(w * 0.58, h * 0.06, w * 0.6, h * 0.16, w * 0.48, h * 0.24)
        ..cubicTo(w * 0.36, h * 0.32, w * 0.42, h * 0.42, w * 0.56, h * 0.5)
        ..cubicTo(w * 0.7, h * 0.58, w * 0.66, h * 0.7, w * 0.5, h * 0.76)
        ..cubicTo(w * 0.4, h * 0.8, w * 0.3, h * 0.86, w * 0.36, h * 0.94)
        ..lineTo(w * 0.28, h * 0.94)
        ..cubicTo(w * 0.2, h * 0.84, w * 0.3, h * 0.76, w * 0.42, h * 0.72)
        ..cubicTo(w * 0.56, h * 0.66, w * 0.58, h * 0.58, w * 0.46, h * 0.52)
        ..cubicTo(w * 0.3, h * 0.44, w * 0.3, h * 0.3, w * 0.4, h * 0.22)
        ..cubicTo(w * 0.46, h * 0.17, w * 0.42, h * 0.12, w * 0.22, h * 0.1)
        ..close(),
      _fill(_T.xuyenVietLand),
    )
    ..drawPath(
      dashPath(
        Path()
          ..moveTo(w * 0.34, h * 0.09)
          ..cubicTo(w * 0.5, h * 0.12, w * 0.5, h * 0.18, w * 0.43, h * 0.24)
          ..cubicTo(w * 0.33, h * 0.34, w * 0.4, h * 0.44, w * 0.52, h * 0.51)
          ..cubicTo(w * 0.64, h * 0.58, w * 0.6, h * 0.68, w * 0.45, h * 0.74)
          ..cubicTo(w * 0.34, h * 0.79, w * 0.28, h * 0.86, w * 0.32, h * 0.92),
        5,
        4,
      ),
      _stroke(_T.xuyenVietRoute, 2.2),
    );
  for (final (x, y) in const [
    (0.34, 0.09),
    (0.43, 0.24),
    (0.52, 0.51),
    (0.45, 0.74),
    (0.32, 0.92),
  ]) {
    canvas
      ..drawCircle(Offset(w * x, h * y), 3.4, _fill(_T.xuyenVietStop))
      ..drawCircle(Offset(w * x, h * y), 1.8, _fill(_T.xuyenVietRoute));
  }
  // Sóng biển.
  final wave = _stroke(_T.xuyenVietWave, 1.2);
  for (var i = 0; i < 3; i++) {
    final x = w * 0.72, y = h * (0.24 + i * 0.06);
    canvas.drawPath(
      Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + 7, y - 5, x + 14, y)
        ..quadraticBezierTo(x + 21, y + 5, x + 28, y),
      wave,
    );
  }
}

void _dongNamA(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  _poster(canvas, size, const [
    (0, _T.dongNamASky1),
    (0.4, _T.dongNamASky2),
    (0.75, _T.dongNamASky3),
    (1, _T.dongNamASky4),
  ], 404);
  _sun(
    canvas,
    Offset(w * 0.5, h * 0.52),
    w * 0.18,
    _T.dongNamASun,
    _T.dongNamASunGlow,
  );
  // Bảo tháp ở giữa, chùa tầng hai bên.
  final base = h * 0.8;
  final ink = _fill(_T.dongNamAInk);
  canvas
    ..drawPath(
      Path()
        ..moveTo(w * 0.4, base)
        ..quadraticBezierTo(w * 0.41, base - 36, w * 0.5, base - 46)
        ..quadraticBezierTo(w * 0.59, base - 36, w * 0.6, base)
        ..close(),
      ink,
    )
    ..drawPath(
      Path()
        ..moveTo(w * 0.47, base - 44)
        ..lineTo(w * 0.5, base - 84)
        ..lineTo(w * 0.53, base - 44)
        ..close(),
      ink,
    );
  for (final (x, tier) in const [(0.16, 28.0), (0.8, 24.0)]) {
    for (var i = 0; i < 3; i++) {
      final ww = 32.0 - i * 9, y = base - i * tier * 0.45;
      canvas
        ..drawPath(
          Path()
            ..moveTo(w * x - ww / 2 - 5, y - 4)
            ..lineTo(w * x, y - 14)
            ..lineTo(w * x + ww / 2 + 5, y - 4)
            ..close(),
          ink,
        )
        ..drawRect(Rect.fromLTWH(w * x - ww / 2 + 3, y - 4, ww - 6, 10), ink);
    }
  }
  canvas.drawRect(Rect.fromLTWH(0, base, w, h - base), ink);
  // Cây dừa.
  void palm(double x, double y, double s) {
    canvas.drawPath(
      Path()
        ..moveTo(x, y)
        ..quadraticBezierTo(x + s * 0.15, y - s * 0.5, x + s * 0.05, y - s),
      _stroke(_T.dongNamAInk, 3),
    );
    final frond = _stroke(_T.dongNamAInk, 2.4);
    for (final (dx, dy) in const [
      (-1.0, 0.1),
      (-0.7, -0.25),
      (0.7, -0.25),
      (1.0, 0.1),
      (0.0, -0.45),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x + s * 0.05, y - s)
          ..quadraticBezierTo(
            x + s * (0.05 + dx * 0.3),
            y - s * (1.15 - dy * 0.2),
            x + s * (0.05 + dx * 0.55),
            y - s * (1 + dy * -0.3),
          ),
        frond,
      );
    }
  }

  palm(w * 0.06, base + 6, 50);
  palm(w * 0.94, base + 6, 44);
  // Bảy thủ đô nối nhau.
  const capitals = [
    (0.14, 0.12),
    (0.3, 0.22),
    (0.46, 0.1),
    (0.6, 0.24),
    (0.74, 0.14),
    (0.82, 0.3),
    (0.9, 0.2),
  ];
  final route = Path();
  for (final (i, (x, y)) in capitals.indexed) {
    i == 0 ? route.moveTo(w * x, h * y) : route.lineTo(w * x, h * y);
  }
  canvas.drawPath(dashPath(route, 3, 3), _stroke(_T.dongNamARoute, 1.2));
  for (final (x, y) in capitals) {
    canvas.drawCircle(Offset(w * x, h * y), 2.6, _fill(_T.dongNamACapital));
  }
}

/// Mặt sau thẻ Hành trình: biểu tượng chặng trong vòng nhũ màu bậc, nguyệt
/// quế ôm hai bên. Chặng lạ vẽ như Marathon.
class JourneyCardEmblem extends StatelessWidget {
  const JourneyCardEmblem({
    super.key,
    required this.campaign,
    required this.tier,
  });

  final String campaign;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    // Nền huy hiệu luôn tối, nên bộ màu sáng mượn màu bậc của bộ tối.
    final skin = RunCardSkin.of(context);
    final foil = (skin.darkMap ? skin : RunCardSkin.classic).accent(tier);
    return RepaintBoundary(
      child: CustomPaint(painter: _EmblemPainter(campaign, foil)),
    );
  }
}

typedef _Glyph =
    void Function(Canvas canvas, Offset center, double s, Paint ink, Color bg);

typedef _Emblem = ({Color top, Color bottom, int seed, _Glyph glyph});

const _emblems = <String, _Emblem>{
  'marathon': (
    top: _T.marathonEmblemTop,
    bottom: _T.marathonEmblemBottom,
    seed: 901,
    glyph: _templeGlyph,
  ),
  'mont_blanc': (
    top: _T.montBlancEmblemTop,
    bottom: _T.montBlancEmblemBottom,
    seed: 902,
    glyph: _peakGlyph,
  ),
  'xuyen_viet': (
    top: _T.xuyenVietEmblemTop,
    bottom: _T.xuyenVietEmblemBottom,
    seed: 903,
    glyph: _sGlyph,
  ),
  'dong_nam_a': (
    top: _T.dongNamAEmblemTop,
    bottom: _T.dongNamAEmblemBottom,
    seed: 904,
    glyph: _stupaGlyph,
  ),
};

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter(this.campaign, this.foil);

  final String campaign;
  final Color foil;

  @override
  void paint(Canvas canvas, Size size) {
    paintScene(canvas, size, (canvas, size) {
      final e = _emblems[campaign] ?? _emblems['marathon']!;
      final rect = Offset.zero & size;
      final center = size.center(Offset.zero);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: size.height * 0.7 / size.shortestSide,
            colors: [e.top, e.bottom],
          ).createShader(rect),
      );
      paintGrain(canvas, size, e.seed, alpha: 0.04);
      final r = size.width * 0.27;
      canvas
        ..drawCircle(
          center,
          r * 2,
          Paint()
            ..shader = ui.Gradient.radial(
              center,
              r * 2,
              [foil.withValues(alpha: 0.2), foil.withValues(alpha: 0)],
              [0.25, 1],
            ),
        )
        ..drawCircle(center, r, _fill(e.bottom))
        ..drawCircle(center, r, _stroke(foil, 2.2))
        ..drawCircle(
          center,
          r - 5,
          _stroke(foil.withValues(alpha: foil.a * 0.7), 0.8),
        );
      e.glyph(canvas, center, r * 0.62, _fill(foil), e.bottom);
      _laurel(canvas, center, r + 16, foil);
    });
  }

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.campaign != campaign || old.foil != foil;
}

/// Hai cành nguyệt quế mọc từ đáy vòng lên hai bên.
void _laurel(Canvas canvas, Offset center, double r, Color color) {
  final stem = _stroke(color, 1.4);
  final leaf = _fill(color);
  for (final side in const [-1.0, 1.0]) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      math.pi / 2 + side * 0.25,
      side * 2.35,
      false,
      stem,
    );
    for (var i = 0; i < 9; i++) {
      final a = math.pi / 2 + side * (0.4 + i * 0.25);
      final out = Offset(math.cos(a), math.sin(a));
      final at = center + out * r;
      final tilt = a + side * math.pi / 2 + side * 0.6;
      _ellipse(canvas, at + out * 4, 6.5, 2.6, tilt, leaf);
      _ellipse(canvas, at - out * 4, 6.5, 2.6, tilt - side * 1.1, leaf);
    }
  }
}

/// Đền cột Hy Lạp.
void _templeGlyph(Canvas canvas, Offset c, double s, Paint ink, Color bg) {
  final Offset(dx: cx, dy: cy) = c;
  canvas
    ..drawPath(
      Path()
        ..moveTo(cx - s * 0.62, cy - s * 0.32)
        ..lineTo(cx, cy - s * 0.7)
        ..lineTo(cx + s * 0.62, cy - s * 0.32)
        ..close(),
      ink,
    )
    ..drawRect(
      Rect.fromLTWH(cx - s * 0.62, cy - s * 0.3, s * 1.24, s * 0.12),
      ink,
    );
  for (var i = 0; i < 4; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        cx - s * 0.5 + i * s * 0.32,
        cy - s * 0.12,
        s * 0.13,
        s * 0.6,
      ),
      ink,
    );
  }
  canvas
    ..drawRect(
      Rect.fromLTWH(cx - s * 0.68, cy + s * 0.5, s * 1.36, s * 0.1),
      ink,
    )
    ..drawRect(
      Rect.fromLTWH(cx - s * 0.76, cy + s * 0.62, s * 1.52, s * 0.1),
      ink,
    );
}

/// Núi có chóp tuyết khoét theo màu nền.
void _peakGlyph(Canvas canvas, Offset c, double s, Paint ink, Color bg) {
  final Offset(dx: cx, dy: cy) = c;
  canvas
    ..drawPath(
      Path()
        ..moveTo(cx - s * 0.8, cy + s * 0.55)
        ..lineTo(cx - s * 0.1, cy - s * 0.65)
        ..lineTo(cx + s * 0.3, cy - s * 0.05)
        ..lineTo(cx + s * 0.45, cy - s * 0.3)
        ..lineTo(cx + s * 0.85, cy + s * 0.55)
        ..close(),
      ink,
    )
    ..drawPath(
      Path()
        ..moveTo(cx - s * 0.1, cy - s * 0.65)
        ..lineTo(cx - s * 0.32, cy - s * 0.27)
        ..lineTo(cx - s * 0.18, cy - s * 0.33)
        ..lineTo(cx - s * 0.06, cy - s * 0.22)
        ..lineTo(cx + s * 0.06, cy - s * 0.34)
        ..lineTo(cx + s * 0.13, cy - s * 0.3)
        ..close(),
      _fill(bg),
    );
}

/// Dải chữ S, sao đánh dấu điểm xuất phát Hà Nội.
void _sGlyph(Canvas canvas, Offset c, double s, Paint ink, Color bg) {
  final Offset(dx: cx, dy: cy) = c;
  canvas.drawPath(
    Path()
      ..moveTo(cx - s * 0.2, cy - s * 0.7)
      ..cubicTo(
        cx + s * 0.55,
        cy - s * 0.62,
        cx + s * 0.2,
        cy - s * 0.2,
        cx - s * 0.1,
        cy,
      )
      ..cubicTo(
        cx - s * 0.4,
        cy + s * 0.2,
        cx + s * 0.6,
        cy + s * 0.3,
        cx + s * 0.05,
        cy + s * 0.55,
      )
      ..lineTo(cx - s * 0.25, cy + s * 0.72),
    Paint()
      ..color = ink.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.2
      ..strokeCap = StrokeCap.round,
  );
  final star = Path();
  final starAt = Offset(cx - s * 0.55, cy - s * 0.62);
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isOdd ? s * 0.2 * 0.45 : s * 0.2;
    final p = starAt + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(star..close(), ink);
}

/// Bảo tháp trên bệ hai bậc.
void _stupaGlyph(Canvas canvas, Offset c, double s, Paint ink, Color bg) {
  final Offset(dx: cx, dy: cy) = c;
  canvas
    ..drawPath(
      Path()
        ..moveTo(cx - s * 0.55, cy + s * 0.5)
        ..quadraticBezierTo(cx - s * 0.52, cy - s * 0.05, cx, cy - s * 0.15)
        ..quadraticBezierTo(
          cx + s * 0.52,
          cy - s * 0.05,
          cx + s * 0.55,
          cy + s * 0.5,
        )
        ..close(),
      ink,
    )
    ..drawPath(
      Path()
        ..moveTo(cx - s * 0.12, cy - s * 0.13)
        ..lineTo(cx, cy - s * 0.78)
        ..lineTo(cx + s * 0.12, cy - s * 0.13)
        ..close(),
      ink,
    );
  for (var i = 0; i < 3; i++) {
    canvas.drawCircle(
      Offset(cx, cy - s * (0.28 + i * 0.15)),
      s * (0.1 - i * 0.02),
      ink,
    );
  }
  canvas
    ..drawRect(
      Rect.fromLTWH(cx - s * 0.72, cy + s * 0.5, s * 1.44, s * 0.1),
      ink,
    )
    ..drawRect(
      Rect.fromLTWH(cx - s * 0.82, cy + s * 0.62, s * 1.64, s * 0.1),
      ink,
    );
}
