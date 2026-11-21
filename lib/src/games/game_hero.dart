import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

const gameTitleFont = 'Barlow Condensed';

/// Các bước trong một ngày của ván, theo phase của backend
/// (`werewolf/state.go`): đêm 22h, rạng sáng 0h, đề cử 10h, biểu quyết 20h.
const _steps = [
  ('night', 'Đêm', Icons.dark_mode_outlined),
  ('dawn', 'Rạng sáng', Icons.wb_twilight),
  ('day', 'Đề cử', Icons.campaign_outlined),
  ('trial', 'Biểu quyết', Icons.gavel),
];

/// Bước trong ngày của phase key `r3/day` hay `r3/night/hunter`; -1 là không
/// thuộc bước nào (chuẩn bị).
int gameStepOf(String? phaseKey) {
  final parts = (phaseKey ?? '').split('/');
  if (parts.length < 2) return -1;
  return _steps.indexWhere((s) => s.$1 == parts[1]);
}

/// Lúc chuẩn bị (`r1/setup`): đã chia bài, chưa vào đêm 1.
bool gameIsPreparing(String? phaseKey) =>
    (phaseKey ?? '').split('/').elementAtOrNull(1) == 'setup';

/// Tên lớn của trang ván, dùng chung cho header đầy đủ và header thu gọn.
String _heroTitle(GameDetail detail, {required bool closing}) {
  final phase = detail.phase;
  final step = gameStepOf(phase?.key);
  if (detail.status == 'ended' && detail.winnerLabel != null) {
    return '${detail.winnerLabel} thắng'.toUpperCase();
  }
  if (closing) return 'ĐANG CHỐT…';
  if (gameIsPreparing(phase?.key)) return 'CHUẨN BỊ';
  if (step >= 0) return _steps[step].$2.toUpperCase();
  return (phase?.label ?? detail.statusLabel).toUpperCase();
}

/// Header trang ván: vòng, bước đang chạy, giờ chốt, ba ô số và dải đồi.
class GameHero extends StatelessWidget {
  const GameHero({
    super.key,
    required this.detail,
    required this.closing,
    required this.serverNow,
    this.rounds = 0,
    this.subtitle = '',
  });

  final GameDetail detail;

  /// Câu phụ khi ván đã xong (`summary.subtitle`), rỗng là không có.
  final String subtitle;

  /// Số vòng ván đã đi khi ván đã xong (`me.cardRounds`); 0 là không biết.
  final int rounds;

  /// Đã qua hạn phase, đang chờ backend chốt.
  final bool closing;
  final DateTime Function() serverNow;

