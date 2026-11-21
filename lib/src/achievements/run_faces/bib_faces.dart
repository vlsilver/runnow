import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/flipboard_faces.dart'
    show fadeBottom;
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _ink = RunFaceTokens.bibInk;
const _paper = RunFaceTokens.bibPaper;
const _coal = RunFaceTokens.bibCoal;

List<Widget> _pins(double inset, double size, Color color, {Color? border}) => [
  for (final (left, top) in const [
    (true, true),
    (true, false),
    (false, true),
    (false, false),
  ])
    pin(
      l: left ? inset : null,
      r: left ? null : inset,
      t: top ? inset : null,
      b: top ? null : inset,
      w: size,
      h: size,
      c: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: border == null ? null : Border.all(color: border, width: 2),
        ),
      ),
    ),
];

Widget _bib(
  RunFace f, {
  required double width,
  required double height,
  required double number,
  required double unit,
  required double degrees,
  bool head = true,
}) => Transform.rotate(
  angle: degrees * math.pi / 180,
  child: Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(5),
      boxShadow: const [
        BoxShadow(
          color: RunFaceTokens.shade50,
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: _coal),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            child: Column(
              children: [
                if (head)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      txt('3I RUN', 9.5, w: w7, ls: 1.1),
                      txt(f.rarity, 9.5, w: w7, ls: 1.1),
                    ],
                  ),
                Expanded(
                  child: Center(
                    child: slotKm(
                      fit(
                        hero(f.km, number, unit, h: 0.9),
                        a: Alignment.center,
                      ),
                      a: Alignment.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._pins(4, 5, RunFaceTokens.pinGray),
        ],
      ),
    ),
  ),
);

Widget bibFront(RunFace f, RunCardTextLayout t) => faceBox(
  bg: RunFaceTokens.night,
  ink: _ink,
  children: [
    artOf(f, route: t == RunCardTextLayout.top ? (0.37, 0.81) : null),
    badgeAt(f, l: 17, t: 17),
    stampAt(f, r: 14, t: 14, size: t == RunCardTextLayout.top ? 56 : 60),
    ...switch (t) {
      RunCardTextLayout.full => [
        fadeBottom(140),
        pin(
          l: 17,
          b: 17,
          c: _bib(f, width: 132, height: 92, number: 60, unit: 13, degrees: -2),
        ),
        pin(
          l: 162,
          r: 17,
          b: 17,
          c: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              txt(f.name, 20, w: w7, h: 1.1),
              const SizedBox(height: 2),
              slotPace(
                fit(
                  Text(
                    '${f.pace} /km · ${f.time}',
                    style: faceStyle(13, w: w6),
                  ),
                ),
                a: Alignment.centerLeft,
              ),
              const SizedBox(height: 5),
              txt('${f.owner} · ${f.clock}', 11, w: w6, ls: 1.2),
              const SizedBox(height: 2),
              txt(f.data.meta, 11, w: w6, ls: 1.2, c: RunFaceTokens.paper62),
            ],
          ),
        ),
      ],
      RunCardTextLayout.top => [
        fadeBottom(100),
        pin(
          l: 54,
          t: 14,
          c: _bib(f, width: 168, height: 118, number: 80, unit: 16, degrees: 2),
        ),
        pin(
          l: 16,
          r: 16,
          b: 14,
          c: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              txt(f.name, 20, w: w7, h: 1.1),
              const SizedBox(height: 4),
              slotPace(
                txt(
                  '${f.pace} /km · ${f.time} · ${f.owner} ${f.clock}',
                  14,
                  w: w6,
                ),
                a: Alignment.bottomCenter,
              ),
            ],
          ),
        ),
      ],
      RunCardTextLayout.compact => [
        pin(
          l: 17,
          b: 17,
          c: _bib(
            f,
            width: 104,
            height: 64,
            number: 42,
            unit: 11,
            degrees: -3,
            head: false,
          ),
        ),
      ],
    },
  ],
);

Widget _mapStats(RunFace f) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 34),
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: slotTime(
              fit(Text(f.time, style: faceStyle(40, h: 1))),
              a: Alignment.centerLeft,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: slotPace(
              fit(
                Text('${f.pace} /km', style: faceStyle(26, h: 1)),
                a: Alignment.centerRight,
              ),
              a: Alignment.centerRight,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      txt(
        '${f.date} · ${f.when}',
        12,
        w: w7,
        ls: 1.2,
        c: RunFaceTokens.labelGray,
      ),
    ],
  ),
);

Widget bibBack(RunFace f, {bool map = false}) => faceBox(
  bg: RunFaceTokens.night,
  ink: _coal,
  children: [
    pin(
      l: 12,
      t: 12,
      w: 276,
      h: 396,
      c: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: _paper,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (f.hasRoute && !map)
                FaceMap(
                  f,
                  dark: false,
                  route: null,
                  padding: const EdgeInsets.fromLTRB(40, 80, 40, 80),
                  maxZoom: 22,
                  tileFilter: faceMapWash(_coal, dark: false, strength: 0.2),
                  creditAt: Alignment.bottomCenter,
                  creditPadding: const EdgeInsets.only(bottom: 5),
                ),
              Column(
                children: [
                  Container(
                    height: 44,
                    color: _coal,
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        txt('3I RUN', 20, ls: 1.5, c: _paper),
                        txt(f.rarity, 11, ls: 2, c: RunFaceTokens.silver),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: map ? 112 : 196,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: fit(
                        hero(
                          f.km,
                          map ? 112 : 190,
                          map ? 20 : 26,
                          h: 0.8,
                          ls: -3,
                        ),
                        a: Alignment.center,
                      ),
                    ),
                  ),
                  const DashLine(
                    color: RunFaceTokens.dashGray,
                    width: 2,
                    dash: 5,
                  ),
                  if (map) ...[
                    SizedBox(
                      height: 148,
                      child: FaceMap(
                        f,
                        dark: false,
                        route: _coal,
                        stroke: 3.2,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                    const DashLine(
                      color: RunFaceTokens.dashGray,
                      width: 2,
                      dash: 5,
                    ),
                    Expanded(child: _mapStats(f)),
                  ] else
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            routeOrChart(
                              f,
                              routeSize: 92,
                              routeStroke: 8,
                              chartWidth: 92,
                              chartHeight: 50,
                              color: _coal,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  fit(
                                    Text(f.time, style: faceStyle(40, h: 1)),
                                    a: Alignment.centerRight,
                                  ),
                                  const SizedBox(height: 4),
                                  fit(
                                    Text(
                                      '${f.pace} /km',
                                      style: faceStyle(26, h: 1),
                                    ),
                                    a: Alignment.centerRight,
                                  ),
                                  const SizedBox(height: 4),
                                  txt(
                                    '${f.date} · ${f.when}',
                                    12,
                                    w: w7,
                                    ls: 1.2,
                                    c: RunFaceTokens.labelGray,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    ..._pins(20, 9, RunFaceTokens.night, border: RunFaceTokens.pinEdge),
  ],
);
