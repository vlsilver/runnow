import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme_tokens.dart';

typedef _T = RunNowCardSceneTokens;

/// Màu nền một hạng: trên, dưới, quầng sáng.
typedef _Look = ({Color top, Color bottom, Color glow});

const _shade = _T.journeyShade;
const _shine = _T.medalShine;

/// Thẻ tháng ngả về trời đêm; hạng ngoài 1..10 mặc màu hạng 10.
_Look _lookOf(int rank, bool month) {
  final i = rank.clamp(1, 10) - 1;
  final top = _T.rankTop[i], bottom = _T.rankBottom[i], glow = _T.rankGlow[i];
  if (!month) return (top: top, bottom: bottom, glow: glow);
  return (
    top: Color.lerp(top, _T.rankNightTop, 0.35)!,
    bottom: Color.lerp(bottom, _T.rankNightBottom, 0.4)!,
    glow: glow,
  );
}

const rankSportNames = {
  ClubRankingSport.run: 'CHẠY · ĐI BỘ',
  ClubRankingSport.steps: 'BƯỚC CHÂN',
  ClubRankingSport.bike: 'ĐẠP XE',
};

String rankTitleUpper(int rank) => switch (rank) {
  1 => 'QUÁN QUÂN',
  2 => 'Á QUÂN',
  3 => 'HẠNG BA',
  _ => 'TOP 10',
};

LinearGradient _metal(GameCardTierStyle m, Alignment a, Alignment b) =>
    m.gems == 5
    ? LinearGradient(
        begin: a,
        end: b,
        colors: _T.rankDiamond,
        stops: const [0, 0.3, 0.55, 0.75, 1],
      )
    : LinearGradient(begin: a, end: b, colors: m.frame, stops: m.frameStops);

/// Nền theo hạng: dải màu, tia sáng toả từ huy chương, quầng, hạt nhiễu; thẻ
/// tháng thêm sao.
void _paintGround(
  Canvas canvas,
  Size size,
  _Look look,
  Offset c,
  bool month,
  int seed,
) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          look.top,
          Color.lerp(look.top, look.bottom, 0.55)!,
          look.bottom,
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect),
  );
  if (month) {
    paintStars(canvas, size, count: 70, seed: seed, color: _shine, maxY: 0.62);
  }
  canvas.saveLayer(rect, Paint());
  final rays = Path();
  const n = 18;
  for (var i = 0; i < n; i++) {
    final a = i * 2 * math.pi / n;
    final b = a + math.pi / n;
    rays
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + math.cos(a) * 600, c.dy + math.sin(a) * 600)
      ..lineTo(c.dx + math.cos(b) * 600, c.dy + math.sin(b) * 600)
      ..close();
  }
  canvas
    ..drawPath(
      rays,
      Paint()..color = _shine.withValues(alpha: month ? 0.05 : 0.08),
    )
    ..drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          center: Alignment(
            c.dx / size.width * 2 - 1,
            c.dy / size.height * 2 - 1,
          ),
          radius: 0.75,
          colors: [_shine, _shine.withValues(alpha: 0)],
        ).createShader(rect),
    )
    ..restore();
  canvas.drawCircle(
    c,
    130,
    Paint()
      ..shader = RadialGradient(
        colors: [
          look.glow.withValues(alpha: 0.42),
          look.glow.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: 130)),
  );
  paintGrain(canvas, size, seed, alpha: 0.04);
}

