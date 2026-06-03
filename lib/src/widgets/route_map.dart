import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class RouteMap extends StatelessWidget {
  const RouteMap({required this.encodedPolyline, super.key});

  final String? encodedPolyline;

  @override
  Widget build(BuildContext context) {
    final points = encodedPolyline == null
        ? const <LatLng>[]
        : decodePolyline(encodedPolyline!);
    if (points.isEmpty) {
      return const Card(
        child: SizedBox(
          height: 180,
          child: Center(child: Text('Không có dữ liệu route.')),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            Positioned.fill(child: _MapLibreRoute(points: points)),
            const Positioned(
              left: 8,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xcc101820),
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    '© OpenStreetMap contributors · OpenFreeMap',
                    style: TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLibreRoute extends StatefulWidget {
  const _MapLibreRoute({required this.points});

  final List<LatLng> points;

  @override
  State<_MapLibreRoute> createState() => _MapLibreRouteState();
}

class _MapLibreRouteState extends State<_MapLibreRoute> {
  static const _style = 'https://tiles.openfreemap.org/styles/dark';
  MapLibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: _style,
      initialCameraPosition: routeCameraPosition(widget.points),
      attributionButtonPosition: AttributionButtonPosition.topRight,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      myLocationEnabled: false,
      onMapCreated: (controller) => _controller = controller,
      onStyleLoadedCallback: _drawRoute,
    );
  }

  Future<void> _drawRoute() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.addLine(
      LineOptions(
        geometry: widget.points,
        lineColor: '#101820',
        lineOpacity: 0.78,
        lineWidth: 9,
        lineJoin: 'round',
      ),
    );
    await controller.addLine(
      LineOptions(
        geometry: widget.points,
        lineColor: '#D62828',
        lineWidth: 5,
        lineJoin: 'round',
      ),
    );
    await controller.addCircle(
      CircleOptions(
        geometry: widget.points.first,
        circleRadius: 7,
        circleColor: '#0057B8',
        circleStrokeWidth: 2,
        circleStrokeColor: '#FFFFFF',
      ),
    );
    await controller.addCircle(
      CircleOptions(
        geometry: widget.points.last,
        circleRadius: 7,
        circleColor: '#D62828',
        circleStrokeWidth: 2,
        circleStrokeColor: '#FFFFFF',
      ),
    );
  }
}

CameraPosition routeCameraPosition(List<LatLng> points) {
  final bounds = routeBounds(points);
  final latitudeSpan = bounds.northeast.latitude - bounds.southwest.latitude;
  final longitudeSpan = bounds.northeast.longitude - bounds.southwest.longitude;
  final span = math.max(latitudeSpan, longitudeSpan);
  final zoom = span <= 0
      ? 15.0
      : (math.log(360 / span) / math.ln2 - 1.4).clamp(8.0, 16.0);
  return CameraPosition(
    target: LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    ),
    zoom: zoom,
  );
}

LatLngBounds routeBounds(List<LatLng> points) {
  var minLatitude = points.first.latitude;
  var maxLatitude = points.first.latitude;
  var minLongitude = points.first.longitude;
  var maxLongitude = points.first.longitude;
  for (final point in points.skip(1)) {
    if (point.latitude < minLatitude) minLatitude = point.latitude;
    if (point.latitude > maxLatitude) maxLatitude = point.latitude;
    if (point.longitude < minLongitude) minLongitude = point.longitude;
    if (point.longitude > maxLongitude) maxLongitude = point.longitude;
  }
  return LatLngBounds(
    southwest: LatLng(minLatitude, minLongitude),
    northeast: LatLng(maxLatitude, maxLongitude),
  );
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
