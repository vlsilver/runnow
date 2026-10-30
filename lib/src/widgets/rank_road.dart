import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// Chia người trên đường ra các làn để avatar không đè nhau. [xs] tăng dần;
/// mỗi người vào làn thấp nhất mà người trước trong làn đã cách đủ [minGap].
/// Hết làn thì vào làn có người trước nằm xa nhất về bên trái, cho đè ít nhất.
List<int> roadLanes(
  List<double> xs, {
  required double minGap,
  required int maxLanes,
}) {
  final lastX = <double>[];
  final lanes = <int>[];
  for (final x in xs) {
    var lane = lastX.indexWhere((last) => x - last >= minGap);
    if (lane < 0 && lastX.length < maxLanes) {
      lastX.add(x);
      lanes.add(lastX.length - 1);
      continue;
    }
    if (lane < 0) {
      lane = 0;
      for (var i = 1; i < lastX.length; i++) {
        if (lastX[i] < lastX[lane]) lane = i;
      }
    }
    lastX[lane] = x;
    lanes.add(lane);
  }
  return lanes;
}

/// BXH tuần vẽ thành một con đường: top [shown] đứng dọc đường theo số km,
/// người dẫn đầu ở vạch đích. Mình ngoài top vẫn có mặt, và đoạn đường tới
/// chỗ mình được tô như thanh tiến độ. [ranked] là cả bảng, hạng cao trước.
class RankRoad extends StatelessWidget {
  const RankRoad({required this.ranked, required this.myUid, super.key});

  final List<ClubRankedMember> ranked;
  final String? myUid;

  static const shown = 10;
  static const _avatar = 34.0;
  static const _road = 14.0;
  static const _laneGap = 6.0;
  static const _maxLanes = 3;
  static const _flag = 26.0;

  @override
  Widget build(BuildContext context) {
    if (ranked.isEmpty) return const SizedBox.shrink();
    final top = ranked.take(shown).toList();
    final me = ranked.where((m) => m.entry.uid == myUid).firstOrNull;
    final riders = [...top, if (me != null && !top.contains(me)) me];
    final best = ranked.first.score;
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final light = Theme.of(context).brightness == Brightness.light;
    final medals = light ? RunNowRankColors.light : RunNowRankColors.dark;
    return Semantics(
      label:
          'BXH tuần: ${[for (final m in top.take(3)) 'hạng ${m.rank} ${m.entry.displayName} ${_km(m.score)} km'].join(', ')}',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final start = _avatar / 2;
            final end = constraints.maxWidth - _flag - _avatar / 2;
            double xOf(ClubRankedMember m) =>
                start + (end - start) * (best <= 0 ? 0 : m.score / best);
            final byX = [...riders]..sort((a, b) => xOf(a).compareTo(xOf(b)));
            final lanes = roadLanes(
              [for (final m in byX) xOf(m)],
              minGap: _avatar + 2,
              maxLanes: _maxLanes,
            );
            final laneOf = {
              for (var i = 0; i < byX.length; i++) byX[i]: lanes[i],
            };
            final laneCount = lanes.fold(0, math.max) + 1;
            final height = _road + 4 + laneCount * (_avatar + _laneGap);
            // Người hạng cao vẽ sau cùng, nằm trên khi đè.
            final painted = [...riders]
              ..sort((a, b) => b.rank.compareTo(a.rank));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: _flag - 4,
                        bottom: 0,
                        height: _road,
                        child: _Road(
                          progress: me == null
                              ? 0
                              : xOf(me) / (constraints.maxWidth - _flag + 4),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: -4,
                        child: Icon(
                          Icons.sports_score_rounded,
                          size: _flag,
                          color: onSurface,
                        ),
                      ),
                      for (final m in painted)
                        Positioned(
                          left: xOf(m) - _avatar / 2,
                          bottom: _road / 2,
                          child: _Rider(
                            member: m,
                            size: _avatar,
                            stem:
                                4 +
                                _road / 2 +
                                laneOf[m]! * (_avatar + _laneGap),
                            ring: m.entry.uid == myUid
                                ? palette.ink
                                : m.rank <= medals.length
                                ? medals[m.rank - 1]
                                : palette.background,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _ScaleLabel('0 km', color: onSurface),
                    const Spacer(),
                    _ScaleLabel('${_km(best)} km', color: onSurface),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _km(double meters) => (meters / 1000).toStringAsFixed(1);

/// Mặt đường nhựa có vạch giữa; đoạn từ xuất phát tới [progress] (0–1) tô
/// màu chính.
class _Road extends StatelessWidget {
  const _Road({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: onSurface.withValues(alpha: 0.14)),
          ),
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: ColoredBox(color: palette.accent.withValues(alpha: 0.45)),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DashPainter(palette.background.withValues(alpha: 0.9)),
            ),
          ),
        ],
      ),
    );
  }

  static const _radius = 999.0;
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    for (var x = 10.0; x < size.width - 10; x += 14) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Một người trên đường: avatar viền theo hạng, số hạng nhỏ ở góc, que chỉ
/// xuống đúng chỗ trên đường.
class _Rider extends StatelessWidget {
  const _Rider({
    required this.member,
    required this.size,
    required this.stem,
    required this.ring,
  });

  final ClubRankedMember member;
  final double size;
  final double stem;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final entry = member.entry;
    final url = entry.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = entry.displayName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: size / 2 - 2,
                    backgroundColor: palette.accent,
                    backgroundImage: hasUrl
                        ? cachedAvatarImage(context, url, size)
                        : null,
                    child: hasUrl
                        ? null
                        : Text(
                            name.isEmpty ? '?' : name[0].toUpperCase(),
                            style: TextStyle(
                              fontSize: size * 0.38,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -3,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ring == palette.background ? palette.ink : ring,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.background, width: 1.5),
                  ),
                  child: Text(
                    '${member.rank}',
                    style: TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: palette.background,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 2,
          height: stem,
          color: ring == palette.background
              ? palette.ink.withValues(alpha: 0.35)
              : ring.withValues(alpha: 0.7),
        ),
      ],
    );
  }
}

class _ScaleLabel extends StatelessWidget {
  const _ScaleLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color.withValues(alpha: 0.5),
      fontFamily: 'Barlow Condensed',
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );
}
