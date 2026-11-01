import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

/// Màu cảnh núi, pha từ palette nên đổi hành hay sáng tối là núi đổi theo.
class MountainColors {
  const MountainColors({
    required this.sky,
    required this.glow,
    required this.far,
    required this.mid,
    required this.face,
    required this.shade,
    required this.snow,
    required this.hill,
    required this.trail,
    required this.pole,
    required this.flag,
    required this.contour,
    required this.night,
  });

  factory MountainColors.of(RunNowPalette palette) {
    final ramp = palette.element.ramp;
    final sky = palette.tint;
    final ink = palette.ink;
    if (palette.appearance == RunNowAppearance.light) {
      final face = Color.lerp(ramp[3], palette.textMuted, 0.55)!;
      return MountainColors(
        sky: sky,
        glow: Color.lerp(sky, RunNowRankColors.light[0], 0.4)!,
        far: Color.lerp(sky, ramp[1], 0.3)!,
        mid: Color.lerp(sky, ramp[2], 0.45)!,
        face: face,
        shade: Color.lerp(face, ink, 0.2)!,
        snow: palette.glassStart,
        hill: Color.lerp(sky, ramp[3], 0.5)!,
        trail: palette.glassStart.withValues(alpha: 0.85),
        pole: ink,
        flag: palette.accentDeep,
        contour: ink.withValues(alpha: 0.28),
        night: false,
      );
    }
    final face = Color.lerp(sky, Color.lerp(ramp[2], ink, 0.35)!, 0.3)!;
    return MountainColors(
      sky: sky,
      glow: ink,
      far: Color.lerp(sky, ramp[4], 0.2)!,
      mid: Color.lerp(sky, ramp[3], 0.18)!,
      face: face,
      shade: Color.lerp(face, sky, 0.4)!,
      snow: ink.withValues(alpha: 0.9),
      hill: Color.lerp(sky, ramp[3], 0.28)!,
      trail: ink.withValues(alpha: 0.6),
      pole: ink,
      flag: palette.accent,
      contour: ink.withValues(alpha: 0.3),
      night: true,
    );
  }

  final Color sky;

  /// Mặt trời khi sáng, trăng khi tối.
  final Color glow;
  final Color far;
  final Color mid;

  /// Sườn núi chính đón sáng; [shade] là sườn khuất.
  final Color face;
  final Color shade;
  final Color snow;
  final Color hill;
  final Color trail;
  final Color pole;
  final Color flag;
  final Color contour;

  /// Tối thì vẽ trăng và sao thay mặt trời.
  final bool night;
}

/// BXH tuần vẽ thành ngọn núi: top [shown] đứng trên đường mòn, hạng 1 sát
/// cờ. Tên, km xếp thành một cột bên trái như thang độ cao, mỗi dòng nối với
/// avatar bằng một vạch đồng mức. Chỗ đứng theo hạng chứ không theo km, nên
/// km sát nhau cũng không đè nhau. Mình ngoài top thì đứng ở trại chân núi;
/// chưa có km mà có [myEntry] thì ở trại, ghi chưa xuất phát.
class RankMountain extends StatelessWidget {
  const RankMountain({
    required this.ranked,
    required this.myUid,
    this.myEntry,
    this.caption,
    super.key,
  });

  /// Cả bảng, hạng cao trước.
  final List<ClubRankedMember> ranked;
  final String? myUid;
  final LeaderboardEntry? myEntry;
  final String? caption;

  static const shown = 5;
  static const height = 296.0;

  // Toạ độ thiết kế trên khung 358 x 296; bề ngang co giãn theo khung thật.
  static const _designWidth = 358.0;
  static const _rowYs = [64.0, 104.0, 144.0, 184.0, 224.0];
  static const _avatarXs = [296.0, 318.0, 262.0, 300.0, 250.0];
  static const _campY = 266.0;
  static const _campX = 200.0;
  static const _lineStart = 150.0;

