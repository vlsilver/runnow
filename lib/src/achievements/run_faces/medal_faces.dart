import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _bg = RunFaceTokens.medalBg;
const _paper = RunFaceTokens.medalPaper;
const _coal = RunFaceTokens.medalCoal;
const _light = RunFaceTokens.medalLight;
const _dark = RunFaceTokens.medalDark;
const _rib = RunFaceTokens.medalRib;
const _white = RunFaceTokens.medalWhite;
const _muted = RunFaceTokens.medalMuted;

void _poly(Canvas canvas, List<Offset> points, Color color) =>
    canvas.drawPath(Path()..addPolygon(points, true), Paint()..color = color);

class _Medal extends CustomPainter {
  const _Medal(this.cy, this.r, {this.plate = false});

  final double cy;
  final double r;
  final bool plate;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = r + 14;
    final end = cy - outer + 8;
    _poly(canvas, [
      const Offset(240, 0),
      const Offset(180, 0),
      Offset(135, end),
      Offset(195, end),
    ], _dark);
    _poly(canvas, [
      const Offset(60, 0),
      const Offset(120, 0),
      Offset(165, end),
      Offset(105, end),
    ], _light);
    if (plate) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 300, 110),
        Paint()..color = _bg,
      );
    }
    final center = Offset(150, cy);
    canvas.drawCircle(center, outer, Paint()..color = _bg);
    final arc = Rect.fromCircle(center: center, radius: outer);
    const degree = math.pi / 180;
    for (var i = 0; i < 6; i++) {
      canvas.drawArc(
        arc,
        (-90 + i * 60) * degree,
        57 * degree,
        true,
        Paint()..color = _rib,
      );
    }
  }

  @override
  bool shouldRepaint(_Medal old) =>
      old.cy != cy || old.r != r || old.plate != plate;
}

Widget medalFront(RunFace f, RunCardTextLayout t) {
  final (cy, r) = switch (t) {
    RunCardTextLayout.full => (170.0, 112.0),
    RunCardTextLayout.top => (280.0, 112.0),
    RunCardTextLayout.compact => (190.0, 124.0),
  };
  final outer = r + 14;
  final stack = [
    fit(hero(f.km, 62, 16, h: 0.9), a: Alignment.center),
    const SizedBox(height: 4),
    txt(
      '${f.name} · ${f.pace} /km · ${f.time}',
      16,
      w: w7,
      a: TextAlign.center,
    ),
  ];
  return faceBox(
    bg: _bg,
    ink: _paper,
    children: [
      CustomPaint(painter: _Medal(cy, r, plate: t == RunCardTextLayout.top)),
      pin(
        l: 150 - outer + 12,
        t: cy - outer + 12,
        w: (outer - 12) * 2,
        h: (outer - 12) * 2,
        c: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _bg,
            border: Border.all(color: _white, width: 2),
          ),
          child: artOf(f),
        ),
      ),
      badgeAt(f, l: 17, t: 17),
      stampAt(f, r: 14, t: 14, size: 52),
      ...switch (t) {
        RunCardTextLayout.full => [
          pin(
            l: 16,
            r: 16,
            b: 14,
            c: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...stack,
                const SizedBox(height: 4),
                txt(f.rarity, 11, ls: 2, c: _rib),
              ],
            ),
          ),
        ],
        RunCardTextLayout.top => [
          pin(
            l: 56,
            r: 56,
            t: 16,
            c: Column(mainAxisSize: MainAxisSize.min, children: stack),
          ),
        ],
        RunCardTextLayout.compact => [
          pin(
            l: 16,
            r: 16,
            b: 16,
            c: fit(hero(f.km, 42, 14, h: 1), a: Alignment.center),
          ),
        ],
      },
    ],
  );
}

/// Mặt sau huy chương: vòng ngoài chia theo từng km, đoạn trắng là km nhanh
/// nhất; có GPS thì đường chạy khắc trong đĩa.
class _MedalBack extends CustomPainter {
  const _MedalBack(this.f, {this.engrave = true});

  final RunFace f;

  /// Bản đồ thật phủ đĩa thì không khắc đường chạy nữa.
  final bool engrave;

