import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _ink = RunFaceTokens.paperInk;
const _red = RunFaceTokens.paperRed;
const _sheet = RunFaceTokens.paperSheet;

/// Bản trơn không có sông và đường đồng mức giả, để lót dưới bản đồ thật.
Widget _paper({bool plain = false}) => SvgPicture.asset(
  plain
      ? 'assets/run_card/paper-map-plain.svg'
      : 'assets/run_card/paper-map.svg',
  fit: BoxFit.cover,
  placeholderBuilder: (_) => const ColoredBox(color: RunFaceTokens.mapPaper),
);

class _Outline extends CustomPainter {
  const _Outline();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).inflate(2.5),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_Outline old) => false;
}

Widget _legend(
  Widget inner, {
  EdgeInsets pad = const EdgeInsets.fromLTRB(12, 9, 12, 9),
}) => CustomPaint(
  foregroundPainter: const _Outline(),
  child: Container(
    padding: pad,
    decoration: BoxDecoration(
      color: _sheet,
      border: Border.all(color: _ink, width: 1.5),
    ),
    child: inner,
  ),
);

Widget _legendFull(RunFace f, String footLeft) => Column(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: slotKm(
              fit(hero(f.km, 58, 15, h: 0.92, ls: -0.5)),
              a: Alignment.centerLeft,
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(width: 1, child: ColoredBox(color: _ink)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                slotTime(_pair('THỜI GIAN', f.time)),
                const SizedBox(height: 2),
                slotPace(_pair('PACE /KM', f.pace)),
              ],
            ),
          ),
        ],
      ),
    ),
    Row(
      children: [
        Expanded(child: txt(footLeft, 11, w: w7, ls: 1.3)),
        txt(f.rarity, 11, ls: 2.2, c: _red),
      ],
    ),
  ],
);

Widget _pair(String label, String value) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  crossAxisAlignment: CrossAxisAlignment.baseline,
  textBaseline: TextBaseline.alphabetic,
  children: [
    txt(label, 11, w: w7, ls: 1.2),
    Flexible(child: fit(Text(value, style: faceStyle(22, h: 1)))),
  ],
);

Widget _photo(
  RunFace f, {
  required double left,
  required double top,
  required double width,
  required double height,
  required double degrees,
}) => pin(
  l: left,
  t: top,
  w: width,
  h: height,
  c: Transform.rotate(
    angle: degrees * math.pi / 180,
    child: Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: RunFaceTokens.white,
            boxShadow: [
              BoxShadow(
                color: RunFaceTokens.mapShadow,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
        ),
        pin(l: 6, t: 6, r: 6, b: 6, c: artOf(f)),
        badgeAt(f, l: 14, t: 14),
        stampAt(f, r: 12, t: 12, size: 52),
        pin(
          l: width / 2 - 32,
          t: -9,
          w: 64,
          h: 20,
          c: Transform.rotate(
            angle: -3 * math.pi / 180,
            child: const ColoredBox(color: RunFaceTokens.mapHighlight),
          ),
        ),
      ],
    ),
  ),
);

Widget paperMapFront(RunFace f, RunCardTextLayout t) {
  final foot = '${f.name} · ${f.when}';
  return faceBox(
    bg: RunFaceTokens.mapPaper,
    ink: _ink,
    children: [
      _paper(),
      ...switch (t) {
        RunCardTextLayout.full => [
          _photo(f, left: 26, top: 24, width: 248, height: 276, degrees: -2),
          pin(l: 14, r: 14, b: 14, h: 96, c: _legend(_legendFull(f, foot))),
        ],
        RunCardTextLayout.top => [
          pin(l: 14, r: 14, t: 14, h: 96, c: _legend(_legendFull(f, foot))),
          _photo(f, left: 26, top: 126, width: 248, height: 276, degrees: 2),
        ],
        RunCardTextLayout.compact => [
          _photo(f, left: 18, top: 18, width: 264, height: 346, degrees: -1.5),
          pin(
            r: 14,
            b: 14,
            w: 132,
            h: 56,
            c: _legend(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: slotKm(
                      fit(hero(f.km, 30, 13, h: 1)),
                      a: Alignment.centerLeft,
                    ),
                  ),
                  txt(f.rarity, 10, ls: 1.6, c: _red),
                ],
              ),
              pad: const EdgeInsets.fromLTRB(10, 3, 10, 3),
            ),
          ),
        ],
      },
    ],
  );
}

