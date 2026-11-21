import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

typedef _K = RunNowContractCardTokens;
const _condensed = 'Barlow Condensed';

/// Cảnh trên mặt trước thẻ Kèo, mỗi cách đo kèo một cảnh.
enum ContractCardScene {
  /// Cổng về đích lúc hoàng hôn.
  distance,

  /// Sân điền kinh, gạch đếm buổi.
  count,

  /// Bảy viên đá trong tuần, ngày chạy được tô.
  days,

  /// Đỉnh núi cắm cờ dưới trăng.
  longRun,

  /// Bản đồ đường đồng mức với tuyến và mốc km.
  route,

  /// Rạng sáng bên hồ, cả nhóm tụ về điểm hẹn.
  meet,

  /// Tờ lịch xé đúng ngày kèo.
  today,
}

/// Tranh phủ cả thẻ: cảnh ở 58% trên, phần dưới là nền tối cho khối chữ của
/// khuôn thẻ. Vẽ theo hệ toạ độ 300 điểm ngang của bản thiết kế rồi phóng
/// theo bề ngang thật.
class ContractCardArt extends StatelessWidget {
  const ContractCardArt({super.key, required this.scene, this.day});

  final ContractCardScene scene;

  /// Ngày in trên tờ lịch của kèo trong ngày, đã đổi sang giờ VN.
  final DateTime? day;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ArtPainter(scene, day),
      child: const SizedBox.expand(),
    ),
  );
}

/// Chiều cao cảnh trong hệ toạ độ thiết kế.
const _sceneHeight = 244.0;

/// Đường vẽ viết theo cú pháp path của SVG, chỉ nhận M, L, C, Q, Z với toạ độ
/// tuyệt đối, đủ cho các hình chép từ bản thiết kế.
Path _svg(String d) {
  final tokens = RegExp(
    r'[MLCQZ]|-?\d*\.?\d+',
  ).allMatches(d).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var command = 'M';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'^[MLCQZ]$').hasMatch(tokens[i])) {
      command = tokens[i++];
      if (command == 'Z') {
        path.close();
        continue;
      }
    }
    switch (command) {
      case 'M':
        path.moveTo(next(), next());
        command = 'L';
      case 'L':
        path.lineTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
    }
  }
  return path;
}

Paint _fill(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _vertical(Rect rect, List<Color> colors, [List<double>? stops]) => Paint()
  ..shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
  ).createShader(rect);

void _glow(Canvas canvas, Offset center, double radius, Color from, Color to) {
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [from, to],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
}

void _dashes(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final metric in path.computeMetrics()) {
    for (var at = 0.0; at < metric.length; at += on + off) {
      canvas.drawPath(metric.extractPath(at, at + on), paint);
    }
  }
}

void _text(Canvas canvas, String text, Offset baselineCenter, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontFamily: _condensed),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.paint(canvas, baselineCenter - Offset(painter.width / 2, baseline));
}

/// Ô bàn cờ 2 màu trong [clip], ô cạnh [cell], canh theo gốc toạ độ.
void _checker(Canvas canvas, Path clip, double cell, Color dark, Color light) {
  final bounds = clip.getBounds();
  canvas
    ..save()
    ..clipPath(clip)
    ..drawRect(bounds, _fill(dark));
  final paint = _fill(light);
  final step = cell * 2;
  for (
    var x = (bounds.left / step).floor() * step;
    x < bounds.right;
    x += step
  ) {
    for (
      var y = (bounds.top / step).floor() * step;
      y < bounds.bottom;
      y += step
    ) {
      canvas
        ..drawRect(Rect.fromLTWH(x, y, cell, cell), paint)
        ..drawRect(Rect.fromLTWH(x + cell, y + cell, cell, cell), paint);
    }
  }
  canvas.restore();
}

