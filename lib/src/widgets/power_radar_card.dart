import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class PowerRadarMetric {
  const PowerRadarMetric({
    required this.label,
    required this.value,
    required this.score,
    required this.color,
  });

  final String label;
  final String value;
  final double score;
  final Color color;
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
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            icon: icon,
            title: title,
            trailing: '$powerScore power',
            color: AppColors.amber,
          ),
          const SizedBox(height: 14),
          if (controls != null) ...[controls!, const SizedBox(height: 14)],
          SizedBox(height: 214, child: _PowerRadar(metrics: metrics)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in metrics)
                _PowerChip(
                  label: metric.label,
                  value: metric.value,
                  color: metric.color,
                ),
            ],
          ),
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

class _PowerChip extends StatelessWidget {
  const _PowerChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.58),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerRadar extends StatelessWidget {
  const _PowerRadar({required this.metrics});

  final List<PowerRadarMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PowerRadarPainter(
        metrics: metrics,
        textColor: Theme.of(context).colorScheme.onSurface,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PowerRadarPainter extends CustomPainter {
  const _PowerRadarPainter({required this.metrics, required this.textColor});

  final List<PowerRadarMetric> metrics;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.length < 3) return;

    final center = Offset(size.width / 2, size.height / 2 + 4);
    final radius = math.min(size.width, size.height) * 0.34;
    final axisCount = metrics.length;
    final gridPaint = Paint()
      ..color = AppColors.blueGlow.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = AppColors.blueGlow.withValues(alpha: 0.16)
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
      ..color = AppColors.blueGlow.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final fillPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          for (final metric in metrics) metric.color.withValues(alpha: 0.30),
          metrics.first.color.withValues(alpha: 0.30),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    final linePaint = Paint()
      ..color = AppColors.blueGlow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(dataPath, glowPaint);
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, linePaint);

    for (var index = 0; index < points.length; index++) {
      final metric = metrics[index];
      final point = points[index];
      canvas.drawCircle(point, 4.4, Paint()..color = metric.color);
      canvas.drawCircle(
        point,
        8,
        Paint()..color = metric.color.withValues(alpha: 0.18),
      );
    }

    for (var index = 0; index < axisCount; index++) {
      final metric = metrics[index];
      final labelPoint = _point(center, radius + 30, index, axisCount);
      _drawCenteredText(
        canvas,
        metric.label,
        labelPoint,
        TextStyle(
          color: textColor.withValues(alpha: 0.62),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
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

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 72);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PowerRadarPainter oldDelegate) {
    return oldDelegate.metrics != metrics || oldDelegate.textColor != textColor;
  }
}
