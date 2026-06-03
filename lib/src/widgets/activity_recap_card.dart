import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/pace_sampling.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/route_map.dart';

const _routeSlotHeight = 156.0;
const _routeAreaTop = 82.0;
const _routeAreaHeight = 118.0;

class ActivityRecapCard extends StatelessWidget {
  const ActivityRecapCard({
    required this.activity,
    this.streams = const {},
    this.repaintBoundaryKey,
    super.key,
  });

  final ActivitySummary activity;
  final Map<String, List<double>> streams;
  final GlobalKey? repaintBoundaryKey;

  @override
  Widget build(BuildContext context) {
    final route = activity.polyline == null
        ? const <LatLng>[]
        : decodePolyline(activity.polyline!);
    final paceSamples = standardizePaceSamples(
      activityDistanceMeters: activity.distanceMeters,
      distances: streams['distance'],
      speeds: streams['velocity_smooth'],
    );
    return RepaintBoundary(
      key: repaintBoundaryKey,
      child: AspectRatio(
        aspectRatio: 0.62,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.blueGlow, width: 1.2),
            gradient: const LinearGradient(
              colors: [Color(0xff020812), Color(0xff06365c), Color(0xff630f2d)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(
            painter: _RecapPosterPainter(route: route),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RUNNOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.4,
                          ),
                        ),
                        _StatusBadge(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'PERFORMANCE // ACTIVITY REPORT',
                      style: TextStyle(
                        color: AppColors.blueGlow,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: _routeSlotHeight),
                    Text(
                      activity.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatDate(activity.startedAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _PosterPaceChart(
                      samples: paceSamples,
                      activityDistanceMeters: activity.distanceMeters,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 18,
                      runSpacing: 14,
                      children: [
                        _RecapMetric(
                          label: 'DISTANCE',
                          value: formatDistance(activity.distanceMeters),
                        ),
                        _RecapMetric(
                          label: 'MOVING TIME',
                          value: formatDuration(activity.movingTimeSeconds),
                        ),
                        _RecapMetric(
                          label: 'AVG PACE',
                          value: formatPace(activity.paceSecondsPerKm),
                        ),
                        if (activity.averageHeartRate != null)
                          _RecapMetric(
                            label: 'HEART RATE',
                            value: '${activity.averageHeartRate!.round()} bpm',
                          ),
                        if (activity.elevationGainMeters != null)
                          _RecapMetric(
                            label: 'ELEVATION',
                            value: '${activity.elevationGainMeters!.round()} m',
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "P'RC",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'SYNC // COMPLETE',
                          style: TextStyle(
                            color: AppColors.blueGlow,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterPaceChart extends StatelessWidget {
  const _PosterPaceChart({
    required this.samples,
    required this.activityDistanceMeters,
  });

  final List<PaceSample> samples;
  final double activityDistanceMeters;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PACE // TELEMETRY',
              style: TextStyle(
                color: AppColors.blueGlow,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'DISTANCE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 62,
          child: CustomPaint(
            painter: _PaceChartPainter(
              samples: samples,
              activityDistanceMeters: activityDistanceMeters,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _PaceChartPainter extends CustomPainter {
  const _PaceChartPainter({
    required this.samples,
    required this.activityDistanceMeters,
  });

  final List<PaceSample> samples;
  final double activityDistanceMeters;

  @override
  void paint(Canvas canvas, Size size) {
    final paces = samples.map((sample) => sample.paceSecondsPerKm).toList();
    final minPace = paces.reduce(math.min);
    final maxPace = paces.reduce(math.max);
    final paceRange = math.max(maxPace - minPace, 1);
    final maxDistance = math.max(activityDistanceMeters, 1);
    const verticalPadding = 6.0;
    final chartHeight = math.max(size.height - (verticalPadding * 2), 1);

    final gridPaint = Paint()
      ..color = const Color(0x3300d9ff)
      ..strokeWidth = 0.8;
    for (var index = 0; index <= 3; index++) {
      final y = size.height / 3 * index;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset offsetFor(PaceSample sample) {
      return Offset(
        sample.distanceMeters / maxDistance * size.width,
        verticalPadding +
            (sample.paceSecondsPerKm - minPace) / paceRange * chartHeight,
      );
    }

    final points = samples.map(offsetFor).toList();
    final path = smoothPacePath(points, size);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x9900d9ff)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.blueGlow
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PaceChartPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.activityDistanceMeters != activityDistanceMeters;
}

@visibleForTesting
Path smoothPacePath(List<Offset> points, Size size) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;

  for (var index = 0; index < points.length - 1; index++) {
    final previous = index == 0 ? points[index] : points[index - 1];
    final current = points[index];
    final next = points[index + 1];
    final afterNext = index + 2 < points.length ? points[index + 2] : next;
    final control1 = Offset(
      current.dx + (next.dx - previous.dx) / 6,
      current.dy + (next.dy - previous.dy) / 6,
    );
    final control2 = Offset(
      next.dx - (afterNext.dx - current.dx) / 6,
      next.dy - (afterNext.dy - current.dy) / 6,
    );
    path.cubicTo(
      control1.dx.clamp(0, size.width),
      control1.dy.clamp(0, size.height),
      control2.dx.clamp(0, size.width),
      control2.dy.clamp(0, size.height),
      next.dx.clamp(0, size.width),
      next.dy.clamp(0, size.height),
    );
  }
  return path;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.9),
        border: Border.all(color: Colors.white54),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          'RUN // LOGGED',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _RecapMetric extends StatelessWidget {
  const _RecapMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 124,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.blueGlow, width: 2)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecapPosterPainter extends CustomPainter {
  const _RecapPosterPainter({required this.route});

  final List<LatLng> route;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawCorners(canvas, size);
    if (route.length > 1) _drawRoute(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    const spacing = 24.0;
    final paint = Paint()
      ..color = const Color(0x1f00d9ff)
      ..strokeWidth = 0.6;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawCorners(Canvas canvas, Size size) {
    const length = 18.0;
    const inset = 8.0;
    final paint = Paint()
      ..color = AppColors.blueGlow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(size.width - inset - length, inset)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset, inset + length)
      ..moveTo(size.width - inset, size.height - inset - length)
      ..lineTo(size.width - inset, size.height - inset)
      ..lineTo(size.width - inset - length, size.height - inset);
    canvas.drawPath(path, paint);
  }

  void _drawRoute(Canvas canvas, Size size) {
    final coordinates = route
        .map((point) => Offset(point.longitude, point.latitude))
        .toList();
    final minX = coordinates.map((point) => point.dx).reduce(math.min);
    final maxX = coordinates.map((point) => point.dx).reduce(math.max);
    final minY = coordinates.map((point) => point.dy).reduce(math.min);
    final maxY = coordinates.map((point) => point.dy).reduce(math.max);
    final width = math.max(maxX - minX, 0.00001);
    final height = math.max(maxY - minY, 0.00001);
    final routeArea = Rect.fromLTWH(
      34,
      _routeAreaTop,
      size.width - 68,
      _routeAreaHeight,
    );
    final scale = math.min(routeArea.width / width, routeArea.height / height);
    final routeWidth = width * scale;
    final routeHeight = height * scale;
    final origin = Offset(
      routeArea.left + (routeArea.width - routeWidth) / 2,
      routeArea.top + (routeArea.height - routeHeight) / 2,
    );
    final path = Path();
    for (var index = 0; index < coordinates.length; index++) {
      final point = coordinates[index];
      final offset = Offset(
        origin.dx + (point.dx - minX) * scale,
        origin.dy + routeHeight - (point.dy - minY) * scale,
      );
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x9900d9ff)
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.blueGlow
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_RecapPosterPainter oldDelegate) =>
      oldDelegate.route != route;
}
