import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/route_map.dart';

void main() {
  test('decodes a Google encoded polyline', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, hasLength(3));
    expect(points.first.latitude, closeTo(38.5, 0.00001));
    expect(points.first.longitude, closeTo(-120.2, 0.00001));
  });

  test('calculates bounds that contain the decoded route', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    final bounds = routeBounds(points);
    expect(points.every(bounds.contains), isTrue);
  });

  test('calculates an initial camera without a native bounds update', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    final camera = routeCameraPosition(points);
    expect(camera.center.latitude, closeTo(40.876, 0.00001));
    expect(camera.center.longitude, closeTo(-123.3265, 0.00001));
    expect(camera.zoom, inInclusiveRange(8, 16));
  });

  test('maps chart distance proportionally onto a downsampled route', () {
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');

    final start = routePointAtActivityDistance(
      points,
      selectedDistanceMeters: 0,
      activityDistanceMeters: 10000,
    );
    final middle = routePointAtActivityDistance(
      points,
      selectedDistanceMeters: 5000,
      activityDistanceMeters: 10000,
    );
    final finish = routePointAtActivityDistance(
      points,
      selectedDistanceMeters: 10000,
      activityDistanceMeters: 10000,
    );

    expect(start, points.first);
    expect(finish, points.last);
    expect(middle, isNot(points.first));
    expect(middle, isNot(points.last));
  });
}
