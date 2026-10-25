import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_role_card.dart';

const _condensed = 'Barlow Condensed';

const _teamLabels = {
  'village': 'Phe Dân',
  'wolves': 'Phe Sói',
  'lovers': 'Cặp đôi',
};

const _winnerTitles = {
  'village': 'Dân làng thắng',
  'wolves': 'Bầy sói thắng',
  'lovers': 'Cặp đôi thắng',
};

/// Thẻ Ma Sói của một người trong một ván. Bậc bốc lúc chia bài; ván kết thúc
/// thì phe thắng giữ thẻ ở users/{uid}/gameCards/{gameId} (backend ghi), còn
/// màn ván dựng cùng thẻ từ /me để người chơi thấy thẻ mình từ đầu.
class GamePlayerCard {
  const GamePlayerCard({
    required this.gameId,
    required this.tier,
    required this.role,
    required this.team,
    required this.alive,
    required this.round,
    required this.playerCount,
    required this.owned,
    this.roleLabel,
    this.winner,
    this.deathRound,
    this.endedAt,
    this.testMode = false,
  });

  /// Doc gameCards chỉ có ở người phe thắng nên luôn là thẻ đã sở hữu.
  /// Đọc từ Firestore thì provider đổi Timestamp sang DateTime trước.
  factory GamePlayerCard.fromJson(String gameId, Map<String, dynamic> json) {
    final deathRound = json['deathRound'];
    final endedAt = json['endedAt'];
    return GamePlayerCard(
      gameId: gameId,
      tier: runCardTierFromKey(json['tier'] as String?),
      role: json['role'] as String? ?? '',
      team: json['team'] as String? ?? '',
      winner: json['winner'] as String?,
      alive: json['alive'] == true,
      round: (json['rounds'] as num?)?.toInt() ?? 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      deathRound: deathRound is num ? deathRound.toInt() : null,
      endedAt: endedAt is DateTime ? endedAt : null,
      testMode: json['testMode'] == true,
      owned: true,
    );
  }

  /// Thẻ của người xem trong màn ván, từ /me và chi tiết ván. Thẻ đã thuộc về
  /// mình thì phe mình chính là phe thắng (cả cặp đôi phe ba); còn lại lấy
  /// phe theo vai, vì /me không nói ai đang trong cặp Sói–Dân.
  factory GamePlayerCard.fromMe({
    required GameDetail detail,
    required GameMe me,
    GamePlayer? player,
  }) {
    final ended = detail.status == 'ended';
    final role = me.role ?? '';
    return GamePlayerCard(
      gameId: detail.id,
      tier: runCardTierFromKey(me.cardTier),
      role: role,
      roleLabel: me.roleLabel,
      team: me.cardOwned && detail.winner != null
          ? detail.winner!
          : role == 'wolf'
          ? 'wolves'
          : 'village',
      winner: ended ? detail.winner : null,
      alive: me.alive,
      round: ended ? me.cardRounds : gameRoundOf(detail.phase?.key),
      playerCount: detail.playerCount,
      deathRound: player?.deathRound,
      testMode: detail.testMode,
      owned: me.cardOwned,
    );
  }

  final String gameId;
  final GameCardTier tier;

  /// Khoá vai của backend: wolf, seer, …
  final String role;

  /// Tên vai backend gửi; null thì lấy tên mặc định của app.
  final String? roleLabel;

  /// Phe lúc xét thắng thua: village, wolves, lovers.
  final String team;

  /// Phe thắng; null khi ván chưa xong.
  final String? winner;
  final bool alive;

  /// Vòng hiện tại khi ván đang chạy, số vòng đã chơi khi ván xong.
  final int round;
  final int playerCount;
  final int? deathRound;
  final DateTime? endedAt;
  final bool testMode;

  /// Người phe thắng, ván đã xong: được khoe và nằm trong bộ thẻ.
  final bool owned;

  bool get ended => winner != null;
  String get label => roleLabel ?? gameRoleStyle(role).label;
  String get teamLabel => _teamLabels[team] ?? gameRoleStyle(role).team;

  String get result => owned
      ? 'Thắng'
      : ended
      ? 'Thua'
      : 'Đang chơi';
  String get fate => alive
      ? (ended ? 'Sống sót' : 'Còn sống')
      : deathRound == null
      ? 'Bị loại'
      : 'Ngã vòng $deathRound';
}