void _stars(Canvas canvas, List<(double, double, double)> stars) {
  final paint = _fill(_K.star);
  for (final (x, y, r) in stars) {
    canvas.drawCircle(Offset(x, y), r, paint);
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.scene, this.day);

  final ContractCardScene scene;
  final DateTime? day;

  Color get _panel => switch (scene) {
    ContractCardScene.distance => _K.duskRoad,
    ContractCardScene.count => _K.trackPanel,
    ContractCardScene.days => _K.daysPanel,
    ContractCardScene.longRun => _K.nightPanel,
    ContractCardScene.route => _K.mapPanel,
    ContractCardScene.meet => _K.dawnPanel,
    ContractCardScene.today => _K.calendarInk,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final panel = _panel;
    canvas.drawRect(Offset.zero & size, _fill(panel));
    final scale = size.width / 300;
    canvas
      ..save()
      ..scale(scale)
      ..clipRect(const Rect.fromLTWH(0, 0, 300, _sceneHeight));
    switch (scene) {
      case ContractCardScene.distance:
        _distance(canvas);
      case ContractCardScene.count:
        _count(canvas);
      case ContractCardScene.days:
        _days(canvas);
      case ContractCardScene.longRun:
        _longRun(canvas);
      case ContractCardScene.route:
        _route(canvas);
      case ContractCardScene.meet:
        _meet(canvas);
      case ContractCardScene.today:
        _today(canvas);
    }
    // Cảnh chìm dần vào nền khối chữ.
    const fade = Rect.fromLTWH(0, 196, 300, _sceneHeight - 196);
    canvas
      ..drawRect(fade, _vertical(fade, [panel.withValues(alpha: 0), panel]))
      ..restore();
  }

  void _distance(Canvas canvas) {
    const sky = Rect.fromLTWH(0, 0, 300, _sceneHeight);
    canvas.drawRect(
      sky,
      _vertical(
        sky,
        const [_K.duskTop, _K.duskMid, _K.duskLow, _K.duskHorizon],
        const [0, 0.5, 0.8, 1],
      ),
    );
    _stars(canvas, const [
      (30, 24, 1.2),
      (64, 46, 0.8),
      (110, 18, 1),
      (208, 30, 1.1),
      (250, 58, 0.8),
      (276, 20, 1),
      (180, 52, 0.7),
      (88, 72, 0.7),
    ]);
    _glow(canvas, const Offset(150, 172), 96, _K.duskGlow, _K.duskGlowEdge);
    canvas
      ..drawCircle(const Offset(150, 172), 40, _fill(_K.duskSun))
      ..drawPath(_Paths.duskHillFar, _fill(_K.duskHillFar))
      ..drawPath(_Paths.duskHillNear, _fill(_K.duskHillNear))
      ..drawPath(_Paths.duskRoad, _fill(_K.duskRoad))
      ..drawPath(_Paths.duskRoadEdges, _stroke(_K.duskRoadEdge, 1.2))
      ..drawPath(_Paths.duskDashes, _fill(_K.duskDash))
      ..drawRect(const Rect.fromLTWH(100, 134, 5, 80), _fill(_K.duskPost))
      ..drawRect(const Rect.fromLTWH(195, 134, 5, 80), _fill(_K.duskPost));
    final banner = Path()..addRect(const Rect.fromLTWH(96, 124, 108, 16));
    _checker(canvas, banner, 4, _K.duskRoad, _K.paper);
    canvas
      ..drawPath(banner, _stroke(_K.duskPost, 2))
      ..drawPath(_Paths.duskTape, _fill(_K.flagRed));
    for (final (x, y, w, h, color, turn) in const [
      (126.0, 152.0, 5.0, 2.4, _K.duskDash, 30.0),
      (168.0, 146.0, 5.0, 2.4, _K.confettiTeal, -25.0),
      (140.0, 160.0, 4.0, 2.0, _K.flagRed, 60.0),
      (160.0, 164.0, 4.0, 2.0, _K.duskDash, -50.0),
      (118.0, 170.0, 4.0, 2.0, _K.confettiTeal, 15.0),
      (178.0, 172.0, 4.0, 2.0, _K.paper, 40.0),
    ]) {
      canvas
        ..save()
        ..translate(x + w / 2, y + h / 2)
        ..rotate(turn * math.pi / 180)
        ..drawRect(Rect.fromLTWH(-w / 2, -h / 2, w, h), _fill(color))
        ..restore();
    }
  }

  void _count(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, _sceneHeight),
      _fill(_K.trackField),
    );
    for (var x = 0.0; x < 300; x += 60) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 30, _sceneHeight),
        _fill(_K.trackStripe),
      );
    }
    const center = Offset(150, 122);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 368, height: 216),
      _fill(_K.trackLane),
    );
    for (final (w, h) in const [
      (344.0, 196.0),
      (320.0, 176.0),
      (296.0, 156.0),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: w, height: h),
        _stroke(_K.trackLineSoft, 1),
      );
    }
    final infield = Rect.fromCenter(center: center, width: 272, height: 136);
    canvas
      ..drawOval(infield, _fill(_K.trackInfield))
      ..drawOval(infield, _stroke(_K.trackLine, 1.6));
    _checker(
      canvas,
      Path()..addRect(const Rect.fromLTWH(144, 190, 12, 40)),
      3,
      _K.trackChecker,
      _K.trackLine,
    );
    canvas.drawPath(_Paths.tally, _stroke(_K.trackTally, 5));
  }

  void _days(Canvas canvas) {
    const sky = Rect.fromLTWH(0, 0, 300, _sceneHeight);
    canvas.drawRect(
      sky,
      _vertical(
        sky,
        const [_K.daysTop, _K.daysMid, _K.daysLow],
        const [0, 0.55, 1],
      ),
    );
    _glow(
      canvas,
      const Offset(236, 78),
      70,
      _K.daysSun.withValues(alpha: 0.9),
      _K.daysLow.withValues(alpha: 0),
    );
    canvas
      ..drawCircle(const Offset(236, 78), 26, _fill(_K.daysSun))
      ..drawPath(_Paths.daysHillFar, _fill(_K.daysHillFar))
      ..drawPath(_Paths.daysHillNear, _fill(_K.daysHillNear))
      ..drawPath(_Paths.daysHillFront, _fill(_K.daysPanel));
    _dashes(canvas, _Paths.daysTrail, _stroke(_K.daysLow, 2), 4, 5);
    const stones = [
      Offset(34, 196),
      Offset(72, 182),
      Offset(110, 172),
      Offset(148, 160),
      Offset(186, 148),
      Offset(222, 136),
      Offset(258, 122),
    ];
    const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    for (final (i, stone) in stones.indexed) {
      // Thứ Tư nghỉ: viên đá chỉ có viền.
      if (i == 2) {
        canvas
          ..drawCircle(stone, 12, _fill(_K.daysHillNear))
          ..drawCircle(stone, 12, _stroke(_K.daysStoneMissed, 2));
      } else {
        canvas
          ..drawCircle(stone, 13, _fill(_K.daysLow))
          ..drawPath(
            _svg(
              'M${stone.dx - 6} ${stone.dy} L${stone.dx - 2} ${stone.dy + 4} '
              'L${stone.dx + 6} ${stone.dy - 5}',
            ),
            _stroke(_K.daysPanel, 3),
          );
      }
      _text(
        canvas,
        labels[i],
        stone + const Offset(0, 26),
        const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1,
          color: _K.daysLabel,
        ),
      );
    }
  }

  void _longRun(Canvas canvas) {
    const sky = Rect.fromLTWH(0, 0, 300, _sceneHeight);
    canvas.drawRect(
      sky,
      _vertical(
        sky,
        const [_K.nightTop, _K.nightMid, _K.nightLow],
        const [0, 0.7, 1],
      ),
    );
    _stars(canvas, const [
      (24, 20, 1),
      (120, 14, 1.2),
      (150, 40, 0.7),
      (196, 22, 1),
      (232, 48, 0.8),
      (270, 18, 1.2),
      (288, 70, 0.7),
      (104, 58, 0.8),
      (250, 96, 0.7),
      (20, 84, 0.8),
    ]);
    _glow(
      canvas,
      const Offset(66, 54),
      44,
      _K.moonGlow,
      _K.moon.withValues(alpha: 0),
    );
    canvas
      ..drawCircle(const Offset(66, 54), 16, _fill(_K.moon))
      ..drawPath(_Paths.mountain, _fill(_K.mountain))
      ..drawPath(_Paths.mountainShade, _fill(_K.mountainShade))
      ..drawPath(_Paths.snowCap, _fill(_K.snow));
    _dashes(canvas, _Paths.summitTrail, _stroke(_K.trail, 2), 5, 5);
    canvas
      ..drawLine(
        const Offset(160, 64),
        const Offset(160, 36),
        _stroke(_K.snow, 2),
      )
      ..drawPath(_Paths.summitFlag, _fill(_K.flagRed));
  }

  void _route(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, _sceneHeight),
      _fill(_K.mapField),
    );
    final contour = _stroke(_K.mapContour, 1);
    for (final line in _Paths.contours) {
      canvas.drawPath(line, contour);
    }
    final hill = _stroke(_K.mapHill, 1);
    for (final (w, h) in const [(80.0, 44.0), (48.0, 24.0), (18.0, 8.0)]) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(252, 150), width: w, height: h),
        hill,
      );
    }
    canvas
      ..drawPath(_Paths.routeLoop, _stroke(_K.mapRouteCasing, 10))
      ..drawPath(_Paths.routeLoop, _stroke(_K.mapRoute, 4));
    for (final (at, label) in const [
      (Offset(96, 62), '1'),
      (Offset(190, 86), '2'),
      (Offset(220, 160), '4'),
      (Offset(130, 194), '5'),
    ]) {
      canvas
        ..drawCircle(at, 8, _fill(_K.paper))
        ..drawCircle(at, 8, _stroke(_K.mapRouteCasing, 2));
      _text(
        canvas,
        label,
        at + const Offset(0, 3.5),
        const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 10,
          color: _K.mapRouteCasing,
        ),
      );
    }
    final start = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 176), radius: 11));
    _checker(canvas, start, 3, _K.mapRouteCasing, _K.paper);
    canvas.drawPath(start, _stroke(_K.paper, 2));
  }

  void _meet(Canvas canvas) {
    const sky = Rect.fromLTWH(0, 0, 300, 150);
    canvas
      ..drawRect(
        sky,
        _vertical(
          sky,
          const [_K.dawnTop, _K.dawnMid, _K.dawnLow],
          const [0, 0.55, 1],
        ),
      )
      ..drawCircle(const Offset(104, 150), 26, _fill(_K.dawnSun));
    const lake = Rect.fromLTWH(0, 150, 300, 94);
    canvas
      ..drawRect(lake, _vertical(lake, const [_K.lakeTop, _K.lakeBottom]))
      ..drawPath(_Paths.ripples, _stroke(_K.dawnRipple, 2))
      ..drawPath(_Paths.trees, _fill(_K.shore))
      ..drawPath(_Paths.promenade, _fill(_K.shore));
    // Đồng hồ chỉ giờ hẹn cho có hình, giờ thật in ở dòng loại thẻ.
    const clock = Offset(52, 76);
    canvas
      ..drawCircle(clock, 22, _fill(_K.clockFace))
      ..drawCircle(clock, 22, _stroke(_K.shore, 2))
      ..drawPath(_Paths.clockTicks, _stroke(_K.shore, 1.6))
      ..drawLine(clock, clock + const Offset(-16, 0), _stroke(_K.shore, 2))
      ..drawLine(clock, clock + const Offset(1.6, 11.5), _stroke(_K.shore, 3))
      ..drawCircle(clock, 2.4, _fill(_K.flagRed))
      ..drawPath(_Paths.pin, _fill(_K.meetPin))
      ..drawPath(_Paths.pin, _stroke(_K.shore, 1.5))
      ..drawCircle(const Offset(150, 154), 5, _fill(_K.meetPinDot));
    for (final (at, color, initial) in const [
      (Offset(102, 192), _K.runnerGreen, 'A'),
      (Offset(126, 188), _K.runnerGold, 'M'),
      (Offset(174, 188), _K.runnerBlue, 'H'),
      (Offset(198, 192), _K.runnerCoral, 'T'),
    ]) {
      canvas
        ..drawCircle(at, 10, _fill(color))
        ..drawCircle(at, 10, _stroke(_K.shore, 2));
      _text(
        canvas,
        initial,
        at + const Offset(0, 3.5),
        const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 10,
          color: _K.shore,
        ),
      );
    }
  }

  void _today(Canvas canvas) {
    const sky = Rect.fromLTWH(0, 0, 300, _sceneHeight);
    canvas.drawRect(
      sky,
      _vertical(
        sky,
        const [_K.dayTop, _K.dayMid, _K.dayLow],
        const [0, 0.55, 1],
      ),
    );
    _glow(
      canvas,
      const Offset(150, 116),
      104,
      _K.dayGlow,
      _K.dayGlow.withValues(alpha: 0),
    );
    canvas
      ..drawCircle(const Offset(46, 64), 13, _fill(_K.daySun))
      ..drawPath(_Paths.dayGround, _fill(_K.dayGround))
      ..drawPath(_Paths.dayLanes, _stroke(_K.dayLane, 1.2))
      ..drawLine(
        const Offset(244, 196),
        const Offset(244, 160),
        _stroke(_K.paper, 2),
      )
      ..drawPath(_Paths.dayFlag, _fill(_K.flagRed));
    _text(
      canvas,
      '2K',
      const Offset(255, 170.5),
      const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 7.5,
        color: _K.calendarPage,
      ),
    );
    canvas
      ..save()
      ..translate(150, 112)
      ..rotate(-5 * math.pi / 180)
      ..translate(-150, -112);
    final page = RRect.fromRectAndRadius(
      const Rect.fromLTWH(94, 48, 112, 124),
      const Radius.circular(8),
    );
    final header = RRect.fromRectAndCorners(
      const Rect.fromLTWH(94, 48, 112, 28),
      topLeft: const Radius.circular(8),
      topRight: const Radius.circular(8),
    );
    canvas
      ..drawRRect(page, _fill(_K.calendarPage))
      ..drawRRect(header, _fill(_K.flagRed))
      ..drawRRect(page, _stroke(_K.calendarInk, 2))
      ..drawLine(
        const Offset(94, 76),
        const Offset(206, 76),
        _stroke(_K.calendarInk, 2),
      );
    final day = this.day;
    if (day != null) {
      _text(
        canvas,
        'THÁNG ${day.month}',
        const Offset(150, 67),
        const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 2,
          color: _K.calendarPage,
        ),
      );
      _text(
        canvas,
        day.day.toString().padLeft(2, '0'),
        const Offset(150, 138),
        const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 58,
          color: _K.calendarInk,
        ),
      );
      _text(
        canvas,
        _weekdays[day.weekday - 1],
        const Offset(150, 158),
        TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 2,
          color: _K.calendarInk.withValues(alpha: 0.7),
        ),
      );
    }
    for (final x in const [116.0, 178.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 40, 6, 16),
          const Radius.circular(3),
        ),
        _fill(_K.calendarInk),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.scene != scene || old.day != day;
}

