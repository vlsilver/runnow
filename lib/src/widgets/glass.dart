import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

class RunNowBackdrop extends StatelessWidget {
  const RunNowBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return ColoredBox(
      color: isLight ? AppColors.lightBackground : AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isLight
                    ? const [
                        Color(0xffeaf1f8),
                        Color(0xfff8fbff),
                        Color(0xffe9eef6),
                      ]
                    : const [
                        Color(0xff0d1a2a),
                        Color(0xff0a1421),
                        Color(0xff080f19),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: _TechGridPainter(isLight))),
          _Glow(
            alignment: Alignment.topRight,
            color: isLight ? const Color(0x18006fff) : const Color(0x2238b0ff),
            size: isLight ? 220 : 190,
          ),
          _Glow(
            alignment: Alignment.centerLeft,
            color: isLight ? const Color(0x10206ed0) : const Color(0x16215f9e),
            size: isLight ? 210 : 170,
          ),
          _Glow(
            alignment: Alignment.bottomRight,
            color: isLight ? const Color(0x12206ed0) : const Color(0x1c3a9bff),
            size: isLight ? 190 : 150,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x3308172b) : const Color(0x8a000000),
            blurRadius: isLight ? 22 : 24,
            offset: Offset(0, isLight ? 10 : 12),
          ),
          BoxShadow(
            color: isLight ? const Color(0x0f0075ff) : const Color(0x1600d9ff),
            blurRadius: 18,
          ),
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
                  LinearGradient(
                    colors: isLight
                        ? const [Color(0xfff8fbff), Color(0xffe6eef7)]
                        : const [Color(0xb307172b), Color(0x8a06101e)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isLight
                    ? const Color(0x2408172b)
                    : const Color(0x2600d9ff),
              ),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GlassPanel(
      borderRadius: 999,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        color: isLight ? AppColors.lightText : Colors.white,
      ),
    );
  }
}

class _TechGridPainter extends CustomPainter {
  const _TechGridPainter(this.isLight);

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 32.0;
    final minor = Paint()
      ..color = isLight ? const Color(0x100075ff) : const Color(0x1200d9ff)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = isLight ? const Color(0x180075ff) : const Color(0x1f00d9ff)
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
      oldDelegate.isLight != isLight;
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