/// Số vòng trong khoá phase của backend ("r3/day" là 3); khoá lạ thì 0.
int gameRoundOf(String? phaseKey) {
  final match = RegExp(r'^r(\d+)/').firstMatch(phaseKey ?? '');
  return match == null ? 0 : int.parse(match.group(1)!);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal();
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

/// Dữ liệu thẻ khuôn thẻ thành tích: tranh vai phủ cả mặt trước, mặt sau là
/// số liệu ván. Thẻ của phe thắng có thêm dấu THẮNG.
AchievementCardData gameCardData(GamePlayerCard card, {required String owner}) {
  return AchievementCardData(
    tier: card.tier,
    art: GameRoleArt(role: card.role, tier: card.tier),
    stamp: card.owned ? GameWinStamp(tier: card.tier) : null,
    backFace: GameCardBackFace(card: card),
    kind: 'MA SÓI · ${card.teamLabel.toUpperCase()}',
    hero: card.label.toUpperCase(),
    heroUnit: '',
    title: card.ended
        ? _winnerTitles[card.winner] ?? 'Ván đã xong'
        : 'Ván đang chơi',
    owner: owner.toUpperCase(),
    serial: card.fate.toUpperCase(),
    desc: gameRoleStyle(card.role).flavor,
    meta: card.ended
        ? '${card.round} VÒNG · ${card.playerCount} NGƯỜI'
        : 'VÒNG ${card.round} · ${card.playerCount} NGƯỜI',
    date: _date(card.endedAt),
  );
}

/// Thẻ Ma Sói đem khoe. Chỉ thẻ đã sở hữu mới khoe được, lúc đó ván đã xong
/// nên vai không còn bí mật.
CardShareSubject gameCardShareSubject(
  GamePlayerCard card, {
  required String owner,
}) => CardShareSubject(
  id: 'masoi-${card.gameId}',
  printed: [
    card.tier.name,
    card.role,
    card.label,
    card.team,
    card.winner ?? '',
    card.alive,
    card.deathRound ?? '',
    card.round,
    card.playerCount,
    card.owned,
    _date(card.endedAt),
    owner,
  ].join('|'),
  text:
      '${card.label} · ${_winnerTitles[card.winner] ?? 'Ma Sói'}\nChia sẻ từ 3i',
);

/// Màu icon vai trên nền thẻ: màu vai vốn dịu cho nền đêm, nền sáng thì kéo
/// về phía mực để còn đọc được.
Color _roleInk(String role, RunCardSkin skin) {
  final accent = gameRoleStyle(role).accent;
  return skin.field.computeLuminance() > 0.5
      ? Color.lerp(accent, skin.ink, 0.55)!
      : accent;
}

/// Tranh mặt trước: đêm có trăng, đồi và con đường, icon vai to ở giữa trong
/// quầng sáng màu bậc. Màu nền theo bộ màu thẻ như tranh đường chạy.
class GameRoleArt extends StatelessWidget {
  const GameRoleArt({super.key, required this.role, required this.tier});

  final String role;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final icon = _roleInk(role, skin);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _NightPainter(tier: tier, skin: skin, road: icon),
        ),
        const Align(
          alignment: Alignment(-0.62, -0.42),
          child: GameMoon(size: 30, glow: 26),
        ),
        Align(
          alignment: const Alignment(0, -0.08),
          child: CustomPaint(
            size: const Size.square(124),
            painter: GameRoleIconPainter(role, icon),
          ),
        ),
      ],
    );
  }
}

class _NightPainter extends CustomPainter {
  _NightPainter({required this.tier, required this.skin, required this.road});

  final GameCardTier tier;
  final RunCardSkin skin;
  final Color road;

