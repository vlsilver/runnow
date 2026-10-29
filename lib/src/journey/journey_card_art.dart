import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/card_scene.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowCardSceneTokens;

/// Màu một chặng: nền trên và dưới, nét đường chạy, sọc dây huy chương.
typedef _Look = ({Color top, Color bottom, Color route, List<Color> ribbon});

const _looks = <String, _Look>{
  'marathon': (
    top: _T.marathonTop,
    bottom: _T.marathonBottom,
    route: _T.marathonRoute,
    ribbon: _T.marathonRibbon,
  ),
  'mont_blanc': (
    top: _T.montBlancTop,
    bottom: _T.montBlancBottom,
    route: _T.montBlancRoute,
    ribbon: _T.montBlancRibbon,
  ),
  'xuyen_viet': (
    top: _T.xuyenVietTop,
    bottom: _T.xuyenVietBottom,
    route: _T.xuyenVietRoute,
    ribbon: _T.xuyenVietRibbon,
  ),
  'dong_nam_a': (
    top: _T.dongNamATop,
    bottom: _T.dongNamABottom,
    route: _T.dongNamARoute,
    ribbon: _T.dongNamARibbon,
  ),
};

/// Chặng lạ mặc màu Marathon.
_Look _look(String campaign) => _looks[campaign] ?? _looks['marathon']!;

/// Đường chạy của cung, null khi cung lạ hoặc chưa tải được. Thẻ khi đó vẽ
/// thiếu đường; lỗi tải hiện ra lúc khoe (xem `showJourneyCardViewer`).
JourneyRoute? _watchRoute(WidgetRef ref, String routeId) {
  final id = parseJourneyRouteId(routeId);
  if (id == null) return null;
  return switch (ref.watch(journeyRouteDetailProvider(id))) {
    AsyncData(:final value) => value,
    _ => null,
  };
}

/// Mặt trước thẻ Hành trình: huy chương về đích kim loại theo bậc, dây đeo
/// màu chặng, đường chạy khắc giữa mặt, [rim] chạy quanh vành. Huy chương nằm
/// phần trên, phần dưới để trống cho tên và số liệu.
class JourneyMedalArt extends ConsumerWidget {
  const JourneyMedalArt({
    super.key,
    required this.campaign,
    required this.routeId,
    required this.tier,
    required this.rim,
  });

  /// Khoá chặng của backend: marathon, mont_blanc, xuyen_viet, dong_nam_a.
  final String campaign;

  /// Cung đã đi, ví dụ hcm_trail.
  final String routeId;
  final GameCardTier tier;

  /// Chữ quanh vành, ví dụ "MARATHON ATHENS · 42 KM".
  final String rim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = _watchRoute(ref, routeId);
    // Thẻ vẽ lại mỗi khung hình khi nghiêng; tranh đứng yên nên tách lớp.
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MedalPainter(
          _look(campaign),
          gameCardTiers[tier]!,
          route == null ? null : _Shape.of(route),
          rim,
        ),
      ),
    );
  }
}

/// Mặt sau thẻ Hành trình: bản đồ đường chạy thật trên nền đường đồng mức,
/// có các mốc, điểm xuất phát, đích và toạ độ.
class JourneyRouteMap extends ConsumerWidget {
  const JourneyRouteMap({
    super.key,
    required this.campaign,
    required this.routeId,
    required this.title,
  });

  final String campaign;
  final String routeId;

  /// Tên chặng in dưới bản đồ.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = _watchRoute(ref, routeId);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _MapPainter(
          _look(campaign),
          route == null ? null : _Shape.of(route),
          title,
          campaign.codeUnits.fold(0, (sum, unit) => sum + unit),
        ),
      ),
    );
  }
}

final _shapes = Expando<_Shape>();

/// Đường chạy chiếu phẳng, kinh độ co theo vĩ độ giữa, đưa về hộp có cạnh
/// dài bằng 1. Provider giữ route suốt phiên nên mỗi route chỉ chiếu một lần.
class _Shape {
  _Shape._(this.points, this.stops, this.names, this.size, this.origin);

