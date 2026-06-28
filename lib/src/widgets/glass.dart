import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

class RunNowBackdrop extends StatelessWidget {
  const RunNowBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return ColoredBox(
      color: palette.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: CustomPaint(painter: _TechGridPainter(palette))),
          child,
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 18,
    this.gradient,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final effectiveRadius = borderRadius >= 900
        ? borderRadius
        : math.min(borderRadius, 12).toDouble();
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(effectiveRadius),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient:
                gradient ??
                LinearGradient(
                  colors: [palette.glassStart, palette.glassEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
            borderRadius: BorderRadius.circular(effectiveRadius),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 999,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _TechGridPainter extends CustomPainter {
  const _TechGridPainter(this.palette);

  final RunNowPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    final minor = Paint()
      ..color = palette.gridMinor
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = palette.gridMajor
      ..strokeWidth = 0.8;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (var y = 0.0; y <= size.height; y += spacing * 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }
  }

  @override
  bool shouldRepaint(_TechGridPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