/// Huy chương treo dây: vành kim loại theo bậc, chữ chạy quanh vành, lòng
/// khắc số hạng (mặt trước) hoặc biểu tượng bộ môn (mặt sau, [sport]).
void _paintMedal(
  Canvas canvas,
  Offset c,
  double r,
  int rank,
  GameCardTierStyle metal,
  _Look look,
  String rim,
  double numeral, {
  ClubRankingSport? sport,
}) {
  final strap = Color.lerp(look.top, _shade, 0.3)!;
  final stripes = [strap, look.glow, strap, look.glow, strap];
  void ribbon({required bool left}) {
    Offset at(double dx, double y) => Offset(c.dx + (left ? -dx : dx), y);
    final outerTop = at(r * 1.22, -12), innerTop = at(r * 0.42, -12);
    final outerFoot = at(r * 0.22, c.dy - r + r * 0.58);
    final innerFoot = at(-r * 0.2, c.dy - r + r * 0.42);
    final n = stripes.length;
    Offset top(int j) => Offset.lerp(outerTop, innerTop, j / n)!;
    Offset foot(int j) => Offset.lerp(outerFoot, innerFoot, j / n)!;
    for (final (i, color) in stripes.indexed) {
      final stripe = Path()
        ..moveTo(top(i).dx, top(i).dy)
        ..lineTo(top(i + 1).dx, top(i + 1).dy)
        ..lineTo(foot(i + 1).dx, foot(i + 1).dy)
        ..lineTo(foot(i).dx, foot(i).dy)
        ..close();
      canvas.drawPath(stripe, Paint()..color = color);
      if (left) {
        canvas.drawPath(
          stripe,
          Paint()..color = _shade.withValues(alpha: 0.18),
        );
      }
    }
  }

  ribbon(left: false);
  ribbon(left: true);
  if (metal.gems == 5) {
    final halo = Rect.fromCircle(center: c, radius: r * 1.6);
    canvas
      ..saveLayer(halo, Paint())
      ..drawCircle(
        c,
        r * 1.6,
        Paint()
          ..shader = const SweepGradient(
            colors: _T.rankDiamondHalo,
          ).createShader(halo),
      )
      ..drawCircle(
        c,
        r * 1.6,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = RadialGradient(
            colors: [
              _shine.withValues(alpha: 0.7),
              _shine.withValues(alpha: 0.3),
              _shine.withValues(alpha: 0),
            ],
            stops: const [0, 0.6, 1],
          ).createShader(halo),
      )
      ..restore();
  }
  final medal = Rect.fromCircle(center: c, radius: r);
  final gloss = _metal(
    metal,
    Alignment.topLeft,
    Alignment.bottomRight,
  ).createShader(medal);
  // Lòng huy chương đổ sáng ngược vành nên trông lõm xuống.
  final dish = _metal(
    metal,
    Alignment.bottomRight,
    Alignment.topLeft,
  ).createShader(medal);
  final ink = Color.lerp(
    metal.frame.first,
    _shade,
    0.35,
  )!.withValues(alpha: 0.9);
  final field = r - r * 0.24;
  Paint line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
  canvas
    ..drawCircle(
      c + Offset(0, -r - 6),
      8,
      Paint()
        ..shader = gloss
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    )
    ..drawCircle(
      c + const Offset(3, 7),
      r,
      Paint()
        ..color = _shade.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    )
    ..drawCircle(c, r, Paint()..shader = gloss)
    ..drawCircle(c, r - 4, line(_shade.withValues(alpha: 0.25), 1))
    ..drawCircle(c, field, Paint()..shader = dish)
    ..drawCircle(c, field, line(_shade.withValues(alpha: 0.35), 1.5))
    ..drawCircle(c, field - 1.5, line(_shine.withValues(alpha: 0.35), 0.8));
  paintRingText(canvas, c, r - r * 0.118, rim, ink);
  // Khắc chìm: nét sáng lệch xuống phải, nét mực đè lên.
  if (sport != null) {
    _paintSport(
      canvas,
      c + const Offset(1.2, 1.4),
      field * 1.15,
      sport,
      _shine.withValues(alpha: 0.5),
    );
    _paintSport(canvas, c, field * 1.15, sport, ink);
    return;
  }
  TextPainter lay(double s, Color color) => TextPainter(
    text: TextSpan(
      text: '$rank',
      style: TextStyle(
        fontFamily: 'Barlow Condensed',
        fontWeight: FontWeight.w800,
        fontSize: s,
        height: 1,
        letterSpacing: -s * 0.02,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  var s = numeral;
  final probe = lay(s, ink);
  if (probe.width > field * 1.35) s *= field * 1.35 / probe.width;
  final glyph = lay(s, ink);
  final baseline = glyph.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  // Chữ số Barlow cao ~0.7 cỡ chữ: đặt giữa thân số vào tâm.
  final at = Offset(c.dx - glyph.width / 2, c.dy + s * 0.35 - baseline);
  lay(
    s,
    _shine.withValues(alpha: 0.5),
  ).paint(canvas, at + const Offset(1.2, 1.4));
  glyph.paint(canvas, at);
}

/// Biểu tượng bộ môn cỡ [size] đặt giữa [c]: chạy và xe đạp lấy từ Material
/// Icons, bước chân là hai dấu bàn chân vẽ tay.
void _paintSport(
  Canvas canvas,
  Offset c,
  double size,
  ClubRankingSport sport,
  Color color,
) {
  if (sport == ClubRankingSport.steps) {
    final u = size / 24;
    Offset p(double x, double y) => c + Offset((x - 12) * u, (y - 12) * u);
    final paint = Paint()..color = color;
    void sole(Offset at, double rx, double ry, double deg) {
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(deg * math.pi / 180)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: rx * 2 * u,
            height: ry * 2 * u,
          ),
          paint,
        )
        ..restore();
    }

    sole(p(8, 11.5), 3, 4.8, -12);
    sole(p(9.3, 19), 2.2, 1.8, -12);
    sole(p(16.2, 6.5), 3, 4.8, 12);
    sole(p(15, 14), 2.2, 1.8, 12);
    return;
  }
  final icon = sport == ClubRankingSport.run
      ? Icons.directions_run_rounded
      : Icons.directions_bike_rounded;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        height: 1,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
}

String _rim(int rank, String period, ClubRankingSport sport) =>
    '$period · ${rankTitleUpper(rank)} · ${rankSportNames[sport]} · ';

/// Tranh mặt trước thẻ BXH: nền theo hạng, huy chương khắc số hạng.
class RankMedalArt extends StatelessWidget {
  const RankMedalArt({
    super.key,
    required this.rank,
    required this.month,
    required this.period,
    required this.sport,
    required this.tier,
  });

  final int rank;
  final bool month;

  /// In quanh vành huy chương, vd "TUẦN 19–25/10".
  final String period;
  final ClubRankingSport sport;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RankArtPainter(rank, month, period, sport, tier));
}

