import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowCardSceneTokens;

/// Tranh mặt trước thẻ Ma Sói theo phe: Sói hú dưới trăng máu, làng thắp
/// đèn dưới mắt tiên tri, hay cặp đôi dưới trăng hồng. Phe lạ vẽ như phe Dân.
class GameTeamArt extends StatelessWidget {
  const GameTeamArt({super.key, required this.team});

  /// village, wolves hay lovers.
  final String team;

  @override
  Widget build(BuildContext context) {
    // Thẻ vẽ lại mỗi khung hình khi nghiêng; tranh đứng yên nên tách lớp.
    return RepaintBoundary(
      child: CustomPaint(painter: _TeamScenePainter(team)),
    );
  }
}

class _TeamScenePainter extends CustomPainter {
  const _TeamScenePainter(this.team);

  final String team;

  @override
  void paint(Canvas canvas, Size size) {
    paintScene(canvas, size, switch (team) {
      'wolves' => _wolves,
      'lovers' => _lovers,
      _ => _village,
    });
  }

  @override
  bool shouldRepaint(_TeamScenePainter old) => old.team != team;
}

void _wolves(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, const [
    (0, _T.wolvesSky1),
    (0.45, _T.wolvesSky2),
    (0.75, _T.wolvesSky3),
    (1, _T.wolvesSky4),
  ]);
  paintStars(
    canvas,
    size,
    count: 34,
    seed: 11,
    maxY: 0.5,
    color: _T.wolvesStar,
  );
  paintMoon(
    canvas,
    Offset(w * 0.58, h * 0.36),
    w * 0.22,
    core: _T.wolvesMoonCore,
    rim: _T.wolvesMoonRim,
    glow: _T.wolvesMoonGlow,
  );
  paintFog(canvas, w, h * 0.68, 18, _T.wolvesFog);
  paintPines(canvas, w, h * 0.8, h * 0.2, 9, _T.wolvesPines, 5);
  // Mỏm đá và sói hú ngược trăng.
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.02, h)
      ..lineTo(w * 0.1, h * 0.74)
      ..lineTo(w * 0.3, h * 0.68)
      ..lineTo(w * 0.56, h * 0.7)
      ..lineTo(w * 0.7, h * 0.82)
      ..lineTo(w * 0.8, h)
      ..close(),
    Paint()..color = _T.wolvesRock,
  );
  paintWolf(canvas, Offset(w * 0.2, h * 0.4), w * 0.36, _T.wolvesRock);
  // Ba vết cào góc trên phải.
  final claw = Paint()
    ..color = _T.wolvesClaw
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  const len = 40.0;
  for (var i = 0; i < 3; i++) {
    final ox = w * 0.78 + i * 9;
    final oy = h * 0.08 + i * 4;
    claw.strokeWidth = 3.2 - i * 0.4;
    canvas.drawPath(
      Path()
        ..moveTo(ox, oy)
        ..quadraticBezierTo(ox - 6, oy + len * 0.5, ox - 16, oy + len),
      claw,
    );
  }
  paintGrain(canvas, size, 4);
}

void _village(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, const [
    (0, _T.villageSky1),
    (0.5, _T.villageSky2),
    (0.8, _T.villageSky3),
    (1, _T.villageSky4),
  ]);
  paintStars(
    canvas,
    size,
    count: 40,
    seed: 21,
    maxY: 0.55,
    color: _T.villageStar,
  );
  final moon = Offset(w * 0.5, h * 0.34);
  final mr = w * 0.21;
  paintMoon(
    canvas,
    moon,
    mr,
    core: _T.villageMoonCore,
    rim: _T.villageMoonRim,
    glow: _T.villageMoonGlow,
  );
  // Mắt tiên tri trong trăng.
  canvas
    ..drawPath(
      Path()
        ..moveTo(moon.dx - mr * 0.7, moon.dy)
        ..quadraticBezierTo(
          moon.dx,
          moon.dy - mr * 0.62,
          moon.dx + mr * 0.7,
          moon.dy,
        )
        ..quadraticBezierTo(
          moon.dx,
          moon.dy + mr * 0.62,
          moon.dx - mr * 0.7,
          moon.dy,
        ),
      Paint()
        ..color = _T.villageEye
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    )
    ..drawCircle(moon, mr * 0.24, Paint()..color = _T.villageEye)
    ..drawCircle(
      moon + Offset(-mr * 0.07, -mr * 0.08),
      mr * 0.07,
      Paint()..color = _T.villageMoonCore,
    );
  paintFog(canvas, w, h * 0.7, 18, _T.villageFog);
  paintPines(canvas, w, h * 0.78, h * 0.16, 10, _T.villagePines, 7);
  _houses(canvas, w, h * 0.94);
  // Hai đốm mắt sói rình ở bìa rừng.
  for (final x in const [0.86, 0.89]) {
    final eye = Rect.fromCenter(
      center: Offset(w * x, h * 0.74),
      width: 4.4,
      height: 2.6,
    );
    canvas
      ..drawOval(
        eye.inflate(2),
        Paint()
          ..color = _T.villageWolfEye
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawOval(eye, Paint()..color = _T.villageWolfEye);
  }
  paintGrain(canvas, size, 8);
}

