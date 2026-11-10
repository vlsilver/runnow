import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _ink = RunFaceTokens.flipboardInk;
const _hinge = RunFaceTokens.flipboardHinge;
const _label = RunFaceTokens.flipboardLabel;
const _soft = RunFaceTokens.flipboardSoft;
const _fade = RunFaceTokens.flipboardFade;

Widget tile(
  String c,
  double w,
  double h,
  double font, {
  double hinge = 1,
  bool shadow = false,
}) => Container(
  width: w,
  height: h,
  clipBehavior: Clip.hardEdge,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(h < 60 ? 3 : 6),
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [RunFaceTokens.flapTop, RunFaceTokens.flapBottom],
    ),
    boxShadow: shadow
        ? const [
            BoxShadow(
              color: RunFaceTokens.shade60,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ]
        : null,
  ),
  child: Stack(
    alignment: Alignment.center,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: fit(
          Text(c, maxLines: 1, style: faceStyle(font, h: 1)),
          a: Alignment.center,
        ),
      ),
      pin(
        l: 0,
        r: 0,
        t: h / 2 - hinge / 2,
        h: hinge,
        c: const ColoredBox(color: _hinge),
      ),
    ],
  ),
);

Widget flaps(String text, {double w = 26, double h = 38, double f = 30}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (final (i, c) in text.characters.indexed) ...[
      if (i > 0) const SizedBox(width: 3),
      if (c == ':')
        SizedBox(
          width: 8,
          child: Text(
            ':',
            textAlign: TextAlign.center,
            style: faceStyle(f, h: h / f),
          ),
        )
      else
        tile(c, w, h, f),
    ],
  ],
);

/// Ô số lớn của quãng đường: số tự co để con số dài vẫn nằm đủ trên bảng.
Widget heroTiles(
  String km,
  double width, {
  required double digit,
  required double comma,
  required double unit,
  required double height,
  required double font,
  required double unitFont,
  double hinge = 1,
  bool shadow = false,
  bool spread = true,
  double gap = 3,
}) {
  final chars = km.characters.toList();
  final sum =
      chars.fold<double>(0, (t, c) => t + (c == ',' ? comma : digit)) + unit;
  final k = math.min(1.0, (width - gap * chars.length) / sum);
  return Row(
    mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
    mainAxisAlignment: spread
        ? MainAxisAlignment.spaceBetween
        : MainAxisAlignment.start,
    children: [
      for (final (i, c) in [...chars, 'KM'].indexed) ...[
        if (i > 0 && !spread) SizedBox(width: gap),
        tile(
          c,
          (c == 'KM'
                  ? unit
                  : c == ','
                  ? comma
                  : digit) *
              k,
          height,
          (c == 'KM' ? unitFont : font) * k,
          hinge: hinge,
          shadow: shadow,
        ),
      ],
    ],
  );
}

Widget _heroBoard(RunFace f) => heroTiles(
  f.km,
  268,
  digit: 84,
  comma: 34,
  unit: 54,
  height: 112,
  font: 104,
  unitFont: 30,
  hinge: 2,
  shadow: true,
);

Widget _totals(RunFace f) {
  Widget block(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      txt(label, 10, w: w7, ls: 1.4, c: _label),
      const SizedBox(height: 2),
      fit(flaps(value)),
    ],
  );
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Flexible(flex: 7, child: block('THỜI GIAN', f.time)),
      const SizedBox(width: 6),
      Flexible(flex: 4, child: block('PACE /KM', f.pace)),
    ],
  );
}

Widget _line(RunFace f) => Row(
  children: [
    Expanded(
      child: txt(
        '${f.name} · ${f.owner} ${f.clock} · ${f.when}',
        11,
        w: w6,
        ls: 1.1,
        c: RunFaceTokens.paper76,
      ),
    ),
    const SizedBox(width: 6),
    txt(f.rarity, 11, ls: 1.1, c: _soft),
  ],
);

Widget fadeBottom(double height) => pin(
  l: 0,
  r: 0,
  b: 0,
  h: height,
  c: const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [_fade, _fade, RunFaceTokens.shade00],
        stops: [0, 0.42, 1],
      ),
    ),
  ),
);

