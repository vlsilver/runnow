import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _dark = RunFaceTokens.cityDark;
const _gold = RunFaceTokens.cityGold;
const _dim = RunFaceTokens.cityDim;
const _ink = RunFaceTokens.cityInk;
const _muted = RunFaceTokens.cityMuted;
const _line = RunFaceTokens.cityLine;
const _street = RunFaceTokens.cityStreet;

class _Windows extends CustomPainter {
  const _Windows(this.light);

  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final dark = Paint()..color = _dark;
    canvas
      ..clipRect(box)
      ..drawRect(box, Paint()..color = light);
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, size.height), dark);
    }
    for (var y = size.height - 6; y > -6; y -= 12) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 6), dark);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 5), dark);
  }

  @override
  bool shouldRepaint(_Windows old) => old.light != light;
}

Widget _tower(FaceRow row, double height) => SizedBox(
  height: height,
  child: CustomPaint(painter: _Windows(row.best ? _gold : _dim)),
);

Widget _skyline(RunFace f, double bottom) => pin(
  l: 2,
  r: 2,
  b: bottom,
  c: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (final row in f.rows(6))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: SizedBox(width: 45, child: _tower(row, row.share * 115)),
        ),
    ],
  ),
);

Widget _streetBox(double height, Widget child) => pin(
  l: 0,
  r: 0,
  b: 0,
  h: height,
  c: Container(
    padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
    decoration: const BoxDecoration(
      color: _street,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: child,
  ),
);

Widget cityFront(RunFace f, RunCardTextLayout t) {
  final tag = txt(f.rarity, 11, c: _gold, ls: 2);
  return faceBox(
    bg: RunFaceTokens.duskNight,
    ink: _ink,
    children: [
      artOf(
        f,
        route: switch (t) {
          RunCardTextLayout.full => (0.17, 0.5),
          RunCardTextLayout.top => (0.29, 0.61),
          RunCardTextLayout.compact => null,
        },
      ),
      ...switch (t) {
        RunCardTextLayout.full => [
          badgeAt(f, l: 17, t: 17),
          stampAt(f, r: 14, t: 14),
          _skyline(f, 90),
          _streetBox(
            90,
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(flex: 4, child: fit(hero(f.km, 46, 14, h: 0.95))),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          txt(f.name, 19, w: w7, h: 1.1),
                          fit(
                            Text(
                              '${f.pace} /km · ${f.time}',
                              style: faceStyle(13, w: w6),
                            ),
                            a: Alignment.centerRight,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: txt(
                        '${f.owner} · ${f.clock} · ${f.when}',
                        11,
                        w: w6,
                        ls: 1.2,
                        c: _muted,
                      ),
                    ),
                    tag,
                  ],
                ),
              ],
            ),
          ),
        ],
        RunCardTextLayout.top => [
          pin(
            l: 0,
            r: 0,
            t: 0,
            h: 170,
            c: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    RunFaceTokens.duskNight90,
                    RunFaceTokens.duskNight00,
                  ],
                ),
              ),
            ),
          ),
          pin(
            l: 14,
            t: 12,
            r: 62,
            h: 100,
            c: fit(hero(f.km, 104, 20, h: 0.88, ls: -1), a: Alignment.topLeft),
          ),
          badgeAt(f, r: 17, t: 17),
          stampAt(f, r: 14, t: 90),
          _skyline(f, 46),
          _streetBox(
            46,
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: txt(f.name, 17, w: w7)),
                const SizedBox(width: 8),
                txt('${f.pace} /km · ${f.time}', 14, w: w7),
              ],
            ),
          ),
        ],
        RunCardTextLayout.compact => [
          badgeAt(f, l: 17, t: 17),
          stampAt(f, r: 14, t: 14),
          _skyline(f, 46),
          _streetBox(
            46,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: fit(hero(f.km, 30, 12, h: 1))),
                tag,
              ],
            ),
          ),
        ],
      },
    ],
  );
}

