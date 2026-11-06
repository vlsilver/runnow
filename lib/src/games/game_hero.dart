import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _M = RunNowMoonlitTokens;

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

/// Header trang ván: vòng, bước đang chạy, giờ chốt, ba ô số và dải đồi.
class GameHero extends StatelessWidget {
  const GameHero({
    super.key,
    required this.detail,
    required this.closing,
    required this.serverNow,
  });

  final GameDetail detail;

  /// Đã qua hạn phase, đang chờ backend chốt.
  final bool closing;
  final DateTime Function() serverNow;

  @override
  Widget build(BuildContext context) {
    final phase = detail.phase;
    final step = gameStepOf(phase?.key);
    final round = gameRoundOf(phase?.key);
    final deadline = phase?.deadline;
    final startError = detail.startError;
    final table = detail.kmTable;
    final running = detail.status == 'running';
    final title = closing
        ? 'ĐANG CHỐT…'
        : step >= 0
        ? _steps[step].$2.toUpperCase()
        : (phase?.label ?? detail.statusLabel).toUpperCase();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _M.amberLine),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_M.heroTop, _M.heroMid, _M.heroBottom],
          stops: [0, 0.45, 1],
        ),
        boxShadow: const [
          BoxShadow(color: _M.amberGlow, blurRadius: 50, offset: Offset(0, 20)),
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
                    if (detail.testMode) const _Chip('VÁN THỬ', faint: true),
                    if (phase != null && step >= 0 && !closing)
                      Text(
                        phase.label,
                        style: const TextStyle(fontSize: 12, color: _M.inkSoft),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 92, 0),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: gameTitleFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 40,
                    height: 1,
                    letterSpacing: 0.5,
                    color: _M.ink,
                  ),
                ),
              ),
              if (!closing && deadline != null && phase != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: GameCountdown(
                    deadline: deadline,
                    serverNow: serverNow,
                  ),
                ),
              if (detail.winnerLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    detail.winnerLabel!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _M.amberSoft,
                    ),
                  ),
                ),
              if (startError != null && detail.status == 'registering')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    startError.message,
                    style: const TextStyle(color: _M.danger),
                  ),
                ),
              if (step >= 0) ...[
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
              const SizedBox(
                height: 54,
                child: CustomPaint(painter: _HillsPainter()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.faint = false});

  final String label;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: faint ? _M.track : _M.amberTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: faint ? _M.border : _M.amberLine),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: faint ? _M.inkSoft : _M.amberPale,
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
  });

  final DateTime deadline;
  final DateTime Function() serverNow;

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          clock,
          style: const TextStyle(
            fontFamily: gameTitleFont,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            height: 1,
            color: _M.amberCream,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'tới $at thì chốt',
            style: const TextStyle(fontSize: 12, color: _M.inkSoft),
          ),
        ),
      ],
    );
  }
}

/// Thanh bước của một ngày: bước hiện tại hổ phách, các bước khác mờ.
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
                  color: i == current ? _M.amberPale : _M.faint,
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == current ? null : _M.track,
                    gradient: i == current
                        ? const LinearGradient(
                            colors: [_M.amberDeep, _M.amberSoft],
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
                    color: i == current ? _M.amberPale : _M.faint,
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
        color: _M.well,
        borderRadius: BorderRadius.circular(12),
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
                    style: const TextStyle(fontSize: 14, color: _M.muted),
                  ),
              ],
            ),
            style: TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w700,
              fontSize: 22,
              height: 1,
              color: accent ? _M.amberPale : _M.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _M.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// Dải đồi mực ở đáy header, vài cặp mắt sói hổ phách.
class _HillsPainter extends CustomPainter {
  const _HillsPainter();

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
    canvas.drawPath(path, Paint()..color = _M.page);
    final eye = Paint()..color = _M.amberBright;
    for (final (x, y) in const [(122.0, 36.0), (131.0, 36.0)]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x * sx, y * sy), width: 5, height: 3),
        eye,
      );
    }
    final far = Paint()..color = _M.amberStrong.withValues(alpha: 0.8);
    for (final (x, y) in const [(286.0, 30.0), (294.0, 30.0)]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x * sx, y * sy), width: 4, height: 3),
        far,
      );
    }
  }

  @override
  bool shouldRepaint(_HillsPainter old) => false;
}
