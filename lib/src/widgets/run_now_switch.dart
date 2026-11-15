import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Công tắc của app. [Switch] của Material không đổi được hình, nên kiểu Thép
/// và Pixel vẽ riêng một công tắc vuông; các kiểu khác vẫn là [Switch].
class RunNowSwitch extends StatelessWidget {
  const RunNowSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    if (!palette.squared) return Switch(value: value, onChanged: onChanged);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 46,
              height: 24,
              padding: const EdgeInsets.all(3),
              color: value ? palette.accent : palette.border,
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox.square(
                  dimension: 18,
                  child: ColoredBox(
                    color: value ? palette.onAccent : palette.background,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [SwitchListTile] với công tắc theo kiểu của app.
class RunNowSwitchListTile extends StatelessWidget {
  const RunNowSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
    this.visualDensity,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    if (!context.runNowPalette.squared) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        contentPadding: contentPadding,
        dense: dense,
        visualDensity: visualDensity,
      );
    }
    final toggle = onChanged;
    return ListTile(
      enabled: toggle != null,
      onTap: toggle == null ? null : () => toggle(!value),
      leading: secondary,
      title: title,
      subtitle: subtitle,
      contentPadding: contentPadding,
      dense: dense,
      visualDensity: visualDensity,
      trailing: ExcludeSemantics(
        child: IgnorePointer(
          child: RunNowSwitch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
