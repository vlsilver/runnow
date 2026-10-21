import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:xml/xml.dart';

/// Đọc file .gpx (chuẩn GPX 1.1) thành danh sách điểm track thật — ưu tiên
/// `<trkpt>` (track — phổ biến nhất khi export từ Strava/Garmin...), dự
/// phòng `<rtept>` (route) rồi `<wpt>` (waypoint rời) nếu file không có
/// track/route.
List<LatLng> parseGpxTrack(String gpxXml) {
  final document = XmlDocument.parse(gpxXml);

  List<LatLng> collect(String tag) {
    final points = <LatLng>[];
    for (final element in document.findAllElements(tag)) {
      final lat = double.tryParse(element.getAttribute('lat') ?? '');
      final lon = double.tryParse(element.getAttribute('lon') ?? '');
      if (lat != null && lon != null) points.add(LatLng(lat, lon));
    }
    return points;
  }

  final trackPoints = collect('trkpt');
  final resolved = trackPoints.isNotEmpty
      ? trackPoints
      : collect('rtept').isNotEmpty
      ? collect('rtept')
      : collect('wpt');
  if (resolved.isEmpty) {
    throw const FormatException('File GPX không có điểm toạ độ nào.');
  }
  return resolved;
}

/// 1 điểm thô theo hệ trục của file SVG gốc (đơn vị "user unit" của SVG,
/// trục y hướng xuống) — chưa quy đổi ra mét/lat-lon thật.
class SvgPoint {
  const SvgPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Lấy toàn bộ điểm từ mọi `<path>` trong 1 file SVG (nối theo thứ tự xuất
/// hiện trong file), đã làm phẳng các đoạn cong Bézier thành đoạn thẳng nhỏ
/// — dùng để "vẽ tay" 1 hình (chữ, logo, hình dạng...) thành tuyến chạy
/// thật (kiểu "GPS art").
List<SvgPoint> parseSvgPathPoints(String svgXml) {
  final document = XmlDocument.parse(svgXml);
  final proxy = _PointCollectorProxy();
  for (final pathElement in document.findAllElements('path')) {
    final d = pathElement.getAttribute('d');
    if (d == null || d.isEmpty) continue;
    writeSvgPathDataToPath(d, proxy);
  }
  if (proxy.points.isEmpty) {
    throw const FormatException('File SVG không có path nào để vẽ tuyến.');
  }
  return proxy.points;
}

class _PointCollectorProxy implements PathProxy {
  final points = <SvgPoint>[];
  var _currentX = 0.0;
  var _currentY = 0.0;

  @override
  void moveTo(double x, double y) {
    points.add(SvgPoint(x, y));
    _currentX = x;
    _currentY = y;
  }

  @override
  void lineTo(double x, double y) {
    points.add(SvgPoint(x, y));
    _currentX = x;
    _currentY = y;
  }

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    const steps = 16;
    final x0 = _currentX;
    final y0 = _currentY;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final mt = 1 - t;
      final x =
          mt * mt * mt * x0 +
          3 * mt * mt * t * x1 +
          3 * mt * t * t * x2 +
          t * t * t * x3;
      final y =
          mt * mt * mt * y0 +
          3 * mt * mt * t * y1 +
          3 * mt * t * t * y2 +
          t * t * t * y3;
      points.add(SvgPoint(x, y));
    }
    _currentX = x3;
    _currentY = y3;
  }

  @override
  void close() {
    // Không tự nối lại điểm đầu — 1 tuyến chạy không cần khép kín thành
    // hình kín, chạy hết nét vẽ là đủ.
  }
}

/// Đặt hình [shape] (toạ độ SVG thô) lên bản đồ thật quanh [center]: co
/// giãn đều (giữ tỉ lệ hình gốc) sao cho bề ngang thật bằng
/// [targetWidthMeters], tâm hình trùng [center]. Dùng xấp xỉ
/// equirectangular quanh [center] — đủ chính xác cho phạm vi vài km của 1
/// tuyến chạy.
List<LatLng> projectShapeOntoMap(
  List<SvgPoint> shape, {
  required LatLng center,
  required double targetWidthMeters,
}) {
  var minX = shape.first.x;
  var maxX = shape.first.x;
  var minY = shape.first.y;
  var maxY = shape.first.y;
  for (final point in shape) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }
  final shapeWidth = math.max(maxX - minX, 1e-6);
  final scale = targetWidthMeters / shapeWidth;
  final centerX = (minX + maxX) / 2;
  final centerY = (minY + maxY) / 2;

  const earthRadiusMeters = 6371008.8;
  final centerLatRad = center.latitude * math.pi / 180;

  LatLng offsetLatLng({required double eastMeters, required double northMeters}) {
    final deltaLat = (northMeters / earthRadiusMeters) * (180 / math.pi);
    final deltaLon =
        (eastMeters / (earthRadiusMeters * math.cos(centerLatRad))) *
        (180 / math.pi);
    return LatLng(center.latitude + deltaLat, center.longitude + deltaLon);
  }

  return [
    for (final point in shape)
      offsetLatLng(
        eastMeters: (point.x - centerX) * scale,
        // Trục y của SVG hướng xuống; hướng Bắc (lat tăng) là hướng lên —
        // đảo dấu để hình không bị lật trên bản đồ.
        northMeters: -(point.y - centerY) * scale,
      ),
  ];
}
