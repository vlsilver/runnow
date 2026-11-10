import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _ink = RunFaceTokens.blueprintInk;
const _blue = RunFaceTokens.blueprintBlue;
const _white = RunFaceTokens.blueprintWhite;

Widget _cell(String label, Widget value, {bool first = false}) => Expanded(
  child: Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    decoration: BoxDecoration(
      border: first ? null : const Border(left: BorderSide(color: _ink)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        txt(label, 9, w: w7, ls: 1.2),
        Expanded(child: fit(value)),
      ],
    ),
  ),
);

Widget _foot(String text, {bool first = false, bool heavy = false}) => Expanded(
  child: Container(
    padding: const EdgeInsets.only(left: 8),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      border: Border(
        top: const BorderSide(color: _ink),
        left: first ? BorderSide.none : const BorderSide(color: _ink),
      ),
    ),
    child: txt(text, 12, w: heavy ? w8 : w7, ls: heavy ? 1 : 0),
  ),
);

Widget _strip(RunFace f, String a, String b, String c) => Container(
  decoration: const BoxDecoration(
    color: _blue,
    border: Border(top: BorderSide(color: _ink, width: 1.5)),
  ),
  child: Column(
    children: [
      SizedBox(
        height: 51,
        child: Row(
          children: [
            _cell('QUÃNG ĐƯỜNG', hero(f.km, 30, 13, h: 1, ls: 0), first: true),
            _cell('THỜI GIAN', Text(f.time, style: faceStyle(30, h: 1))),
            _cell('PACE /KM', Text(f.pace, style: faceStyle(30, h: 1))),
          ],
        ),
      ),
      Expanded(
        child: Row(
          children: [_foot(a, first: true), _foot(b), _foot(c, heavy: true)],
        ),
      ),
    ],
  ),
);

Widget blueprintFront(RunFace f, RunCardTextLayout t) => faceBox(
  bg: _blue,
  ink: _ink,
  children: [
    pin(
      l: 12,
      t: 12,
      r: 12,
      b: 12,
      c: artOf(f, route: t == RunCardTextLayout.top ? (0.35, 0.85) : null),
    ),
    pin(
      l: 12,
      t: 12,
      r: 12,
      b: 12,
      c: const CustomPaint(painter: _Grid(0.26, 0.1)),
    ),
    pin(
      l: 12,
      t: 12,
      r: 12,
      b: 12,
      c: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.5)),
      ),
    ),
    ...switch (t) {
      RunCardTextLayout.full => [
        badgeAt(f, l: 20, t: 20),
        stampAt(f, r: 20, t: 20),
        pin(
          l: 12,
          r: 12,
          b: 12,
          h: 84,
          c: _strip(f, f.name, '${f.owner} · ${f.clock}', f.rarity),
        ),
      ],
      RunCardTextLayout.top => [
        badgeAt(f, l: 20, t: 112),
        stampAt(f, r: 20, t: 112),
        pin(
          l: 12,
          r: 12,
          t: 12,
          h: 92,
          c: Container(
            decoration: const BoxDecoration(
              color: _blue,
              border: Border(bottom: BorderSide(color: _ink, width: 1.5)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 148,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: fit(
                      hero(f.km, 80, 16, h: 0.92),
                      a: Alignment.center,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: _ink)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        txt(f.name, 22, h: 1),
                        fit(
                          Text(
                            '${f.pace} /km · ${f.time}',
                            style: faceStyle(14, w: w7),
                          ),
                        ),
                        txt(f.rarity, 11, ls: 1.2),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      RunCardTextLayout.compact => [
        badgeAt(f, l: 20, t: 20),
        stampAt(f, r: 20, t: 20),
        pin(
          r: 12,
          b: 12,
          w: 124,
          h: 56,
          c: Container(
            padding: const EdgeInsets.fromLTRB(9, 3, 9, 3),
            decoration: const BoxDecoration(
              color: _blue,
              border: Border(
                top: BorderSide(color: _ink, width: 1.5),
                left: BorderSide(color: _ink, width: 1.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fit(hero(f.km, 34, 14, h: 1))),
                txt(f.rarity, 10, ls: 1.3),
              ],
            ),
          ),
        ),
      ],
    },
  ],
);

Widget blueprintBack(RunFace f, {bool map = false}) => faceBox(
  bg: _blue,
  ink: _ink,
  children: [
    if (map)
      pin(
        l: 12,
        t: 12,
        r: 12,
        b: 12,
        c: FaceMap(
          f,
          dark: true,
          route: null,
          // Khớp ô fitRunRoute của _RoutePlan, tính trong khung cách mép 12.
          padding: const EdgeInsets.fromLTRB(41, 60, 57, 110),
          maxZoom: 22,
          tileFilter: faceMapWash(_ink, dark: true, strength: 0.55),
          creditAt: Alignment.topRight,
          creditPadding: const EdgeInsets.fromLTRB(5, 5, 6, 3),
        ),
      ),
    const CustomPaint(painter: _Grid(0.16, 0.07)),
    pin(
      l: 12,
      t: 12,
      r: 12,
      b: 12,
      c: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.5)),
      ),
    ),
    pin(
      l: 22,
      t: 20,
      r: 22,
      c: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [txt('3I RUN', 11, ls: 2.2), txt(f.when, 25, h: 1)],
      ),
    ),
    CustomPaint(painter: f.hasRoute ? _RoutePlan(f) : _PaceSheet(f)),
    pin(
      l: 12,
      r: 12,
      b: 12,
      h: 84,
      c: _strip(f, f.date, '${f.owner} · ${f.clock}', f.rarity),
    ),
  ],
);

