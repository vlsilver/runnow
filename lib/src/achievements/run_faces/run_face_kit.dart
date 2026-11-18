import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_faces/face_edit.dart';
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/games/game_role_card.dart';
import '../../theme_tokens.dart';

const faceFont = 'Barlow Condensed';
const w8 = FontWeight.w800;
const w7 = FontWeight.w700;
const w6 = FontWeight.w600;

/// Một hàng số liệu theo km sau khi gộp. [share] là độ dài thanh 0,6..1: thanh
/// dài nhất là km nhanh nhất.
class FaceRow {
  const FaceRow(this.km, this.pace, this.seconds, this.share, this.best);

  final String km;
  final String pace;
  final double seconds;
  final double share;
  final bool best;
}

String facePace(double? secondsPerKm) {
  if (secondsPerKm == null || !secondsPerKm.isFinite || secondsPerKm <= 0) {
    return '--';
  }
  final s = secondsPerKm.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Mọi giá trị một mặt thẻ cần, lấy từ thẻ và dữ liệu thẻ đã định dạng.
class RunFace {
  RunFace(this.card, this.data);

  final RunCard card;
  final AchievementCardData data;

  RunCardSnapshot get snap => card.snapshot;
  GameCardTier get tier => card.tier;
  String get km => data.hero;
  String get rarity => gameCardTiers[card.tier]!.label.toUpperCase();
  String get name => data.title;
  String get owner => data.owner;
  String get clock => data.serial;
  String get date => data.date;
  String get when => data.meta.replaceAll(' · ', ' ');
  String get time => formatDuration(snap.movingTimeSeconds);
  double? get averagePace => card.km > 0 && snap.movingTimeSeconds > 0
      ? snap.movingTimeSeconds / card.km
      : null;
  String get pace => facePace(averagePace);
  List<LatLng> get route => snap.route;
  bool get hasRoute =>
      fitRunRoute(route, const Rect.fromLTWH(0, 0, 1, 1)).isNotEmpty;

  late final List<RunCardSplit> _splits = [
    for (final s in snap.splits)
      if (s.distanceMeters >= runCardMinSplitMeters && s.movingTimeSeconds > 0)
        s,
  ];

  String? get bestPace => rows(1 << 16).where((r) => r.best).firstOrNull?.pace;

  /// Thẻ chỉ có chỗ cho [max] hàng: buổi dài hơn thì gộp các km liền nhau, nhãn
  /// là km cuối nhóm, pace là tổng thời gian trên tổng quãng của nhóm.
  List<FaceRow> rows(int max) {
    final n = _splits.length;
    if (n == 0) return const [];
    final count = math.min(n, max);
    final groups = [
      for (var i = 0; i < count; i++)
        (from: i * n ~/ count, to: (i + 1) * n ~/ count),
    ];
    final paces = [
      for (final g in groups)
        _splits
                .sublist(g.from, g.to)
                .fold<double>(0, (sum, s) => sum + s.movingTimeSeconds) /
            _splits
                .sublist(g.from, g.to)
                .fold<double>(0, (sum, s) => sum + s.distanceMeters) *
            1000,
    ];
    final fast = paces.reduce(math.min);
    final slow = paces.reduce(math.max);
    final best = paces.indexOf(fast);
    return [
      for (final (i, g) in groups.indexed)
        FaceRow(
          '${g.to}',
          facePace(paces[i]),
          paces[i],
          slow == fast ? 1.0 : 0.6 + 0.4 * (slow - paces[i]) / (slow - fast),
          i == best,
        ),
    ];
  }

  /// Pace dọc buổi để vẽ khi không có đường chạy.
  List<double> get series {
    final fine = snap.pace?.secondsPerKm.where((p) => p > 0).toList();
    if (fine != null && fine.length > 1) return fine;
    return [for (final r in rows(1 << 16)) r.seconds];
  }

  /// Vòng splits trên huy chương: từng đoạn theo độ dài thật, kể cả đoạn lẻ.
  List<({double share, bool best})> get arcs {
    final total = snap.splits.fold<double>(0, (t, s) => t + s.distanceMeters);
    if (total <= 0) return const [];
    final fastest = _splits.isEmpty
        ? null
        : _splits.reduce(
            (a, b) =>
                b.movingTimeSeconds / b.distanceMeters <
                    a.movingTimeSeconds / a.distanceMeters
                ? b
                : a,
          );
    return [
      for (final s in snap.splits)
        (share: s.distanceMeters / total, best: identical(s, fastest)),
    ];
  }
}

double _segmentKm(LatLng a, LatLng b) {
  const kmPerDegree = 111.32;
  final dy = (b.latitude - a.latitude) * kmPerDegree;
  final dx =
      (b.longitude - a.longitude) *
      kmPerDegree *
      math.cos((a.latitude + b.latitude) * math.pi / 360);
  return math.sqrt(dx * dx + dy * dy);
}

/// Bề ngang và bề dọc thật của đường chạy.
({double width, double height}) routeSpanKm(List<LatLng> route) {
  final lats = route.map((p) => p.latitude);
  final lngs = route.map((p) => p.longitude);
  final south = LatLng(lats.reduce(math.min), lngs.reduce(math.min));
  return (
    width: _segmentKm(south, LatLng(south.latitude, lngs.reduce(math.max))),
    height: _segmentKm(south, LatLng(lats.reduce(math.max), south.longitude)),
  );
}

/// Điểm trên hình đường chạy ứng với mỗi km. Đường dài thì giãn bước để còn
/// tối đa [max] mốc.
List<({Offset at, int km})> routeKmMarks(
  List<LatLng> route,
  List<Offset> fitted, {
  int max = 8,
}) {
  var total = 0.0;
  for (var i = 1; i < route.length; i++) {
    total += _segmentKm(route[i - 1], route[i]);
  }
  final step = math.max(1, (total / max).ceil());
  final marks = <({Offset at, int km})>[];
  var next = step.toDouble();
  var walked = 0.0;
  for (var i = 1; i < route.length; i++) {
    final length = _segmentKm(route[i - 1], route[i]);
    while (length > 0 && walked + length >= next && next < total) {
      marks.add((
        at: Offset.lerp(fitted[i - 1], fitted[i], (next - walked) / length)!,
        km: next.round(),
      ));
      next += step;
    }
    walked += length;
  }
  return marks;
}

Rect boundsOf(List<Offset> points) {
  var box = Rect.fromPoints(points.first, points.first);
  for (final p in points) {
    box = box.expandToInclude(Rect.fromPoints(p, p));
  }
  return box;
}

TextStyle faceStyle(
  double size, {
  FontWeight w = w8,
  Color? c,
  double ls = 0,
  double? h,
}) => TextStyle(
  fontFamily: faceFont,
  fontSize: size,
  fontWeight: w,
  color: c,
  letterSpacing: ls,
  height: h,
  leadingDistribution: TextLeadingDistribution.even,
  decoration: TextDecoration.none,
);

/// Một dòng chữ; dài quá thì cắt, dùng cho tên buổi.
Widget txt(
  String s,
  double size, {
  FontWeight w = w8,
  Color? c,
  double ls = 0,
  double? h,
  TextAlign? a,
}) => Text(
  s,
  maxLines: 1,
  softWrap: false,
  overflow: TextOverflow.ellipsis,
  textAlign: a,
  style: faceStyle(size, w: w, c: c, ls: ls, h: h),
);

/// Khe chủ thẻ chỉnh được cho số km, thời gian, pace (cả nhãn đi kèm). [a] là
/// góc mà bố cục của bộ bám vào: phần to ra từ góc đó và dời theo góc đó.
///
/// Khe ôm sát phần, kể cả khi bộ đặt phần trong ô rộng hơn (Expanded): ô vẫn
/// giữ cỡ, phần đứng ở góc [a] của ô như cũ, còn khung chọn và chỗ lưu là của
/// đúng con số chứ không phải cả ô.
Widget slotKm(Widget child, {Alignment a = Alignment.bottomLeft}) =>
    _slot(CardPart.km, a, child);

Widget slotTime(Widget child, {Alignment a = Alignment.centerLeft}) =>
    _slot(CardPart.time, a, child);

Widget slotPace(Widget child, {Alignment a = Alignment.centerLeft}) =>
    _slot(CardPart.pace, a, child);

Widget _slot(CardPart part, Alignment a, Widget child) => Align(
  alignment: a,
  widthFactor: 1,
  heightFactor: 1,
  child: PartSlot(part, anchor: a, child: child),
);

/// Giữ cỡ thiết kế, chỉ thu nhỏ khi con số dài hơn chỗ có.
Widget fit(Widget child, {Alignment a = Alignment.centerLeft}) =>
    FittedBox(fit: BoxFit.scaleDown, alignment: a, child: child);

Widget baseline(List<Widget> children, {double gap = 3}) => Row(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.baseline,
  textBaseline: TextBaseline.alphabetic,
  children: [
    for (final (i, c) in children.indexed) ...[
      if (i > 0) SizedBox(width: gap),
      c,
    ],
  ],
);

/// Số to kèm đơn vị trên cùng một đường chân chữ.
Widget hero(
  String value,
  double size,
  double unit, {
  double? h,
  double ls = 0,
  String label = 'KM',
  Color? c,
}) => baseline([
  Text(
    value,
    maxLines: 1,
    softWrap: false,
    style: faceStyle(size, c: c, h: h, ls: ls),
  ),
  Text(label, maxLines: 1, style: faceStyle(unit, c: c)),
]);

Positioned pin({
  double? l,
  double? t,
  double? r,
  double? b,
  double? w,
  double? h,
  required Widget c,
}) => Positioned(
  left: l,
  top: t,
  right: r,
  bottom: b,
  width: w,
  height: h,
  child: c,
);

/// Khung một mặt thẻ, ruột vẽ theo toạ độ 300x420.
Widget faceBox({
  Color? bg,
  Gradient? gradient,
  required Color ink,
  required List<Widget> children,
}) => DecoratedBox(
  decoration: BoxDecoration(color: bg, gradient: gradient),
  child: DefaultTextStyle(
    style: faceStyle(14, c: ink),
    child: Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: children,
    ),
  ),
);

