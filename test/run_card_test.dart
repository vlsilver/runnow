import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';

ActivitySummary _run({
  double distanceMeters = 15000,
  int movingTimeSeconds = 4965,
  double? elevationGainMeters = 40,
  String? polyline,
  List<RoutePoint> routePoints = const [],
}) => ActivitySummary(
  id: 'r1',
  name: 'Dọc bờ sông Hồng',
  kind: ActivityKind.run,
  // Thứ Bảy.
  startedAt: DateTime(2026, 10, 24, 6, 12),
  distanceMeters: distanceMeters,
  movingTimeSeconds: movingTimeSeconds,
  elapsedTimeSeconds: movingTimeSeconds,
  elevationGainMeters: elevationGainMeters,
  polyline: polyline,
  routePoints: routePoints,
);

// Ví dụ trong tài liệu Encoded Polyline của Google:
// (38.5, -120.2), (40.7, -120.95), (43.252, -126.453).
const _googleSample = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

RoutePoint _at(double lat, double lng) =>
    RoutePoint(latitude: lat, longitude: lng, timestamp: DateTime(2026));

final _photo = ActivityPhoto(
  id: 'p1',
  capturedAt: DateTime(2026, 10, 24, 6, 40),
  latitude: 21.03,
  longitude: 105.85,
  distanceMeters: 5000,
  storagePath: 'activities/r1/p1.jpg',
);

Future<void> _pumpCard(
  WidgetTester tester, {
  List<ActivityPhoto> photos = const [],
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RunShareCard(
            activity: _run(),
            photos: photos,
            owner: 'An',
            captureKey: GlobalKey(),
          ),
        ),
      ),
    ),
  );
}

/// Độ sáng trung bình RGB tại điểm (fx, fy) tính theo tỉ lệ khung 300x420.
Future<int Function(double, double)> _paintArt(
  WidgetTester tester,
  List<LatLng> points,
) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: 300,
          height: 420,
          child: RunRouteArt(points: points, tier: GameCardTier.rare),
        ),
      ),
    ),
  );
  late ByteData pixels;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    pixels = (await (await render.toImage()).toByteData())!;
  });
  return (fx, fy) {
    final i = ((420 * fy).toInt() * 300 + (300 * fx).toInt()) * 4;
    return (pixels.getUint8(i) +
            pixels.getUint8(i + 1) +
            pixels.getUint8(i + 2)) ~/
        3;
  };
}

void main() {
  test('tier follows the distance printed on the card', () {
    // Bậc đi theo số km in trên thẻ (làm tròn 0,1 km), để 4,95 km in "5,0"
    // không ra thẻ Thường.
    expect(runCardTier(4949), GameCardTier.common);
    expect(runCardTier(4950), GameCardTier.rare);
    expect(runCardTier(9949), GameCardTier.rare);
    expect(runCardTier(9950), GameCardTier.superRare);
    expect(runCardTier(21049), GameCardTier.superRare);
    expect(runCardTier(21050), GameCardTier.legendary);
    expect(runCardTier(42195), GameCardTier.legendary);
  });

  test('only running activities get a card', () {
    ActivitySummary kind(ActivityKind k) => ActivitySummary(
      id: 'a',
      name: 'a',
      kind: k,
      startedAt: DateTime(2026),
      distanceMeters: 40000,
      movingTimeSeconds: 3600,
      elapsedTimeSeconds: 3600,
    );
    expect(hasRunCard(kind(ActivityKind.run)), isTrue);
    expect(hasRunCard(kind(ActivityKind.trailRun)), isTrue);
    expect(hasRunCard(kind(ActivityKind.virtualRun)), isTrue);
    expect(hasRunCard(kind(ActivityKind.ride)), isFalse);
    expect(hasRunCard(kind(ActivityKind.walk)), isFalse);
    expect(hasRunCard(kind(ActivityKind.motorbike)), isFalse);
  });

  test('card text comes from the run', () {
    final card = runCardData(
      _run(),
      owner: 'An Nguyễn',
      art: const Placeholder(),
    );
    expect(card.tier, GameCardTier.superRare);
    expect(card.kind, 'BUỔI CHẠY');
    expect(card.hero, '15,0');
    expect(card.heroUnit, 'KM');
    expect(card.title, 'Dọc bờ sông Hồng');
    expect(card.owner, 'AN NGUYỄN');
    expect(card.serial, '06:12');
    expect(card.desc, 'Pace 5:31 /km · 1:22:45 · leo 40 m');
    expect(card.meta, 'THỨ BẢY · SÁNG');
    expect(card.date, '24.10.2026');
  });

  test('flat runs leave the climb out', () {
    final card = runCardData(
      _run(elevationGainMeters: null),
      owner: 'An',
      art: const Placeholder(),
    );
    expect(card.desc, 'Pace 5:31 /km · 1:22:45');
  });

  test('route uses the points the app recorded before the Strava polyline', () {
    final recorded = runCardRoute(
      _run(polyline: _googleSample, routePoints: [_at(21, 105), _at(22, 106)]),
    );
    expect(recorded, [const LatLng(21, 105), const LatLng(22, 106)]);

    final strava = runCardRoute(_run(polyline: _googleSample));
    expect(strava, hasLength(3));
    expect(strava.first.latitude, closeTo(38.5, 1e-5));
    expect(strava.last.longitude, closeTo(-126.453, 1e-5));

    expect(runCardRoute(_run()), isEmpty);
  });

  testWidgets('route art draws the run as a bright line across the card', (
    tester,
  ) async {
    // Đường thẳng bắc–nam: hình vẽ nằm giữa thẻ theo chiều ngang, trong khoảng
    // trống phía trên khối chữ.
    final luma = await _paintArt(tester, const [
      LatLng(21.00, 105.8),
      LatLng(21.01, 105.8),
    ]);
    expect(luma(0.5, 0.38), greaterThan(200), reason: 'nét đường chạy');
    expect(luma(0.05, 0.05), lessThan(80), reason: 'nền');

    final empty = await _paintArt(tester, const []);
    expect(empty(0.5, 0.38), lessThan(80), reason: 'không GPS thì chỉ có nền');
  });

  testWidgets('photo backgrounds are offered only when the run has photos', (
    tester,
  ) async {
    await _pumpCard(tester);
    expect(find.text('Đường chạy'), findsNothing);

    await _pumpCard(tester, photos: [_photo]);
    await tester.pump();
    expect(find.text('Đường chạy'), findsOneWidget);
    expect(find.text('Ảnh 1'), findsOneWidget);
  });

  testWidgets('tapping the card opens the 3D viewer', (tester) async {
    await _pumpCard(tester);
    await tester.tap(find.byType(AchievementCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('15,0 km'), findsOneWidget);
  });
}
