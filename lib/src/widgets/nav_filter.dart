import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Khung chung cho filter gắn trong navigation bar: padding gọn + divider mảnh
/// ngăn cách với hàng điều hướng phía dưới.
class NavFilterShell extends StatelessWidget {
  const NavFilterShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 8),
          Divider(
            height: 1,
            thickness: 1,
            color: onSurface.withValues(alpha: 0.08),
          ),
        ],
      ),
    );
  }
}

/// Toggle dạng pill (track + ô chọn fill) cho 2-3 lựa chọn ngắn.
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.blueGlow.withValues(alpha: 0.22)),
      ),
      child: Row(
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
      ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueGlow : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.blueGlow.withValues(alpha: 0.4),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.black : onSurface.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w900,
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

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        isDense: true,
        value: value,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        dropdownColor: isLight
            ? const Color(0xfff8fbff)
            : const Color(0xff071426),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.blueGlow),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      ),
    );
  }
}