  factory _Shape.of(JourneyRoute route) =>
      _shapes[route] ??= _Shape._project(route);

  factory _Shape._project(JourneyRoute route) {
    final all = [
      ...route.points,
      for (final stop in route.milestones) stop.location,
    ];
    if (all.isEmpty) {
      return _Shape._(const [], const [], const [], Size.zero, null);
    }
    final lat0 = all.fold(0.0, (sum, p) => sum + p.latitude) / all.length;
    final k = math.cos(lat0 * math.pi / 180);
    Offset flat(LatLng p) => Offset(p.longitude * k, -p.latitude);
    final first = flat(all.first);
    var left = first.dx, right = first.dx, top = first.dy, bottom = first.dy;
    for (final p in all.map(flat)) {
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
      top = math.min(top, p.dy);
      bottom = math.max(bottom, p.dy);
    }
    final side = math.max(math.max(right - left, bottom - top), 1e-9);
    Offset unit(LatLng p) => (flat(p) - Offset(left, top)) / side;
    return _Shape._(
      [for (final p in route.points) unit(p)],
      [for (final stop in route.milestones) unit(stop.location)],
      [for (final stop in route.milestones) _placeName(stop.name)],
      Size((right - left) / side, (bottom - top) / side),
      route.points.isEmpty ? null : route.points.first,
    );
  }

  final List<Offset> points;
  final List<Offset> stops;
  final List<String> names;

  /// Khung của đường và mốc, cạnh dài bằng 1.
  final Size size;

  /// Điểm xuất phát, in toạ độ ở góc bản đồ.
  final LatLng? origin;

  /// Vòng (Mont Blanc) thì xuất phát và đích trùng nhau.
  bool get loop =>
      stops.length > 1 && (stops.first - stops.last).distance < 0.02;

  /// Hàm đặt điểm chuẩn hoá vào giữa [box], giữ tỉ lệ.
  Offset Function(Offset) fit(Rect box) {
    final scale = math.min(
      box.width / math.max(size.width, 1e-9),
      box.height / math.max(size.height, 1e-9),
    );
    final at = box.center - Offset(size.width, size.height) * scale / 2;
    return (p) => at + p * scale;
  }

  Path path(Offset Function(Offset) to) {
    final path = Path();
    for (final (i, p) in points.indexed) {
      final q = to(p);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    return path;
  }
}

/// "Chamonix (xuất phát)" thành "CHAMONIX".
String _placeName(String name) {
  final cut = name.indexOf(' (');
  return (cut < 0 ? name : name.substring(0, cut)).toUpperCase();
}

/// 38.153 thành "38.15°N".
String _degrees(double value, String positive, String negative) =>
    '${value.abs().toStringAsFixed(2)}°${value < 0 ? negative : positive}';

Paint _fill(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

TextStyle _type(double size, FontWeight weight, {Color? color, Paint? paint}) =>
    TextStyle(
      fontFamily: 'Barlow Condensed',
      fontWeight: weight,
      fontSize: size,
      letterSpacing: size * 0.16,
      height: 1,
      color: color,
      foreground: paint,
    );

TextPainter _label(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout();

/// Nền chặng: dải màu trên xuống và hạt nhiễu.
void _ground(Canvas canvas, Size size, _Look look, int seed) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [look.top, look.bottom],
      ).createShader(rect),
  );
  paintGrain(canvas, size, seed, alpha: 0.04);
}

class _MedalPainter extends CustomPainter {
  const _MedalPainter(this.look, this.metal, this.shape, this.rim);

  final _Look look;
  final GameCardTierStyle metal;
  final _Shape? shape;
  final String rim;

