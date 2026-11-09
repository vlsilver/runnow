import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

const _condensed = 'Barlow Condensed';

/// Thẻ chỉ dành cho buổi chạy bộ. Server còn chặn buổi dưới 500 m và buổi
/// trùng; app chỉ dùng hàm này để biết có hiện chỗ lật thẻ không.
bool hasRunCard(ActivitySummary activity) => switch (activity.kind) {
  ActivityKind.run || ActivityKind.trailRun || ActivityKind.virtualRun => true,
  _ => false,
};

const _weekdays = [
  'THỨ HAI',
  'THỨ BA',
  'THỨ TƯ',
  'THỨ NĂM',
  'THỨ SÁU',
  'THỨ BẢY',
  'CHỦ NHẬT',
];

String _dayPart(int hour) {
  if (hour >= 4 && hour < 11) return 'SÁNG';
  if (hour >= 11 && hour < 13) return 'TRƯA';
  if (hour >= 13 && hour < 18) return 'CHIỀU';
  if (hour >= 18 && hour < 22) return 'TỐI';
  return 'ĐÊM';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Số km in trên thẻ: "15,0".
String runCardKm(double km) => km.toStringAsFixed(1).replaceAll('.', ',');

/// Pace m:ss không kèm đơn vị, cho ô số liệu đã có nhãn /KM.
String _pace(double secondsPerKm) {
  if (!secondsPerKm.isFinite || secondsPerKm <= 0) return '--';
  final s = secondsPerKm.round();
  return '${s ~/ 60}:${_two(s % 60)}';
}

/// Dữ liệu thẻ dựng từ snapshot server. Nền là tranh đã vẽ, chưa có tranh thì
/// là đường chạy phát sáng màu bậc. Có tranh thì đường chạy thu về con dấu
/// tròn góc trên. [previewArt] mặc thử một nền chưa vẽ thật, như ảnh ví dụ lúc
/// chọn phong cách.
AchievementCardData runCardData(
  RunCard card, {
  required String owner,
  Widget? previewArt,
}) {
  final snap = card.snapshot;
  final start = (snap.startedAt ?? card.rolledAt ?? DateTime.now()).toLocal();
  final climb = snap.elevationGainMeters?.round() ?? 0;
  final artPath = card.artPath;
  final hasArt = artPath != null || previewArt != null;
  return AchievementCardData(
    tier: card.tier,
    secret: card.secret,
    art:
        previewArt ??
        (artPath == null
            ? RunRouteArt(points: snap.route, tier: card.tier)
            : StoragePhoto(
                path: artPath,
                cacheWidth: 960,
                // Tranh nặng cả MB, giữ đường chạy tới lúc tải xong.
                placeholder: RunRouteArt(points: snap.route, tier: card.tier),
              )),
    stamp: hasArt && snap.route.length > 1
        ? RunRouteStamp(points: snap.route)
        : null,
    backFace: RunCardBack(card: card),
    artFollowsSkin: !hasArt,
    kind: 'BUỔI CHẠY',
    hero: runCardKm(card.km),
    title: snap.name.isEmpty ? 'Buổi chạy' : snap.name,
    owner: owner.toUpperCase(),
    serial: '${_two(start.hour)}:${_two(start.minute)}',
    desc: [
      'Pace ${formatPace(_paceOf(snap.movingTimeSeconds, card.km))}',
      formatDuration(snap.movingTimeSeconds),
      if (climb > 0) 'leo $climb m',
    ].join(' · '),
    meta: '${_weekdays[start.weekday - 1]} · ${_dayPart(start.hour)}',
    date: '${_two(start.day)}.${_two(start.month)}.${start.year}',
  );
}

double? _paceOf(int movingSeconds, double km) =>
    km > 0 && movingSeconds > 0 ? movingSeconds / km : null;

/// Màu phát sáng của bậc ở ngoài thẻ (bảng tỉ lệ), không theo bộ màu thẻ.
Color runCardGlow(GameCardTier tier) => RunCardSkin.classic.glow(tier);

/// Chiếu kinh/vĩ độ lên mặt phẳng rồi đặt giữa [box], giữ đúng tỉ lệ hình
/// đường chạy. Đường chỉ có một điểm hay đứng yên thì trả rỗng.
List<Offset> _fitRoute(List<LatLng> points, Rect box) {
  if (points.length < 2) return const [];
  final lat0 =
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
  final k = math.cos(lat0 * math.pi / 180);
  final xs = [for (final p in points) p.longitude * k];
  final ys = [for (final p in points) -p.latitude];
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  final spanX = maxX - minX, spanY = maxY - minY;
  if (spanX == 0 && spanY == 0) return const [];
  final scale = math.min(
    spanX == 0 ? double.infinity : box.width / spanX,
    spanY == 0 ? double.infinity : box.height / spanY,
  );
  final dx = box.left + (box.width - spanX * scale) / 2;
  final dy = box.top + (box.height - spanY * scale) / 2;
  return [
    for (var i = 0; i < xs.length; i++)
      Offset(dx + (xs[i] - minX) * scale, dy + (ys[i] - minY) * scale),
  ];
}

Path _pathOf(List<Offset> route) {
  final path = Path()..moveTo(route.first.dx, route.first.dy);
  for (final p in route.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..strokeWidth = width
  ..color = color;

/// Nền thẻ vẽ từ đường chạy: đường sáng màu bậc trên nền tối, có điểm xuất
/// phát và điểm về đích. Buổi không có GPS thì chỉ còn nền.
class RunRouteArt extends StatelessWidget {
  const RunRouteArt({super.key, required this.points, required this.tier});

  final List<LatLng> points;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RouteArtPainter(
        points: points,
        tier: tier,
        skin: RunCardSkin.of(context),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _RouteArtPainter extends CustomPainter {
  _RouteArtPainter({
    required this.points,
    required this.tier,
    required this.skin,
  });

  final List<LatLng> points;
  final GameCardTier tier;
  final RunCardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final (field, edge, glow) = skin.routes[tier]!;
    final whole = Offset.zero & size;
    canvas.drawRect(
      whole,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.24),
          radius: 0.9,
          colors: [field, edge],
        ).createShader(whole),
    );

    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = skin.routeContour;
    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.16 + i * 0.1);
      canvas.drawPath(
        Path()
          ..moveTo(-20, y)
          ..cubicTo(
            size.width * 0.25,
            y - size.height * 0.07,
            size.width * 0.5,
            y + size.height * 0.08,
            size.width + 20,
            y - size.height * 0.04,
          ),
        contour,
      );
    }

    // Đặt đường chạy vào khoảng trống giữa nhãn trên và khối chữ dưới.
    final route = _fitRoute(
      points,
      Rect.fromLTRB(
        size.width * 0.16,
        size.height * 0.2,
        size.width * 0.84,
        size.height * 0.56,
      ),
    );
    if (route.isEmpty) return;
    final path = _pathOf(route);
    canvas.drawPath(path, _stroke(skin.routeLine, 2.6));

    final ring = _stroke(skin.routeLine, 2.4);
    canvas
      ..drawCircle(route.first, 6, Paint()..color = skin.routeStart)
      ..drawCircle(route.first, 6, ring)
      ..drawCircle(route.last, 7, Paint()..color = glow)
      ..drawCircle(route.last, 7, ring);
  }

  @override
  bool shouldRepaint(_RouteArtPainter old) =>
      old.tier != tier ||
      !identical(old.skin, skin) ||
      !identical(old.points, points);
}