class _Grid extends CustomPainter {
  const _Grid(this.major, this.minor);

  final double major;
  final double minor;

  @override
  void paint(Canvas canvas, Size size) {
    void lines(double step, double alpha) {
      final paint = Paint()
        ..color = _ink.withValues(alpha: alpha)
        ..strokeWidth = 1;
      for (var x = 0.5; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = 0.5; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }

    lines(20, minor);
    lines(100, major);
  }

  @override
  bool shouldRepaint(_Grid old) => false;
}

void _arrowHead(Canvas canvas, Offset tip, Offset direction) {
  final side = Offset(-direction.dy, direction.dx) * 2.5;
  final back = tip + direction * 7;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + side.dx, back.dy + side.dy)
      ..lineTo(back.dx - side.dx, back.dy - side.dy)
      ..close(),
    Paint()..color = _ink,
  );
}

String _kmText(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} KM';

/// Đường chạy như mặt bằng kỹ thuật: mốc từng km và kích thước thật.
class _RoutePlan extends CustomPainter {
  const _RoutePlan(this.f);

  final RunFace f;

  @override
  void paint(Canvas canvas, Size size) {
    final points = fitRunRoute(f.route, const Rect.fromLTRB(53, 72, 231, 298));
    if (points.isEmpty) return;
    final box = boundsOf(points);
    final span = routeSpanKm(f.route);
    final thin = Paint()
      ..color = _ink
      ..strokeWidth = 0.75;
    const dimY = 312.0, dimX = 250.0;
    canvas
      ..drawLine(Offset(box.left, dimY), Offset(box.right, dimY), thin)
      ..drawLine(Offset(box.left, dimY - 7), Offset(box.left, dimY + 4), thin)
      ..drawLine(Offset(box.right, dimY - 7), Offset(box.right, dimY + 4), thin)
      ..drawLine(Offset(dimX, box.top), Offset(dimX, box.bottom), thin)
      ..drawLine(Offset(dimX - 6, box.top), Offset(dimX + 6, box.top), thin)
      ..drawLine(
        Offset(dimX - 6, box.bottom),
        Offset(dimX + 6, box.bottom),
        thin,
      );
    _arrowHead(canvas, Offset(box.left, dimY), const Offset(1, 0));
    _arrowHead(canvas, Offset(box.right, dimY), const Offset(-1, 0));
    _arrowHead(canvas, Offset(dimX, box.top), const Offset(0, 1));
    _arrowHead(canvas, Offset(dimX, box.bottom), const Offset(0, -1));
    final plate = Paint()..color = _blue;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(box.center.dx, dimY),
        width: 44,
        height: 14,
      ),
      plate,
    );
    paintLabel(
      canvas,
      _kmText(span.width),
      Offset(box.center.dx, dimY + 7),
      11,
      _ink,
    );
    canvas
      ..drawRect(
        Rect.fromCenter(
          center: Offset(dimX, box.center.dy),
          width: 14,
          height: 44,
        ),
        plate,
      )
      ..save()
      ..translate(dimX + 6, box.center.dy)
      ..rotate(-1.5707963);
    paintLabel(canvas, _kmText(span.height), Offset.zero, 11, _ink);
    canvas
      ..restore()
      ..drawPath(polyline(points), strokePaint(_white, 2.4));
    final stroke = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final mark in routeKmMarks(f.route, points)) {
      canvas
        ..drawCircle(mark.at, 3.2, plate)
        ..drawCircle(mark.at, 3.2, stroke);
      final out = mark.at.dx < box.center.dx ? -11.0 : 11.0;
      paintLabel(canvas, '${mark.km}', mark.at + Offset(out, 6), 10, _ink);
    }
    final start = points.first;
    canvas
      ..drawCircle(start, 6, stroke..strokeWidth = 1)
      ..drawLine(
        start - const Offset(10, 0),
        start + const Offset(10, 0),
        stroke,
      )
      ..drawLine(
        start - const Offset(0, 10),
        start + const Offset(0, 10),
        stroke,
      );
  }

  @override
  bool shouldRepaint(_RoutePlan old) => !identical(old.f.card, f.card);
}