  // Tranh tràn 10 điểm quanh thẻ 300x420, nên vẽ trên khổ 320 ngang; tâm
  // huy chương ở (150, 122) của thẻ, đáy huy chương trên khối chữ.
  static const _width = 320.0;
  static const _center = Offset(160, 132);
  static const _r = 72.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _width;
    canvas
      ..save()
      ..scale(k);
    _ground(canvas, Size(_width, size.height / k), look, 911);
    const c = _center, r = _r;
    final spot = Rect.fromCircle(center: c, radius: r * 1.75);
    canvas.drawCircle(
      c,
      r * 1.75,
      Paint()
        ..shader = RadialGradient(
          colors: [
            look.route.withValues(alpha: 0.22),
            look.route.withValues(alpha: 0),
          ],
        ).createShader(spot),
    );
    _ribbon(canvas, left: false);
    _ribbon(canvas, left: true);
    final medal = Rect.fromCircle(center: c, radius: r);
    LinearGradient metalFrom(Alignment begin, Alignment end) => LinearGradient(
      begin: begin,
      end: end,
      colors: metal.frame,
      stops: metal.frameStops,
    );
    final shine = metalFrom(
      Alignment.topLeft,
      Alignment.bottomRight,
    ).createShader(medal);
    // Lòng huy chương đổ sáng ngược vành nên trông lõm xuống.
    final dish = metalFrom(
      Alignment.bottomRight,
      Alignment.topLeft,
    ).createShader(medal);
    final ink = Color.lerp(
      metal.frame.first,
      _T.journeyShade,
      0.35,
    )!.withValues(alpha: 0.9);
    final field = r - 17;
    canvas
      ..drawCircle(
        c + const Offset(0, -r - 6),
        8,
        Paint()
          ..shader = shine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      )
      ..drawCircle(
        c + const Offset(3, 7),
        r,
        Paint()
          ..color = _T.journeyShade.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawCircle(c, r, Paint()..shader = shine)
      ..drawCircle(
        c,
        r - 4,
        _stroke(_T.journeyShade.withValues(alpha: 0.25), 1),
      )
      ..drawCircle(c, field, Paint()..shader = dish)
      ..drawCircle(
        c,
        field,
        _stroke(_T.journeyShade.withValues(alpha: 0.35), 1.5),
      )
      ..drawCircle(
        c,
        field - 1.5,
        _stroke(_T.medalShine.withValues(alpha: 0.35), 0.8),
      );
    _ringText(canvas, c, r - 8.5, '$rim · VỀ ĐÍCH · ', ink);
    if (shape case final shape? when shape.points.isNotEmpty) {
      final to = shape.fit(Rect.fromCircle(center: c, radius: field * 0.66));
      final path = shape.path(to);
      canvas
        ..save()
        ..translate(0.8, 0.8)
        ..drawPath(path, _stroke(_T.medalShine.withValues(alpha: 0.5), 2.2))
        ..restore()
        ..drawPath(path, _stroke(ink, 2.2));
      if (shape.stops.isNotEmpty) {
        canvas.drawCircle(to(shape.stops.first), 2.6, _fill(ink));
        if (!shape.loop) {
          canvas.drawCircle(to(shape.stops.last), 2.6, _stroke(ink, 1.4));
        }
      }
    }
    canvas.restore();
  }