const _weekdays = [
  'THỨ HAI',
  'THỨ BA',
  'THỨ TƯ',
  'THỨ NĂM',
  'THỨ SÁU',
  'THỨ BẢY',
  'CHỦ NHẬT',
];

/// Đường vẽ dựng một lần cho cả phiên.
abstract final class _Paths {
  static final duskHillFar = _svg(
    'M0 168 C50 150 96 166 132 160 C176 152 226 168 300 146 L300 244 '
    'L0 244 Z',
  );
  static final duskHillNear = _svg(
    'M0 196 C64 176 112 192 150 186 C196 180 244 196 300 180 L300 244 '
    'L0 244 Z',
  );
  static final duskRoad = _svg('M142 178 L158 178 L238 244 L62 244 Z');
  static final duskRoadEdges = _svg('M142 178 L62 244 M158 178 L238 244');
  static final duskDashes = _svg(
    'M149.4 184 L150.6 184 L151 190 L149 190 Z M148.8 197 L151.2 197 '
    'L152 208 L148 208 Z M147.8 218 L152.2 218 L153.6 240 L146.4 240 Z',
  );
  static final duskTape = _svg(
    'M105 190 Q122 198 137 209 L133 213 Q120 203 105 196 Z '
    'M195 190 Q178 197 165 205 L168 209 Q181 202 195 196 Z',
  );

