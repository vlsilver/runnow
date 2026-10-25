import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Bậc của lá bài khoe. Bậc chỉ hiện ở chất liệu khung: than chì, bạc, vàng,
/// vàng foil có ánh xà cừ. Thần thoại (cực quang) hiện chỉ thẻ buổi chạy quay ra.
enum GameCardTier { common, rare, superRare, legendary, mythic }

extension GameCardTierParse on GameCardTier {
  static GameCardTier fromKey(String? key) => switch (key) {
    'rare' => GameCardTier.rare,
    'super' => GameCardTier.superRare,
    'legendary' => GameCardTier.legendary,
    'mythic' => GameCardTier.mythic,
    _ => GameCardTier.common,
  };
}

/// Kích thước gốc của lá bài; nơi dùng bọc trong [FittedBox] để phóng to nhỏ.
const gameCardSize = Size(250, 350);

const _ink = RunNowGameTokens.nightInk;
const _gold = RunNowGameTokens.gold;

class GameRoleStyle {
  const GameRoleStyle(this.label, this.team, this.accent, this.flavor);

  final String label;
  final String team;
  final Color accent;
  final String flavor;
}

// Mọi vai chung nền mực; vai chỉ khác nhau ở một màu nhấn dịu cho icon và nhãn.
const _roles = {
  'wolf': GameRoleStyle(
    'Sói',
    'Phe Sói',
    RunNowGameTokens.roleWolf,
    'Trăng lên thì cả đàn xỏ giày. Sáng ra lại là đồng nghiệp hiền lành.',
  ),
  'villager': GameRoleStyle(
    'Dân làng',
    'Phe Dân',
    RunNowGameTokens.roleVillager,
    'Không phép thuật, chỉ có đôi giày và lá phiếu.',
  ),
  'seer': GameRoleStyle(
    'Tiên tri',
    'Phe Dân',
    RunNowGameTokens.roleSeer,
    'Mỗi đêm nhìn thấu một người. Giữ được bí mật mới khó.',
  ),
  'guard': GameRoleStyle(
    'Bảo vệ',
    'Phe Dân',
    RunNowGameTokens.roleGuard,
    'Đứng gác cổng làng tới sáng, không ngủ, không than.',
  ),
  'witch': GameRoleStyle(
    'Phù thuỷ',
    'Phe Dân',
    RunNowGameTokens.roleWitch,
    'Một lọ cứu, một lọ độc. Dùng lúc nào mới là nghề.',
  ),
  'hunter': GameRoleStyle(
    'Thợ săn',
    'Phe Dân',
    RunNowGameTokens.roleHunter,
    'Có ngã xuống thì cũng không ngã một mình.',
  ),
  'cupid': GameRoleStyle(
    'Cupid',
    'Phe Dân',
    RunNowGameTokens.roleCupid,
    'Một mũi tên, hai số phận chạy chung một đường.',
  ),
};

class GameCardTierStyle {
  const GameCardTierStyle(
    this.label,
    this.gems,
    this.gem,
    this.frame,
    this.frameStops,
    this.holo,
    this.sparkle,
  );

  final String label;
  final int gems;
  final Color gem;
  final List<Color> frame;
  final List<double>? frameStops;
  final double holo;
  final bool sparkle;
}

const gameCardTiers = {
  GameCardTier.common: GameCardTierStyle(
    'Thường',
    1,
    RunNowGameTokens.gemGraphite,
    [
      RunNowGameTokens.graphiteEdge,
      RunNowGameTokens.graphiteCore,
      RunNowGameTokens.graphiteEdge,
    ],
    null,
    0,
    false,
  ),
  GameCardTier.rare: GameCardTierStyle(
    'Hiếm',
    2,
    RunNowGameTokens.gemSilver,
    [
      RunNowGameTokens.silverEdge,
      RunNowGameTokens.silverLight,
      RunNowGameTokens.silverDeep,
      RunNowGameTokens.silverBright,
      RunNowGameTokens.silverEdge,
    ],
    [0, 0.3, 0.55, 0.8, 1],
    0.08,
    false,
  ),
  GameCardTier.superRare: GameCardTierStyle(
    'Siêu hiếm',
    3,
    RunNowGameTokens.goldDeep,
    [
      RunNowGameTokens.goldEdge,
      RunNowGameTokens.goldDeep,
      RunNowGameTokens.goldMid,
      RunNowGameTokens.goldDeep,
    ],
    [0, 0.35, 0.65, 1],
    0.14,
    false,
  ),
  GameCardTier.legendary: GameCardTierStyle(
    'Huyền thoại',
    4,
    _gold,
    [
      RunNowGameTokens.foilDark,
      _gold,
      RunNowGameTokens.foilMid,
      RunNowGameTokens.goldPale,
      RunNowGameTokens.foilDeep,
      RunNowGameTokens.goldDeep,
    ],
    [0, 0.2, 0.42, 0.6, 0.8, 1],
    0.24,
    true,
  ),
  GameCardTier.mythic: GameCardTierStyle(
    'Thần thoại',
    5,
    RunNowAchievementTokens.auroraTeal,
    [
      RunNowAchievementTokens.auroraDeep,
      RunNowAchievementTokens.auroraTeal,
      RunNowAchievementTokens.auroraBlue,
      RunNowAchievementTokens.auroraViolet,
      RunNowAchievementTokens.auroraIce,
      RunNowAchievementTokens.auroraDeep,
    ],
    [0, 0.2, 0.42, 0.6, 0.8, 1],
    0.3,
    true,
  ),
};