  @override
  Widget build(BuildContext context) {
    final phase = detail.phase;
    final step = gameStepOf(phase?.key);
    final preparing = gameIsPreparing(phase?.key);
    final round = gameRoundOf(phase?.key);
    final deadline = phase?.deadline;
    final startError = detail.startError;
    final table = detail.kmTable;
    final running = detail.status == 'running';
    final winner = detail.status == 'ended' ? detail.winnerLabel : null;
    final title = _heroTitle(detail, closing: closing);
    if (winner != null) {
      return _EndedHero(title: title, rounds: rounds, subtitle: subtitle);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: context.runNowPalette.radius(20),
        border: context.runNowPalette.tintedBorder(context.moonlit.amberLine),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.moonlit.heroTop,
            context.moonlit.heroMid,
            context.moonlit.heroBottom,
          ],
          stops: [0, 0.45, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: context.moonlit.amberGlow,
            blurRadius: 50,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(right: 10, top: 8, child: GameMoonEmblem(size: 76)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 92, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (round > 0) _Chip('VÒNG $round'),
                    if (phase != null && step >= 0 && !closing)
                      Text(
                        phase.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.moonlit.inkSoft,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 92, 0),
                // Tiêu đề dài như ĐANG MỞ ĐĂNG KÝ thu nhỏ cho vừa một dòng.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: context.runNowPalette.narrowFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 42,
                      height: 1,
                      letterSpacing: 0.5,
                      color: context.moonlit.ink,
                    ),
                  ),
                ),
              ),
              if (!closing && deadline != null && phase != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: GameCountdown(
                    deadline: deadline,
                    serverNow: serverNow,
                    ending: preparing ? 'thì vào đêm 1' : 'thì chốt',
                  ),
                ),
              if (detail.winnerLabel != null && winner == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    detail.winnerLabel!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.moonlit.amberSoft,
                    ),
                  ),
                ),
              if (startError != null && detail.status == 'registering')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    startError.message,
                    style: TextStyle(color: context.moonlit.danger),
                  ),
                ),
              if (step >= 0 || preparing) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _Steps(current: step),
                ),
              ],
              if (running && detail.players.isNotEmpty) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          value:
                              '${detail.players.where((p) => p.alive).length}',
                          unit: '/${detail.players.length}',
                          label: 'còn sống',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          value:
                              '${detail.players.where((p) => p.onTrial).length}',
                          label: 'lên giàn',
                          accent: true,
                        ),
                      ),
                      if (table?.unitLabel case final label?) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Stat(
                            value: gameKmUnitText(table!.unitKm),
                            unit: ' km',
                            label: label,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SizedBox(
                height: 54,
                child: PixelArt(
                  child: CustomPaint(painter: _HillsPainter(context.moonlit)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Header khi ván đã có phe thắng: trăng, số vòng, tên phe, ở giữa.
class _EndedHero extends StatelessWidget {
  const _EndedHero({
    required this.title,
    required this.rounds,
    required this.subtitle,
  });

  final String title;
  final int rounds;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: BoxDecoration(
        borderRadius: context.runNowPalette.radius(22),
        border: context.runNowPalette.tintedBorder(context.moonlit.amberLine),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.moonlit.heroTop,
            context.moonlit.heroMid,
            context.moonlit.heroBottom,
          ],
          stops: [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: context.moonlit.amberGlow,
            blurRadius: 50,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          const GameMoonEmblem(size: 84),
          if (rounds > 0) ...[
            const SizedBox(height: 6),
            Text(
              'KẾT THÚC SAU $rounds VÒNG',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: context.moonlit.amber,
              ),
            ),
          ],
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  context.moonlit.amberBright,
                  context.moonlit.amber,
                  context.moonlit.amberDeep,
                ],
                stops: [0, 0.7, 1],
              ).createShader(bounds),
              child: Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: context.runNowPalette.narrowFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 44,
                  height: 0.95,
                  letterSpacing: 0.5,
                  color: context.moonlit.ink,
                ),
              ),
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.moonlit.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// Header thu gọn hiện khi header đầy đủ đã cuộn khỏi màn.
class GameHeroBar extends StatelessWidget {
  const GameHeroBar({
    super.key,
    required this.detail,
    required this.closing,
    required this.serverNow,
    this.rounds = 0,
  });

  static const height = 58.0;

  final GameDetail detail;
  final bool closing;
  final DateTime Function() serverNow;
  final int rounds;

  @override
  Widget build(BuildContext context) {
    final ended = detail.status == 'ended' && detail.winnerLabel != null;
    final round = gameRoundOf(detail.phase?.key);
    final deadline = detail.phase?.deadline;
    final detailLine = ended
        ? (rounds > 0 ? 'sau $rounds vòng' : null)
        : (round > 0 ? 'Vòng $round' : null);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: context.runNowPalette.radius(16),
        border: context.runNowPalette.tintedBorder(context.moonlit.amberLine),
        gradient: LinearGradient(
          colors: [
            context.moonlit.heroTop,
            context.moonlit.heroMid,
            context.moonlit.heroBottom,
          ],
          stops: [0, 0.6, 1],
        ),
      ),
      child: Row(
        children: [
          const GameMoonEmblem(size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _heroTitle(detail, closing: closing),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: context.runNowPalette.narrowFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1,
                    letterSpacing: 0.5,
                    color: ended
                        ? context.moonlit.amberSoft
                        : context.moonlit.ink,
                  ),
                ),
                if (detailLine != null)
                  Text(
                    detailLine,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.moonlit.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          if (!ended && !closing && deadline != null)
            GameCountdown(
              deadline: deadline,
              serverNow: serverNow,
              clockOnly: true,
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: context.moonlit.amberTint,
        borderRadius: context.runNowPalette.radius(999),
        border: context.runNowPalette.tintedBorder(context.moonlit.amberLine),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: context.moonlit.amberPale,
        ),
      ),
    );
  }
}

/// Giờ còn lại tới hạn phase (H:MM:SS), đếm theo giờ server từng giây.
class GameCountdown extends StatefulWidget {
  const GameCountdown({
    super.key,
    required this.deadline,
    required this.serverNow,
    this.ending = 'thì chốt',
    this.clockOnly = false,
  });

  /// Chỉ hiện giờ đếm ngược, cho header thu gọn.
  final bool clockOnly;
  final DateTime deadline;
  final DateTime Function() serverNow;

