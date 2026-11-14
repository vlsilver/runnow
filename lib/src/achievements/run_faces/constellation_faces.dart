import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _gold = RunFaceTokens.constellationGold;
const _bright = RunFaceTokens.constellationBright;
const _night = RunFaceTokens.constellationNight;

const _stars = [
  (24.0, 40.0),
  (58.0, 68.0),
  (36.0, 300.0),
  (270.0, 52.0),
  (282.0, 150.0),
  (252.0, 300.0),
  (196.0, 42.0),
  (100.0, 40.0),
  (20.0, 214.0),
  (276.0, 240.0),
  (204.0, 300.0),
  (108.0, 306.0),
  (226.0, 72.0),
  (66.0, 262.0),
];

/// Viền chia độ quanh [center], 64 vạch như mặt đồng hồ thiên văn.
void _ticks(Canvas canvas, Offset center, double alpha) {
  final tick = Paint()
    ..color = _gold.withValues(alpha: alpha)
    ..strokeWidth = 1;
  for (var i = 0; i < 60; i++) {
    final a = i * 2 * math.pi / 60;
    final d = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(center + d * 127, center + d * 133, tick);
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.cy);

  final double cy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(150, cy);
    final vignette = Rect.fromCircle(center: center, radius: 152);
    canvas
      ..drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addOval(vignette),
        Paint()..color = _night.withValues(alpha: 0.96),
      )
      ..drawCircle(
        center,
        152,
        Paint()
          ..shader = const RadialGradient(
            colors: [
              RunFaceTokens.skyFade00,
              RunFaceTokens.skyFade00,
              RunFaceTokens.skyFade96,
            ],
            stops: [0, 0.737, 1],
          ).createShader(vignette),
      );
    final line = Paint()
      ..color = _gold.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas
      ..drawCircle(center, 136, line)
      ..drawCircle(center, 120, line);
    _ticks(canvas, center, 0.7);
  }

  @override
  bool shouldRepaint(_Ring old) => old.cy != cy;
}

Widget constellationFront(RunFace f, RunCardTextLayout t) {
  final stack = [
    fit(hero(f.km, 66, 15, h: 0.9, c: _bright), a: Alignment.center),
    const SizedBox(height: 5),
    txt('${f.time} · ${f.pace} /km', 18, w: w6),
  ];
  final cy = switch (t) {
    RunCardTextLayout.full => 168.0,
    RunCardTextLayout.top => 268.0,
    RunCardTextLayout.compact => 186.0,
  };
  return faceBox(
    bg: _night,
    ink: _gold,
    children: [
      artOf(f, route: t == RunCardTextLayout.top ? (0.44, 0.8) : null),
      CustomPaint(painter: _Ring(cy)),
      const CustomPaint(painter: StarField(_stars, 1)),
      badgeAt(f, l: 17, t: 17),
      stampAt(f, r: 14, t: 14),
      ...switch (t) {
        RunCardTextLayout.full => [
          pin(
            l: 18,
            r: 18,
            b: 16,
            c: Column(mainAxisSize: MainAxisSize.min, children: stack),
          ),
        ],
        RunCardTextLayout.top => [
          pin(
            l: 62,
            r: 62,
            t: 18,
            c: Column(mainAxisSize: MainAxisSize.min, children: stack),
          ),
        ],
        RunCardTextLayout.compact => [
          pin(
            l: 18,
            r: 18,
            b: 18,
            c: fit(hero(f.km, 40, 13, h: 1, c: _bright), a: Alignment.center),
          ),
        ],
      },
    ],
  );
}

