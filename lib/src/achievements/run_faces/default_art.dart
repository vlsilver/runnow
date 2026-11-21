import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_edit.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

typedef _T = RunFaceTokens;

/// Nền mặc định của [set] khi thẻ chưa vẽ tranh: cùng chất liệu với mặt sau
/// của bộ, đường chạy vẽ theo nét của bộ đó. Null là bộ theo bộ màu thẻ, giữ
/// nền đường chạy màu bậc.
Widget? runSetArt(RunCardSet set, List<LatLng> points) {
  final paint = _painters[set];
  if (paint == null) return null;
  return LayoutBuilder(
    builder: (context, constraints) {
      final box = RunRouteBand.boxIn(context, constraints.biggest);
      final edit = RouteEdit.of(context);
      return editableRouteArt(
        context,
        box,
        CustomPaint(
          painter: _SetArt(
            paint,
            edit?.hidden ?? false ? const [] : points,
            box,
            edit?.color,
          ),
          child: const SizedBox.expand(),
        ),
      );
    },
  );
}

/// [brand] vẽ dấu 3i và người chạy mờ bằng màu đưa vào; gọi sau khi vẽ nền,
/// trước khi vẽ đường chạy.
typedef _Paint =
    void Function(
      Canvas canvas,
      Size size,
      List<Offset> route,
      void Function(Color color) brand,
      Color? ink,
    );

const _painters = <RunCardSet, _Paint>{
  RunCardSet.blueprint: _blueprint,
  RunCardSet.city: _city,
  RunCardSet.cassette: _cassette,
  RunCardSet.constellation: _constellation,
  RunCardSet.blocks: _blocks,
  RunCardSet.stopwatch: _stopwatch,
  RunCardSet.flipBoard: _flipBoard,
  RunCardSet.bib: _bib,
  RunCardSet.finish: _finish,
  RunCardSet.paperMap: _paperMap,
  RunCardSet.receipt: _receipt,
  RunCardSet.medal: _medal,
  RunCardSet.iron: _iron,
};

class _SetArt extends CustomPainter {
  const _SetArt(this.draw, this.points, this.box, this.ink);

  final _Paint draw;
  final List<LatLng> points;
  final Rect box;

  /// Màu nét đường chạy chủ thẻ chọn; null là màu của bộ.
  final Color? ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    draw(
      canvas,
      size,
      fitRunRoute(points, box),
      (color) => paintRunBrand(canvas, box, color),
      ink,
    );
  }

  @override
  bool shouldRepaint(_SetArt old) =>
      old.draw != draw ||
      !identical(old.points, points) ||
      old.box != box ||
      old.ink != ink;
}

// ------------------------------------------------------------ dùng chung

Paint _fill(Color color) => Paint()..color = color;

void _wash(Canvas canvas, Size size, Gradient gradient) {
  final whole = Offset.zero & size;
  canvas.drawRect(whole, Paint()..shader = gradient.createShader(whole));
}

void _line(Canvas canvas, List<Offset> route, Color color, double width) {
  if (route.isEmpty) return;
  canvas.drawPath(polyline(route), strokePaint(color, width));
}

/// Quầng sáng quanh đường chạy, cho các bộ nền đêm.
void _glow(Canvas canvas, List<Offset> route, Color color, double width) {
  if (route.isEmpty) return;
  canvas.drawPath(
    polyline(route),
    strokePaint(color, width)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
  );
}

/// [count] điểm cách đều theo chiều dài đường, kể cả hai đầu.
List<Offset> _along(List<Offset> route, int count) {
  if (route.isEmpty) return const [];
  final metric = polyline(route).computeMetrics().first;
  return [
    for (var i = 0; i < count; i++)
      metric.getTangentForOffset(metric.length * i / (count - 1))!.position,
  ];
}