/// Con dấu tròn: đường chạy thu nhỏ, đặt trên tranh để thẻ vẫn là của buổi
/// chạy này.
class RunRouteStamp extends StatelessWidget {
  const RunRouteStamp({super.key, required this.points});

  final List<LatLng> points;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    return CustomPaint(
      painter: _StampPainter(points: points, line: skin.routeLine),
      child: const SizedBox.expand(),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.points, required this.line});

  final List<LatLng> points;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final route = _fitRoute(points, (Offset.zero & size).deflate(13));
    if (route.isEmpty) return;
    final path = _pathOf(route);
    canvas.drawPath(path, _stroke(line, 2.2));
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.line != line || !identical(old.points, points);
}

/// Đoạn lẻ cuối ngắn hơn thế này thì bỏ khỏi biểu đồ: pace của vài chục mét
/// cuối nhiễu, kéo cả biểu đồ lệch.
const _minSplitMeters = 300.0;

/// Pace từng km để vẽ biểu đồ mặt sau.
List<double> runCardSplitPaces(List<RunCardSplit> splits) => [
  for (final s in splits)
    if (s.distanceMeters >= _minSplitMeters) s.paceSecondsPerKm,
];

int _fastest(List<double> paces, int from, int to) {
  var fast = from;
  for (var i = from + 1; i < to; i++) {
    if (paces[i] < paces[fast]) fast = i;
  }
  return fast;
}