  @override
  Widget build(BuildContext context) {
    final top = ranked.take(shown).toList();
    final myIndex = ranked.indexWhere((m) => m.entry.uid == myUid);
    final camp = myIndex >= shown
        ? _Climber.ranked(ranked[myIndex])
        : myIndex < 0 && myEntry != null
        ? _Climber.waiting(myEntry!)
        : null;
    final palette = context.runNowPalette;
    final colors = MountainColors.of(palette);
    final light = palette.appearance == RunNowAppearance.light;
    final medals = light ? RunNowRankColors.light : RunNowRankColors.dark;
    final me = light ? palette.accentDeep : palette.accent;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label:
          'BXH tuần: ${[for (final m in top) 'hạng ${m.rank} ${m.entry.displayName} ${_km(m.score)} km'].join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sx = constraints.maxWidth / _designWidth;
              final lineStart = _lineStart * sx;
              final rows = <_Row>[
                for (final (i, m) in top.indexed)
                  _Row(
                    y: _rowYs[i],
                    x: _avatarXs[i] * sx,
                    size: i == 0 ? 40 : 32,
                    climber: _Climber.ranked(m),
                  ),
                if (camp != null)
                  _Row(y: _campY, x: _campX * sx, size: 30, climber: camp),
              ];
              final children = <Widget>[];
              for (final row in rows) {
                final climber = row.climber;
                final isMe = climber.entry.uid == myUid;
                final rank = climber.rank;
                final ring = isMe
                    ? (light ? palette.ink : palette.accent)
                    : rank != null && rank <= medals.length
                    ? medals[rank - 1]
                    : light
                    ? palette.glassStart
                    : palette.ink;
                final rankColor = isMe
                    ? me
                    : rank != null && rank <= medals.length
                    ? (light
                          ? Color.lerp(medals[rank - 1], palette.ink, 0.3)!
                          : medals[rank - 1])
                    : onSurface;
                children.addAll([
                  Positioned(
                    left: 14,
                    top: row.y - 18,
                    width: lineStart - 18,
                    height: 36,
                    child: _Label(
                      rank: rank == null ? '–' : '$rank',
                      name: isMe ? 'Bạn' : climber.entry.displayName,
                      score: climber.score,
                      rankColor: rankColor,
                      nameColor: isMe ? me : onSurface,
                    ),
                  ),
                  Positioned(
                    left: row.x - row.size / 2,
                    top: row.y - row.size / 2,
                    child: _Avatar(
                      entry: climber.entry,
                      size: row.size,
                      ring: ring,
                    ),
                  ),
                ]);
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MountainPainter(
                        colors: colors,
                        scaleX: sx,
                        contours: [
                          for (final row in rows)
                            (
                              y: row.y,
                              from: lineStart,
                              to: row.x - row.size / 2 - 6,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (caption case final caption?)
                    Positioned(
                      left: 16,
                      top: 12,
                      right: 16,
                      child: Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ...children,
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

/// Một người trên núi: có hạng, hoặc chưa có km ([rank], [score] null).
class _Climber {
  _Climber.ranked(ClubRankedMember member)
    : entry = member.entry,
      rank = member.rank,
      score = member.score;

  _Climber.waiting(this.entry) : rank = null, score = null;

  final LeaderboardEntry entry;
  final int? rank;
  final double? score;
}

class _Row {
  const _Row({
    required this.y,
    required this.x,
    required this.size,
    required this.climber,
  });

  final double y;

  /// Tâm avatar theo bề ngang thật.
  final double x;
  final double size;
  final _Climber climber;
}

typedef _Contour = ({double y, double from, double to});

class _MountainPainter extends CustomPainter {
  _MountainPainter({
    required this.colors,
    required this.scaleX,
    required this.contours,
  });

  final MountainColors colors;
  final double scaleX;
  final List<_Contour> contours;

  @override
  void paint(Canvas canvas, Size size) {
    final stretch = Matrix4.diagonal3Values(scaleX, 1, 1).storage;
    Path fit(Path path) => path.transform(stretch);
    void fill(Path path, Color color) =>
        canvas.drawPath(fit(path), Paint()..color = color);

    canvas.drawRect(Offset.zero & size, Paint()..color = colors.sky);
    final glowAt = Offset(232 * scaleX, 70);
    if (colors.night) {
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: glowAt, radius: 18)),
        Path()
          ..addOval(
            Rect.fromCircle(center: glowAt + const Offset(8, -6), radius: 16),
          ),
      );
      canvas.drawPath(moon, Paint()..color = colors.glow);
      final star = Paint()..color = colors.glow.withValues(alpha: 0.7);
      for (final (x, y) in const [(170, 40), (200, 96), (340, 30), (262, 22)]) {
        canvas.drawCircle(Offset(x * scaleX, y.toDouble()), 1.2, star);
      }
    } else {
      canvas.drawCircle(glowAt, 28, Paint()..color = colors.glow);
    }

    fill(
      Path()
        ..moveTo(0, 196)
        ..cubicTo(40, 168, 82, 178, 122, 150)
        ..cubicTo(160, 124, 198, 140, 232, 114)
        ..cubicTo(262, 92, 300, 120, 358, 112)
        ..lineTo(358, 296)
        ..lineTo(0, 296)
        ..close(),
      colors.far,
    );
    fill(
      Path()
        ..moveTo(0, 238)
        ..cubicTo(46, 214, 92, 228, 138, 206)
        ..cubicTo(170, 192, 196, 208, 224, 200)
        ..lineTo(358, 230)
        ..lineTo(358, 296)
        ..lineTo(0, 296)
        ..close(),
      colors.mid,
    );
    fill(
      Path()
        ..moveTo(118, 296)
        ..cubicTo(168, 232, 214, 160, 250, 104)
        ..lineTo(274, 66)
        ..quadraticBezierTo(286, 40, 296, 32)
        ..quadraticBezierTo(306, 40, 318, 60)
        ..lineTo(342, 100)
        ..cubicTo(350, 114, 354, 122, 358, 128)
        ..lineTo(358, 296)
        ..close(),
      colors.face,
    );
    fill(
      Path()
        ..moveTo(296, 32)
        ..quadraticBezierTo(306, 40, 318, 60)
        ..lineTo(342, 100)
        ..cubicTo(350, 114, 354, 122, 358, 128)
        ..lineTo(358, 296)
        ..lineTo(306, 296)
        ..cubicTo(310, 230, 298, 160, 304, 112)
        ..cubicTo(306, 80, 300, 52, 296, 32)
        ..close(),
      colors.shade,
    );
    fill(
      Path()
        ..moveTo(296, 32)
        ..quadraticBezierTo(287, 40, 279, 54)
        ..lineTo(288, 50)
        ..lineTo(294, 60)
        ..lineTo(301, 49)
        ..lineTo(309, 57)
        ..lineTo(318, 60)
        ..quadraticBezierTo(306, 40, 296, 32)
        ..close(),
      colors.snow,
    );
    fill(
      Path()
        ..moveTo(0, 270)
        ..cubicTo(60, 256, 120, 270, 170, 262)
        ..cubicTo(200, 258, 220, 266, 250, 296)
        ..lineTo(0, 296)
        ..close(),
      colors.hill,
    );

    final trail = fit(
      Path()
        ..moveTo(168, 290)
        ..cubicTo(182, 278, 190, 270, 200, 266)
        ..cubicTo(226, 252, 236, 238, 250, 224)
        ..cubicTo(268, 206, 292, 198, 300, 184)
        ..cubicTo(308, 168, 268, 160, 262, 144)
        ..cubicTo(256, 128, 312, 120, 318, 104)
        ..cubicTo(324, 88, 298, 78, 296, 64)
        ..lineTo(296, 44),
    );
    _dots(canvas, trail, colors.trail, width: 2.5, gap: 8);

    final peak = 296 * scaleX;
    canvas.drawLine(
      Offset(peak, 34),
      Offset(peak, 8),
      Paint()
        ..color = colors.pole
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(peak, 8)
        ..lineTo(peak + 20, 13)
        ..lineTo(peak, 19)
        ..close(),
      Paint()..color = colors.flag,
    );
    final tent = 230 * scaleX;
    canvas.drawPath(
      Path()
        ..moveTo(tent - 12, 276)
        ..lineTo(tent, 260)
        ..lineTo(tent + 12, 276)
        ..close(),
      Paint()..color = colors.flag,
    );
    canvas.drawLine(
      Offset(tent, 276),
      Offset(tent, 268),
      Paint()
        ..color = colors.hill
        ..strokeWidth = 2.5,
    );

    for (final line in contours) {
      if (line.to <= line.from) continue;
      _dots(
        canvas,
        Path()
          ..moveTo(line.from, line.y)
          ..lineTo(line.to, line.y),
        colors.contour,
        width: 1.5,
        gap: 4,
      );
    }
  }

  /// Chấm tròn đều dọc [path].
  static void _dots(
    Canvas canvas,
    Path path,
    Color color, {
    required double width,
    required double gap,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var d = 0.0; d <= metric.length; d += gap) {
        canvas.drawPath(metric.extractPath(d, d + 0.01), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MountainPainter old) =>
      old.colors != colors ||
      old.scaleX != scaleX ||
      old.contours.length != contours.length ||
      Iterable.generate(
        contours.length,
      ).any((i) => old.contours[i] != contours[i]);
}

/// Avatar viền theo hạng.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.size, required this.ring});

  final LeaderboardEntry entry;
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final url = entry.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = entry.displayName;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: size / 2 - 2.5,
        backgroundColor: palette.accent,
        backgroundImage: hasUrl ? cachedAvatarImage(context, url, size) : null,
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
    );
  }
}

/// Một dòng ở cột thang độ cao: hạng, tên, km.
class _Label extends StatelessWidget {
  const _Label({
    required this.rank,
    required this.name,
    required this.score,
    required this.rankColor,
    required this.nameColor,
  });

  final String rank;
  final String name;
  final double? score;
  final Color rankColor;
  final Color nameColor;

  @override
  Widget build(BuildContext context) {
    final muted = context.runNowPalette.textMuted;
    final score = this.score;
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            rank,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Barlow Condensed',
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w800,
              color: rankColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: nameColor,
                ),
              ),
              if (score == null)
                Text(
                  'chưa xuất phát',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                )
              else
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: _km(score)),
                      TextSpan(
                        text: ' km',
                        style: TextStyle(fontSize: 10, color: muted),
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
          ),
        ),
      ],
    );
  }
}
