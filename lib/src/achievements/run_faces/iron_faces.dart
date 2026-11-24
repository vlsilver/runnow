import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _coal = RunFaceTokens.ironCoal;
const _paper = RunFaceTokens.ironPaper;
const _red = RunFaceTokens.ironRed;
const _muted = RunFaceTokens.ironMuted;
const _line = RunFaceTokens.ironLine;

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

/// Tấm đỏ mặt sau mang số km: số trắng to bên trái, đơn vị và bậc bên phải.
Widget _plate(RunFace f, double height, double size) => SizedBox(
  height: height,
  width: double.infinity,
  child: ColoredBox(
    color: _red,
    child: Stack(
      fit: StackFit.expand,
      children: [
        pin(r: 14, t: 12, c: txt('3I RUN', 12, ls: 2.2, c: _coal)),
        pin(l: 10, b: 10, c: _big(f.km, size, 206, ls: -4)),
        pin(
          r: 14,
          b: 11,
          c: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              txt('KM', 26, h: 1, c: _coal),
              const SizedBox(height: 5),
              txt(f.rarity, 11, ls: 2, c: _coal),
            ],
          ),
        ),
      ],
    ),
  ),
);

/// Dải đen chân thẻ: thời gian trái, pace phải.
Widget _strip(RunFace f) => Container(
  height: 58,
  color: _coal,
  padding: const EdgeInsets.symmetric(horizontal: 14),
  child: Row(
    children: [
      Expanded(
        flex: 5,
        child: slotTime(
          fit(Text(f.time, maxLines: 1, style: faceStyle(40, h: 1))),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox.square(dimension: 10, child: ColoredBox(color: _red)),
      ),
      Expanded(
        flex: 4,
        child: slotPace(
          fit(
            hero(f.pace, 40, 13, h: 1, label: '/KM'),
            a: Alignment.centerRight,
          ),
          a: Alignment.centerRight,
        ),
      ),
    ],
  ),
);

/// Hàng chữ nhỏ: tên app trái, bậc phải.
Widget _labels(RunFace f) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    txt('3I RUN', 13, ls: 2.4),
    txt(f.rarity, 11, ls: 2, c: _coal),
  ],
);

/// Poster đỏ: đường chạy đen, số km trắng to tràn mép, chân đen.
Widget ironFront(RunFace f, RunCardTextLayout t) {
  Widget poster((double, double) route, List<Widget> over) => Expanded(
    child: Stack(
      fit: StackFit.expand,
      children: [
        artOf(f, route: route),
        ...over,
      ],
    ),
  );
  return faceBox(
    bg: _red,
    ink: _paper,
    children: [
      Column(
        children: switch (t) {
          RunCardTextLayout.full => [
            poster(
              (0.06, 0.4),
              [
                badgeAt(f, l: 14, t: 14),
                stampAt(f, r: 14, t: 14),
                pin(l: 14, r: 14, b: 176, c: _labels(f)),
                pin(l: 6, b: 2, c: slotKm(_big(f.km, 220, 288, ls: -8))),
              ],
            ),
            _strip(f),
          ],
          RunCardTextLayout.top => [
            poster(
              (0.68, 0.95),
              [
                pin(l: 14, r: 14, t: 14, c: _labels(f)),
                pin(
                  l: 6,
                  t: 30,
                  c: slotKm(_big(f.km, 220, 288, ls: -8), a: Alignment.topLeft),
                ),
                badgeAt(f, l: 14, b: 14),
                stampAt(f, r: 14, b: 14),
              ],
            ),
            _strip(f),
          ],
          RunCardTextLayout.compact => [
            poster(
              (0.1, 0.9),
              [badgeAt(f, l: 14, t: 14), stampAt(f, r: 14, t: 14)],
            ),
            Container(
              height: 66,
              color: _coal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: slotKm(
                      fit(hero(f.km, 60, 18, h: 1)),
                      a: Alignment.centerLeft,
                    ),
                  ),
                  txt(f.rarity, 11, ls: 2, c: _red),
                ],
              ),
            ),
          ],
        },
      ),
    ],
  );
}

/// Hai ô số cạnh nhau, ngăn bằng một vạch đứng.
Widget _pair(RunFace f, double height, double size) => SizedBox(
  height: height,
  child: Row(
    children: [
      Expanded(child: _cell('THỜI GIAN', f.time, size)),
      const SizedBox(
        width: 2,
        height: double.infinity,
        child: ColoredBox(color: _line),
      ),
      Expanded(child: _cell('PACE /KM', f.pace, size)),
    ],
  ),
);

Widget _cell(String label, String value, double size) => Stack(
  fit: StackFit.expand,
  children: [
    pin(l: 14, t: 9, c: txt(label, 11, ls: 1.6, c: _muted)),
    pin(l: 13, b: 12, c: _big(value, size, 126, ls: 0)),
  ],
);

/// Khối trắng chân mặt sau: tên buổi, ngày giờ, bậc; [lead] là hình bên trái.
Widget _foot(RunFace f, {Widget? lead}) => Expanded(
  child: ColoredBox(
    color: _paper,
    child: _on(
      _coal,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  txt(f.name.toUpperCase(), 17, h: 1.05),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      txt('${f.date} · ${f.when}', 11, w: w6, ls: 1.3),
                      const SizedBox(height: 3),
                      txt(f.rarity, 11, ls: 2.2, c: _red),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget ironBack(RunFace f, {required bool map}) => faceBox(
  bg: _coal,
  ink: _paper,
  children: [
    Column(
      children: map
          ? [
              SizedBox(
                height: 138,
                width: double.infinity,
                child: FaceMap(
                  f,
                  dark: true,
                  route: _red,
                  stroke: 3.2,
                  padding: const EdgeInsets.all(14),
                ),
              ),
              _plate(f, 110, 120),
              _pair(f, 82, 44),
              _foot(f),
            ]
          : [
              _plate(f, 188, 184),
              _pair(f, 94, 48),
              _foot(
                f,
                lead: SizedBox.square(
                  dimension: 86,
                  child: Center(
                    child: routeOrChart(
                      f,
                      routeSize: 86,
                      routeStroke: 9,
                      chartWidth: 86,
                      chartHeight: 44,
                      color: _coal,
                      chartStroke: 3,
                    ),
                  ),
                ),
              ),
            ],
    ),
  ],
);