  /// Một quai dây từ mép trên chui xuống sau huy chương, sọc chạy dọc quai.
  /// Quai trái vẽ sau nên phủ lên quai phải, và tối hơn một chút.
  void _ribbon(Canvas canvas, {required bool left}) {
    const c = _center, r = _r;
    Offset at(double dx, double y) => Offset(c.dx + (left ? -dx : dx), y);
    final outerTop = at(88, -2), innerTop = at(30, -2);
    final outerFoot = at(16, c.dy - r + 42);
    final innerFoot = at(-14, c.dy - r + 30);
    final n = look.ribbon.length;
    Offset top(int j) => Offset.lerp(outerTop, innerTop, j / n)!;
    Offset foot(int j) => Offset.lerp(outerFoot, innerFoot, j / n)!;
    for (final (i, color) in look.ribbon.indexed) {
      final stripe = Path()
        ..moveTo(top(i).dx, top(i).dy)
        ..lineTo(top(i + 1).dx, top(i + 1).dy)
        ..lineTo(foot(i + 1).dx, foot(i + 1).dy)
        ..lineTo(foot(i).dx, foot(i).dy)
        ..close();
      canvas.drawPath(stripe, _fill(color));
      if (left) {
        canvas.drawPath(stripe, _fill(_T.journeyShade.withValues(alpha: 0.18)));
      }
    }
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.look != look ||
      old.metal != metal ||
      old.shape != shape ||
      old.rim != rim;
}

/// [text] lặp quanh vòng bán kính [r], đọc xuôi chiều kim đồng hồ từ đỉnh.
/// Lặp đủ số lần cho kín vòng rồi giãn đều; một lần đã dài hơn vòng thì thu
/// nhỏ chữ.
void _ringText(Canvas canvas, Offset c, double r, String text, Color color) {
  final around = 2 * math.pi * r;
  List<TextPainter> lay(String s, double size) => [
    for (final ch in s.characters)
      _label(ch, _type(size, FontWeight.w800, color: color)),
  ];
  double width(List<TextPainter> glyphs) =>
      glyphs.fold(0.0, (sum, g) => sum + g.width);
  void dispose(List<TextPainter> glyphs) {
    for (final g in glyphs) {
      g.dispose();
    }
  }

  var size = 9.5;
  final probe = lay(text, size);
  final once = width(probe);
  dispose(probe);
  if (once > around) size *= around / once * 0.95;
  final times = math.max(1, (around / (once * size / 9.5)).floor());
  final glyphs = lay(text * times, size);
  final gap = (around - width(glyphs)) / glyphs.length;
  var angle = -math.pi / 2;
  for (final g in glyphs) {
    final step = (g.width + gap) / r;
    final mid = angle + step / 2;
    canvas
      ..save()
      ..translate(c.dx + r * math.cos(mid), c.dy + r * math.sin(mid))
      ..rotate(mid + math.pi / 2);
    g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
    canvas.restore();
    angle += step;
  }
  dispose(glyphs);
}

class _MapPainter extends CustomPainter {
  const _MapPainter(this.look, this.shape, this.title, this.seed);

  final _Look look;
  final _Shape? shape;
  final String title;
  final int seed;

  static const _width = 300.0;

  /// Vùng bản đồ; dưới nó là tên chặng.
  static const _box = Rect.fromLTWH(36, 54, 228, 244);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _width;
    canvas
      ..save()
      ..scale(k);
    final area = Size(_width, size.height / k);
    _ground(canvas, area, look, seed);
    final glow = Rect.fromCircle(center: _box.center, radius: 190);
    canvas.drawRect(
      Offset.zero & area,
      Paint()
        ..shader = RadialGradient(
          colors: [
            look.route.withValues(alpha: 0.14),
            look.route.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    _contours(canvas);
    final grid = _stroke(_T.mapInk.withValues(alpha: 0.04), 1);
    for (var x = 60.0; x < _width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, 320), grid);
    }
    for (var y = 70.0; y < 320; y += 70) {
      canvas.drawLine(Offset(0, y), Offset(_width, y), grid);
    }
    if (shape case final shape? when shape.points.isNotEmpty) {
      _route(canvas, shape);
    }
    _footer(canvas, area);
    canvas.restore();
  }