/// Sao rải cố định theo [seed], để thẻ vẽ lại không nhấp nháy.
void _starField(Canvas canvas, Size size, int seed, int count, Color color) {
  final random = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final at = Offset(
      random.nextDouble() * size.width,
      random.nextDouble() * size.height,
    );
    final alpha = 0.25 + random.nextDouble() * 0.6;
    canvas.drawCircle(
      at,
      0.5 + random.nextDouble() * 0.9,
      _fill(color.withValues(alpha: alpha)),
    );
  }
}

void _star4(Canvas canvas, Offset c, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final radius = i.isEven ? r : r * 0.28;
    final a = i * math.pi / 4 - math.pi / 2;
    final p = c + Offset(math.cos(a), math.sin(a)) * radius;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  canvas.drawPath(path..close(), _fill(color));
}

/// Dấu nhận diện nằm chìm dưới đường chạy: một người đang chạy và chữ 3i, vẽ
/// trong [box] là vùng đường chạy của mặt thẻ.
void paintRunBrand(Canvas canvas, Rect box, Color color) {
  if (box.isEmpty) return;
  // Người chạy: khung 100x100, hướng sang phải, nét tròn đầu như dấu 3i.
  final side = math.min(box.height, box.width * 1.1);
  final runner = Rect.fromCenter(
    center: box.center + Offset(box.width * 0.12, 0),
    width: side,
    height: side,
  );
  canvas
    ..save()
    ..translate(runner.left, runner.top)
    ..scale(side / 100);
  // Gom vào một layer để chỗ các nét chồng nhau không đậm lên.
  canvas.saveLayer(const Rect.fromLTWH(0, 0, 100, 100), Paint());
  final solid = strokePaint(color, 9);
  canvas
    ..drawCircle(const Offset(64, 13), 9, _fill(color))
    ..drawPath(
      Path()
        ..moveTo(57, 31)
        ..lineTo(46, 56),
      strokePaint(color, 12),
    )
    ..drawPath(
      Path()
        ..moveTo(56, 33)
        ..lineTo(70, 44)
        ..lineTo(83, 37),
      solid,
    )
    ..drawPath(
      Path()
        ..moveTo(56, 33)
        ..lineTo(40, 38)
        ..lineTo(30, 51),
      solid,
    )
    ..drawPath(
      Path()
        ..moveTo(46, 56)
        ..lineTo(63, 66)
        ..lineTo(59, 88),
      solid,
    )
    ..drawPath(
      Path()
        ..moveTo(46, 56)
        ..lineTo(34, 72)
        ..lineTo(14, 73),
      solid,
    )
    ..drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..blendMode = BlendMode.dstIn,
    )
    ..restore()
    ..restore();

  // Chữ 3i theo dấu thương hiệu (khung 512), đặt ở góc dưới trái vùng đường.
  final mark = side * 0.3;
  canvas
    ..save()
    ..translate(box.left + box.width * 0.04, box.bottom - mark * 0.98)
    ..scale(mark / 240)
    ..translate(-130, -135);
  final thick = strokePaint(color.withValues(alpha: 0.24), 48);
  canvas
    ..drawPath(
      Path()
        ..addArc(
          Rect.fromCircle(center: const Offset(200, 203), radius: 44),
          math.pi,
          math.pi * 1.5,
        )
        ..addArc(
          Rect.fromCircle(center: const Offset(200, 295), radius: 51),
          -math.pi / 2,
          math.pi * 1.5,
        ),
      thick,
    )
    ..drawCircle(
      const Offset(354, 178),
      24,
      _fill(color.withValues(alpha: 0.24)),
    )
    ..drawLine(
      const Offset(340, 240),
      const Offset(323, 328),
      strokePaint(color.withValues(alpha: 0.24), 46),
    )
    ..restore();
}

// ------------------------------------------------------------ từng bộ