  @override
  void paint(Canvas canvas, Size size) {
    _poly(canvas, const [
      Offset(62, 0),
      Offset(108, 0),
      Offset(170, 92),
      Offset(140, 110),
    ], _dark);
    _poly(canvas, const [
      Offset(238, 0),
      Offset(192, 0),
      Offset(130, 92),
      Offset(160, 110),
    ], _light);
    _poly(canvas, const [
      Offset(212, 0),
      Offset(202, 0),
      Offset(140, 94),
      Offset(146, 98),
    ], RunFaceTokens.plaqueShade);
    const center = Offset(150, 196);
    final rim = Rect.fromCircle(center: center, radius: 114);
    final disc = Rect.fromCircle(center: center, radius: 97);
    canvas
      ..drawCircle(
        center,
        114,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_white, _light, _dark],
          ).createShader(rim),
      )
      ..drawCircle(center, 110, Paint()..color = _coal)
      ..drawCircle(
        center,
        97,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment(-0.6, -1),
            end: Alignment(0.6, 1),
            colors: [
              RunFaceTokens.gaugeLight,
              RunFaceTokens.medalMid,
              RunFaceTokens.gaugeDark,
            ],
            stops: [0, 0.55, 1],
          ).createShader(disc),
      );
    final ring = Rect.fromCircle(center: center, radius: 104);
    final grey = Paint()
      ..color = RunFaceTokens.medalEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final arcs = f.arcs;
    if (arcs.isEmpty) {
      canvas.drawCircle(center, 104, grey);
    } else {
      const full = 2 * math.pi;
      const gap = 3 / 104;
      var at = -math.pi / 2;
      for (final arc in arcs) {
        final sweep = arc.share * full;
        canvas.drawArc(
          ring,
          at,
          math.max(sweep - gap, 0.01),
          false,
          arc.best ? (Paint.from(grey)..color = _white) : grey,
        );
        at += sweep;
      }
    }
    final points = engrave
        ? fitRunRoute(f.route, const Rect.fromLTRB(112, 112, 188, 198))
        : const <Offset>[];
    if (points.isNotEmpty) {
      canvas.drawPath(polyline(points), strokePaint(_coal, 2.9));
    }
  }

  @override
  bool shouldRepaint(_MedalBack old) =>
      !identical(old.f.card, f.card) || old.engrave != engrave;
}

Widget medalBack(RunFace f, {bool map = false}) {
  final gps = f.hasRoute;
  return faceBox(
    gradient: const RadialGradient(
      center: Alignment(0, -0.08),
      radius: 0.86,
      colors: [RunFaceTokens.plaqueTop, _bg],
    ),
    ink: _paper,
    children: [
      if (gps && !map)
        FaceMap(
          f,
          dark: true,
          route: null,
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 120),
          maxZoom: 22,
          tileFilter: faceMapWash(_paper, dark: true, strength: 0.35),
          creditAt: Alignment.topCenter,
          // Khe trống giữa viền huy chương và hàng số.
          creditPadding: const EdgeInsets.only(top: 318),
        ),
      CustomPaint(painter: _MedalBack(f, engrave: !map)),
      pin(l: 17, t: 15, c: txt('3I RUN', 11, ls: 2.2, c: _rib)),
      pin(
        r: 17,
        t: 15,
        c: txt(f.owner, 11, w: w7, ls: 1.5, c: _rib),
      ),
      if (map) ...[
        pin(
          l: 53,
          t: 99,
          w: 194,
          h: 194,
          // Nhãn số đè đáy đĩa, chừa để đường chạy không nằm dưới.
          c: FaceMap(
            f,
            dark: false,
            route: _coal,
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 54),
            circle: true,
            creditAt: Alignment.topCenter,
            creditPadding: const EdgeInsets.fromLTRB(44, 16, 44, 0),
          ),
        ),
        pin(
          l: 88,
          t: 258,
          w: 124,
          h: 54,
          c: DecoratedBox(
            decoration: BoxDecoration(
              color: _coal,
              border: Border.all(color: _light, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                fit(hero(f.km, 32, 12, h: 0.95), a: Alignment.center),
                txt(f.rarity, 10, ls: 1.6, c: _rib),
              ],
            ),
          ),
        ),
      ] else
        pin(
          l: 70,
          r: 70,
          t: gps ? 200 : 136,
          c: DefaultTextStyle.merge(
            style: const TextStyle(color: _coal),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                fit(
                  hero(f.km, gps ? 62 : 98, gps ? 15 : 18, h: 0.86),
                  a: Alignment.center,
                ),
                SizedBox(height: gps ? 5 : 8),
                txt(f.rarity, gps ? 11 : 12, ls: gps ? 1.6 : 1.8),
              ],
            ),
          ),
        ),
      pin(
        l: 17,
        r: 17,
        b: 15,
        c: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            statColumns(
              [
                (f.time, 'THỜI GIAN'),
                (f.pace, 'PACE /KM'),
                (f.bestPace ?? '--', 'NHANH NHẤT'),
              ],
              labelColor: _muted,
              align: TextAlign.center,
            ),
            const SizedBox(height: 9),
            txt(
              '${f.date} · ${f.when}',
              10,
              w: w6,
              ls: 1.3,
              c: RunFaceTokens.paper60,
            ),
          ],
        ),
      ),
    ],
  );
}