/// Một ô số liệu ở giữa lá bài.
class GameCardStat {
  const GameCardStat(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;
}

/// Dữ liệu một lá bài, để màn ván và màn xem to vẽ cùng một lá.
class GameCardData {
  const GameCardData({
    required this.role,
    required this.player,
    required this.stats,
    this.roleLabel,
    this.caption = 'Ma Sói',
    this.tier = GameCardTier.common,
  });

  final String role;
  final String? roleLabel;
  final String player;
  final List<GameCardStat> stats;
  final String caption;
  final GameCardTier tier;

  GameRoleCard front({Offset holo = const Offset(0.4, 0.3)}) => GameRoleCard(
    role: role,
    roleLabel: roleLabel,
    player: player,
    stats: stats,
    caption: caption,
    tier: tier,
    holo: holo,
  );
}

/// Lá bài vẽ ở [size] rồi thu phóng theo bề ngang [width].
class GameCardScaled extends StatelessWidget {
  const GameCardScaled({
    super.key,
    required this.width,
    required this.child,
    this.size = gameCardSize,
  });

  final double width;
  final Widget child;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * size.height / size.width,
      child: FittedBox(child: child),
    );
  }
}

/// Mặt trước lá bài, vẽ ở [gameCardSize]. [holo] là điểm sáng (0..1 mỗi
/// chiều) mà lớp xà cừ và vệt sáng chạy theo khi nghiêng.
class GameRoleCard extends StatelessWidget {
  const GameRoleCard({
    super.key,
    required this.role,
    required this.player,
    required this.stats,
    this.roleLabel,
    this.caption = 'Ma Sói',
    this.tier = GameCardTier.common,
    this.holo = const Offset(0.4, 0.3),
  });

  /// Khoá vai của backend: wolf, seer, …
  final String role;

  /// Tên vai backend gửi; null thì lấy tên mặc định của app.
  final String? roleLabel;
  final String player;
  final List<GameCardStat> stats;
  final String caption;
  final GameCardTier tier;
  final Offset holo;

  @override
  Widget build(BuildContext context) {
    final r = gameRoleStyle(role);
    final t = gameCardTiers[tier]!;
    final accent = r.accent;
    return GameCardFrame(
      colors: t.frame,
      stops: t.frameStops,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.3,
                colors: [
                  RunNowGameTokens.cardFieldTop,
                  RunNowGameTokens.cardFieldBottom,
                ],
                stops: [0, 0.64],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (roleLabel ?? r.label).toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.76,
                          color: accent,
                        ),
                      ),
                    ),
                    for (var i = 0; i < t.gems; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: CustomPaint(
                          size: const Size(9, 11),
                          painter: GameCardGemPainter(t.gem),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  player,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                    shadows: [
                      const Shadow(
                        color: RunNowGameTokens.cardTextShadow,
                        offset: Offset(0, 2),
                      ),
                      Shadow(
                        color: accent.withValues(alpha: 0.25),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _Art(role: role, accent: accent),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      r.team,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _ink.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(child: _StatBox(stat: stats[i])),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    r.flavor,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.38,
                      fontStyle: FontStyle.italic,
                      color: _ink.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '3I RUN · MA SÓI',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.26,
                          color: _ink.withValues(alpha: 0.66),
                        ),
                      ),
                    ),
                    Text(
                      t.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.26,
                        fontWeight: FontWeight.w800,
                        color: t.gem,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (t.holo > 0) GameCardHolo(strength: t.holo, at: holo),
          if (t.sparkle)
            IgnorePointer(
              child: CustomPaint(painter: GameCardSparklePainter(holo)),
            ),
          GameCardGlare(at: holo, strength: 0.4),
        ],
      ),
    );
  }
}