/// Dải dọc mà đường chạy được vẽ trong tranh, tính theo phần chiều cao tranh.
/// Mỗi kiểu chữ đặt số ở một chỗ, nên kiểu nào che dải mặc định thì tự chọn dải
/// trống của mình.
class RunRouteBand extends InheritedWidget {
  const RunRouteBand({
    super.key,
    required this.top,
    required this.bottom,
    required super.child,
  });

  final double top;
  final double bottom;

  /// Khung vẽ đường chạy trong tranh cỡ [size], đã theo chỗ và cỡ chủ thẻ
  /// chỉnh.
  static Rect boxIn(BuildContext context, Size size) {
    final band = context.dependOnInheritedWidgetOfExactType<RunRouteBand>();
    final box = Rect.fromLTRB(
      size.width * 0.16,
      size.height * (band?.top ?? 0.2),
      size.width * 0.84,
      size.height * (band?.bottom ?? 0.56),
    );
    return RouteEdit.of(context)?.boxIn(box, size) ?? box;
  }

  @override
  bool updateShouldNotify(RunRouteBand old) =>
      old.top != top || old.bottom != bottom;
}

Widget artOf(RunFace f, {(double, double)? route}) {
  final art = ClipRect(child: SizedBox.expand(child: f.data.art));
  if (route == null) return art;
  return RunRouteBand(top: route.$1, bottom: route.$2, child: art);
}