/// Bản vẽ: giấy xanh kẻ ô, đường chạy nét trắng, mốc đầu và tâm ngắm ở đích.
void _blueprint(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const RadialGradient(
      center: Alignment(0, -0.2),
      radius: 1,
      colors: [_T.blueprintGlow, _T.blueprintBlue],
    ),
  );
  void grid(double step, double alpha) {
    final paint = Paint()
      ..color = _T.blueprintInk.withValues(alpha: alpha)
      ..strokeWidth = 1;
    for (var x = 0.5; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.5; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  grid(20, 0.09);
  grid(100, 0.22);
  brand(_T.blueprintInk);
  if (route.isEmpty) return;
  final line = ink ?? _T.blueprintWhite;
  _line(canvas, route, line, 2.2);
  final thin = strokePaint(line, 1.2);
  for (final p in _along(route, 5).skip(1).take(3)) {
    canvas
      ..drawCircle(p, 3.2, _fill(_T.blueprintBlue))
      ..drawCircle(p, 3.2, thin);
  }
  final end = route.last;
  canvas
    ..drawCircle(route.first, 4, _fill(line))
    ..drawCircle(end, 7, _fill(_T.blueprintBlue))
    ..drawCircle(end, 7, thin)
    ..drawLine(end - const Offset(11, 0), end + const Offset(11, 0), thin)
    ..drawLine(end - const Offset(0, 11), end + const Offset(0, 11), thin);
}

/// Thành phố: trời chạng vạng, trăng và sao, đường chạy là vệt đèn vàng.
void _city(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_T.duskNight, _T.duskMid, _T.duskLow],
      stops: [0, 0.62, 1],
    ),
  );
  _starField(canvas, Size(size.width, size.height * 0.6), 7, 34, _T.sunCream);
  final moon = Offset(size.width * 0.8, size.height * 0.13);
  final r = size.shortestSide * 0.075;
  canvas
    ..drawCircle(
      moon,
      r * 1.9,
      _fill(_T.sunGlow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    )
    ..drawCircle(moon, r, _fill(_T.sunCream));
  brand(_T.sunCream);
  if (route.isEmpty) return;
  final line = ink ?? _T.cityGold;
  _glow(canvas, route, line.withValues(alpha: 0.55), 7);
  _line(canvas, route, line, 2.6);
  canvas
    ..drawCircle(route.first, 4, _fill(_T.cityInk))
    ..drawCircle(route.last, 5.5, _fill(line))
    ..drawCircle(route.last, 5.5, strokePaint(_T.cityInk, 1.6));
}

/// Cassette: mặt máy tối có khe loa, ba vạch màu chéo, đường chạy màu nhãn băng.
void _cassette(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.cassetteDeck));
  final slot = Paint()
    ..color = _T.cassetteDeckLine.withValues(alpha: 0.55)
    ..strokeWidth = 1;
  for (var y = 7.5; y < size.height; y += 9) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), slot);
  }
  canvas
    ..save()
    ..translate(size.width / 2, size.height * 0.46)
    ..rotate(-0.42);
  final long = size.longestSide * 1.6;
  const stripes = [_T.cassetteRed, _T.cassetteAmber, _T.cassetteTeal];
  final band = size.shortestSide * 0.06;
  for (final (i, color) in stripes.indexed) {
    canvas.drawRect(
      Rect.fromLTWH(-long / 2, (i - 1.5) * band, long, band),
      _fill(color.withValues(alpha: 0.9)),
    );
  }
  canvas.restore();
  brand(_T.cassettePaper);
  if (route.isEmpty) return;
  final line = ink ?? _T.cassettePaper;
  _line(canvas, route, _T.cassetteShell, 6.5);
  _line(canvas, route, line, 3);
  canvas
    ..drawCircle(route.first, 4.5, _fill(line))
    ..drawCircle(route.last, 6, _fill(_T.cassetteRed))
    ..drawCircle(route.last, 6, strokePaint(line, 2));
}

