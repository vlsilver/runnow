import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/run_contracts/route_import.dart';

void main() {
  group('parseGpxTrack', () {
    test('reads trkpt lat/lon in order', () {
      const gpx = '''
<?xml version="1.0"?>
<gpx>
  <trk>
    <trkseg>
      <trkpt lat="21.0285" lon="105.8542"><ele>10</ele></trkpt>
      <trkpt lat="21.0300" lon="105.8560"></trkpt>
    </trkseg>
  </trk>
</gpx>
''';
      final points = parseGpxTrack(gpx);
      expect(points, hasLength(2));
      expect(points[0].latitude, 21.0285);
      expect(points[0].longitude, 105.8542);
      expect(points[1].latitude, 21.03);
    });

    test('falls back to rtept when there is no track', () {
      const gpx = '''
<?xml version="1.0"?>
<gpx>
  <rte>
    <rtept lat="10.5" lon="106.1"></rtept>
    <rtept lat="10.6" lon="106.2"></rtept>
  </rte>
</gpx>
''';
      final points = parseGpxTrack(gpx);
      expect(points, hasLength(2));
      expect(points[1].latitude, 10.6);
    });

    test('falls back to wpt when there is no track or route', () {
      const gpx = '''
<?xml version="1.0"?>
<gpx>
  <wpt lat="1" lon="2"></wpt>
</gpx>
''';
      final points = parseGpxTrack(gpx);
      expect(points, hasLength(1));
    });

    test('throws FormatException when no coordinates are found', () {
      const gpx = '<?xml version="1.0"?><gpx></gpx>';
      expect(() => parseGpxTrack(gpx), throwsFormatException);
    });
  });

  group('parseSvgPathPoints', () {
    test('collects straight line points from a simple path', () {
      const svg =
          '<svg><path d="M0,0 L10,0 L10,10 L0,10 Z"/></svg>';
      final points = parseSvgPathPoints(svg);
      expect(points.first.x, 0);
      expect(points.first.y, 0);
      expect(points.any((p) => p.x == 10 && p.y == 10), isTrue);
    });

    test('flattens cubic beziers into multiple sampled points', () {
      const svg = '<svg><path d="M0,0 C0,10 10,10 10,0"/></svg>';
      final points = parseSvgPathPoints(svg);
      // moveTo + 16 sampled cubic steps.
      expect(points.length, 17);
      expect(points.last.x, closeTo(10, 0.001));
      expect(points.last.y, closeTo(0, 0.001));
    });

    test('throws FormatException when there is no path', () {
      const svg = '<svg><rect width="10" height="10"/></svg>';
      expect(() => parseSvgPathPoints(svg), throwsFormatException);
    });
  });

  group('projectShapeOntoMap', () {
    test('centers the shape on the given point and scales to target width', () {
      const shape = [
        SvgPoint(0, 0),
        SvgPoint(100, 0),
        SvgPoint(100, 100),
        SvgPoint(0, 100),
      ];
      const center = LatLng(10.0, 106.0);
      final points = projectShapeOntoMap(
        shape,
        center: center,
        targetWidthMeters: 1000,
      );
      expect(points, hasLength(4));
      // Toạ độ trung tâm hình (50,50) phải map đúng ra [center].
      final xs = points.map((p) => p.longitude).toList();
      final ys = points.map((p) => p.latitude).toList();
      final midLon = (xs.reduce((a, b) => a < b ? a : b) +
              xs.reduce((a, b) => a > b ? a : b)) /
          2;
      final midLat = (ys.reduce((a, b) => a < b ? a : b) +
              ys.reduce((a, b) => a > b ? a : b)) /
          2;
      expect(midLon, closeTo(center.longitude, 1e-6));
      expect(midLat, closeTo(center.latitude, 1e-6));
    });

    test('flips the y axis so north is up, not SVG-down', () {
      const shape = [SvgPoint(0, 0), SvgPoint(0, 100)];
      const center = LatLng(10.0, 106.0);
      final points = projectShapeOntoMap(
        shape,
        center: center,
        targetWidthMeters: 200,
      );
      // Điểm thứ 2 có y SVG lớn hơn (xuống dưới) phải có lat NHỎ hơn (về nam).
      expect(points[1].latitude, lessThan(points[0].latitude));
    });
  });
}