Positioned badgeAt(RunFace f, {double? l, double? t, double? r, double? b}) =>
    pin(
      l: l,
      t: t,
      r: r,
      b: b,
      c: AchievementTierBadge(tier: f.tier),
    );

Positioned stampAt(
  RunFace f, {
  double? r,
  double? t,
  double? b,
  double size = 56,
}) => pin(
  r: r,
  t: t,
  b: b,
  w: size,
  h: size,
  c: FaceStamp(face: f),
);

/// Con dấu tròn đường chạy; thẻ chưa có tranh thì nền đã là đường chạy nên
/// không có dấu.
class FaceStamp extends StatelessWidget {
  const FaceStamp({super.key, required this.face});

  final RunFace face;

  @override
  Widget build(BuildContext context) {
    final stamp = face.data.stamp?.call(context);
    if (stamp == null) return const SizedBox.shrink();
    final skin = RunCardSkin.of(context);
    // Thẻ có tranh thì đường chạy là con dấu: dời, đổi cỡ, ẩn cả con dấu.
    return PartSlot(
      CardPart.route,
      tint: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: skin.stamp,
          border: Border.all(color: skin.accent(face.tier), width: 1.5),
        ),
        child: ClipOval(child: stamp),
      ),
    );
  }
}

/// Đường chạy co vừa ô vuông [size]. Nét [stroke] tính theo khung 244 của
/// thiết kế để ô nhỏ không bị nét đè nhau.
class FaceRoute extends StatelessWidget {
  const FaceRoute(
    this.route, {
    super.key,
    required this.size,
    required this.color,
    required this.stroke,
  });

  final List<LatLng> route;
  final double size;
  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: FaceRoutePainter(route, color, stroke * size / 244),
    ),
  );
}

class FaceRoutePainter extends CustomPainter {
  const FaceRoutePainter(this.route, this.color, this.width);

  final List<LatLng> route;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final points = fitRunRoute(route, (Offset.zero & size).deflate(width));
    if (points.isEmpty) return;
    canvas.drawPath(polyline(points), strokePaint(color, width));
  }

  @override
  bool shouldRepaint(FaceRoutePainter old) =>
      !identical(old.route, route) || old.color != color || old.width != width;
}