  static final tally = _svg(
    'M96 104 L96 142 M106 104 L106 142 M116 104 L116 142 M126 104 L126 142 '
    'M88 138 L134 108 M152 104 L152 142 M162 104 L162 142 M172 104 L172 142 '
    'M182 104 L182 142 M144 138 L190 108 M206 104 L206 142 M216 104 L216 142',
  );

  static final daysHillFar = _svg(
    'M0 150 C60 128 120 150 170 134 C214 120 256 132 300 118 L300 244 '
    'L0 244 Z',
  );
  static final daysHillNear = _svg(
    'M0 182 C70 162 150 186 300 160 L300 244 L0 244 Z',
  );
  static final daysHillFront = _svg(
    'M0 214 C80 198 170 220 300 202 L300 244 L0 244 Z',
  );
  static final daysTrail = _svg(
    'M34 196 L72 182 L110 172 L148 160 L186 148 L222 136 L258 122',
  );

  static final mountain = _svg(
    'M0 212 L70 148 L104 170 L160 64 L214 158 L244 138 L300 194 L300 244 '
    'L0 244 Z',
  );
  static final mountainShade = _svg('M160 64 L214 158 L192 158 L170 108 Z');
  static final snowCap = _svg(
    'M160 64 L143 96 L153 91 L161 101 L170 89 L178 97 Z',
  );
  static final summitTrail = _svg(
    'M62 244 L122 212 L94 194 L142 168 L122 148 L152 118 L160 70',
  );
  static final summitFlag = _svg('M160 36 L184 43 L160 51 Z');