Path _star(Offset at, double scale) {
  final r = 14 * scale;
  return Path()
    ..moveTo(at.dx, at.dy - r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
    ..close();
}

/// Mỗi km là một ngôi sao, chạy càng nhanh sao càng to.
class _Chart extends CustomPainter {
  const _Chart(this.f, {required this.onClearMap});

  final RunFace f;

  /// Bản đồ rõ nhiều nét nên chòm sao cần nét đậm và viền tối mới nổi.
  final bool onClearMap;

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(150, 185);
    final grid = Paint()
      ..color = _gold.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas
      ..drawCircle(center, 136, grid)
      ..drawCircle(center, 96, grid)
      ..drawCircle(center, 50, grid)
      ..drawLine(const Offset(14, 185), const Offset(286, 185), grid)
      ..drawLine(const Offset(150, 49), const Offset(150, 321), grid)
      ..drawLine(const Offset(54, 89), const Offset(246, 281), grid)
      ..drawLine(const Offset(246, 89), const Offset(54, 281), grid);
    _ticks(canvas, center, 0.5);
    final link = Paint()
      ..color = _gold.withValues(alpha: onClearMap ? 1 : 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = onClearMap ? 2 : 1;
    final fill = Paint()..color = _bright;
    final halo = Paint()
      ..color = _night.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void drawStar(Offset at, double scale) {
      final star = _star(at, scale);
      if (onClearMap) canvas.drawPath(star, halo);
      canvas.drawPath(star, fill);
    }

    double scaleOf(FaceRow? row) =>
        row == null ? 0.75 : (row.best ? 1.25 : row.share);

    if (f.hasRoute) {
      final points = fitRunRoute(
        f.route,
        const Rect.fromLTRB(66, 72, 234, 290),
      );
      final marks = routeKmMarks(f.route, points, max: 10);
      final rows = f.rows(marks.length);
      final nodes = [points.first, ...marks.map((m) => m.at), points.last];
      final line = polyline(nodes);
      if (onClearMap) canvas.drawPath(line, halo);
      canvas.drawPath(line, link);
      drawStar(nodes.first, 0.5);
      for (final (i, m) in marks.indexed) {
        drawStar(m.at, scaleOf(rows.length == marks.length ? rows[i] : null));
      }
      canvas.drawCircle(nodes.last, 2.4, fill);
      return;
    }
    final rows = f.rows(6);
    if (rows.isEmpty) return;
    final step = rows.length == 1 ? 0.0 : 220 / (rows.length - 1);
    final nodes = [
      for (final (i, row) in rows.indexed)
        Offset(40 + i * step, 130 + (1 - row.share) / 0.4 * 88),
    ];
    canvas.drawPath(polyline(nodes), link);
    for (final (i, row) in rows.indexed) {
      canvas.drawPath(_star(nodes[i], scaleOf(row)), fill);
    }
  }

  @override
  bool shouldRepaint(_Chart old) =>
      !identical(old.f.card, f.card) || old.onClearMap != onClearMap;
}

Widget constellationBack(RunFace f, {bool map = false}) => faceBox(
  gradient: const RadialGradient(
    center: Alignment(0, -0.12),
    radius: 1.1,
    colors: [RunFaceTokens.skyTop, _night],
    stops: [0, 0.78],
  ),
  ink: _gold,
  children: [
    // Khung tròn trùng vòng ngoài của tinh đồ, padding khớp ô vẽ chòm sao để
    // từng ngôi sao nằm đúng chỗ trên bản đồ.
    if (f.hasRoute)
      pin(
        l: 14,
        r: 14,
        t: 49,
        b: 99,
        c: FaceMap(
          f,
          dark: true,
          route: null,
          circle: true,
          padding: const EdgeInsets.fromLTRB(52, 23, 52, 31),
          maxZoom: 22,
          tileFilter: map
              ? null
              : faceMapWash(_gold, dark: true, strength: 0.45),
          creditAt: Alignment.bottomCenter,
          creditPadding: const EdgeInsets.only(bottom: 12),
        ),
      ),
    const CustomPaint(painter: StarField(_stars, 1)),
    CustomPaint(painter: _Chart(f, onClearMap: map)),
    pin(l: 0, r: 0, t: 16, c: txt('3I RUN', 11, ls: 4, a: TextAlign.center)),
    pin(
      l: 18,
      r: 18,
      b: 16,
      c: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          fit(hero(f.km, 66, 15, h: 0.9, c: _bright), a: Alignment.center),
          const SizedBox(height: 5),
          txt('${f.time} · ${f.pace} /km', 18, w: w6),
        ],
      ),
    ),
  ],
);