/// Mặt sau chung của mọi lá, không lộ vai.
class GameCardBack extends StatelessWidget {
  const GameCardBack({super.key, this.holo = const Offset(0.4, 0.3)});

  final Offset holo;

  @override
  Widget build(BuildContext context) {
    return GameCardFrame(
      colors: const [
        RunNowGameTokens.backEdge,
        RunNowGameTokens.backLight,
        RunNowGameTokens.backDeep,
        RunNowGameTokens.backBright,
        RunNowGameTokens.backEdge,
      ],
      stops: const [0, 0.22, 0.46, 0.66, 0.86],
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.24),
                radius: 0.9,
                colors: [
                  RunNowGameTokens.backFieldTop,
                  RunNowGameTokens.backFieldBottom,
                ],
                stops: [0, 0.7],
              ),
            ),
          ),
          const CustomPaint(painter: _BackOrnamentPainter()),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const GameMoon(size: 74, glow: 40),
              const SizedBox(height: 14),
              const Text(
                'MA SÓI',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5.7,
                  color: _gold,
                  shadows: [
                    Shadow(
                      color: RunNowGameTokens.cardShadow,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '3I RUN · PSC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: _ink.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          GameCardGlare(at: holo, strength: 0.5),
        ],
      ),
    );
  }
}

class GameCardFrame extends StatelessWidget {
  const GameCardFrame({
    super.key,
    required this.colors,
    required this.child,
    this.stops,
  });

  final List<Color> colors;
  final List<double>? stops;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: gameCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            stops: stops,
          ),
          boxShadow: const [
            BoxShadow(
              color: RunNowGameTokens.cardShadow,
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.role, required this.accent});

  final String role;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 122,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: RadialGradient(
          center: const Alignment(-0.4, 1),
          radius: 1.2,
          colors: [accent.withValues(alpha: 0.18), RunNowGameTokens.cardArt],
          stops: const [0, 0.7],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            right: 18,
            top: 12,
            child: GameMoon(size: 30, glow: 24),
          ),
          Positioned.fill(
            child: CustomPaint(painter: GameCardHillsPainter(accent)),
          ),
          CustomPaint(
            size: const Size(76, 76),
            painter: GameRoleIconPainter(role, accent),
          ),
        ],
      ),
    );
  }
}

class GameMoon extends StatelessWidget {
  const GameMoon({super.key, required this.size, required this.glow});

  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [
            RunNowGameTokens.moonLight,
            RunNowGameTokens.moonMid,
            RunNowGameTokens.moonShade,
          ],
          stops: [0, 0.6, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: RunNowGameTokens.moonGlow.withValues(alpha: 0.5),
            blurRadius: glow,
          ),
        ],
      ),
    );
  }
}

/// Mặt trời của header ban ngày, cùng dáng với [GameMoon].
class GameSun extends StatelessWidget {
  const GameSun({super.key, required this.size, required this.glow});

  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [
            RunNowGameTokens.sunLight,
            RunNowGameTokens.sunMid,
            RunNowGameTokens.sunShade,
          ],
          stops: [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: RunNowGameTokens.sunMid.withValues(alpha: 0.55),
            blurRadius: glow,
          ),
        ],
      ),
    );
  }
}

/// Tên, phe, màu nhấn và lời dẫn của vai; vai lạ thì như Dân làng.
GameRoleStyle gameRoleStyle(String role) => _roles[role] ?? _roles['villager']!;

/// Màu nhấn của vai, như trên lá bài; vai lạ thì vàng.
Color gameRoleAccent(String role) => _roles[role]?.accent ?? _gold;

class _StatBox extends StatelessWidget {
  const _StatBox({required this.stat});

  final GameCardStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.7,
              color: _ink.withValues(alpha: 0.72),
            ),
          ),
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: stat.highlight ? _gold : _ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lớp xà cừ: dải kem, xanh băng, tím nhạt lặp lại, dời theo điểm sáng.
class GameCardHolo extends StatelessWidget {
  const GameCardHolo({super.key, required this.strength, required this.at});

  final double strength;
  final Offset at;