  static final contours = [
    for (final d in const [
      'M-10 40 C60 20 120 60 180 40 C230 24 270 40 310 30',
      'M-10 72 C50 54 110 94 170 74 C230 56 270 78 310 64',
      'M-10 106 C40 94 100 128 160 110 C220 92 262 114 310 100',
      'M-10 142 C60 128 120 158 180 142 C236 128 270 148 310 136',
      'M-10 178 C50 166 120 192 180 178 C230 166 272 182 310 172',
      'M-10 212 C60 200 130 224 190 212 C240 202 276 216 310 208',
    ])
      _svg(d),
  ];
  static final routeLoop = _svg(
    'M60 176 C30 136 44 72 96 62 C144 52 150 96 190 86 C232 76 236 130 '
    '220 160 C204 192 160 178 130 194 C100 208 76 198 60 176 Z',
  );

  static final ripples = _svg(
    'M84 158 L124 158 M90 166 L118 166 M96 174 L112 174',
  );
  static final trees = _svg(
    'M300 150 L300 112 C290 100 278 106 274 116 C266 108 254 114 254 128 '
    'C244 128 240 140 246 146 L240 150 Z',
  );
  static final promenade = _svg(
    'M0 196 C80 184 220 184 300 196 L300 244 L0 244 Z',
  );
  static final clockTicks = _svg(
    'M52 57 L52 61 M52 91 L52 95 M33 76 L37 76 M67 76 L71 76',
  );
  static final pin = _svg(
    'M150 180 C142 168 136 162 136 154 C136 146.3 142.3 140 150 140 '
    'C157.7 140 164 146.3 164 154 C164 162 158 168 150 180 Z',
  );