/// Chòm sao: trời đêm, đường chạy nối các ngôi sao như một chòm.
void _constellation(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const RadialGradient(
      center: Alignment(0, -0.15),
      radius: 0.95,
      colors: [_T.skyTop, _T.constellationNight],
    ),
  );
  _starField(canvas, size, 11, 70, _T.constellationBright);
  brand(_T.constellationBright);
  if (route.isEmpty) return;
  final line = ink ?? _T.constellationGold;
  final line2 = ink ?? _T.constellationBright;
  _line(canvas, route, line.withValues(alpha: 0.5), 1.1);
  final stars = _along(route, 9);
  for (final (i, p) in stars.indexed) {
    final last = i == stars.length - 1;
    canvas.drawCircle(
      p,
      last ? 11 : 6,
      _fill(line.withValues(alpha: 0.22))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    _star4(canvas, p, last ? 9 : (i.isEven ? 6 : 4.5), line2);
  }
}

/// Khối chữ: mảng màu phẳng, đường chạy nét kem dày.
/// Nền đen, một khối đỏ vuông góc trên, đường chạy trắng.
void _iron(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.ironRed));
  brand(_T.ironRedDeep);
  if (route.isEmpty) return;
  final line = ink ?? _T.ironCoal;
  _line(canvas, route, line, 6);
  canvas
    ..drawRect(
      Rect.fromCenter(center: route.first, width: 12, height: 12),
      _fill(line),
    )
    ..drawRect(
      Rect.fromCenter(center: route.last, width: 14, height: 14),
      _fill(_T.ironPaper),
    );
}

void _blocks(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.blocksBlue));
  final r = size.shortestSide * 0.62;
  canvas
    ..drawCircle(
      Offset(size.width, size.height * 0.08),
      r,
      _fill(_T.blocksCoal),
    )
    ..drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width * 0.34, size.height),
      _fill(_T.blocksBlueDeep),
    );
  brand(_T.blocksCream);
  if (route.isEmpty) return;
  final line = ink ?? _T.blocksCream;
  _line(canvas, route, line, 5);
  canvas
    ..drawCircle(route.first, 6, _fill(_T.blocksCoal))
    ..drawCircle(route.first, 6, strokePaint(line, 3))
    ..drawRect(
      Rect.fromCenter(center: route.last, width: 13, height: 13),
      _fill(line),
    );
}

/// Đồng hồ: mặt số tối có các vòng khắc, đường chạy sáng như kim.
void _stopwatch(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const RadialGradient(radius: 0.75, colors: [_T.dialTop, _T.stopwatchDisc]),
  );
  final c = size.center(Offset.zero);
  final ring = strokePaint(_T.stopwatchSteel.withValues(alpha: 0.13), 1);
  for (final k in const [0.16, 0.3, 0.44]) {
    canvas.drawCircle(c, size.shortestSide * k, ring);
  }
  final far = size.longestSide;
  canvas
    ..drawLine(c - Offset(far, 0), c + Offset(far, 0), ring)
    ..drawLine(c - Offset(0, far), c + Offset(0, far), ring);
  brand(_T.stopwatchSteel);
  if (route.isEmpty) return;
  final line = ink ?? _T.stopwatchWhite;
  _glow(canvas, route, _T.stopwatchSoft.withValues(alpha: 0.35), 6);
  _line(canvas, route, line, 2.6);
  canvas
    ..drawCircle(route.first, 4, _fill(_T.stopwatchDisc))
    ..drawCircle(route.first, 4, strokePaint(line, 2))
    ..drawCircle(route.last, 5.5, _fill(_T.stopwatchAlert));
}

