import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class PowerRadarMetric {
  const PowerRadarMetric({
    required this.label,
    required this.value,
    required this.score,
  });

  final String label;
  final String value;
  final double score;
}

class PowerRadarCard extends StatelessWidget {
  const PowerRadarCard({
    required this.title,
    required this.metrics,
    required this.powerScore,
    this.icon = Icons.radar_rounded,
    this.controls,
    super.key,
  });

  final String title;
  final List<PowerRadarMetric> metrics;
  final int powerScore;
  final IconData icon;
  final Widget? controls;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: icon,
            title: title,
            trailing: '$powerScore power',
            color: palette.accent,
          ),
          const SizedBox(height: 14),
          if (controls != null) ...[controls!, const SizedBox(height: 14)],
          SizedBox(height: 292, child: _PowerRadar(metrics: metrics)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.66),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Text(
          trailing,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PowerRadar extends StatelessWidget {
  const _PowerRadar({required this.metrics});

  final List<PowerRadarMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final top = _metricAt(0);
    final right = _metricAt(1);
    final bottomRight = _metricAt(2);
    final bottomLeft = _metricAt(3);
    final left = _metricAt(4);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PowerRadarPainter(
              metrics: metrics,
              lineColor: palette.secondary,
              gridColor: palette.gridMajor,
            ),
          ),
        ),
        if (top != null)
          Positioned(
            top: 26,
            left: 0,
            right: 0,
            child: Center(
              child: _RadarMetricBadge(metric: top, color: palette.accent),
            ),
          ),
        if (left != null)
          Positioned(
            left: 36,
            top: 118,
            width: 92,
            child: _RadarMetricBadge(
              metric: left,
              color: palette.accent,
              alignment: TextAlign.left,
            ),
          ),
        if (right != null)
          Positioned(
            right: 36,
            top: 118,
            width: 92,
            child: _RadarMetricBadge(
              metric: right,
              color: palette.accent,
              alignment: TextAlign.right,
            ),
          ),
        if (bottomLeft != null)
          Positioned(
            left: 62,
            bottom: 26,
            width: 128,
            child: _RadarMetricBadge(
              metric: bottomLeft,
              color: palette.accent,
              alignment: TextAlign.center,
            ),
          ),
        if (bottomRight != null)
          Positioned(
            right: 62,
            bottom: 26,
            width: 128,
            child: _RadarMetricBadge(
              metric: bottomRight,
              color: palette.accent,
              alignment: TextAlign.center,
            ),
          ),
      ],
    );
  }

  PowerRadarMetric? _metricAt(int index) {
    return index < metrics.length ? metrics[index] : null;
  }
}

class _RadarMetricBadge extends StatelessWidget {
  const _RadarMetricBadge({
    required this.metric,
    required this.color,
    this.alignment = TextAlign.center,
  });

  final PowerRadarMetric metric;
  final Color color;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: switch (alignment) {
        TextAlign.left => CrossAxisAlignment.start,
        TextAlign.right => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.center,
      },
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment,
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.58),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          metric.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PowerRadarPainter extends CustomPainter {
  const _PowerRadarPainter({
    required this.metrics,
    required this.lineColor,
    required this.gridColor,
  });

  final List<PowerRadarMetric> metrics;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.length < 3) return;

    final center = Offset(size.width / 2, size.height / 2 + 12);
    final radius = math.min(size.width, size.height) * 0.24;
    final axisCount = metrics.length;
    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var ring = 1; ring <= 4; ring++) {
      final ringPath = Path();
      final ringRadius = radius * ring / 4;
      for (var index = 0; index < axisCount; index++) {
        final point = _point(center, ringRadius, index, axisCount);
        if (index == 0) {
          ringPath.moveTo(point.dx, point.dy);
        } else {
          ringPath.lineTo(point.dx, point.dy);
        }
      }
      ringPath.close();
      canvas.drawPath(ringPath, gridPaint);
    }

    for (var index = 0; index < axisCount; index++) {
      canvas.drawLine(
        center,
        _point(center, radius, index, axisCount),
        axisPaint,
      );
    }

    final dataPath = Path();
    final points = <Offset>[];
    for (var index = 0; index < axisCount; index++) {
      final metric = metrics[index];
      final point = _point(center, radius * metric.score, index, axisCount);
      points.add(point);
      if (index == 0) {
        dataPath.moveTo(point.dx, point.dy);
      } else {
        dataPath.lineTo(point.dx, point.dy);
      }
    }
    dataPath.close();

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(dataPath, glowPaint);
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, linePaint);

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      canvas.drawCircle(point, 4.4, Paint()..color = lineColor);
      canvas.drawCircle(
        point,
        8,
        Paint()..color = lineColor.withValues(alpha: 0.18),
      );
    }
  }

  Offset _point(Offset center, double radius, int index, int total) {
    final angle = -math.pi / 2 + (math.pi * 2 * index / total);
    return Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
  }

  @override
  bool shouldRepaint(covariant _PowerRadarPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor;
  }
}
