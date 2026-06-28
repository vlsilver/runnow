import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Khung chung cho filter gắn trong navigation bar: padding gọn + divider mảnh
/// ngăn cách với hàng điều hướng phía dưới.
class NavFilterShell extends StatelessWidget {
  const NavFilterShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: child,
    );
  }
}

/// Toggle gọn, không khung viền — chỉ ô đang chọn được tô nền.
class NavPillToggle<T> extends StatelessWidget {
  const NavPillToggle({
    required this.items,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Map<T, String> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in items.entries)
          Expanded(
            child: _NavSegment(
              label: entry.value,
              selected: entry.key == value,
              onTap: () => onChanged(entry.key),
            ),
          ),
      ],
    );
  }
}

class _NavSegment extends StatelessWidget {
  const _NavSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : onSurface.withValues(alpha: 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Dropdown gọn cho filter nhiều lựa chọn, dùng trong navigation bar.
class NavDropdown<T> extends StatelessWidget {
  const NavDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  Future<void> _open(BuildContext context) async {
    final selected = await showNavSelectMenu<T>(
      context: context,
      items: items,
      value: value,
      icon: icon,
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                items[value] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: onSurface.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSurface,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? accent : onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? accent : onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 17, color: accent),
        ],
      ),
    );
  }
}

/// Mở menu chọn tuỳ biến (navy bo góc, ô chọn tô accent + tick) ngay tại vị trí
/// widget gọi. Dùng chung cho nav bar và các selector trong chart/activity
/// detail để mọi dropdown trông đồng nhất.
Future<T?> showNavSelectMenu<T>({
  required BuildContext context,
  required Map<T, String> items,
  required T value,
  IconData icon = Icons.tune_rounded,
}) {
  final scheme = Theme.of(context).colorScheme;
  final palette = context.runNowPalette;
  final onSurface = scheme.onSurface;
  final button = context.findRenderObject() as RenderBox;
  final overlayBox =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlayBox),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    ),
    Offset.zero & overlayBox.size,
  );
  return showMenu<T>(
    context: context,
    position: position,
    elevation: 14,
    constraints: const BoxConstraints(minWidth: 168),
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    color: palette.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
    ),
    items: [
      for (final entry in items.entries)
        PopupMenuItem<T>(
          value: entry.key,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _MenuRow(
            icon: icon,
            label: entry.value,
            selected: entry.key == value,
            onSurface: onSurface,
          ),
        ),
    ],
  );
}