/// Bảng lật: bảng ô lật trống, đường chạy là hàng chấm đèn hổ phách.
void _flipBoard(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.flipboardHinge));
  const w = 27.0, h = 37.0, gap = 3.0;
  final cols = (size.width / (w + gap)).ceil();
  final left = (size.width - cols * (w + gap) + gap) / 2;
  for (var y = gap; y < size.height; y += h + gap) {
    for (var i = 0; i < cols; i++) {
      final tile = Rect.fromLTWH(left + i * (w + gap), y, w, h);
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(tile, const Radius.circular(3)),
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_T.flapTop, _T.flapBottom],
            ).createShader(tile),
        )
        ..drawLine(
          tile.centerLeft,
          tile.centerRight,
          Paint()
            ..color = _T.flipboardHinge
            ..strokeWidth = 1.2,
        );
    }
  }
  brand(_T.flipboardAmber);
  if (route.isEmpty) return;
  final line = ink ?? _T.flipboardAmber;
  final length = polyline(route).computeMetrics().first.length;
  final dots = _along(route, math.max(12, (length / 9).round()));
  for (final (i, p) in dots.indexed) {
    final last = i == dots.length - 1;
    canvas
      ..drawCircle(
        p,
        last ? 9 : 5,
        _fill(line.withValues(alpha: 0.28))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      )
      ..drawCircle(p, last ? 5 : 2.4, _fill(line));
  }
}

/// Số áo: mặt đường nhựa với các làn chạy cong, đường chạy sơn trắng.
void _bib(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_T.graphite, _T.bibCoal],
    ),
  );
  final centre = Offset(-size.width * 0.25, size.height * 1.05);
  final lane = strokePaint(_T.bibPaper.withValues(alpha: 0.1), 2);
  for (var i = 0; i < 9; i++) {
    canvas.drawCircle(centre, size.width * (0.5 + i * 0.17), lane);
  }
  brand(_T.bibPaper);
  if (route.isEmpty) return;
  final line = ink ?? _T.bibPaper;
  _line(canvas, route, line, 3);
  canvas
    ..drawCircle(route.first, 5, _fill(_T.bibCoal))
    ..drawCircle(route.first, 5, strokePaint(line, 2.4))
    ..drawCircle(route.last, 6, _fill(line));
}

/// Băng đích: mặt sân đỏ gạch kẻ làn, đường chạy trắng, đích ô cờ.
void _finish(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  _wash(
    canvas,
    size,
    const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_T.brickLight, _T.brick],
    ),
  );
  canvas
    ..save()
    ..translate(size.width / 2, size.height / 2)
    ..rotate(-0.21);
  final long = size.longestSide * 1.5;
  final lane = Paint()
    ..color = _T.finishWhite.withValues(alpha: 0.22)
    ..strokeWidth = 1.6;
  final step = size.shortestSide * 0.19;
  for (var y = -long / 2; y < long / 2; y += step) {
    canvas.drawLine(Offset(-long / 2, y), Offset(long / 2, y), lane);
  }
  canvas.restore();
  brand(_T.finishWhite);
  if (route.isEmpty) return;
  final line = ink ?? _T.finishWhite;
  _line(canvas, route, _T.brickDeep.withValues(alpha: 0.55), 6.5);
  _line(canvas, route, line, 3);
  canvas.drawCircle(route.first, 4.5, _fill(line));
  const cell = 4.0;
  final flag = Rect.fromCenter(center: route.last, width: 16, height: 16);
  canvas.drawRect(flag.inflate(1.5), _fill(_T.finishCoal));
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      canvas.drawRect(
        Rect.fromLTWH(flag.left + c * cell, flag.top + r * cell, cell, cell),
        _fill((r + c).isEven ? _T.finishWhite : _T.finishCoal),
      );
    }
  }
}