Path polyline(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

Paint strokePaint(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Đổi chuỗi pace thành toạ độ trong [box], nhanh hơn thì cao hơn.
List<Offset> paceLine(List<double> series, Rect box) {
  if (series.length < 2) return const [];
  final fast = series.reduce(math.min);
  final slow = series.reduce(math.max);
  final span = slow - fast;
  return [
    for (final (i, p) in series.indexed)
      Offset(
        box.left + box.width * i / (series.length - 1),
        span == 0 ? box.center.dy : box.top + box.height * (p - fast) / span,
      ),
  ];
}

class FaceChart extends StatelessWidget {
  const FaceChart(
    this.series, {
    super.key,
    required this.color,
    this.stroke = 2.6,
    this.fill,
  });

  final List<double> series;
  final Color color;
  final double stroke;
  final Color? fill;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: FaceChartPainter(series, color, stroke, fill));
}

class FaceChartPainter extends CustomPainter {
  const FaceChartPainter(this.series, this.color, this.stroke, this.fill);

  final List<double> series;
  final Color color;
  final double stroke;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final box = (Offset.zero & size).deflate(stroke);
    final points = paceLine(series, box);
    if (points.isEmpty) return;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    curveThroughPoints(line, points);
    if (fill case final fill?) {
      canvas.drawPath(
        Path.from(line)
          ..lineTo(box.right, size.height)
          ..lineTo(box.left, size.height)
          ..close(),
        Paint()..color = fill,
      );
    }
    canvas.drawPath(line, strokePaint(color, stroke));
  }

  @override
  bool shouldRepaint(FaceChartPainter old) =>
      !identical(old.series, series) ||
      old.color != color ||
      old.stroke != stroke ||
      old.fill != fill;
}

/// Đường chạy nếu có, không thì biểu đồ pace, cho ô hình nhỏ trên mặt sau.
Widget routeOrChart(
  RunFace f, {
  required double routeSize,
  required double routeStroke,
  required double chartWidth,
  required double chartHeight,
  required Color color,
  double chartStroke = 2.6,
}) => f.hasRoute
    ? FaceRoute(f.route, size: routeSize, color: color, stroke: routeStroke)
    : SizedBox(
        width: chartWidth,
        height: chartHeight,
        child: FaceChart(f.series, color: color, stroke: chartStroke),
      );

/// Ba cột bằng nhau: số trên, nhãn dưới.
Widget statColumns(
  List<(String, String)> items, {
  double value = 27,
  double label = 10,
  Color? labelColor,
  double ls = 1.2,
  TextAlign? align,
}) => Row(
  children: [
    for (final (v, l) in items)
      Expanded(
        child: Column(
          crossAxisAlignment: align == TextAlign.center
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(
                right: align == TextAlign.center ? 0 : 8,
              ),
              child: SizedBox(
                width: double.infinity,
                child: fit(
                  Text(v, maxLines: 1, style: faceStyle(value, h: 1)),
                  a: align == TextAlign.center
                      ? Alignment.center
                      : Alignment.centerLeft,
                ),
              ),
            ),
            txt(l, label, w: w6, ls: ls, c: labelColor, a: align),
          ],
        ),
      ),
  ],
);

/// Điểm sao nhỏ trải trên nền trời.
class StarField extends CustomPainter {
  const StarField(this.stars, this.radius);

  final List<(double, double)> stars;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = RunFaceTokens.white;
    for (final (x, y) in stars) {
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(StarField old) => false;
}

/// Đường ngang nét đứt.
class DashLine extends StatelessWidget {
  const DashLine({
    super.key,
    required this.color,
    this.width = 1,
    this.dash = 3,
    this.gap = 2,
  });

  final Color color;
  final double width;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: width,
    width: double.infinity,
    child: CustomPaint(painter: _Dash(color, width, dash, gap)),
  );
}

class _Dash extends CustomPainter {
  const _Dash(this.color, this.width, this.dash, this.gap);

  final Color color;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, width / 2),
        Offset(math.min(x + dash, size.width), width / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}

/// Chữ vẽ trực tiếp trên canvas, canh theo [anchor] 0 trái, 0,5 giữa, 1 phải.
void paintLabel(
  Canvas canvas,
  String text,
  Offset at,
  double size,
  Color color, {
  double anchor = 0.5,
  FontWeight w = w7,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: faceStyle(size, w: w, c: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset(at.dx - painter.width * anchor, at.dy - painter.height),
  );
}
