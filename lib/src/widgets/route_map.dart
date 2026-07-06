import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

const _lightTileTemplate =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const _tileAttribution = '© OpenStreetMap contributors · CARTO';

class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.encodedPolyline,
    this.routePoints,
    this.photos = const [],
    this.onPhotoTap,
    this.highlightedDistanceMeters,
    this.totalDistanceMeters,
    this.height = 330,
    super.key,
  });

  const RouteMap.fromRoutePoints({
    required List<RoutePoint> points,
    this.height = 330,
    this.photos = const [],
    this.onPhotoTap,
    this.highlightedDistanceMeters,
    this.totalDistanceMeters,
    super.key,
  }) : encodedPolyline = null,
       routePoints = points;

  final String? encodedPolyline;
  final List<RoutePoint>? routePoints;
  final double height;
  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto>? onPhotoTap;
  final double? highlightedDistanceMeters;
  final double? totalDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final points = _mapPoints();
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (points.isEmpty) {
      return const GlassPanel(
        borderRadius: 0,
        child: SizedBox(
          height: 180,
          child: Center(child: Text('Không có dữ liệu route.')),
        ),
      );
    }
    return ClipRect(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: _FlutterRouteMap(
                points: points,
                photos: photos,
                onPhotoTap: onPhotoTap,
                highlightedDistanceMeters: highlightedDistanceMeters,
                totalDistanceMeters: totalDistanceMeters,
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _RoutePill(label: 'START', color: palette.secondary),
                  const SizedBox(width: 6),
                  _RoutePill(label: 'FINISH', color: palette.accent),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.black : Colors.white).withValues(
                        alpha: 0.86,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        _tileAttribution,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<LatLng> _mapPoints() {
    final directPoints = routePoints;
    if (directPoints != null && directPoints.isNotEmpty) {
      return directPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    }
    final encoded = encodedPolyline;
    if (encoded == null || encoded.isEmpty) return const <LatLng>[];
    return decodePolyline(encoded);
  }
}

class _FlutterRouteMap extends StatelessWidget {
  const _FlutterRouteMap({
    required this.points,
    required this.photos,
    required this.onPhotoTap,
    required this.highlightedDistanceMeters,
    required this.totalDistanceMeters,
  });

  final List<LatLng> points;
  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto>? onPhotoTap;
  final double? highlightedDistanceMeters;
  final double? totalDistanceMeters;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileTemplate = isDark ? _darkTileTemplate : _lightTileTemplate;
    final routeOutline = isDark
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.88);
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: routeBounds(points),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: isDark
            ? palette.backgroundDeep
            : const Color(0xFFF2F1ED),
        interactionOptions: const InteractionOptions(
          flags:
              InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.pinchMove |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          key: ValueKey(tileTemplate),
          urlTemplate: tileTemplate,
          userAgentPackageName: 'com.threeaeidiot.runnow',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: routeOutline,
              strokeWidth: 6.5,
              borderStrokeWidth: 0,
            ),
            Polyline(
              points: points,
              color: palette.secondary,
              strokeWidth: 3.5,
              borderColor: isDark ? palette.backgroundDeep : Colors.white,
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _routeMarker(
              point: points.first,
              color: palette.secondary,
              icon: Icons.play_arrow_rounded,
              semanticLabel: 'Điểm bắt đầu',
            ),
            _routeMarker(
              point: points.last,
              color: palette.accent,
              icon: Icons.sports_score_rounded,
              semanticLabel: 'Điểm kết thúc',
            ),
            for (final photo in photos)
              Marker(
                point: LatLng(photo.latitude, photo.longitude),
                width: 38,
                height: 38,
                child: _PhotoMapMarker(
                  onTap: onPhotoTap == null ? null : () => onPhotoTap!(photo),
                ),
              ),
            if (highlightedDistanceMeters case final distance?)
              Marker(
                point: routePointAtActivityDistance(
                  points,
                  selectedDistanceMeters: distance,
                  activityDistanceMeters: totalDistanceMeters,
                ),
                width: 38,
                height: 38,
                child: _TelemetryMapMarker(color: palette.accent),
              ),
          ],
        ),
      ],
    );
  }
}

