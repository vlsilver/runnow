import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Avatar của app: tròn như [CircleAvatar], riêng kiểu Thép và Pixel thì vuông.
class RunNowAvatar extends StatelessWidget {
  const RunNowAvatar({
    super.key,
    this.radius = 20,
    this.backgroundColor,
    this.backgroundImage,
    this.foregroundImage,
    this.child,
  });

  final double radius;
  final Color? backgroundColor;
  final ImageProvider? backgroundImage;
  final ImageProvider? foregroundImage;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!context.runNowPalette.squared) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: backgroundImage,
        foregroundImage: foregroundImage,
        child: child,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final image = foregroundImage ?? backgroundImage;
    return Container(
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.primaryContainer,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: child == null || foregroundImage != null
          ? null
          : DefaultTextStyle.merge(
              style: TextStyle(color: scheme.onPrimaryContainer),
              child: child!,
            ),
    );
  }
}

/// Khung cắt ảnh đại diện: tròn như [ClipOval], kiểu Thép và Pixel thì vuông.
class RunNowRoundClip extends StatelessWidget {
  const RunNowRoundClip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => context.runNowPalette.squared
      ? ClipRect(child: child)
      : ClipOval(child: child);
}