  static final dayGround = _svg(
    'M0 200 C90 186 210 186 300 200 L300 244 L0 244 Z',
  );
  static final dayLanes = _svg(
    'M0 214 C90 202 210 202 300 214 M0 228 C90 218 210 218 300 228',
  );
  static final dayFlag = _svg('M244 160 L268 166 L244 174 Z');

  static final flagRight = _svg('M164 150 L206 162 L200 192 L156 180 Z');
  static final flagLeft = _svg('M136 150 L94 162 L100 192 L144 180 Z');
  static final ribbon = _svg(
    'M78 266 L222 266 L212 279 L222 292 L78 292 L88 279 Z',
  );
}

/// Một dòng chữ in dưới huy hiệu, [y] là đường chân chữ theo hệ 300×420.
typedef ContractEmblemLine = ({String text, double y, TextStyle style});

/// Huy hiệu cờ đích bắt chéo trong vòng tròn, dải ruy băng và các dòng chữ
/// bên dưới, vẽ theo hệ 300×420 của thẻ rồi phóng theo bề ngang thật. Mặt sau
/// thẻ tô bằng màu của bậc, thẻ úp tô màu bạc.
class ContractCardEmblem extends StatelessWidget {
  const ContractCardEmblem({
    super.key,
    required this.gem,
    required this.ground,
    required this.ribbon,
    required this.lines,
    this.rayAlpha = 0.1,
  });