const _stars = [
  (28.0, 96.0),
  (62.0, 124.0),
  (88.0, 34.0),
  (212.0, 28.0),
  (248.0, 60.0),
  (276.0, 34.0),
  (226.0, 104.0),
  (40.0, 170.0),
  (262.0, 118.0),
  (178.0, 22.0),
];

Widget cityBack(RunFace f, {bool map = false}) {
  final rows = f.rows(6);
  Widget crater(double l, double t, double s) => pin(
    l: l,
    t: t,
    w: s,
    h: s,
    c: const DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RunFaceTokens.bronzeGlow,
      ),
    ),
  );
  return faceBox(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        RunFaceTokens.duskNight,
        RunFaceTokens.duskMid,
        RunFaceTokens.duskLow,
      ],
      stops: [0, 0.58, 1],
    ),
    ink: _ink,
    children: [
      if (f.hasRoute && !map)
        FaceMap(
          f,
          dark: true,
          route: null,
          padding: const EdgeInsets.fromLTRB(30, 40, 30, 150),
          maxZoom: 22,
          tileFilter: faceMapWash(_ink, dark: true, strength: 0.38),
          creditAt: Alignment.topRight,
          creditPadding: const EdgeInsets.fromLTRB(0, 16, 16, 0),
        ),
      const CustomPaint(painter: StarField(_stars, 1.1)),
      if (map)
        pin(
          l: 134,
          t: 14,
          w: 152,
          h: 152,
          c: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: RunFaceTokens.sunGlow, blurRadius: 34),
              ],
            ),
            child: FaceMap(
              f,
              dark: false,
              route: RunFaceTokens.bronze,
              padding: const EdgeInsets.all(26),
              circle: true,
              tileFilter: const ColorFilter.mode(
                RunFaceTokens.sunCream,
                BlendMode.multiply,
              ),
              creditAt: Alignment.bottomCenter,
              creditPadding: const EdgeInsets.fromLTRB(32, 0, 32, 14),
            ),
          ),
        )
      else if (!f.hasRoute)
        pin(
          l: 106,
          t: 48,
          w: 88,
          h: 88,
          c: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RunFaceTokens.sunCream,
              boxShadow: [
                BoxShadow(color: RunFaceTokens.sunGlow, blurRadius: 34),
              ],
            ),
            child: Stack(
              children: [
                crater(20, 24, 18),
                crater(50, 44, 13),
                crater(30, 60, 9),
              ],
            ),
          ),
        ),
      pin(
        l: 18,
        t: 16,
        r: 18,
        c: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            txt('3I RUN', 11, ls: 2.2, c: RunFaceTokens.silver),
            txt(f.when, 25, h: 1),
          ],
        ),
      ),
      pin(
        l: 20,
        r: 20,
        b: 94,
        c: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, row) in rows.indexed)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 18,
                        child: fit(
                          Text(
                            row.pace,
                            style: faceStyle(
                              15,
                              h: 1.2,
                              c: row.best ? _gold : _ink,
                            ),
                          ),
                          a: Alignment.center,
                        ),
                      ),
                      _tower(row, row.share * (map ? 110 : 200)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      pin(
        l: 0,
        r: 0,
        b: 0,
        h: 94,
        c: Container(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 13),
          decoration: const BoxDecoration(
            color: _street,
            border: Border(top: BorderSide(color: _line)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  for (final (i, row) in rows.indexed)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: txt(
                          row.km,
                          12,
                          w: w7,
                          c: _muted,
                          a: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: fit(hero(f.km, 32, 11, h: 1))),
                  Flexible(
                    child: fit(Text(f.time, style: faceStyle(32, h: 1))),
                  ),
                  Flexible(
                    child: fit(hero(f.pace, 32, 11, h: 1, label: '/KM')),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  txt(f.date, 10, w: w6, ls: 1.3, c: _muted),
                  txt(f.rarity, 10, ls: 2.2, c: RunFaceTokens.silver),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
