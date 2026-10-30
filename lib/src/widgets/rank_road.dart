import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// BXH tuần vẽ thành một đường đua uốn lượn: top [shown] đứng ở năm chỗ cố
/// định dọc đường, hạng 1 sát vạch đích. Chỗ đứng theo hạng chứ không theo
/// km, nên avatar và chữ không bao giờ đè nhau dù km sát nhau; km ghi dưới
/// tên. [ranked] là cả bảng, hạng cao trước.
class RankRoad extends StatelessWidget {
  const RankRoad({required this.ranked, required this.myUid, super.key});

  final List<ClubRankedMember> ranked;
  final String? myUid;

  static const shown = 5;
  static const height = 206.0;

  /// Năm chỗ đứng (tỉ lệ ngang, dọc của khung), từ xa đích tới sát đích. Cao
  /// thấp xen kẽ: chỗ cao ghi chữ phía trên, chỗ thấp ghi phía dưới, nên chữ
  /// hai người cạnh nhau không chung một hàng.
  static const _slots = [
    Offset(0.08, 0.66),
    Offset(0.27, 0.31),
    Offset(0.46, 0.66),
    Offset(0.65, 0.31),
    Offset(0.84, 0.66),
  ];
  static const _start = Offset(0, 0.9);
  static const _finish = Offset(0.97, 0.3);

  @override
  Widget build(BuildContext context) {
    if (ranked.isEmpty) return const SizedBox.shrink();
    final top = ranked.take(shown).toList();
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final light = Theme.of(context).brightness == Brightness.light;
    final medals = light ? RunNowRankColors.light : RunNowRankColors.dark;
    // Ít hơn năm người thì đứng ở các chỗ gần đích nhất.
    final firstSlot = shown - top.length;
    return Semantics(
      label:
          'BXH tuần: ${[for (final m in top) 'hạng ${m.rank} ${m.entry.displayName} ${_km(m.score)} km'].join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, height);
              Offset at(Offset f) =>
                  Offset(f.dx * size.width, f.dy * size.height);
              final labelWidth = size.width * 0.3;
              final riders = <Widget>[];
              // Hạng thấp trước: đứng xa đích, ở chỗ đầu đường.
              for (final (i, m) in top.reversed.indexed) {
                final slot = _slots[firstSlot + i];
                final center = at(slot);
                final avatar = m.rank == 1 ? 50.0 : 40.0;
                final high = slot.dy < 0.5;
                riders.addAll([
                  Positioned(
                    left: center.dx - labelWidth / 2,
                    width: labelWidth,
                    top: high ? null : center.dy + avatar / 2 + 4,
                    bottom: high
                        ? size.height - center.dy + avatar / 2 + 4
                        : null,
                    child: _Label(member: m),
                  ),
                  Positioned(
                    left: center.dx - avatar / 2,
                    top: center.dy - avatar / 2,
                    child: _Rider(
                      member: m,
                      size: avatar,
                      ring: m.entry.uid == myUid
                          ? palette.ink
                          : m.rank <= medals.length
                          ? medals[m.rank - 1]
                          : palette.background,
                    ),
                  ),
                ]);
              }
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RoadPainter(
                        points: [
                          at(_start),
                          for (final slot in _slots) at(slot),
                          at(_finish),
                        ],
                        asphalt: onSurface.withValues(alpha: 0.13),
                        dash: palette.background,
                      ),
                    ),
                  ),
                  Positioned(
                    left: at(_finish).dx - 6,
                    top: at(_finish).dy - 30,
                    child: Icon(
                      Icons.sports_score_rounded,
                      size: 28,
                      color: onSurface,
                    ),
                  ),
                  ...riders,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _km(double meters) => (meters / 1000).toStringAsFixed(1);

/// Mặt đường đi qua [points] bằng đường cong mềm (Catmull-Rom), vạch đứt ở
/// giữa.
class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.points,
    required this.asphalt,
    required this.dash,
  });

  final List<Offset> points;
  final Color asphalt;
  final Color dash;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = asphalt,
    );
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = dash;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 8.0; d < metric.length - 8; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 7), dashPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.points.length != points.length ||
      old.asphalt != asphalt ||
      old.dash != dash ||
      Iterable.generate(points.length).any((i) => old.points[i] != points[i]);
}

/// Avatar viền theo hạng, số hạng nhỏ ở góc.
class _Rider extends StatelessWidget {
  const _Rider({required this.member, required this.size, required this.ring});

  final ClubRankedMember member;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final entry = member.entry;
    final url = entry.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = entry.displayName;
    final badge = ring == palette.background ? palette.ink : ring;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: CircleAvatar(
                radius: size / 2 - 2.5,
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
            right: -3,
            bottom: -2,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badge,
                shape: BoxShape.circle,
                border: Border.all(color: palette.background, width: 1.5),
              ),
              child: Text(
                '${member.rank}',
                style: TextStyle(
                  fontFamily: 'Barlow Condensed',
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: _onColor(badge),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// Tên và km của một người, canh giữa trên hoặc dưới avatar.
class _Label extends StatelessWidget {
  const _Label({required this.member});

  final ClubRankedMember member;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          member.entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _km(member.score)),
              TextSpan(
                text: ' km',
                style: TextStyle(
                  fontSize: 10,
                  color: onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          style: const TextStyle(
            fontFamily: 'Barlow Condensed',
            fontSize: 15,
            height: 1.1,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