/// Tiêu đề biểu đồ theo bước của đường đang vẽ.
String runCardPaceTitle(RunCardPace? pace) =>
    pace == null || pace.stepMeters >= 1000
    ? 'PACE MỖI KM'
    : 'PACE MỖI ${pace.stepMeters} M';

/// Điểm được đánh dấu trên đường [paces]. Dòng "NHANH NHẤT" tính theo km, nên
/// đường mịn đánh dấu điểm nhanh nhất nằm trong đúng km đó. Không biết km nào
/// nhanh nhất thì lấy điểm nhanh nhất cả đường.
int runCardPaceMark(
  List<double> paces, {
  required List<double> kmPaces,
  int? stepMeters,
}) {
  if (stepMeters != null && kmPaces.length > 1) {
    final km = _fastest(kmPaces, 0, kmPaces.length);
    final from = km * 1000 ~/ stepMeters;
    final to = math.min((km + 1) * 1000 ~/ stepMeters, paces.length);
    if (from < to) return _fastest(paces, from, to);
  }
  return _fastest(paces, 0, paces.length);
}

/// Mặt sau thẻ buổi chạy: bản đồ thật kèm đường chạy, pace từng km và ba số
/// chính. Buổi không có GPS thì bỏ bản đồ, không có từng km thì bỏ biểu đồ.
class RunCardBack extends StatelessWidget {
  const RunCardBack({super.key, required this.card});

  final RunCard card;

