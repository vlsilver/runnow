import 'dart:math' as math;
import 'dart:ui' as ui;
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
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                isComplex: true,
                willChange: false,
                painter: _TechGridPainter(palette),
              ),
            ),
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
    this.border,
    super.key,
  });

  final Widget child;
  final BoxBorder? border; // viền vẽ ĐÚNG bán kính đã kẹp (không lệch góc)
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final effectiveRadius = borderRadius >= 900
        ? borderRadius
        : palette.corner(math.min(borderRadius, 12).toDouble());
    if (palette.isPixel) {
      // Kiểu Pixel: khối góc bậc thang, viền mực, bóng cứng không nhoè. Ô tròn
      // (nút biểu tượng, thanh tab) không đổ bóng để không lệch hàng.
      final frame = PixelBorder(
        side: BorderSide(color: palette.foreground, width: 2),
      );
      return Container(
        margin: margin,
        foregroundDecoration: ShapeDecoration(shape: frame),
        decoration: ShapeDecoration(
          shape: const PixelBorder(),
          gradient: gradient,
          color: gradient == null ? palette.glassStart : null,
          shadows: borderRadius >= 900
              ? null
              : [BoxShadow(color: palette.foreground, offset: pixelShadow)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );
    }
    return Container(
      margin: margin,
      decoration: border == null
          ? null
          : BoxDecoration(
              border: border,
              borderRadius: context.runNowPalette.radius(effectiveRadius),
            ),
      child: ClipRRect(
        borderRadius: context.runNowPalette.radius(effectiveRadius),
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
            borderRadius: context.runNowPalette.radius(effectiveRadius),
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}

/// Ở kiểu Pixel bọc [child] bằng khung góc bậc thang, viền mực và bóng cứng.
/// Kiểu khác trả lại [child] nguyên vẹn.
class PixelFrame extends StatelessWidget {
  const PixelFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    if (!palette.isPixel) return child;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const PixelBorder(),
        shadows: [BoxShadow(color: palette.foreground, offset: pixelShadow)],
      ),
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: PixelBorder()),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: PixelBorder(
              side: BorderSide(color: palette.foreground, width: 2),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Ở kiểu Pixel vẽ [child] thành tranh điểm ảnh: chụp hình vẽ, thu nhỏ rồi
/// phóng lại không làm mịn, nên đường cong thành bậc thang. Chỉ bọc hình vẽ
/// đứng yên, không bọc chữ: hình động phải chụp lại mỗi khung.
class PixelArt extends StatefulWidget {
  const PixelArt({required this.child, super.key});

  final Widget child;

  /// Cạnh một điểm ảnh của tranh, tính bằng điểm logic.
  static const cell = RunNowThemeTokens.pixelStep;

  @override
  State<PixelArt> createState() => _PixelArtState();
}

class _PixelArtState extends State<PixelArt> {
  final _controller = SnapshotController(allowSnapshotting: true);
  final _painter = _PixelArtPainter();

  @override
  void dispose() {
    _controller.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.runNowPalette.isPixel) return widget.child;
    return SnapshotWidget(
      controller: _controller,
      painter: _painter,
      autoresize: true,
      child: widget.child,
    );
  }
}

class _PixelArtPainter extends SnapshotPainter {
  _PixelArtPainter();

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    void Function(PaintingContext, Offset) painter,
  ) => painter(context, offset);

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final w = (size.width / PixelArt.cell).ceil();
    final h = (size.height / PixelArt.cell).ceil();
    if (w == 0 || h == 0) return;
    final grid = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Offset.zero & sourceSize,
      grid,
      Paint()..filterQuality = FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final small = picture.toImageSync(w, h);
    picture.dispose();
    context.canvas.drawImageRect(
      small,
      grid,
      offset & Size(w * PixelArt.cell, h * PixelArt.cell),
      Paint()..filterQuality = FilterQuality.none,
    );
    small.dispose();
  }

  @override
  bool shouldRepaint(_PixelArtPainter oldDelegate) => false;
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