/// Sáu nóc nhà có cửa sổ sáng đèn và tháp chuông nhà thờ làng.
void _houses(Canvas canvas, double w, double base) {
  final r = SceneRandom(3);
  final wall = Paint()..color = _T.villageHouse;
  final lit = Paint()..color = _T.villageWindow;
  final glow = Paint()
    ..color = _T.villageWindow
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  for (final (fx, fw, fh) in const [
    (0.04, 0.16, 0.11),
    (0.2, 0.13, 0.09),
    (0.34, 0.18, 0.13),
    (0.55, 0.12, 0.08),
    (0.68, 0.17, 0.12),
    (0.84, 0.14, 0.1),
  ]) {
    final x = fx * w;
    final hw = fw * w;
    final hh = fh * w * 1.25;
    canvas
      ..drawRect(Rect.fromLTWH(x, base - hh, hw, hh + 30), wall)
      ..drawPath(
        Path()
          ..moveTo(x - 4, base - hh)
          ..lineTo(x + hw / 2, base - hh - hw * 0.55)
          ..lineTo(x + hw + 4, base - hh)
          ..close(),
        wall,
      );
    final windows = 1 + (r.next() * 2).floor();
    for (var i = 0; i < windows; i++) {
      final window = Rect.fromLTWH(
        x + hw * (0.22 + i * 0.38),
        base - hh * 0.62,
        hw * 0.2,
        hh * 0.26,
      );
      canvas
        ..drawRect(window, glow)
        ..drawRect(window, lit);
    }
  }
  // Tháp chuông nhà thờ làng: đỉnh chạm mép dưới trăng, không che mắt.
  final tx = 0.47 * w;
  canvas
    ..drawRect(
      Rect.fromLTWH(tx, base - w * 0.24, w * 0.06, w * 0.24 + 30),
      wall,
    )
    ..drawPath(
      Path()
        ..moveTo(tx - 3, base - w * 0.24)
        ..lineTo(tx + w * 0.03, base - w * 0.33)
        ..lineTo(tx + w * 0.06 + 3, base - w * 0.24)
        ..close(),
      wall,
    );
}

void _lovers(Canvas canvas, Size size) {
  final Size(width: w, height: h) = size;
  paintSky(canvas, size, const [
    (0, _T.loversSky1),
    (0.45, _T.loversSky2),
    (0.8, _T.loversSky3),
    (1, _T.loversSky4),
  ]);
  paintStars(
    canvas,
    size,
    count: 32,
    seed: 31,
    maxY: 0.5,
    color: _T.loversStar,
  );
  paintMoon(
    canvas,
    Offset(w * 0.5, h * 0.36),
    w * 0.24,
    core: _T.loversMoonCore,
    rim: _T.loversMoonRim,
    glow: _T.loversMoonGlow,
  );
  // Mũi tên thần tình yêu xuyên trăng.
  final arrow = Paint()
    ..color = _T.loversArrow
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  canvas
    ..drawLine(Offset(w * 0.12, h * 0.52), Offset(w * 0.88, h * 0.2), arrow)
    ..drawPath(
      Path()
        ..moveTo(w * 0.9, h * 0.19)
        ..lineTo(w * 0.82, h * 0.19)
        ..lineTo(w * 0.85, h * 0.26)
        ..close(),
      Paint()..color = _T.loversArrow,
    );
  for (final (x, y) in const [(0.14, 0.51), (0.18, 0.494)]) {
    final tail = Offset(w * x, h * y);
    canvas
      ..drawLine(tail, Offset(w * (x - 0.04), h * (y - 0.045)), arrow)
      ..drawLine(tail, Offset(w * (x - 0.05), h * (y + 0.01)), arrow);
  }
  paintPines(canvas, w, h * 0.82, h * 0.16, 9, _T.loversPines, 13);
  final hill = Paint()..color = _T.loversHill;
  canvas.drawPath(
    Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(w * 0.5, h * 0.74, w, h * 0.88)
      ..lineTo(w, h)
      ..close(),
    hill,
  );
  _person(canvas, w * 0.44, h * 0.9, 40, hill);
  _person(canvas, w * 0.56, h * 0.9, 37, hill);
  // Hai bàn tay nắm nhau.
  canvas.drawLine(
    Offset(w * 0.465, h * 0.83),
    Offset(w * 0.535, h * 0.83),
    Paint()
      ..color = _T.loversHill
      ..strokeWidth = 4,
  );
  paintGrain(canvas, size, 12);
}