  /// Phần câu sau giờ, như "tới 22:00 thì chốt".
  final String ending;

  @override
  State<GameCountdown> createState() => _GameCountdownState();
}

class _GameCountdownState extends State<GameCountdown> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.serverNow();
    final local = widget.deadline.toLocal();
    final sameDay = DateUtils.isSameDay(local, now.toLocal());
    final at = DateFormat(sameDay ? 'HH:mm' : 'HH:mm dd/MM').format(local);
    final left = widget.deadline.difference(now);
    final seconds = left.isNegative ? 0 : left.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    final clock =
        '${seconds ~/ 3600}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
    if (widget.clockOnly) {
      return Text(
        clock,
        style: TextStyle(
          fontFamily: context.runNowPalette.narrowFont,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          height: 1,
          color: context.moonlit.amberCream,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          clock,
          style: TextStyle(
            fontFamily: context.runNowPalette.narrowFont,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            height: 1,
            color: context.moonlit.amberCream,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'tới $at ${widget.ending}',
            style: TextStyle(fontSize: 12, color: context.moonlit.inkSoft),
          ),
        ),
      ],
    );
  }
}

/// Thanh bước của một ngày: bước hiện tại hổ phách, các bước khác mờ. Lúc
/// chuẩn bị [current] là -1 nên cả bốn bước đều mờ.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Icon(
                  _steps[i].$3,
                  size: 22,
                  color: i == current
                      ? context.moonlit.amberPale
                      : context.moonlit.faint,
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: context.runNowPalette.radius(3),
                    color: i == current ? null : context.moonlit.track,
                    gradient: i == current
                        ? LinearGradient(
                            colors: [
                              context.moonlit.amberDeep,
                              context.moonlit.amberSoft,
                            ],
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == current
                        ? FontWeight.w800
                        : FontWeight.w400,
                    color: i == current
                        ? context.moonlit.amberPale
                        : context.moonlit.faint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.unit,
    this.accent = false,
  });

  final String value;
  final String? unit;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.moonlit.well,
        borderRadius: context.runNowPalette.radius(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: value,
              children: [
                if (unit != null)
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.moonlit.muted,
                    ),
                  ),
              ],
            ),
            style: TextStyle(
              fontFamily: context.runNowPalette.narrowFont,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1,
              color: accent ? context.moonlit.amberPale : context.moonlit.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.moonlit.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// Dải đồi mực ở đáy header, vài cặp mắt sói hổ phách.
class _HillsPainter extends CustomPainter {
  const _HillsPainter(this.tokens);

  final RunNowMoonlit tokens;

  // Đỉnh đồi theo khung 390 × 54 của thiết kế: (x, y) nối nhau từ trái sang.
  static const _ridge = [
    (0.0, 34.0),
    (14.0, 20.0),
    (24.0, 32.0),
    (36.0, 10.0),
    (48.0, 30.0),
    (57.0, 20.0),
    (71.0, 36.0),
    (81.0, 22.0),
    (93.0, 40.0),
    (109.0, 16.0),
    (121.0, 36.0),
    (131.0, 28.0),
    (145.0, 42.0),
    (157.0, 22.0),
    (169.0, 40.0),
    (179.0, 30.0),
    (193.0, 46.0),
    (205.0, 24.0),
    (219.0, 46.0),
    (229.0, 34.0),
    (241.0, 48.0),
    (257.0, 28.0),
    (269.0, 46.0),
    (279.0, 38.0),
    (293.0, 54.0),
    (305.0, 36.0),
    (317.0, 52.0),
    (327.0, 42.0),
    (341.0, 56.0),
    (353.0, 38.0),
    (390.0, 38.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 390;
    final sy = size.height / 54;
    final path = Path()..moveTo(0, size.height);
    for (final (x, y) in _ridge) {
      path.lineTo(x * sx, y.clamp(0.0, 54.0) * sy);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = tokens.page);
    final eye = Paint()..color = tokens.amberBright;
    for (final (x, y) in const [(122.0, 36.0), (131.0, 36.0)]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x * sx, y * sy), width: 5, height: 3),
        eye,
      );
    }
    final far = Paint()..color = tokens.amberStrong.withValues(alpha: 0.8);
    for (final (x, y) in const [(286.0, 30.0), (294.0, 30.0)]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x * sx, y * sy), width: 4, height: 3),
        far,
      );
    }
  }

  @override
  bool shouldRepaint(_HillsPainter old) => old.tokens != tokens;
}