/// Bản đồ: giấy ngả vàng có đường đồng mức và một nhánh sông, đường chạy mực đỏ.
void _paperMap(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.mapPaper));
  final contour = strokePaint(_T.paperInk.withValues(alpha: 0.13), 1);
  final hill = Offset(size.width * 0.3, size.height * 0.28);
  for (var i = 1; i <= 7; i++) {
    canvas.drawOval(
      Rect.fromCenter(
        center: hill + Offset(i * 4.0, i * 3.0),
        width: size.width * 0.17 * i,
        height: size.height * 0.11 * i,
      ),
      contour,
    );
  }
  canvas.drawPath(
    Path()
      ..moveTo(-10, size.height * 0.58)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.5,
        size.width * 0.55,
        size.height * 0.86,
        size.width + 10,
        size.height * 0.72,
      ),
    strokePaint(_T.paperRiver, size.shortestSide * 0.035),
  );
  final fold = Paint()
    ..color = _T.mapShadow.withValues(alpha: 0.16)
    ..strokeWidth = 1;
  canvas
    ..drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      fold,
    )
    ..drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      fold,
    );
  brand(_T.paperInk);
  if (route.isEmpty) return;
  final line = ink ?? _T.paperRed;
  _line(canvas, route, _T.mapPaper, 6);
  _line(canvas, route, line, 3);
  canvas
    ..drawCircle(route.first, 4.5, _fill(_T.mapPaper))
    ..drawCircle(route.first, 4.5, strokePaint(line, 2.2))
    ..drawCircle(route.last, 6, _fill(line))
    ..drawCircle(route.last, 2.2, _fill(_T.mapPaper));
}

/// Biên lai: giấy in nhiệt, nền chấm li ti, đường chạy in mực đen.
void _receipt(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  canvas.drawRect(Offset.zero & size, _fill(_T.receiptTint));
  final dot = _fill(_T.receiptCoal.withValues(alpha: 0.14));
  var odd = false;
  for (var y = 5.0; y < size.height; y += 7) {
    for (var x = odd ? 8.5 : 5.0; x < size.width; x += 7) {
      canvas.drawCircle(Offset(x, y), 0.9, dot);
    }
    odd = !odd;
  }
  brand(_T.receiptCoal);
  if (route.isEmpty) return;
  final line = ink ?? _T.receiptCoal;
  _line(canvas, route, _T.receiptTint, 7);
  _line(canvas, route, line, 3);
  canvas
    ..drawCircle(route.first, 4.5, _fill(_T.receiptTint))
    ..drawCircle(route.first, 4.5, strokePaint(line, 2.2))
    ..drawCircle(route.last, 6, _fill(line));
}

/// Huy chương: mặt kim loại tiện tròn, đường chạy dập chìm.
void _medal(
  Canvas canvas,
  Size size,
  List<Offset> route,
  void Function(Color) brand,
  Color? ink,
) {
  final whole = Offset.zero & size;
  canvas.drawRect(
    whole,
    Paint()
      ..shader = ui.Gradient.sweep(
        size.center(Offset.zero),
        const [
          _T.gaugeLight,
          _T.gaugeDark,
          _T.medalMid,
          _T.medalEdge,
          _T.gaugeLight,
          _T.gaugeDark,
          _T.gaugeLight,
        ],
        const [0, 0.17, 0.33, 0.5, 0.67, 0.84, 1],
      ),
  );
  final c = size.center(Offset.zero);
  final groove = strokePaint(_T.medalCoal.withValues(alpha: 0.07), 1);
  for (var r = 8.0; r < size.longestSide * 0.75; r += 8) {
    canvas.drawCircle(c, r, groove);
  }
  brand(_T.medalInk);
  if (route.isEmpty) return;
  final line = ink ?? _T.medalInk;
  canvas
    ..drawPath(
      polyline(route).shift(const Offset(0, 1.6)),
      strokePaint(_T.medalWhite.withValues(alpha: 0.85), 3.4),
    )
    ..drawPath(polyline(route), strokePaint(line, 3.4))
    ..drawCircle(route.first, 4.5, _fill(line))
    ..drawCircle(route.last, 6.5, _fill(line))
    ..drawCircle(route.last, 2.6, _fill(_T.gaugeLight));
}
