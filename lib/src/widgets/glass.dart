import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

class RunNowBackdrop extends StatelessWidget {
  const RunNowBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xff000000),
                  Color(0xff020202),
                  Color(0xff000000),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const IgnorePointer(child: CustomPaint(painter: _TechGridPainter())),
          const _Glow(
            alignment: Alignment.topRight,
            color: Color(0x2600a8ff),
            size: 190,
          ),
          const _Glow(
            alignment: Alignment.centerLeft,
            color: Color(0x180057b8),
            size: 170,
          ),
          const _Glow(
            alignment: Alignment.bottomRight,
            color: Color(0x26ff1744),
            size: 150,
          ),
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
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8a000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
          BoxShadow(color: Color(0x1600d9ff), blurRadius: 18),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient:
                  gradient ??
                  const LinearGradient(
                    colors: [Color(0xb307172b), Color(0x8a06101e)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
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
        color: Colors.white,
      ),
    );
  }
}

class _TechGridPainter extends CustomPainter {
  const _TechGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    final minor = Paint()
      ..color = const Color(0x1200d9ff)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = const Color(0x1f00d9ff)
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
  bool shouldRepaint(_TechGridPainter oldDelegate) => false;
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: SizedBox.square(dimension: size),
        ),
      ),
    );
  }
}