/// Đường chạy đỏ trên giấy, cờ ở điểm xuất phát và thước tỉ lệ thật.
class _PaperRoute extends CustomPainter {
  const _PaperRoute(this.f);

  final RunFace f;

  @override
  void paint(Canvas canvas, Size size) {
    final points = fitRunRoute(f.route, const Rect.fromLTRB(36, 72, 264, 284));
    if (points.isEmpty) return;
    canvas.drawPath(polyline(points), strokePaint(_red, 3.6));
    final s = points.first;
    canvas
      ..drawLine(
        s + const Offset(0, 2),
        s - const Offset(0, 24),
        strokePaint(_ink, 1.6),
      )
      ..drawRect(
        Rect.fromLTWH(s.dx, s.dy - 24, 18, 12),
        Paint()..color = _sheet,
      )
      ..drawRect(
        Rect.fromLTWH(s.dx, s.dy - 24, 18, 12),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    final dark = Paint()..color = _ink;
    for (final (x, y) in const [(0, 0), (12, 0), (6, 4), (0, 8), (12, 8)]) {
      canvas.drawRect(Rect.fromLTWH(s.dx + x, s.dy - 24 + y, 6, 4), dark);
    }
  }

  @override
  bool shouldRepaint(_PaperRoute old) => !identical(old.f.card, f.card);
}

/// Thước 1 km đúng tỉ lệ hình; đường quá ngắn hay quá dài thì đổi bước.
({double width, String label}) _scaleBar(RunFace f) {
  final points = fitRunRoute(f.route, const Rect.fromLTRB(36, 72, 264, 284));
  final box = boundsOf(points);
  final span = routeSpanKm(f.route);
  final perKm = span.width >= span.height
      ? box.width / math.max(span.width, 0.001)
      : box.height / math.max(span.height, 0.001);
  for (final (km, label) in const [
    (0.5, '500 M'),
    (1.0, '1 KM'),
    (2.0, '2 KM'),
    (5.0, '5 KM'),
    (10.0, '10 KM'),
  ]) {
    if (perKm * km >= 44) return (width: perKm * km, label: label);
  }
  return (width: perKm * 20, label: '20 KM');
}

Widget paperMapBack(RunFace f, {bool map = false}) {
  final rows = f.rows(6);
  return faceBox(
    bg: RunFaceTokens.mapPaper,
    ink: _ink,
    children: [
      _paper(plain: f.hasRoute),
      if (f.hasRoute)
        FaceMap(
          f,
          dark: false,
          route: null,
          // Khớp ô fitRunRoute của _PaperRoute trên khổ 300x420.
          padding: const EdgeInsets.fromLTRB(36, 72, 36, 136),
          maxZoom: 22,
          tileFilter: faceMapWash(_ink, dark: false, strength: map ? 0.6 : 0.3),
          creditAt: Alignment.bottomLeft,
          creditPadding: const EdgeInsets.fromLTRB(16, 0, 5, 115),
        ),
      pin(
        l: 18,
        r: 18,
        t: 16,
        c: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            txt('3I RUN', 11, ls: 2.2, c: _red),
            txt(f.when, 30, h: 1),
          ],
        ),
      ),
      if (f.hasRoute) ...[
        CustomPaint(painter: _PaperRoute(f)),
        Builder(
          builder: (context) {
            final bar = _scaleBar(f);
            return pin(
              r: 18,
              b: 124,
              w: math.min(bar.width, 120),
              c: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(border: Border.all(color: _ink)),
                    child: const Row(
                      children: [
                        Expanded(
                          child: ColoredBox(
                            color: _ink,
                            child: SizedBox.expand(),
                          ),
                        ),
                        Expanded(
                          child: ColoredBox(
                            color: _sheet,
                            child: SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      txt('0', 10, w: w7),
                      txt(bar.label, 10, w: w7),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ] else if (f.series.length > 1)
        pin(
          l: 18,
          r: 18,
          t: 112,
          h: 168,
          c: Column(
            children: [
              SizedBox(
                height: 146,
                width: double.infinity,
                child: FaceChart(f.series, color: _red, stroke: 3.6),
              ),
              const SizedBox(height: 4),
              Container(
                height: 18,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _ink)),
                ),
                child: Row(
                  children: [
                    for (final row in rows)
                      Expanded(
                        child: txt(row.km, 12, w: w7, a: TextAlign.center),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      pin(l: 14, r: 14, b: 14, h: 96, c: _legend(_legendFull(f, f.date))),
    ],
  );
}
