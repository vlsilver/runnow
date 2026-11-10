import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _paper = RunFaceTokens.cassettePaper;
const _shell = RunFaceTokens.cassetteShell;
const _ink = RunFaceTokens.cassetteInk;
const _red = RunFaceTokens.cassetteRed;
const _amber = RunFaceTokens.cassetteAmber;
const _teal = RunFaceTokens.cassetteTeal;
const _deck = RunFaceTokens.cassetteDeck;
const _deckLine = RunFaceTokens.cassetteDeckLine;
const _tag = RunFaceTokens.cassetteTag;
const _rule = RunFaceTokens.cassetteRule;

Widget _stripes(double height) => SizedBox(
  height: height,
  child: const Column(
    children: [
      Expanded(
        child: ColoredBox(color: _red, child: SizedBox.expand()),
      ),
      Expanded(
        child: ColoredBox(color: _amber, child: SizedBox.expand()),
      ),
      Expanded(
        child: ColoredBox(color: _teal, child: SizedBox.expand()),
      ),
    ],
  ),
);

class _Spool extends CustomPainter {
  const _Spool(this.radius, {this.scale = 1});

  final double radius;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(c, radius * scale, Paint()..color = RunFaceTokens.reelCore)
      ..drawCircle(c, 11 * scale, Paint()..color = _shell)
      ..drawCircle(c, 6 * scale, Paint()..color = _paper);
  }

  @override
  bool shouldRepaint(_Spool old) => old.radius != radius || old.scale != scale;
}

Widget _window({
  required double width,
  required double height,
  required double spool,
  required double inset,
  required double top,
  double reelScale = 1,
}) => Container(
  width: width,
  height: height,
  decoration: BoxDecoration(
    color: _deck,
    border: Border.all(color: _deckLine),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Stack(
    children: [
      pin(
        l: inset,
        t: top,
        w: spool,
        h: spool,
        c: CustomPaint(painter: _Spool(14, scale: reelScale)),
      ),
      pin(
        r: inset,
        t: top,
        w: spool,
        h: spool,
        c: CustomPaint(painter: _Spool(21.5, scale: reelScale)),
      ),
    ],
  ),
);

Widget _full(RunFace f) => Row(
  children: [
    Expanded(flex: 4, child: fit(hero(f.km, 62, 16, h: 0.9))),
    const SizedBox(width: 6),
    Expanded(
      flex: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          txt(f.name, 22, h: 1.05),
          fit(
            Text('${f.pace} /km · ${f.time}', style: faceStyle(14, w: w6)),
            a: Alignment.centerRight,
          ),
          txt(f.rarity, 11, ls: 1.5, c: _tag),
        ],
      ),
    ),
  ],
);

Widget _min(RunFace f) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Flexible(child: fit(hero(f.km, 28, 12, h: 1))),
    txt(f.rarity, 11, ls: 1.5, c: _tag),
  ],
);

Widget cassetteFront(RunFace f, RunCardTextLayout t) {
  final art = Expanded(
    child: Stack(
      fit: StackFit.expand,
      children: [
        artOf(f),
        badgeAt(f, l: 8, t: 8),
        stampAt(f, r: 6, t: 6, size: 52),
      ],
    ),
  );
  Widget label(double height, Widget inner) => Container(
    height: height,
    color: _paper,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: _ink),
      child: inner,
    ),
  );
  return faceBox(
    bg: _shell,
    ink: _paper,
    children: [
      pin(
        l: 14,
        r: 14,
        t: 14,
        b: 76,
        c: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Column(
            children: switch (t) {
              RunCardTextLayout.full => [art, _stripes(9), label(95, _full(f))],
              RunCardTextLayout.top => [label(90, _full(f)), _stripes(9), art],
              RunCardTextLayout.compact => [
                art,
                _stripes(9),
                label(38, _min(f)),
              ],
            },
          ),
        ),
      ),
      pin(
        l: 84,
        r: 84,
        b: 14,
        h: 56,
        c: _window(width: 132, height: 56, spool: 42, inset: 7, top: 6),
      ),
      pin(l: 22, b: 14, w: 48, h: 56, c: Center(child: txt('A', 48, h: 1))),
      pin(r: 22, b: 14, w: 48, h: 56, c: Center(child: txt('3I', 22, h: 1))),
    ],
  );
}