/// Mặt sau thẻ BXH: huy chương lớn khắc biểu tượng bộ môn, tên bộ môn và kỳ.
class RankBackArt extends StatelessWidget {
  const RankBackArt({
    super.key,
    required this.rank,
    required this.month,
    required this.period,
    required this.sport,
    required this.tier,
  });

  final int rank;
  final bool month;
  final String period;
  final ClubRankingSport sport;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RankBackPainter(rank, month, period, sport, tier));
}

class _RankArtPainter extends CustomPainter {
  const _RankArtPainter(
    this.rank,
    this.month,
    this.period,
    this.sport,
    this.tier,
  );

  final int rank;
  final bool month;
  final String period;
  final ClubRankingSport sport;
  final GameCardTier tier;

  // Tranh tràn quanh thẻ 300x420 như tranh Hành trình, nên vẽ trên khổ 320
  // ngang; huy chương nằm trên khối chữ.
  static const _width = 320.0;
  static const _c = Offset(160, 120);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _width;
    canvas
      ..save()
      ..scale(k);
    final look = _lookOf(rank, month);
    _paintGround(
      canvas,
      Size(_width, size.height / k),
      look,
      _c,
      month,
      400 + rank,
    );
    _paintMedal(
      canvas,
      _c,
      70,
      rank,
      gameCardTiers[tier]!,
      look,
      _rim(rank, period, sport),
      84,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RankArtPainter old) =>
      old.rank != rank ||
      old.month != month ||
      old.period != period ||
      old.sport != sport ||
      old.tier != tier;
}

class _RankBackPainter extends CustomPainter {
  const _RankBackPainter(
    this.rank,
    this.month,
    this.period,
    this.sport,
    this.tier,
  );

  final int rank;
  final bool month;
  final String period;
  final ClubRankingSport sport;
  final GameCardTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    final look = _lookOf(rank, month);
    final c = Offset(size.width / 2, size.height * 0.47);
    _paintGround(canvas, size, look, c, month, 900 + rank);
    // Vòng đồng tâm mảnh như mặt sau huy chương.
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        c,
        104.0 + i * 14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = look.glow.withValues(alpha: 0.18 - i * 0.04),
      );
    }
    _paintMedal(
      canvas,
      c,
      96,
      rank,
      gameCardTiers[tier]!,
      look,
      _rim(rank, period, sport),
      112,
      sport: sport,
    );
    TextPainter label(String text, double size, double spacing, Color color) =>
        TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: 'Barlow Condensed',
              fontWeight: FontWeight.w800,
              fontSize: size,
              letterSpacing: spacing,
              height: 1,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
    // Chữ giãn cách thì lệch phải nửa khoảng giãn, bù lại cho cân giữa.
    final name = label(rankSportNames[sport]!, 26, 5, _shine);
    name.paint(canvas, Offset(c.dx - name.width / 2 + 2.5, size.height - 96));
    final when = label(period, 13, 4, look.glow.withValues(alpha: 0.85));
    when.paint(canvas, Offset(c.dx - when.width / 2 + 2, size.height - 58));
  }

  @override
  bool shouldRepaint(_RankBackPainter old) =>
      old.rank != rank ||
      old.month != month ||
      old.period != period ||
      old.sport != sport ||
      old.tier != tier;
}
