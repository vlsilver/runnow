import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

class PrcBrandMark extends StatelessWidget {
  const PrcBrandMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 5 : 7,
          height: compact ? 5 : 7,
          decoration: const BoxDecoration(
            color: AppColors.blueGlow,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.blueGlow, blurRadius: 8)],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          "P'RC",
          style: TextStyle(
            color: Colors.white70,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 1.4 : 1.8,
          ),
        ),
      ],
    );
  }
}