/// Không có GPS thì mặt sau là biểu đồ pace, có đường trung bình và trục km.
class _PaceSheet extends CustomPainter {
  const _PaceSheet(this.f);

  final RunFace f;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(22, 72);
    const width = 256.0;
    const chart = Rect.fromLTRB(0, 42, width, 176);
    final series = f.series;
    final points = paceLine(series, chart);
    const axis = 184.0;
    if (points.isNotEmpty) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      curveThroughPoints(line, points);
      canvas
        ..drawPath(
          Path.from(line)
            ..lineTo(width, axis)
            ..lineTo(0, axis)
            ..close(),
          Paint()..color = _ink.withValues(alpha: 0.14),
        )
        ..drawPath(line, strokePaint(_white, 2.4));
      final fastest = series.indexOf(series.reduce((a, b) => a < b ? a : b));
      final best = points[fastest];
      canvas
        ..drawCircle(best, 3.4, Paint()..color = _blue)
        ..drawCircle(
          best,
          3.4,
          Paint()
            ..color = _white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3,
        );
      paintLabel(
        canvas,
        facePace(series[fastest]),
        best + Offset(best.dx > width - 40 ? -8 : 8, -6),
        11,
        _ink,
        anchor: best.dx > width - 40 ? 1 : 0,
      );
      final slow = series.reduce((a, b) => a > b ? a : b);
      final fast = series[fastest];
      final average = f.averagePace;
      if (average != null && slow > fast) {
        final y =
            chart.top +
            chart.height * ((average - fast) / (slow - fast)).clamp(0.0, 1.0);
        final dash = Paint()
          ..color = _ink
          ..strokeWidth = 0.8;
        for (var x = 0.0; x < width; x += 7) {
          canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
        }
        paintLabel(
          canvas,
          'TB ${f.pace}',
          Offset(4, y - 3),
          11,
          _ink,
          anchor: 0,
        );
      }
    }
    final thin = Paint()
      ..color = _ink
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(0.5, axis), const Offset(255.5, axis), thin);
    final rows = f.rows(6);
    final step = rows.isEmpty ? width : width / rows.length;
    for (var i = 0; i <= rows.length; i++) {
      final x = (i * step).clamp(0.5, 255.5);
      final edge = i == 0 || i == rows.length;
      canvas.drawLine(Offset(x, axis), Offset(x, axis + (edge ? 10 : 6)), thin);
    }
    for (final (i, row) in rows.indexed) {
      paintLabel(canvas, row.km, Offset((i + 0.5) * step, axis + 21), 10, _ink);
    }
    canvas.drawLine(const Offset(0.5, 222), const Offset(255.5, 222), thin);
    _arrowHead(canvas, const Offset(0.5, 222), const Offset(1, 0));
    _arrowHead(canvas, const Offset(255.5, 222), const Offset(-1, 0));
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(128, 222), width: 44, height: 14),
      Paint()..color = _blue,
    );
    paintLabel(canvas, '${f.km} KM', const Offset(128, 229), 11, _ink);
  }

  @override
  bool shouldRepaint(_PaceSheet old) => !identical(old.f.card, f.card);
}