Widget cassetteBack(RunFace f, {bool map = false}) {
  Widget screw({double? l, double? r, double? t, double? b}) => pin(
    l: l,
    r: r,
    t: t,
    b: b,
    w: 6,
    h: 6,
    c: const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RunFaceTokens.ash,
      ),
    ),
  );
  final rows = f.rows(6);
  Widget kmRow(int i) {
    final row = rows[i];
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: txt(
              '${i + 1}'.padLeft(2, '0'),
              16,
              w: row.best ? w8 : w6,
              c: row.best ? _amber : _paper,
            ),
          ),
          const SizedBox(width: 6),
          txt(
            'KM ${row.km}',
            16,
            w: row.best ? w8 : w6,
            c: row.best ? _amber : _paper,
          ),
          const SizedBox(width: 6),
          const Expanded(child: DashLine(color: _rule, dash: 1, gap: 2)),
          const SizedBox(width: 6),
          txt(
            row.pace,
            16,
            w: row.best ? w8 : w6,
            c: row.best ? _amber : _paper,
          ),
        ],
      ),
    );
  }

  return faceBox(
    bg: RunFaceTokens.deepTeal,
    ink: _paper,
    children: [
      if (f.hasRoute && !map)
        FaceMap(
          f,
          dark: true,
          route: null,
          // Băng che nửa trên thẻ nên đặt khu chạy vào nửa dưới.
          padding: const EdgeInsets.fromLTRB(30, 200, 30, 30),
          maxZoom: 22,
          tileFilter: faceMapWash(_paper, dark: true, strength: 0.32),
          creditAt: Alignment.bottomCenter,
          creditPadding: const EdgeInsets.only(bottom: 15),
        ),
      pin(
        l: 16,
        t: 16,
        w: 268,
        h: map ? 228 : 168,
        c: Container(
          decoration: BoxDecoration(
            color: _shell,
            border: Border.all(color: _deckLine),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              screw(l: 3, t: 3),
              screw(r: 3, t: 3),
              screw(l: 3, b: 3),
              screw(r: 3, b: 3),
              pin(
                l: 11,
                r: 11,
                t: 11,
                h: map ? 170 : 122,
                c: _Label(f, map: map),
              ),
              pin(
                l: 44,
                r: 44,
                b: 0,
                h: 28,
                c: ClipPath(
                  clipper: const _Trapezoid(),
                  child: const ColoredBox(color: RunFaceTokens.graphite),
                ),
              ),
              if (map)
                pin(
                  l: 66,
                  t: 186,
                  w: 134,
                  h: 36,
                  c: _window(
                    width: 134,
                    height: 36,
                    spool: 30,
                    inset: 7,
                    top: 2,
                    reelScale: 0.7,
                  ),
                ),
            ],
          ),
        ),
      ),
      if (map)
        pin(
          l: 16,
          r: 16,
          t: 252,
          c: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < rows.length && i < 3; i++) kmRow(i),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (var i = 3; i < rows.length; i++) kmRow(i)],
                ),
              ),
            ],
          ),
        )
      else
        pin(
          l: 16,
          r: 16,
          t: 194,
          c: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 0; i < rows.length; i++) kmRow(i)],
          ),
        ),
      pin(
        l: 16,
        r: 16,
        t: 322,
        c: Container(
          padding: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _rule)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(child: fit(hero(f.km, 36, 12, h: 1))),
              Flexible(child: fit(Text(f.time, style: faceStyle(36, h: 1)))),
              Flexible(child: fit(hero(f.pace, 36, 12, h: 1, label: '/KM'))),
            ],
          ),
        ),
      ),
      pin(
        l: 16,
        r: 16,
        b: 15,
        c: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            txt(f.date, 11, w: w6, ls: 1.3, c: RunFaceTokens.cream72),
            txt(f.rarity, 11, ls: 2.2, c: _amber),
          ],
        ),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.f, {this.map = false});

  final RunFace f;
  final bool map;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(5),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: _ink),
      child: Stack(
        children: [
          pin(
            l: 10,
            r: 10,
            t: 4,
            c: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [txt('3I RUN', 17), txt(f.when, 12, ls: 1.5)],
            ),
          ),
          pin(l: 0, r: 0, t: 27, h: 9, c: _stripes(9)),
          if (map)
            pin(
              l: 8,
              r: 8,
              t: 42,
              h: 122,
              c: FaceMap(
                f,
                dark: false,
                route: _red,
                padding: const EdgeInsets.all(10),
                radius: 4,
              ),
            )
          else ...[
            pin(
              l: 0,
              w: 56,
              t: 42,
              h: 74,
              c: Center(child: txt('A', 56, h: 1)),
            ),
            pin(
              l: 56,
              t: 48,
              w: 132,
              h: 62,
              c: _window(width: 132, height: 62, spool: 44, inset: 7, top: 8),
            ),
            pin(
              r: 0,
              w: 56,
              t: 42,
              h: 74,
              c: Center(
                child: routeOrChart(
                  f,
                  routeSize: 46,
                  routeStroke: 12,
                  chartWidth: 44,
                  chartHeight: 26,
                  color: _red,
                  chartStroke: 2.4,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Trapezoid extends CustomClipper<Path> {
  const _Trapezoid();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * 0.07, 0)
    ..lineTo(size.width * 0.93, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_Trapezoid old) => false;
}