  @override
  Widget build(BuildContext context) {
    final a = 0.6 * strength;
    final sx = (at.dx - 0.5) * 1.2;
    final sy = (at.dy - 0.5) * 0.6;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          backgroundBlendMode: BlendMode.colorDodge,
          gradient: LinearGradient(
            begin: Alignment(-1 + sx, -1 + sy),
            end: Alignment(-0.45 + sx, -0.7 + sy),
            tileMode: TileMode.repeated,
            colors: [
              RunNowGameTokens.holoClear,
              RunNowGameTokens.holoCream.withValues(alpha: a),
              RunNowGameTokens.holoIce.withValues(alpha: a),
              RunNowGameTokens.holoLilac.withValues(alpha: a),
              RunNowGameTokens.holoClear,
            ],
            stops: const [0, 0.25, 0.5, 0.75, 1],
          ),
        ),
      ),
    );
  }
}

class GameCardGlare extends StatelessWidget {
  const GameCardGlare({super.key, required this.at, required this.strength});

  final Offset at;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          backgroundBlendMode: BlendMode.softLight,
          gradient: RadialGradient(
            center: Alignment(at.dx * 2 - 1, at.dy * 2 - 1),
            radius: 0.7,
            colors: [
              Colors.white.withValues(alpha: strength),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class GameCardGemPainter extends CustomPainter {
  const GameCardGemPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = RunNowGameTokens.gemOutline,
    );
  }

  @override
  bool shouldRepaint(GameCardGemPainter old) => old.color != color;
}

class GameCardHillsPainter extends CustomPainter {
  const GameCardHillsPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Toạ độ theo khung 226×40 của bản thiết kế, kéo theo bề ngang thật.
    final sx = size.width / 226;
    final top = size.height - 40;
    Offset p(double x, double y) => Offset(x * sx, top + y);
    const ridge = [
      [0.0, 26.0],
      [18.0, 18.0],
      [34.0, 24.0],
      [52.0, 12.0],
      [70.0, 22.0],
      [92.0, 14.0],
      [110.0, 24.0],
      [132.0, 10.0],
      [152.0, 22.0],
      [172.0, 16.0],
      [196.0, 26.0],
      [226.0, 18.0],
    ];
    final hills = Path()..moveTo(0, size.height);
    for (final point in ridge) {
      final o = p(point[0], point[1]);
      hills.lineTo(o.dx, o.dy);
    }
    hills
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(hills, Paint()..color = RunNowGameTokens.cardHills);
    final road = Path()
      ..moveTo(p(0, 34).dx, p(0, 34).dy)
      ..cubicTo(
        p(60, 24).dx,
        p(60, 24).dy,
        p(160, 24).dx,
        p(160, 24).dy,
        p(226, 32).dx,
        p(226, 32).dy,
      );
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.55);
    for (final metric in road.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), dash);
      }
    }
  }

  @override
  bool shouldRepaint(GameCardHillsPainter old) => old.accent != accent;
}

/// Icon vai, vẽ lại từ SVG 64×64 của bản thiết kế.
class GameRoleIconPainter extends CustomPainter {
  const GameRoleIconPainter(this.role, this.color);

