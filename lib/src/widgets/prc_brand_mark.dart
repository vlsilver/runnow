import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

class PrcBrandMark extends StatelessWidget {
  const PrcBrandMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = context.runNowPalette.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 5 : 7,
          height: compact ? 5 : 7,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: accent, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          "P'RC",
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 1.4 : 1.8,
          ),
        ),
      ],
    );
  }
}
