import 'dart:math' as math;

import 'package:myrun/src/models.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/tracking_session.dart' show haversineDistanceMeters;

/// Hành lang mặc định (mét) quanh tuyến tham khảo — điểm GPS thật cách tuyến
/// trong khoảng này được coi là "bám đúng tuyến".
const defaultRouteCorridorMeters = 35.0;

/// Tỉ lệ tối thiểu (cả 2 chiều) để 1 buổi chạy được coi là hoàn thành tuyến.
const defaultRouteMatchThreshold = 0.9;

/// Kết quả so khớp 1 buổi chạy thật với tuyến tham khảo — cần đúng cả 2
/// chiều mới tính là hoàn thành tuyến:
/// - [onRouteRatio]: % điểm GPS của buổi chạy nằm trong hành lang quanh
///   tuyến (đảm bảo không chạy lệch sang đường khác).
/// - [routeCoveredRatio]: % chiều dài tuyến có ít nhất 1 điểm GPS của buổi
///   chạy ở gần (đảm bảo chạy hết tuyến, không chỉ 1 đoạn ngắn nằm lọt trong
///   hành lang của tuyến dài hơn).
class RouteMatchResult {
  const RouteMatchResult({
    required this.onRouteRatio,
    required this.routeCoveredRatio,
  });

  final double onRouteRatio;
  final double routeCoveredRatio;

  bool matches({double threshold = defaultRouteMatchThreshold}) =>
      onRouteRatio >= threshold && routeCoveredRatio >= threshold;
}

/// Khoảng cách ngắn nhất (mét) từ 1 điểm tới tuyến gồm nhiều đoạn thẳng nối
/// [polyline] — chiếu điểm lên từng đoạn (kẹp về trong đoạn), lấy khoảng
/// cách nhỏ nhất trong số đó.
double pointToPolylineDistanceMeters(
  double latitude,
  double longitude,
  List<RunContractRoutePoint> polyline,
) {
  if (polyline.isEmpty) return double.infinity;
  if (polyline.length == 1) {
    final only = polyline.first;
    return haversineDistanceMeters(
      latitude,
      longitude,
      only.latitude,
      only.longitude,
    );
  }
  var minDistance = double.infinity;
  for (var index = 1; index < polyline.length; index++) {
    final distance = _pointToSegmentMeters(
      latitude,
      longitude,
      polyline[index - 1],
      polyline[index],
    );
    if (distance < minDistance) minDistance = distance;
  }
  return minDistance;
}

/// So khớp GPS thật của 1 buổi chạy ([activityPoints]) với tuyến tham khảo
/// ([routePoints]) — xem [RouteMatchResult] để hiểu ý nghĩa 2 tỉ lệ trả về.
RouteMatchResult evaluateRouteMatch({
  required List<RoutePoint> activityPoints,
  required List<RunContractRoutePoint> routePoints,
  double corridorMeters = defaultRouteCorridorMeters,
  double routeSampleIntervalMeters = 25,
}) {
  if (activityPoints.isEmpty || routePoints.length < 2) {
    return const RouteMatchResult(onRouteRatio: 0, routeCoveredRatio: 0);
  }

  final onRouteCount = activityPoints
      .where(
        (point) =>
            pointToPolylineDistanceMeters(
              point.latitude,
              point.longitude,
              routePoints,
            ) <=
            corridorMeters,
      )
      .length;
  final onRouteRatio = onRouteCount / activityPoints.length;

  final routeSamples = _sampleRoute(routePoints, routeSampleIntervalMeters);
  final coveredCount = routeSamples
      .where(
        (sample) => activityPoints.any(
          (point) =>
              haversineDistanceMeters(
                sample.latitude,
                sample.longitude,
                point.latitude,
                point.longitude,
              ) <=
              corridorMeters,
        ),
      )
      .length;
  final routeCoveredRatio = routeSamples.isEmpty
      ? 0.0
      : coveredCount / routeSamples.length;

  return RouteMatchResult(
    onRouteRatio: onRouteRatio,
    routeCoveredRatio: routeCoveredRatio,
  );
}

double _pointToSegmentMeters(
  double latitude,
  double longitude,
  RunContractRoutePoint a,
  RunContractRoutePoint b,
) {
  // Xấp xỉ phẳng cục bộ quanh [a] — đủ chính xác cho các đoạn tuyến dài vài
  // chục tới vài trăm mét, không dùng để so khoảng cách xa (độ cong Trái Đất
  // gây sai số đáng kể ở khoảng cách lớn).
  const earthRadiusMeters = 6371008.8;
  double toRadians(double degrees) => degrees * math.pi / 180;
  final originLatRad = toRadians(a.latitude);

  double localX(double longitude) =>
      toRadians(longitude - a.longitude) *
      earthRadiusMeters *
      math.cos(originLatRad);
  double localY(double latitude) =>
      toRadians(latitude - a.latitude) * earthRadiusMeters;

  final pointX = localX(longitude);
  final pointY = localY(latitude);
  final endX = localX(b.longitude);
  final endY = localY(b.latitude);

  final segmentLengthSquared = endX * endX + endY * endY;
  if (segmentLengthSquared == 0) {
    return haversineDistanceMeters(
      latitude,
      longitude,
      a.latitude,
      a.longitude,
    );
  }
  final t = ((pointX * endX + pointY * endY) / segmentLengthSquared).clamp(
    0.0,
    1.0,
  );
  final closestX = endX * t;
  final closestY = endY * t;
  final dx = pointX - closestX;
  final dy = pointY - closestY;
  return math.sqrt(dx * dx + dy * dy);
}

List<RunContractRoutePoint> _sampleRoute(
  List<RunContractRoutePoint> points,
  double intervalMeters,
) {
  if (points.length < 2) return points;
  var totalLength = 0.0;
  for (var index = 1; index < points.length; index++) {
    totalLength += haversineDistanceMeters(
      points[index - 1].latitude,
      points[index - 1].longitude,
      points[index].latitude,
      points[index].longitude,
    );
  }
  if (totalLength <= 0) return points;
  final sampleCount = (totalLength / intervalMeters).ceil().clamp(1, 2000);
  return [
    for (var index = 0; index <= sampleCount; index++)
      _pointAtDistance(points, totalLength * index / sampleCount),
  ];
}

RunContractRoutePoint _pointAtDistance(
  List<RunContractRoutePoint> points,
  double distanceMeters,
) {
  var traversed = 0.0;
  for (var index = 1; index < points.length; index++) {
    final start = points[index - 1];
    final end = points[index];
    final segment = haversineDistanceMeters(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (traversed + segment >= distanceMeters) {
      if (segment <= 0) return end;
      final t = ((distanceMeters - traversed) / segment).clamp(0.0, 1.0);
      return RunContractRoutePoint(
        latitude: start.latitude + (end.latitude - start.latitude) * t,
        longitude: start.longitude + (end.longitude - start.longitude) * t,
      );
    }
    traversed += segment;
  }
  return points.last;
}