  final String role;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final path = _path();
    canvas.drawPath(path, glow);
    canvas.drawPath(path, stroke);
  }

  Path _path() {
    final path = Path();
    void poly(List<double> xy, {bool close = false}) {
      path.moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        path.lineTo(xy[i], xy[i + 1]);
      }
      if (close) path.close();
    }

    void circle(double x, double y, double r) =>
        path.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

    switch (role) {
      case 'wolf':
        poly([
          12, 22, 18, 6, 27, 17, 37, 17, 46, 6, 52, 22, 50, 36, 41, 49, //
          32, 57, 23, 49, 14, 36,
        ], close: true);
        poly([23, 30, 28, 32]);
        poly([41, 30, 36, 32]);
        poly([28, 45, 32, 49, 36, 45]);
      case 'seer':
        path
          ..moveTo(5, 32)
          ..cubicTo(15, 16, 49, 16, 59, 32)
          ..cubicTo(49, 48, 15, 48, 5, 32)
          ..close();
        circle(32, 32, 8);
        poly([32, 6, 32, 11]);
        poly([32, 53, 32, 58]);
        poly([13, 13, 16, 16]);
        poly([51, 13, 48, 16]);
      case 'guard':
        path
          ..moveTo(32, 6)
          ..lineTo(53, 14)
          ..lineTo(53, 30)
          ..cubicTo(53, 44, 44, 53, 32, 58)
          ..cubicTo(20, 53, 11, 44, 11, 30)
          ..lineTo(11, 14)
          ..close();
        poly([23, 31, 30, 38, 42, 25]);
      case 'witch':
        poly([25, 6, 39, 6]);
        path
          ..moveTo(28, 6)
          ..lineTo(28, 22)
          ..lineTo(15, 47)
          ..cubicTo(13, 53, 16, 58, 22, 58)
          ..lineTo(42, 58)
          ..cubicTo(48, 58, 51, 53, 49, 47)
          ..lineTo(36, 22)
          ..lineTo(36, 6);
        poly([19, 41, 45, 41]);
        circle(28, 49, 1.5);
        circle(36, 46, 1.5);
      case 'hunter':
        circle(32, 32, 20);
        circle(32, 32, 9);
        poly([32, 4, 32, 18]);
        poly([32, 46, 32, 60]);
        poly([4, 32, 18, 32]);
        poly([46, 32, 60, 32]);
      case 'cupid':
        path
          ..moveTo(32, 54)
          ..cubicTo(13, 41, 8, 29, 14, 21)
          ..cubicTo(20, 13, 30, 15, 32, 23)
          ..cubicTo(34, 15, 44, 13, 50, 21)
          ..cubicTo(56, 29, 51, 41, 32, 54)
          ..close();
        poly([6, 58, 58, 6]);
        poly([49, 6, 58, 6, 58, 15]);
        poly([12, 58, 6, 58, 6, 52]);
      default:
        poly([8, 32, 32, 12, 56, 32]);
        poly([14, 28, 14, 54, 50, 54, 50, 28]);
        poly([27, 54, 27, 40, 37, 40, 37, 54]);
    }
    return path;
  }

  @override
  bool shouldRepaint(GameRoleIconPainter old) =>
      old.role != role || old.color != color;
}

class GameCardSparklePainter extends CustomPainter {
  const GameCardSparklePainter(this.at);

  final Offset at;

  @override
  void paint(Canvas canvas, Size size) {
    final warm = Paint()
      ..color = RunNowGameTokens.sparkleWarm.withValues(alpha: 0.33)
      ..blendMode = BlendMode.screen;
    final white = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..blendMode = BlendMode.screen;
    void grid(double w, double h, double ox, double oy, double r, Paint p) {
      for (var x = ox % w - w; x < size.width + w; x += w) {
        for (var y = oy % h - h; y < size.height + h; y += h) {
          canvas.drawCircle(Offset(x + w / 2, y + h / 2), r, p);
        }
      }
    }

    grid(23, 29, at.dx * 40, at.dy * 40, 1, warm);
    grid(37, 31, -at.dx * 30, at.dy * 20, 0.8, white);
  }

  @override
  bool shouldRepaint(GameCardSparklePainter old) => old.at != at;
}

class _BackOrnamentPainter extends CustomPainter {
  const _BackOrnamentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, size.width - 20, size.height - 20),
        const Radius.circular(8),
      ),
      gold..color = RunNowGameTokens.backLine,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(16, 16, size.width - 32, size.height - 32),
        const Radius.circular(6),
      ),
      gold..color = RunNowGameTokens.backLineSoft,
    );
    final cx = size.width / 2;
    const cy = 150.0;
    for (final (rx, ry, alpha) in const [
      (92.0, 54.0, 0.28),
      (74.0, 40.0, 0.22),
      (56.0, 27.0, 0.16),
    ]) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = RunNowGameTokens.backRing.withValues(alpha: alpha);
      final oval = Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      for (final metric in oval.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 11) {
          canvas.drawPath(metric.extractPath(d, d + 5), ring);
        }
      }
    }
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = RunNowGameTokens.backLineStrong;
    final r = size.width - 22;
    final b = size.height - 22;
    for (final (x, y, dx, dy) in [
      (22.0, 22.0, 18.0, 18.0),
      (r, 22.0, -18.0, 18.0),
      (22.0, b, 18.0, -18.0),
      (r, b, -18.0, -18.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y), Offset(x + dx, y), corner)
        ..drawLine(Offset(x, y), Offset(x, y + dy), corner);
    }
  }

  @override
  bool shouldRepaint(_BackOrnamentPainter old) => false;
}

/// Góc nghiêng tối đa của lá khi kéo, theo bản thiết kế.
const gameCardMaxTilt = 14 * math.pi / 180;