  @override
  Widget build(BuildContext context) {
    final snap = card.snapshot;
    final skin = RunCardSkin.of(context);
    final accent = skin.accent(card.tier);
    final glow = skin.glow(card.tier);
    final kmPaces = runCardSplitPaces(snap.splits);
    final paces = snap.pace?.secondsPerKm ?? kmPaces;
    final start = (snap.startedAt ?? card.rolledAt ?? DateTime.now()).toLocal();
    final foot = TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w600,
      fontSize: 10,
      letterSpacing: 1.2,
      color: skin.ink.withValues(alpha: 0.66),
    );
    final brand = foot.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 2.2,
      color: accent,
    );
    return ColoredBox(
      color: skin.dataBack,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Text('3I RUN', style: brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MẶT SAU · DỮ LIỆU',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: foot,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (snap.route.length > 1)
              Expanded(
                flex: 11,
                child: _BackMap(points: snap.route, glow: glow, skin: skin),
              ),
            if (paces.length > 1) ...[
              const SizedBox(height: 10),
              _PaceHeader(
                title: runCardPaceTitle(snap.pace),
                kmPaces: kmPaces,
                skin: skin,
              ),
              const SizedBox(height: 6),
              Expanded(
                flex: 4,
                child: CustomPaint(
                  painter: _PaceChartPainter(
                    paces: paces,
                    mark: runCardPaceMark(
                      paces,
                      kmPaces: kmPaces,
                      stepMeters: snap.pace?.stepMeters,
                    ),
                    glow: glow,
                    skin: skin,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
            if (snap.route.length < 2 && paces.length < 2) const Spacer(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _BackStat('KM', runCardKm(card.km), skin),
                  _BackStat(
                    'THỜI GIAN',
                    formatDuration(snap.movingTimeSeconds),
                    skin,
                  ),
                  _BackStat(
                    'PACE /KM',
                    _pace(_paceOf(snap.movingTimeSeconds, card.km) ?? 0),
                    skin,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(
                    '${_two(start.day)}.${_two(start.month)}.${start.year}',
                    style: foot,
                  ),
                  const Spacer(),
                  Text(
                    gameCardTiers[card.tier]!.label.toUpperCase(),
                    style: brand,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bản đồ OSM tối, đứng yên, khung vừa đường chạy. Ghi công OSM in thẳng lên
/// thẻ vì ảnh khoe không bấm được.
class _BackMap extends StatelessWidget {
  const _BackMap({
    required this.points,
    required this.glow,
    required this.skin,
  });

  final List<LatLng> points;
  final Color glow;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    final credit = mapTileCredits(
      currentMapTileTemplate(),
    ).map((c) => c.label).join(' · ');
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: skin.dataMapEdge),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: routeBounds(points),
                    padding: const EdgeInsets.all(20),
                    maxZoom: 16,
                  ),
                  backgroundColor: skin.dataBack,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  mapTileLayer(context, dark: skin.darkMap),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        color: skin.routeLine,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      _dot(points.first, skin.routeStart, 10),
                      _dot(points.last, glow, 12),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 6,
              bottom: 4,
              child: Text(
                '© $credit',
                style: TextStyle(
                  fontSize: 7,
                  color: skin.dataCredit,
                  shadows: [Shadow(color: skin.textShadow, blurRadius: 2)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _dot(LatLng at, Color fill, double size) => Marker(
    point: at,
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: Border.all(color: skin.routeLine, width: 2),
      ),
    ),
  );
}

class _PaceHeader extends StatelessWidget {
  const _PaceHeader({
    required this.title,
    required this.kmPaces,
    required this.skin,
  });

  final String title;
  final List<double> kmPaces;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    final fast = _fastest(kmPaces, 0, kmPaces.length);
    TextStyle label(Color color) => TextStyle(
      fontFamily: _condensed,
      fontWeight: FontWeight.w700,
      fontSize: 9.5,
      letterSpacing: 1.5,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(title, style: label(skin.dataLabel)),
          const SizedBox(width: 8),
          if (kmPaces.length > 1)
            Expanded(
              child: Text(
                'NHANH NHẤT · KM ${fast + 1} · ${_pace(kmPaces[fast])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: label(skin.hero),
              ),
            ),
        ],
      ),
    );
  }
}

/// Đường cong đi qua đúng từng điểm (Catmull-Rom). Điểm điều khiển bị kẹp trong
/// khoảng cao thấp của đoạn để đường không vọt quá giá trị thật.
void _curveThrough(Path path, List<Offset> points) {
  double within(double y, Offset a, Offset b) =>
      y.clamp(math.min(a.dy, b.dy), math.max(a.dy, b.dy));
  for (var i = 0; i + 1 < points.length; i++) {
    final before = points[math.max(i - 1, 0)];
    final from = points[i];
    final to = points[i + 1];
    final after = points[math.min(i + 2, points.length - 1)];
    path.cubicTo(
      from.dx + (to.dx - before.dx) / 6,
      within(from.dy + (to.dy - before.dy) / 6, from, to),
      to.dx - (after.dx - from.dx) / 6,
      within(to.dy - (after.dy - from.dy) / 6, from, to),
      to.dx,
      to.dy,
    );
  }
}

/// Pace dọc buổi chạy: đoạn nhanh hơn thì cao hơn, chấm sáng ở điểm [mark].
class _PaceChartPainter extends CustomPainter {
  _PaceChartPainter({
    required this.paces,
    required this.mark,
    required this.glow,
    required this.skin,
  });

  final List<double> paces;
  final int mark;
  final Color glow;
  final RunCardSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(12, 2, size.width - 12, size.height - 2);
    final grid = Paint()
      ..color = skin.dataGrid
      ..strokeWidth = 1;
    for (final y in [area.top, area.center.dy, area.bottom]) {
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
    }
    final lo = paces.reduce(math.min) - 6;
    final hi = paces.reduce(math.max) + 6;
    Offset at(int i) => Offset(
      area.left + area.width * i / (paces.length - 1),
      area.top + (paces[i] - lo) / (hi - lo) * area.height,
    );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    _curveThrough(line, [for (var i = 0; i < paces.length; i++) at(i)]);
    final fill = Path.from(line)
      ..lineTo(area.right, area.bottom)
      ..lineTo(area.left, area.bottom)
      ..close();
    canvas
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [glow.withValues(alpha: 0.7), glow.withValues(alpha: 0.04)],
          ).createShader(area),
      )
      ..drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2
          ..color = skin.routeLine,
      );
    canvas
      ..drawCircle(at(mark), 4.5, Paint()..color = glow)
      ..drawCircle(at(mark), 4.5, _stroke(skin.routeLine, 2));
  }

  @override
  bool shouldRepaint(_PaceChartPainter old) =>
      old.glow != glow ||
      old.mark != mark ||
      !identical(old.skin, skin) ||
      !identical(old.paces, paces);
}

class _BackStat extends StatelessWidget {
  const _BackStat(this.label, this.value, this.skin);

  final String label;
  final String value;
  final RunCardSkin skin;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontFamily: _condensed,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1,
              color: skin.hero,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: _condensed,
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 1.4,
              color: skin.ink.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
