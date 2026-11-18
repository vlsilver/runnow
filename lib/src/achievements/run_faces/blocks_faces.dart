import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _cream = RunFaceTokens.blocksCream;
const _coal = RunFaceTokens.blocksCoal;
const _blue = RunFaceTokens.blocksBlue;
const _white = RunFaceTokens.blocksWhite;

Widget _on(Color color, Widget child) => DefaultTextStyle.merge(
  style: TextStyle(color: color),
  child: child,
);

Widget _big(String value, double size, double width, {double ls = -2}) =>
    SizedBox(
      width: width,
      child: fit(
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          style: faceStyle(size, h: 0.76, ls: ls),
        ),
        a: Alignment.bottomLeft,
      ),
    );

Widget _creamBlock(RunFace f, double height, double size) => SizedBox(
  height: height,
  child: ColoredBox(
    color: _cream,
    child: _on(
      _coal,
      Stack(
        fit: StackFit.expand,
        children: [
          pin(l: 12, b: 6, c: slotKm(_big(f.km, size, 208))),
          pin(
            r: 16,
            t: 12,
            c: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                txt('KM', 24, h: 1),
                const SizedBox(height: 3),
                txt('3I RUN', 11, ls: 2.2),
              ],
            ),
          ),
          pin(r: 16, b: 10, c: txt(f.rarity, 11, ls: 2)),
        ],
      ),
    ),
  ),
);

Widget _band(RunFace f) => Container(
  height: 74,
  color: _blue,
  padding: const EdgeInsets.symmetric(horizontal: 15),
  child: _on(
    _white,
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 5,
          child: slotTime(
            fit(Text(f.time, style: faceStyle(52, h: 1))),
            a: Alignment.centerLeft,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 3,
          child: slotPace(
            fit(
              Text(f.pace, style: faceStyle(52, h: 1)),
              a: Alignment.centerRight,
            ),
            a: Alignment.centerRight,
          ),
        ),
      ],
    ),
  ),
);

Widget blocksFront(RunFace f, RunCardTextLayout t) {
  final art = Expanded(
    child: Stack(
      fit: StackFit.expand,
      children: [artOf(f), badgeAt(f, l: 17, t: 17), stampAt(f, r: 14, t: 14)],
    ),
  );
  return faceBox(
    bg: _coal,
    ink: _cream,
    children: [
      Column(
        children: switch (t) {
          RunCardTextLayout.full => [art, _creamBlock(f, 120, 140), _band(f)],
          RunCardTextLayout.top => [_creamBlock(f, 150, 170), art, _band(f)],
          RunCardTextLayout.compact => [
            art,
            Container(
              height: 70,
              color: _cream,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _on(
                _coal,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: slotKm(
                        fit(hero(f.km, 62, 18, h: 1)),
                        a: Alignment.centerLeft,
                      ),
                    ),
                    txt(f.rarity, 11, ls: 2),
                  ],
                ),
              ),
            ),
          ],
        },
      ),
    ],
  );
}

Widget blocksBack(RunFace f) => faceBox(
  bg: _coal,
  ink: _cream,
  children: [
    Column(
      children: [
        SizedBox(
          height: 168,
          child: ColoredBox(
            color: _cream,
            child: _on(
              _coal,
              Stack(
                fit: StackFit.expand,
                children: [
                  pin(l: 16, t: 13, c: txt('KM', 11, ls: 1.6)),
                  pin(r: 16, t: 13, c: txt('3I RUN', 11, ls: 2.2)),
                  pin(l: 12, b: 6, c: _big(f.km, 180, 276)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 116,
          child: ColoredBox(
            color: _blue,
            child: _on(
              _white,
              Stack(
                fit: StackFit.expand,
                children: [
                  pin(l: 16, t: 9, c: txt('THỜI GIAN', 11, ls: 1.6)),
                  pin(l: 15, b: 9, c: _big(f.time, 88, 270, ls: 0)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              pin(l: 16, t: 9, c: txt('PACE /KM', 11, ls: 1.6)),
              pin(l: 15, t: 26, c: _big(f.pace, 88, 170, ls: 0)),
              pin(
                r: 16,
                t: 16,
                w: 86,
                h: 86,
                c: Center(
                  child: routeOrChart(
                    f,
                    routeSize: 86,
                    routeStroke: 9,
                    chartWidth: 86,
                    chartHeight: 44,
                    color: _cream,
                    chartStroke: 3,
                  ),
                ),
              ),
              pin(
                l: 16,
                r: 16,
                b: 11,
                c: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: txt(
                        '${f.date} · ${f.when}',
                        11,
                        w: w6,
                        ls: 1.3,
                        c: RunFaceTokens.paper76,
                      ),
                    ),
                    txt(f.rarity, 11, ls: 2.2, c: RunFaceTokens.silver),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ],
);

/// Bản đồ chiếm đầu thẻ, ba khối số thấp xuống.
Widget blocksMapBack(RunFace f) => faceBox(
  bg: _coal,
  ink: _cream,
  children: [
    Column(
      children: [
        SizedBox(
          height: 140,
          width: double.infinity,
          child: FaceMap(
            f,
            dark: true,
            route: _cream,
            stroke: 3.2,
            padding: const EdgeInsets.all(14),
          ),
        ),
        SizedBox(
          height: 96,
          child: ColoredBox(
            color: _cream,
            child: _on(
              _coal,
              Stack(
                fit: StackFit.expand,
                children: [
                  pin(l: 12, b: 5, c: _big(f.km, 118, 210)),
                  pin(r: 16, t: 10, c: txt('3I RUN', 11, ls: 2.2)),
                  pin(r: 16, b: 10, c: txt('KM', 11, ls: 1.6)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 92,
          child: ColoredBox(
            color: _blue,
            child: _on(
              _white,
              Stack(
                fit: StackFit.expand,
                children: [
                  pin(l: 16, t: 7, c: txt('THỜI GIAN', 11, ls: 1.6)),
                  pin(l: 15, b: 6, c: _big(f.time, 72, 270, ls: 0)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              pin(l: 16, t: 7, c: txt('PACE /KM', 11, ls: 1.6)),
              pin(l: 15, b: 6, c: _big(f.pace, 72, 170, ls: 0)),
              pin(
                r: 16,
                b: 9,
                c: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    txt(f.rarity, 11, ls: 2.2, c: RunFaceTokens.silver),
                    const SizedBox(height: 3),
                    txt(f.when, 11, w: w6, ls: 1.3, c: RunFaceTokens.paper76),
                    const SizedBox(height: 3),
                    txt(f.date, 11, w: w6, ls: 1.3, c: RunFaceTokens.paper76),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ],
);
