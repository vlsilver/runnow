import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _ink = RunFaceTokens.stopwatchInk;
const _steel = RunFaceTokens.stopwatchSteel;
const _soft = RunFaceTokens.stopwatchSoft;
const _muted = RunFaceTokens.stopwatchMuted;
const _disc = RunFaceTokens.stopwatchDisc;
const _white = RunFaceTokens.stopwatchWhite;

Gradient _caseAt(double cy) => RadialGradient(
  center: Alignment(0, (cy - 210) / 210),
  radius: 1.3,
  colors: const [RunFaceTokens.dialTop, RunFaceTokens.night],
  stops: const [0, 0.72],
);

class _Ticks extends CustomPainter {
  const _Ticks();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final minor = Paint()
      ..color = _steel.withValues(alpha: 0.72)
      ..strokeWidth = 1.4;
    final major = Paint()
      ..color = _white
      ..strokeWidth = 2.6;
    for (var i = 0; i < 60; i++) {
      final a = i * 2 * math.pi / 60;
      final d = Offset(math.cos(a), math.sin(a));
      if (i % 5 == 0) {
        canvas.drawLine(c + d * 119, c + d * 129, major);
      } else {
        canvas.drawLine(c + d * 121, c + d * 129, minor);
      }
    }
  }

  @override
  bool shouldRepaint(_Ticks old) => false;
}

List<Widget> _dial(double cy, Widget inner) => [
  pin(
    l: 140,
    t: cy - 151,
    w: 20,
    h: 12,
    c: DecoratedBox(
      decoration: BoxDecoration(
        color: _steel,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  ),
  pin(
    l: 146,
    t: cy - 139,
    w: 8,
    h: 11,
    c: const ColoredBox(color: RunFaceTokens.ash),
  ),
  pin(
    l: 16,
    t: cy - 134,
    w: 268,
    h: 268,
    c: const CustomPaint(painter: _Ticks()),
  ),
  pin(
    l: 35,
    t: cy - 115,
    w: 230,
    h: 230,
    c: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _disc,
        border: Border.all(color: _steel, width: 2),
      ),
      child: inner,
    ),
  ),
];

Widget _bigRow(RunFace f) => slotKm(
  fit(
    baseline([
      hero(f.km, 60, 17, h: 0.9),
      Text(
        f.time,
        maxLines: 1,
        style: faceStyle(60, w: w6, h: 0.9, c: _soft),
      ),
    ], gap: 14),
    a: Alignment.center,
  ),
  a: Alignment.center,
);

Widget stopwatchFront(RunFace f, RunCardTextLayout t) {
  final cy = switch (t) {
    RunCardTextLayout.full => 164.0,
    RunCardTextLayout.top => 256.0,
    RunCardTextLayout.compact => 204.0,
  };
  return faceBox(
    gradient: _caseAt(cy),
    ink: _ink,
    children: [
      ..._dial(cy, artOf(f)),
      ...switch (t) {
        RunCardTextLayout.full => [
          badgeAt(f, l: 17, t: 17),
          stampAt(f, r: 14, t: 14, size: 48),
          pin(
            l: 16,
            r: 16,
            b: 16,
            c: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bigRow(f),
                const SizedBox(height: 4),
                slotPace(
                  txt('${f.name} · ${f.pace} /km', 16, w: w7),
                  a: Alignment.center,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: txt(
                        '${f.owner} ${f.clock} · ${f.when} · ',
                        11,
                        w: w6,
                        ls: 1.3,
                        c: _muted,
                      ),
                    ),
                    txt(f.rarity, 11, ls: 1.3, c: _soft),
                  ],
                ),
              ],
            ),
          ),
        ],
        RunCardTextLayout.top => [
          badgeAt(f, l: 17, b: 17),
          stampAt(f, r: 14, b: 14, size: 48),
          pin(
            l: 16,
            r: 16,
            t: 16,
            c: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bigRow(f),
                const SizedBox(height: 4),
                slotPace(
                  txt('${f.name} · ${f.pace} /km', 16, w: w7),
                  a: Alignment.center,
                ),
              ],
            ),
          ),
        ],
        RunCardTextLayout.compact => [
          badgeAt(f, l: 17, t: 17),
          stampAt(f, r: 14, t: 14, size: 48),
          pin(
            l: 16,
            r: 16,
            b: 18,
            c: slotKm(
              fit(hero(f.km, 44, 14, h: 1), a: Alignment.center),
              a: Alignment.center,
            ),
          ),
        ],
      },
    ],
  );
}

/// Đường chạy trên bản đồ mờ; padding khớp ô vẽ đường để hai lớp trùng nhau.
Widget _washedRoute(RunFace f) => FaceMap(
  f,
  dark: true,
  route: null,
  padding: const EdgeInsets.all(22),
  maxZoom: 22,
  tileFilter: faceMapWash(_white, dark: true, strength: 0.35),
  creditAt: Alignment.bottomCenter,
  creditPadding: const EdgeInsets.fromLTRB(55, 0, 55, 16),
  overlay: Center(
    child: FaceRoute(f.route, size: 190, color: _white, stroke: 5),
  ),
);

Widget stopwatchBack(RunFace f, {bool map = false}) {
  final rows = f.rows(6);
  return faceBox(
    gradient: _caseAt(164),
    ink: _ink,
    children: [
      ..._dial(
        164,
        map
            ? FaceMap(
                f,
                dark: true,
                route: _white,
                stroke: 3.4,
                padding: const EdgeInsets.all(34),
                creditAt: Alignment.bottomCenter,
                creditPadding: const EdgeInsets.fromLTRB(55, 0, 55, 16),
              )
            : Center(
                child: f.hasRoute
                    ? _washedRoute(f)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 200,
                            child: fit(
                              Text(f.time, style: faceStyle(62, h: 1)),
                              a: Alignment.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 150,
                            height: 40,
                            child: FaceChart(f.series, color: _soft),
                          ),
                        ],
                      ),
              ),
      ),
      pin(l: 18, t: 16, c: txt('3I RUN', 11, ls: 2.2, c: _soft)),
      pin(
        l: 16,
        r: 16,
        b: 14,
        c: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(child: fit(hero(f.km, 34, 12, h: 1))),
                if (f.hasRoute)
                  Flexible(
                    child: fit(Text(f.time, style: faceStyle(34, h: 1))),
                  ),
                Flexible(child: fit(hero(f.pace, 34, 12, h: 1, label: '/KM'))),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < rows.length; i += 3)
              Row(
                children: [
                  for (var j = i; j < i + 3; j++)
                    Expanded(
                      child: j < rows.length
                          ? Padding(
                              padding: EdgeInsets.only(
                                right: j < i + 2 ? 16 : 0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  txt(
                                    rows[j].km,
                                    15,
                                    w: rows[j].best ? w8 : w6,
                                    c: rows[j].best
                                        ? _white
                                        : RunFaceTokens.paper80,
                                  ),
                                  txt(
                                    rows[j].pace,
                                    15,
                                    w: rows[j].best ? w8 : w6,
                                    c: rows[j].best
                                        ? _white
                                        : RunFaceTokens.paper80,
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                txt(f.date, 11, w: w6, ls: 1.3, c: RunFaceTokens.paper68),
                txt(f.rarity, 11, ls: 2.2, c: _soft),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
