import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _paper = RunFaceTokens.finishPaper;
const _coal = RunFaceTokens.finishCoal;
const _white = RunFaceTokens.finishWhite;

class _Check extends CustomPainter {
  const _Check();

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.height / 2;
    final dark = Paint()..color = _coal;
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = _paper);
    for (var x = 0.0; x < size.width; x += cell * 2) {
      canvas
        ..drawRect(Rect.fromLTWH(x + cell, 0, cell, cell), dark)
        ..drawRect(Rect.fromLTWH(x, cell, cell, cell), dark);
    }
  }

  @override
  bool shouldRepaint(_Check old) => false;
}

Widget _tape(
  double height,
  double degrees,
  List<Widget> inner, {
  double check = 14,
  double left = 78,
}) => Transform.rotate(
  angle: degrees * math.pi / 180,
  child: Container(
    width: 420,
    height: height,
    decoration: const BoxDecoration(
      color: _paper,
      boxShadow: [
        BoxShadow(
          color: RunFaceTokens.shade55,
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: _coal),
      child: Column(
        children: [
          SizedBox(
            height: check,
            width: double.infinity,
            child: const CustomPaint(painter: _Check()),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: left, right: 72),
              child: Row(children: inner),
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget _black(RunFace f, double degrees, String text) => Transform.rotate(
  angle: degrees * math.pi / 180,
  child: Container(
    width: 400,
    height: 28,
    color: RunFaceTokens.nightDeep,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.only(left: 64, right: 60),
    child: txt(text, 13, w: w7, ls: 1.2, c: RunFaceTokens.silver),
  ),
);

Widget _number(RunFace f, double n, double k, double max) => ConstrainedBox(
  constraints: BoxConstraints(maxWidth: max),
  child: fit(hero(f.km, n, k, h: 0.86, ls: -1)),
);

Widget _name(RunFace f) => Expanded(
  child: Padding(
    padding: const EdgeInsets.only(left: 14),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        txt('BUỔI CHẠY', 11, w: w7, ls: 1.5, c: RunFaceTokens.labelGray),
        const SizedBox(height: 1),
        Text(
          f.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: faceStyle(28, h: 0.95),
        ),
      ],
    ),
  ),
);

String _detail(RunFace f) =>
    '${f.pace} /KM  ·  ${f.time}  ·  ${f.owner} ${f.clock}  ·  ${f.rarity}';

Widget finishFront(RunFace f, RunCardTextLayout t) => faceBox(
  bg: RunFaceTokens.night,
  ink: RunFaceTokens.paperBright,
  children: [
    artOf(
      f,
      route: switch (t) {
        RunCardTextLayout.full => (0.1, 0.41),
        RunCardTextLayout.top => (0.57, 0.86),
        RunCardTextLayout.compact => null,
      },
    ),
    badgeAt(f, l: 17, t: 17),
    stampAt(f, r: 14, t: 14, size: 60),
    ...switch (t) {
      RunCardTextLayout.full => [
        pin(
          l: -60,
          t: 205,
          c: _tape(118, -13, [_number(f, 104, 20, 150), _name(f)]),
        ),
        pin(l: -50, t: 366, c: _black(f, 5, _detail(f))),
      ],
      RunCardTextLayout.top => [
        pin(
          l: -60,
          t: 92,
          c: _tape(118, 8, [_number(f, 104, 20, 150), _name(f)]),
        ),
        pin(l: -50, t: 372, c: _black(f, -4, _detail(f))),
      ],
      RunCardTextLayout.compact => [
        pin(
          l: -60,
          t: 330,
          c: _tape(62, -6, [
            _number(f, 44, 14, 110),
            const SizedBox(width: 14),
            txt(f.rarity, 11, ls: 2),
          ], check: 10),
        ),
      ],
    },
  ],
);

Widget finishBack(RunFace f, {bool map = false}) {
  final rows = f.rows(6);
  final lane = rows.isEmpty ? 45.0 : 270 / rows.length;
  return faceBox(
    bg: RunFaceTokens.brick,
    ink: _white,
    children: [
      if (f.hasRoute && !map)
        FaceMap(
          f,
          dark: true,
          route: null,
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 120),
          maxZoom: 22,
          tileFilter: faceMapWash(_white, dark: true, strength: 0.28),
          creditAt: Alignment.topLeft,
          // Khe trống trên đầu thẻ, giữa hai nhãn.
          creditPadding: const EdgeInsets.fromLTRB(66, 15, 0, 0),
        ),
      pin(
        l: 18,
        r: 18,
        t: 14,
        c: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            txt('3I RUN', 11, ls: 2.2),
            txt(f.when, 11, w: w7, ls: 1.4),
          ],
        ),
      ),
      pin(l: 0, r: 0, t: 36, h: 14, c: const CustomPaint(painter: _Check())),
      if (map)
        pin(
          l: 15,
          t: 56,
          w: 270,
          h: 240,
          c: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: _white, width: 2),
            ),
            // Băng đích đè đáy bản đồ, chừa 38 để đường chạy không nằm dưới.
            child: FaceMap(
              f,
              dark: false,
              route: RunFaceTokens.brick,
              stroke: 3.6,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 50),
              creditAt: Alignment.topRight,
              creditPadding: const EdgeInsets.fromLTRB(5, 5, 7, 3),
            ),
          ),
        )
      else if (rows.isNotEmpty)
        pin(
          l: 15,
          t: 56,
          h: 262,
          c: Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: _white, width: 2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Container(
                    width: lane,
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: _white, width: 2),
                      ),
                    ),
                    child: Stack(
                      children: [
                        pin(
                          l: 0,
                          r: 0,
                          t: 0,
                          h: 28,
                          c: txt(row.km, 24, h: 1.16, a: TextAlign.center),
                        ),
                        pin(
                          l: 4,
                          r: 4,
                          b: 0,
                          h: row.share * 200,
                          c: ColoredBox(
                            color: row.best
                                ? RunFaceTokens.paperBright
                                : RunFaceTokens.white28,
                          ),
                        ),
                        pin(
                          l: 0,
                          r: 0,
                          b: row.share * 200 + 2,
                          c: txt(row.pace, 14, a: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      pin(
        l: -60,
        t: 276,
        c: _tape(
          96,
          -6,
          [
            _number(f, 76, 18, 130),
            if (!map) ...[
              const SizedBox(width: 14),
              routeOrChart(
                f,
                routeSize: 66,
                routeStroke: 11,
                chartWidth: 84,
                chartHeight: 36,
                color: _coal,
              ),
            ],
          ],
          check: 12,
          left: map ? 142 : 78,
        ),
      ),
      pin(
        l: -50,
        t: 378,
        c: _black(
          f,
          3,
          '${f.time}  ·  ${f.pace} /KM  ·  ${f.date}  ·  ${f.rarity}',
        ),
      ),
    ],
  );
}
