import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Khung kính bo góc cho từng mục của Hồ sơ và tab Hoạt động.
class SectionCard extends StatelessWidget {
  const SectionCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPanel(
    borderRadius: 20,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// Nhãn in hoa đầu mục.
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
      color: context.runNowPalette.textMuted,
    ),
  );
}

/// Dòng chữ phụ, màu mờ.
class SectionMuted extends StatelessWidget {
  const SectionMuted(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13, color: context.runNowPalette.textMuted),
  );
}
