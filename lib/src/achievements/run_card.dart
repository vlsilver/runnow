import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/route_map.dart' show decodePolyline;

typedef _T = RunNowAchievementTokens;

/// Thẻ chỉ dành cho buổi chạy: bậc tính theo km chạy, đặt cho buổi đạp xe
/// 40 km thì ra Huyền thoại sai nghĩa.
bool hasRunCard(ActivitySummary activity) => switch (activity.kind) {
  ActivityKind.run || ActivityKind.trailRun || ActivityKind.virtualRun => true,
  _ => false,
};

/// Bậc thẻ đi theo số km in trên thẻ (làm tròn 0,1 km), để 4,95 km in "5,0"
/// thì ra thẻ Hiếm như người xem thấy.
GameCardTier runCardTier(double distanceMeters) {
  final km = (distanceMeters / 100).round() / 10;
  if (km >= 21.1) return GameCardTier.legendary;
  if (km >= 10) return GameCardTier.superRare;
  if (km >= 5) return GameCardTier.rare;
  return GameCardTier.common;
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

String _dayPart(int hour) {
  if (hour >= 4 && hour < 11) return 'SÁNG';
  if (hour >= 11 && hour < 13) return 'TRƯA';
  if (hour >= 13 && hour < 18) return 'CHIỀU';
  if (hour >= 18 && hour < 22) return 'TỐI';
  return 'ĐÊM';
}

String _two(int n) => n.toString().padLeft(2, '0');

AchievementCardData runCardData(
  ActivitySummary activity, {
  required String owner,
  required Widget art,
}) {
  final start = activity.startedAt;
  final km = (activity.distanceMeters / 100).round() / 10;
  final climb = activity.elevationGainMeters?.round() ?? 0;
  return AchievementCardData(
    tier: runCardTier(activity.distanceMeters),
    art: art,
    kind: 'BUỔI CHẠY',
    hero: km.toStringAsFixed(1).replaceAll('.', ','),
    title: activity.name,
    owner: owner.toUpperCase(),
    serial: '${_two(start.hour)}:${_two(start.minute)}',
    desc: [
      'Pace ${formatPace(activity.paceSecondsPerKm)}',
      formatDuration(activity.movingTimeSeconds),
      if (climb > 0) 'leo $climb m',
    ].join(' · '),
    meta: '${_weekdays[start.weekday - 1]} · ${_dayPart(start.hour)}',
    date: '${_two(start.day)}.${_two(start.month)}.${start.year}',
  );
}

/// Đường chạy của buổi: điểm app tự ghi trước, không có thì polyline Strava.
List<LatLng> runCardRoute(ActivitySummary activity) {
  if (activity.routePoints.isNotEmpty) {
    return [
      for (final p in activity.routePoints) LatLng(p.latitude, p.longitude),
    ];
  }
  final encoded = activity.polyline;
  if (encoded == null || encoded.isEmpty) return const [];
  return decodePolyline(encoded);
}

/// Thẻ buổi chạy để khoe: nền là đường chạy, hoặc một ảnh chụp trong buổi.
/// Chạm thẻ để xem 3D. [captureKey] bọc đúng tấm thẻ, để chụp ra ảnh khoe.
class RunShareCard extends StatefulWidget {
  const RunShareCard({
    super.key,
    required this.activity,
    required this.photos,
    required this.owner,
    required this.captureKey,
    this.width = 300,
  });

  final ActivitySummary activity;
  final List<ActivityPhoto> photos;
  final String owner;
  final GlobalKey captureKey;
  final double width;

  @override
  State<RunShareCard> createState() => _RunShareCardState();
}

class _RunShareCardState extends State<RunShareCard> {
  /// Null là nền đường chạy; còn lại là chỉ số ảnh trong [RunShareCard.photos].
  int? _photo;

  /// Giải polyline một lần: buổi chạy dài có hàng nghìn điểm, và giữ cùng một
  /// list thì nét vẽ không phải vẽ lại mỗi lần sheet build.
  late final List<LatLng> _route = runCardRoute(widget.activity);

  AchievementCardData _data() {
    final tier = runCardTier(widget.activity.distanceMeters);
    final photo = _photo;
    return runCardData(
      widget.activity,
      owner: widget.owner,
      art: photo == null
          ? RunRouteArt(points: _route, tier: tier)
          : StoragePhoto(
              path: widget.photos[photo].storagePath,
              cacheWidth: 960,
            ),
    );
  }

  void _openViewer(AchievementCardData data) {
    showCardViewer(
      context,
      front: (pose) => AchievementCard(data: data, pose: pose),
      back: (pose) => AchievementCard(data: data, pose: pose, back: true),
      chips: [gameCardTiers[data.tier]!.label, '${data.hero} km'],
      cardSize: achievementCardSize,
      onShare: (cardKey, origin) => shareRunCard(
        cardKey: cardKey,
        shareOriginContext: origin,
        activity: widget.activity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data();
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      children: [
        Semantics(
          button: true,
          label: 'Xem thẻ 3D',
          child: GestureDetector(
            onTap: () => _openViewer(data),
            child: RepaintBoundary(
              key: widget.captureKey,
              child: GameCardScaled(
                width: widget.width,
                size: achievementCardSize,
                child: AchievementCard(data: data),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Chạm thẻ để xem 3D', style: TextStyle(color: muted)),
        if (widget.photos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.route_rounded, size: 18),
                label: const Text('Đường chạy'),
                selected: _photo == null,
                onSelected: (_) => setState(() => _photo = null),
              ),
              for (var i = 0; i < widget.photos.length; i++)
                ChoiceChip(
                  avatar: ClipOval(
                    child: SizedBox.square(
                      dimension: 24,
                      child: StoragePhoto(
                        path: widget.photos[i].storagePath,
                        cacheWidth: 96,
                      ),
                    ),
                  ),
                  label: Text('Ảnh ${i + 1}'),
                  selected: _photo == i,
                  onSelected: (_) => setState(() => _photo = i),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Nền thẻ vẽ từ đường chạy: đường sáng màu bậc trên nền tối, có điểm xuất
/// phát và điểm về đích. Buổi không có GPS thì chỉ còn nền.
class RunRouteArt extends StatelessWidget {
  const RunRouteArt({super.key, required this.points, required this.tier});

  final List<LatLng> points;
  final GameCardTier tier;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RouteArtPainter(points: points, tier: tier),
      child: const SizedBox.expand(),
    );
  }
}

class _RouteArtPainter extends CustomPainter {
  _RouteArtPainter({required this.points, required this.tier});

  final List<LatLng> points;
  final GameCardTier tier;

  (Color, Color, Color) get _colors => switch (tier) {
    GameCardTier.common => (
      _T.routeFieldCommon,
      _T.routeFieldCommonEdge,
      _T.routeGlowCommon,
    ),
    GameCardTier.rare => (
      _T.routeFieldRare,
      _T.routeFieldRareEdge,
      _T.routeGlowRare,
    ),
    GameCardTier.superRare => (
      _T.routeFieldEpic,
      _T.routeFieldEpicEdge,
      _T.routeGlowEpic,
    ),
    GameCardTier.legendary => (
      _T.routeFieldLegendary,
      _T.routeFieldLegendaryEdge,
      _T.routeGlowLegendary,
    ),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final (field, edge, glow) = _colors;
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
      ..color = _T.routeContour;
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

    final route = _fit(size);
    if (route.length < 2) return;
    final path = Path()..moveTo(route.first.dx, route.first.dy);
    for (final p in route.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..color = color;
    canvas
      ..drawPath(path, stroke(glow.withValues(alpha: 0.22), 16))
      ..drawPath(path, stroke(glow.withValues(alpha: 0.45), 7))
      ..drawPath(path, stroke(_T.routeLine, 2.6));

    final ring = stroke(_T.routeLine, 2.4);
    canvas
      ..drawCircle(route.first, 6, Paint()..color = _T.routeStart)
      ..drawCircle(route.first, 6, ring)
      ..drawCircle(route.last, 7, Paint()..color = glow)
      ..drawCircle(route.last, 7, ring);
  }

  /// Chiếu kinh/vĩ độ lên mặt phẳng rồi đặt vào khoảng trống giữa nhãn trên
  /// và khối chữ dưới của thẻ, giữ đúng tỉ lệ hình đường chạy.
  List<Offset> _fit(Size size) {
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

    final box = Rect.fromLTRB(
      size.width * 0.16,
      size.height * 0.2,
      size.width * 0.84,
      size.height * 0.56,
    );
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

  @override
  bool shouldRepaint(_RouteArtPainter old) =>
      old.tier != tier || !identical(old.points, points);
}