  /// Màu nét, cờ và ruy băng.
  final Color gem;

  /// Màu lòng vòng tròn, ô tối của cờ và chữ trên ruy băng.
  final Color ground;
  final String ribbon;
  final List<ContractEmblemLine> lines;
  final double rayAlpha;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _EmblemPainter(this),
    child: const SizedBox.expand(),
  );
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.emblem);

  final ContractCardEmblem emblem;

  static const _center = Offset(150, 196);
  static const _arcText = '3I RUN · KÈO CHẠY BỘ';

  @override
  void paint(Canvas canvas, Size size) {
    final gem = emblem.gem;
    final ground = emblem.ground;
    canvas
      ..save()
      ..scale(size.width / 300);
    final ray = _stroke(gem.withValues(alpha: emblem.rayAlpha), 1);
    for (var i = 0; i < 32; i++) {
      final a = i / 32 * 2 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(_center + dir * 92, _center + dir * 230, ray);
    }
    canvas
      ..drawCircle(_center, 86, _stroke(gem.withValues(alpha: 0.6), 0.8))
      ..drawCircle(_center, 80, _fill(ground))
      ..drawCircle(_center, 80, _stroke(gem, 2.2));
    _arc(canvas, gem);
    for (final (from, to, flag) in [
      (const Offset(120, 250), const Offset(164, 150), _Paths.flagRight),
      (const Offset(180, 250), const Offset(136, 150), _Paths.flagLeft),
    ]) {
      canvas.drawLine(from, to, _stroke(gem, 3));
      _checker(canvas, flag, 4, ground, gem);
      canvas.drawPath(flag, _stroke(gem, 1.5));
    }
    canvas.drawPath(_Paths.ribbon, _fill(gem));
    _text(
      canvas,
      emblem.ribbon,
      const Offset(150, 285),
      TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        letterSpacing: 3,
        color: ground,
      ),
    );
    for (final line in emblem.lines) {
      _line(canvas, line);
    }
    canvas.restore();
  }

  /// Chữ chạy theo nửa trên vòng tròn bán kính 64, canh giữa ở đỉnh.
  void _arc(Canvas canvas, Color color) {
    const radius = 64.0;
    const spacing = 3.0;
    final style = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      color: color,
    );
    final glyphs = [
      for (final char in _arcText.characters)
        TextPainter(
          text: TextSpan(text: char, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final total =
        glyphs.fold(0.0, (sum, glyph) => sum + glyph.width + spacing) - spacing;
    var at = -total / 2;
    for (final glyph in glyphs) {
      final angle = -math.pi / 2 + (at + glyph.width / 2) / radius;
      final baseline = glyph.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      canvas
        ..save()
        ..translate(
          _center.dx + radius * math.cos(angle),
          _center.dy + radius * math.sin(angle),
        )
        ..rotate(angle + math.pi / 2);
      glyph.paint(canvas, Offset(-glyph.width / 2, -baseline));
      canvas.restore();
      at += glyph.width + spacing;
    }
  }

  /// Một dòng canh giữa; dài quá bề ngang huy hiệu thì cắt bằng dấu ba chấm.
  void _line(Canvas canvas, ContractEmblemLine line) {
    final painter = TextPainter(
      text: TextSpan(
        text: line.text,
        style: line.style.copyWith(fontFamily: _condensed),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: 260, maxWidth: 260);
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(canvas, Offset(20, line.y - baseline));
  }

  @override
  bool shouldRepaint(_EmblemPainter old) {
    final (a, b) = (old.emblem, emblem);
    return a.gem != b.gem ||
        a.ground != b.ground ||
        a.ribbon != b.ribbon ||
        a.rayAlpha != b.rayAlpha ||
        !listEquals(a.lines, b.lines);
  }
}