Widget flipBoardFront(RunFace f, RunCardTextLayout t) => faceBox(
  bg: RunFaceTokens.night,
  ink: _ink,
  children: [
    artOf(
      f,
      route: switch (t) {
        RunCardTextLayout.full => (0.17, 0.49),
        RunCardTextLayout.top => (0.34, 0.76),
        RunCardTextLayout.compact => null,
      },
    ),
    ...switch (t) {
      RunCardTextLayout.full => [
        fadeBottom(240),
        badgeAt(f, l: 17, t: 17),
        stampAt(f, r: 14, t: 14, size: 60),
        pin(
          l: 16,
          r: 16,
          b: 14,
          c: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _heroBoard(f),
              const SizedBox(height: 7),
              _totals(f),
              const SizedBox(height: 7),
              _line(f),
            ],
          ),
        ),
      ],
      RunCardTextLayout.top => [
        fadeBottom(130),
        pin(l: 16, r: 16, t: 14, c: _heroBoard(f)),
        badgeAt(f, l: 17, t: 136),
        stampAt(f, r: 14, t: 134),
        pin(
          l: 16,
          r: 16,
          b: 14,
          c: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_totals(f), const SizedBox(height: 7), _line(f)],
          ),
        ),
      ],
      RunCardTextLayout.compact => [
        fadeBottom(110),
        badgeAt(f, l: 17, t: 17),
        stampAt(f, r: 14, t: 14, size: 60),
        pin(
          l: 16,
          r: 16,
          b: 16,
          c: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              heroTiles(
                f.km,
                190,
                digit: 34,
                comma: 16,
                unit: 34,
                height: 46,
                font: 40,
                unitFont: 18,
                spread: false,
              ),
              txt(f.rarity, 11, ls: 2, c: _soft),
            ],
          ),
        ),
      ],
    },
  ],
);

Widget flipBoardBack(RunFace f, {bool map = false}) {
  Widget row(FaceRow r) {
    final lit = (r.share * 10).round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        tile(r.km, 26, 30, 25),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 10; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                child: SizedBox(
                  width: 10,
                  height: 30,
                  child: ColoredBox(
                    color: i < lit
                        ? (r.best ? RunFaceTokens.white : RunFaceTokens.steel)
                        : RunFaceTokens.charcoal,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          width: 104,
          child: fit(
            flaps(r.pace, w: 20, h: 30, f: 24),
            a: Alignment.centerRight,
          ),
        ),
      ],
    );
  }

  return faceBox(
    bg: RunFaceTokens.night,
    ink: _ink,
    children: [
      if (f.hasRoute && !map)
        FaceMap(
          f,
          dark: true,
          route: null,
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 120),
          maxZoom: 22,
          tileFilter: faceMapWash(_ink, dark: true, strength: 0.4),
          creditAt: Alignment.bottomLeft,
          // Khe trống giữa hai nhãn THỜI GIAN và PACE.
          creditPadding: const EdgeInsets.fromLTRB(90, 0, 0, 76),
        ),
      pin(
        l: 16,
        r: 16,
        t: 13,
        b: 14,
        c: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              height: 66,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  heroTiles(
                    f.km,
                    178,
                    digit: 48,
                    comma: 20,
                    unit: 42,
                    height: 64,
                    font: 58,
                    unitFont: 24,
                    spread: false,
                  ),
                  if (map)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        txt('3I RUN', 11, ls: 2.2, c: _soft),
                        const SizedBox(height: 2),
                        txt(
                          f.when,
                          11,
                          w: w7,
                          ls: 1.4,
                          c: RunFaceTokens.paper76,
                        ),
                      ],
                    )
                  else
                    routeOrChart(
                      f,
                      routeSize: 66,
                      routeStroke: 9,
                      chartWidth: 84,
                      chartHeight: 40,
                      color: f.hasRoute ? RunFaceTokens.white : _soft,
                    ),
                ],
              ),
            ),
            if (map)
              SizedBox(
                height: 214,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FaceMap(
                      f,
                      dark: true,
                      route: RunFaceTokens.white,
                      stroke: 3.2,
                      padding: const EdgeInsets.all(16),
                      radius: 6,
                    ),
                    pin(
                      l: 0,
                      r: 0,
                      t: 107,
                      h: 1,
                      c: const ColoredBox(color: _hinge),
                    ),
                  ],
                ),
              )
            else
              for (final r in f.rows(6)) row(r),
            _totals(f),
            _line(f),
          ],
        ),
      ),
    ],
  );
}
