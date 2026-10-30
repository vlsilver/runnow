import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Thẻ nhỏ ở trang Kèo: nền là dải màu [tint] nhạt dần trên surface, kèm
/// [icon] chìm ở góc dưới, để thẻ có hình mà không cần ảnh. Màu trộn sẵn vào
/// surface nên nền vẫn đặc, chữ thường đọc được ở cả sáng lẫn tối.
class TintedCard extends StatelessWidget {
  const TintedCard({
    required this.tint,
    required this.onTap,
    required this.padding,
    required this.child,
    this.icon,
    super.key,
  });

  final Color tint;
  final IconData? icon;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = context.runNowPalette.glassStart;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(24),
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color.alphaBlend(tint.withValues(alpha: 0.30), surface),
              Color.alphaBlend(tint.withValues(alpha: 0.06), surface),
            ],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (icon != null)
                Positioned(
                  right: -14,
                  bottom: -14,
                  child: Icon(
                    icon,
                    size: 88,
                    color: tint.withValues(alpha: 0.14),
                  ),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
