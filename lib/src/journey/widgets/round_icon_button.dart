import 'package:flutter/material.dart';

/// Nút icon tròn nổi trên bản đồ/ảnh (nền đen mờ, viền trắng mờ) — dùng
/// chung cho mọi nút hành động nhỏ trong tính năng Hành Trình (điều khiển
/// bản đồ, đóng popup, chia sẻ, mở khoá...) thay vì mỗi nơi tự vẽ lại.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 32,
    this.iconSize = 18,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
    final label = tooltip;
    return label == null ? button : Tooltip(message: label, child: button);
  }
}