  /// Ba cụm đường đồng mức lượn, cứ năm vòng thì một vòng đậm.
  void _contours(Canvas canvas) {
    final random = SceneRandom(seed);
    for (var n = 0; n < 3; n++) {
      final center = Offset(40 + random.next() * 220, 40 + random.next() * 240);
      for (var ring = 1; ring <= 7; ring++) {
        final base = ring * 17 + random.next() * 4;
        final points = <Offset>[];
        for (var a = 0; a < 24; a++) {
          final angle = a / 24 * 2 * math.pi;
          final radius =
              base *
              (0.86 +
                  0.14 * math.sin(angle * 3 + n + ring * 0.4) +
                  random.next() * 0.06);
          points.add(
            center +
                Offset(
                  math.cos(angle) * radius * 1.25,
                  math.sin(angle) * radius,
                ),
          );
        }
        Offset mid(int i) => (points[i % 24] + points[(i + 1) % 24]) / 2;
        final path = Path()..moveTo(mid(0).dx, mid(0).dy);
        for (var i = 1; i <= 24; i++) {
          final via = points[i % 24];
          path.quadraticBezierTo(via.dx, via.dy, mid(i).dx, mid(i).dy);
        }
        final strong = ring % 5 == 0;
        canvas.drawPath(
          path..close(),
          _stroke(
            look.route.withValues(alpha: strong ? 0.13 : 0.06),
            strong ? 1 : 0.7,
          ),
        );
      }
    }
  }

  void _route(Canvas canvas, _Shape shape) {
    final to = shape.fit(_box);
    final path = shape.path(to);
    canvas
      ..drawPath(
        path,
        _stroke(look.route.withValues(alpha: 0.5), 7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      )
      ..drawPath(path, _stroke(look.route, 2.2));
    if (shape.stops.isEmpty) return;
    for (final stop in shape.stops.skip(1).take(shape.stops.length - 2)) {
      canvas
        ..drawCircle(to(stop), 2.3, _fill(look.bottom))
        ..drawCircle(to(stop), 2.3, _stroke(look.route, 1.2));
    }
    final start = to(shape.stops.first);
    canvas
      ..drawCircle(start, 5.5, _fill(look.bottom))
      ..drawCircle(start, 5.5, _stroke(look.route, 2));
    _mark(canvas, start, shape.names.first);
    if (shape.loop) return;
    final end = to(shape.stops.last);
    canvas
      ..drawCircle(end, 7, _stroke(look.route.withValues(alpha: 0.5), 1))
      ..drawCircle(end, 4.2, _fill(look.route));
    _mark(canvas, end, shape.names.last);
  }

  /// Tên điểm cạnh chấm, lệch về phía giữa thẻ, viền màu nền cho khỏi lẫn
  /// vào đường.
  void _mark(Canvas canvas, Offset at, String name) {
    final fill = _label(
      name,
      _type(9.5, FontWeight.w700, color: look.route.withValues(alpha: 0.92)),
    );
    final edge = _label(
      name,
      _type(9.5, FontWeight.w700, paint: _stroke(look.bottom, 3)),
    );
    final x = at.dx > _width / 2 ? at.dx - 10 - fill.width : at.dx + 10;
    final offset = Offset(
      x.clamp(18.0, _width - 18 - fill.width),
      at.dy - fill.height / 2,
    );
    edge.paint(canvas, offset);
    fill.paint(canvas, offset);
    edge.dispose();
    fill.dispose();
  }

  void _footer(Canvas canvas, Size area) {
    final shape = this.shape;
    if (shape?.origin case final origin?) {
      final coords = _label(
        '${_degrees(origin.latitude, 'N', 'S')}  '
        '${_degrees(origin.longitude, 'E', 'W')}',
        _type(9, FontWeight.w600, color: _T.mapInk.withValues(alpha: 0.55)),
      );
      coords.paint(canvas, Offset(_width - 22 - coords.width, 24));
      coords.dispose();
    }
    final name = _label(title, _type(22, FontWeight.w800, color: _T.mapInk));
    name.paint(canvas, Offset(22, area.height - 92));
    name.dispose();
    if (shape == null || shape.names.isEmpty) return;
    final stops = shape.names.length;
    final line = shape.loop
        ? 'VÒNG ${shape.names.first} · $stops MỐC'
        : '${shape.names.first} – ${shape.names.last} · $stops MỐC';
    final sub = _label(
      line,
      _type(10, FontWeight.w700, color: look.route.withValues(alpha: 0.85)),
    );
    sub.paint(canvas, Offset(22, area.height - 60));
    sub.dispose();
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.look != look ||
      old.shape != shape ||
      old.title != title ||
      old.seed != seed;
}
