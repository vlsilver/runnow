import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const _tileAttribution = '© OpenStreetMap contributors · CARTO';

class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.encodedPolyline,
    this.routePoints,
    this.height = 330,
    super.key,
  });

  const RouteMap.fromRoutePoints({
    required List<RoutePoint> points,
    this.height = 330,
    super.key,
  }) : encodedPolyline = null,
       routePoints = points;

  final String? encodedPolyline;
  final List<RoutePoint>? routePoints;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = _mapPoints();
    final palette = context.runNowPalette;
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
            Positioned.fill(child: _FlutterRouteMap(points: points)),
            const Positioned.fill(child: _MapVignette()),
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
                      color: Colors.black.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        _tileAttribution,
                        style: TextStyle(color: Colors.white70, fontSize: 9),
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
  const _FlutterRouteMap({required this.points});

  final List<LatLng> points;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: routeBounds(points),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: palette.backgroundDeep,
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
          urlTemplate: _darkTileTemplate,
          userAgentPackageName: 'com.threeaeidiot.runnow',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: Colors.black.withValues(alpha: 0.5),
              strokeWidth: 6.5,
              borderStrokeWidth: 0,
            ),
            Polyline(
              points: points,
              color: palette.secondary,
              strokeWidth: 3.5,
              borderColor: palette.backgroundDeep,
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _routeMarker(points.first, palette.secondary),
            _routeMarker(points.last, palette.accent),
          ],
        ),
      ],
    );
  }
}

Marker _routeMarker(LatLng point, Color color) {
  return Marker(
    point: point,
    width: 26,
    height: 26,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14),
        ],
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

class _MapVignette extends StatelessWidget {
  const _MapVignette();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              palette.backgroundDeep.withValues(alpha: 0.22),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
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