  @override
  void paint(Canvas canvas, Size size) {
    final (field, edge, glow) = skin.routes[tier]!;
    final whole = Offset.zero & size;
    canvas.drawRect(
      whole,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.24),
          radius: 0.9,
          colors: [field, edge],
        ).createShader(whole),
    );

    // Sao rải cố định, để thẻ vẽ lại lần nào cũng như nhau.
    final star = Paint()..color = skin.routeContour;
    const stars = [
      (0.12, 0.2), (0.3, 0.12), (0.46, 0.24), (0.58, 0.1), (0.74, 0.2), //
      (0.88, 0.13), (0.16, 0.36), (0.84, 0.34), (0.68, 0.3), (0.36, 0.3),
    ];
    for (final (i, (x, y)) in stars.indexed) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * y),
        i.isEven ? 1.4 : 1,
        star,
      );
    }

    final center = Offset(size.width / 2, size.height * 0.46);
    canvas.drawCircle(
      center,
      size.width * 0.34,
      Paint()
        ..shader =
            RadialGradient(
              colors: [glow.withValues(alpha: 0.42), glow.withValues(alpha: 0)],
            ).createShader(
              Rect.fromCircle(center: center, radius: size.width * 0.34),
            ),
    );

    Path ridge(double base, List<double> peaks) {
      final path = Path()..moveTo(0, size.height);
      for (final (i, h) in peaks.indexed) {
        path.lineTo(
          size.width * i / (peaks.length - 1),
          size.height * (base - h),
        );
      }
      return path
        ..lineTo(size.width, size.height)
        ..close();
    }

    canvas
      ..drawPath(
        ridge(0.7, [0.02, 0.07, 0.03, 0.09, 0.04, 0.08, 0.02]),
        Paint()..color = Color.lerp(edge, Colors.black, 0.18)!,
      )
      ..drawPath(
        ridge(0.76, [0.03, 0.01, 0.05, 0.02, 0.06, 0.01, 0.04, 0.02]),
        Paint()..color = Color.lerp(edge, Colors.black, 0.32)!,
      );

    final path = Path()
      ..moveTo(0, size.height * 0.79)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.75,
        size.width * 0.66,
        size.height * 0.75,
        size.width,
        size.height * 0.78,
      );
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = road.withValues(alpha: 0.55);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_NightPainter old) =>
      old.tier != tier || !identical(old.skin, skin) || old.road != road;
}

/// Dấu tròn trên tranh của thẻ phe thắng.
class GameWinStamp extends StatelessWidget {
  const GameWinStamp({super.key, required this.tier});

  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final accent = skin.accent(tier);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.emoji_events_rounded, size: 24, color: accent),
        const SizedBox(height: 1),
        Text(
          'THẮNG',
          style: TextStyle(
            fontFamily: _condensed,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 1.6,
            color: skin.hero,
          ),
        ),
      ],
    );
  }
}

/// Mặt sau thẻ Ma Sói: icon vai, kết quả ván và sáu ô số liệu.
class GameCardBackFace extends StatelessWidget {
  const GameCardBackFace({super.key, required this.card});

  final GamePlayerCard card;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final accent = skin.accent(card.tier);
    final foot = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w600,
      fontSize: 10,
      letterSpacing: 1.2,
      color: skin.ink.withValues(alpha: 0.66),
    );
    final brand = foot.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 2.2,
      color: accent,
    );
    return ColoredBox(
      color: skin.dataBack,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('3I RUN', style: brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MA SÓI · MẶT SAU',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: foot,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: skin.stamp,
                  border: Border.all(color: accent, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: skin.glow(card.tier).withValues(alpha: 0.3),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(62),
                    painter: GameRoleIconPainter(
                      card.role,
                      _roleInk(card.role, skin),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              card.ended
                  ? (_winnerTitles[card.winner] ?? 'Ván đã xong').toUpperCase()
                  : 'VÁN ĐANG CHƠI',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _condensed,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: 1.5,
                color: skin.hero,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                _BackStat('VAI', card.label, skin),
                _BackStat('PHE', card.teamLabel, skin),
                _BackStat('KẾT QUẢ', card.result, skin),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _BackStat(
                  card.ended ? 'SỐ VÒNG' : 'VÒNG',
                  '${card.round}',
                  skin,
                ),
                _BackStat('NGƯỜI CHƠI', '${card.playerCount}', skin),
                _BackStat('BẢN THÂN', card.fate, skin),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(_date(card.endedAt), style: foot),
                const Spacer(),
                Text(
                  gameCardTiers[card.tier]!.label.toUpperCase(),
                  style: brand,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BackStat extends StatelessWidget {
  const _BackStat(this.label, this.value, this.skin);

  final String label;
  final String value;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: _condensed,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              height: 1,
              color: skin.hero,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: _condensed,
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 1.4,
              color: skin.ink.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