void _person(Canvas canvas, double x, double base, double s, Paint paint) {
  canvas
    ..drawCircle(Offset(x, base - s * 1.62), s * 0.2, paint)
    ..drawPath(
      Path()
        ..moveTo(x - s * 0.2, base - s * 1.38)
        ..lineTo(x + s * 0.2, base - s * 1.38)
        ..lineTo(x + s * 0.3, base - s * 0.55)
        ..lineTo(x + s * 0.14, base - s * 0.55)
        ..lineTo(x + s * 0.12, base)
        ..lineTo(x - s * 0.12, base)
        ..lineTo(x - s * 0.14, base - s * 0.55)
        ..lineTo(x - s * 0.3, base - s * 0.55)
        ..close(),
      paint,
    );
}

typedef _EmblemPalette = ({
  Color top,
  Color bottom,
  Color core,
  Color rim,
  Color glow,
  Color dark,
});

const _emblems = <String, _EmblemPalette>{
  'wolves': (
    top: _T.wolvesEmblemTop,
    bottom: _T.wolvesEmblemBottom,
    core: _T.wolvesMoonCore,
    rim: _T.wolvesMoonRim,
    glow: _T.wolvesEmblemGlow,
    dark: _T.wolvesEmblemDark,
  ),
  'village': (
    top: _T.villageEmblemTop,
    bottom: _T.villageEmblemBottom,
    core: _T.villageMoonCore,
    rim: _T.villageEmblemRim,
    glow: _T.villageMoonGlow,
    dark: _T.villageEmblemDark,
  ),
  'lovers': (
    top: _T.loversEmblemTop,
    bottom: _T.loversEmblemBottom,
    core: _T.loversMoonCore,
    rim: _T.loversMoonRim,
    glow: _T.loversMoonGlow,
    dark: _T.loversEmblemDark,
  ),
};

/// Mặt sau thẻ Ma Sói, cũng là mặt úp lúc chờ lật: chỉ một biểu tượng, sói
/// hú trong vầng trăng màu phe, viền nhũ màu bậc.
class GameCardEmblem extends StatelessWidget {
  const GameCardEmblem({super.key, required this.team, required this.tier});

  final String team;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    // Nền huy hiệu luôn là đêm, nên bộ màu sáng mượn màu bậc của bộ tối.
    final skin = RunCardSkin.of(context);
    final foil = (skin.darkMap ? skin : RunCardSkin.classic).accent(tier);
    return RepaintBoundary(
      child: CustomPaint(painter: _EmblemPainter(team, foil)),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter(this.team, this.foil);

  final String team;
  final Color foil;

  @override
  void paint(Canvas canvas, Size size) {
    paintScene(canvas, size, (canvas, size) {
      final p = _emblems[team] ?? _emblems['village']!;
      final rect = Offset.zero & size;
      final center = size.center(Offset.zero);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: size.height * 0.7 / size.shortestSide,
            colors: [p.top, p.bottom],
          ).createShader(rect),
      );
      paintStars(
        canvas,
        size,
        count: 26,
        seed: 40,
        maxY: 1,
        color: _T.starWhite,
      );
      final r = size.width * 0.32;
      paintMoon(canvas, center, r, core: p.core, rim: p.rim, glow: p.glow);
      // Đồi và sói in bóng, cắt theo vành trăng.
      canvas
        ..save()
        ..clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
      final dark = Paint()..color = p.dark;
      final Offset(dx: cx, dy: cy) = center;
      canvas.drawPath(
        Path()
          ..moveTo(cx - r, cy + r)
          ..lineTo(cx - r, cy + r * 0.62)
          ..quadraticBezierTo(
            cx - r * 0.2,
            cy + r * 0.5,
            cx + r * 0.2,
            cy + r * 0.66,
          )
          ..lineTo(cx + r, cy + r * 0.78)
          ..lineTo(cx + r, cy + r)
          ..close(),
        dark,
      );
      final s = r * 1.15;
      paintWolf(canvas, Offset(cx - s * 0.52, cy - s * 0.4), s, p.dark);
      canvas
        ..restore()
        ..drawCircle(
          center,
          r + 6,
          Paint()
            ..color = foil
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..drawCircle(
          center,
          r + 11,
          Paint()
            ..color = foil.withValues(alpha: foil.a * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      paintGrain(canvas, size, 60, alpha: 0.035);
    });
  }

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.team != team || old.foil != foil;
}