class _TelemetryMapMarker extends StatelessWidget {
  const _TelemetryMapMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vị trí đang chọn trên biểu đồ',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12),
          ],
        ),
        child: Center(
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _PhotoMapMarker extends StatelessWidget {
  const _PhotoMapMarker({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.runNowPalette.accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: const Icon(Icons.photo_camera_rounded, size: 19),
      ),
    );
  }
}

Marker _routeMarker({
  required LatLng point,
  required Color color,
  required IconData icon,
  required String semanticLabel,
}) {
  final foreground = color.computeLuminance() > 0.55
      ? Colors.black87
      : Colors.white;
  return Marker(
    point: point,
    width: 32,
    height: 32,
    child: Semantics(
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.42), blurRadius: 10),
          ],
        ),
        child: Icon(icon, color: foreground, size: 18),
      ),
    ),
  );
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

RouteCamera routeCameraPosition(List<LatLng> points) {
  final bounds = routeBounds(points);
  final latitudeSpan = bounds.north - bounds.south;
  final longitudeSpan = bounds.east - bounds.west;
  final span = math.max(latitudeSpan, longitudeSpan);
  final zoom = span <= 0
      ? 15.0
      : (math.log(360 / span) / math.ln2 - 1.4).clamp(8.0, 16.0);
  return RouteCamera(center: bounds.simpleCenter, zoom: zoom);
}

LatLng routePointAtDistance(List<LatLng> points, double distanceMeters) {
  if (points.isEmpty) throw ArgumentError.value(points, 'points');
  if (points.length == 1 || distanceMeters <= 0) return points.first;
  var traversed = 0.0;
  for (var index = 1; index < points.length; index++) {
    final start = points[index - 1];
    final end = points[index];
    final segment = _distanceMeters(start, end);
    if (traversed + segment >= distanceMeters) {
      if (segment <= 0) return end;
      final progress = ((distanceMeters - traversed) / segment).clamp(0.0, 1.0);
      return LatLng(
        start.latitude + (end.latitude - start.latitude) * progress,
        start.longitude + (end.longitude - start.longitude) * progress,
      );
    }
    traversed += segment;
  }
  return points.last;
}

LatLng routePointAtActivityDistance(
  List<LatLng> points, {
  required double selectedDistanceMeters,
  required double? activityDistanceMeters,
}) {
  if (activityDistanceMeters == null || activityDistanceMeters <= 0) {
    return routePointAtDistance(points, selectedDistanceMeters);
  }
  final routeDistance = routeLengthMeters(points);
  final progress = (selectedDistanceMeters / activityDistanceMeters).clamp(
    0.0,
    1.0,
  );
  return routePointAtDistance(points, routeDistance * progress);
}

double routeLengthMeters(List<LatLng> points) {
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += _distanceMeters(points[index - 1], points[index]);
  }
  return total;
}

double _distanceMeters(LatLng start, LatLng end) {
  const earthRadiusMeters = 6371000.0;
  final latitudeDelta = (end.latitude - start.latitude) * math.pi / 180;
  final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
  final startLatitude = start.latitude * math.pi / 180;
  final endLatitude = end.latitude * math.pi / 180;
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class RouteCamera {
  const RouteCamera({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

LatLngBounds routeBounds(List<LatLng> points) {
  return LatLngBounds.fromPoints(points);
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;
  while (index < encoded.length) {
    final lat = _decodeValue(encoded, index);
    index = lat.$2;
    final lng = _decodeValue(encoded, index);
    index = lng.$2;
    latitude += lat.$1;
    longitude += lng.$1;
    points.add(LatLng(latitude / 1e5, longitude / 1e5));
  }
  return points;
}

(int, int) _decodeValue(String encoded, int start) {
  var index = start;
  var result = 0;
  var shift = 0;
  int byte;
  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);
  return ((result & 1) == 1 ? ~(result >> 1) : result >> 1, index);
}
