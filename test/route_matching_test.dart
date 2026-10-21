import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/run_contracts/route_matching.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';

/// Tuyến thẳng ~1km chạy về hướng bắc, dùng chung cho các test bên dưới.
const _routeStart = (lat: 10.0, lng: 106.0);
const _routeEnd = (lat: 10.009, lng: 106.0); // ~1000m theo hướng bắc

final _route = [
  RunContractRoutePoint(latitude: _routeStart.lat, longitude: _routeStart.lng),
  RunContractRoutePoint(latitude: _routeEnd.lat, longitude: _routeEnd.lng),
];

List<RoutePoint> _pointsAlong({
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
  int count = 20,
}) {
  final startedAt = DateTime.utc(2026, 1, 1);
  return [
    for (var i = 0; i <= count; i++)
      RoutePoint(
        latitude: startLat + (endLat - startLat) * i / count,
        longitude: startLng + (endLng - startLng) * i / count,
        timestamp: startedAt.add(Duration(seconds: i * 10)),
      ),
  ];
}

void main() {
  test('activity chạy đúng dọc tuyến thì match', () {
    final activity = _pointsAlong(
      startLat: _routeStart.lat,
      startLng: _routeStart.lng,
      endLat: _routeEnd.lat,
      endLng: _routeEnd.lng,
    );
    final result = evaluateRouteMatch(
      activityPoints: activity,
      routePoints: _route,
    );
    expect(result.onRouteRatio, greaterThan(0.95));
    expect(result.routeCoveredRatio, greaterThan(0.95));
    expect(result.matches(), isTrue);
  });

  test('activity chạy song song nhưng lệch xa hành lang thì không match', () {
    // Lệch ~110m theo kinh độ ở vĩ độ 10° — vượt xa hành lang mặc định 35m.
    const lngOffset = 0.001;
    final activity = _pointsAlong(
      startLat: _routeStart.lat,
      startLng: _routeStart.lng + lngOffset,
      endLat: _routeEnd.lat,
      endLng: _routeEnd.lng + lngOffset,
    );
    final result = evaluateRouteMatch(
      activityPoints: activity,
      routePoints: _route,
    );
    expect(result.onRouteRatio, lessThan(0.5));
    expect(result.matches(), isFalse);
  });

  test(
    'activity chỉ chạy 1 đoạn ngắn đầu tuyến thì không match do routeCoveredRatio thấp',
    () {
      // Chỉ chạy 10% đầu tuyến — các điểm này vẫn nằm sát tuyến (onRouteRatio
      // cao) nhưng phần lớn tuyến không được "phủ" tới.
      final shortEndLat =
          _routeStart.lat + (_routeEnd.lat - _routeStart.lat) * 0.1;
      final activity = _pointsAlong(
        startLat: _routeStart.lat,
        startLng: _routeStart.lng,
        endLat: shortEndLat,
        endLng: _routeStart.lng,
      );
      final result = evaluateRouteMatch(
        activityPoints: activity,
        routePoints: _route,
      );
      expect(result.onRouteRatio, greaterThan(0.9));
      expect(result.routeCoveredRatio, lessThan(0.3));
      expect(result.matches(), isFalse);
    },
  );

  test('không có điểm GPS hoạt động thì không match', () {
    final result = evaluateRouteMatch(activityPoints: const [], routePoints: _route);
    expect(result.matches(), isFalse);
  });

  test('pointToPolylineDistanceMeters trả về khoảng cách nhỏ nhất tới các đoạn', () {
    final onRoute = pointToPolylineDistanceMeters(
      (_routeStart.lat + _routeEnd.lat) / 2,
      _routeStart.lng,
      _route,
    );
    expect(onRoute, lessThan(1));

    final farAway = pointToPolylineDistanceMeters(
      _routeStart.lat,
      _routeStart.lng + 0.01,
      _route,
    );
    expect(farAway, greaterThan(500));
  });
}
