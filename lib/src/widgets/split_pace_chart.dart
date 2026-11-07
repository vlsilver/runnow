import 'package:flutter/material.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/theme.dart';

typedef KmSplitRow = ({
  String label,
  double pace,
  double widthFactor,
  bool fastest,
});

/// Splits của buổi chạy thành từng dòng: pace mỗi km, độ dài thanh theo tốc
/// độ so với km nhanh nhất. Km lẻ cuối buổi (dưới 950 m) ghi số km thật thay
/// cho số thứ tự và không được tính là km nhanh nhất, vì đoạn ngắn hay chạy
/// nước rút.
List<KmSplitRow> kmSplitRows(List<Map<String, dynamic>> splits) {
  final entries = <({String label, double pace, bool full})>[];
  for (final split in splits) {
    final distance = (split['distanceMeters'] as num?)?.toDouble() ?? 0;
    final seconds = (split['movingTimeSeconds'] as num?)?.toInt() ?? 0;
    if (distance <= 0 || seconds <= 0) continue;
    final full = distance >= 950;
    entries.add((
      label: full
          ? '${split['split'] ?? entries.length + 1}'
          : (distance / 1000).toStringAsFixed(1),
      pace: seconds / (distance / 1000),
      full: full,
    ));
  }
  final fullPaces = [
    for (final e in entries)
      if (e.full) e.pace,
  ];
  if (fullPaces.isEmpty) return const [];
  final best = fullPaces.reduce((a, b) => a < b ? a : b);
  return [
    for (final e in entries)
      (
        label: e.label,
        pace: e.pace,
        widthFactor: (best / e.pace).clamp(0.15, 1.0),
        fastest: e.full && e.pace == best,
      ),
  ];
}

/// Mục "Từng km" của màn chi tiết buổi chạy. Không có km trọn nào thì ẩn.
class SplitPaceChart extends StatelessWidget {
  const SplitPaceChart({required this.splits, super.key});

  final List<Map<String, dynamic>> splits;

  @override
  Widget build(BuildContext context) {
    final rows = kmSplitRows(splits);
    if (rows.isEmpty) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fastest = rows.firstWhere((row) => row.fastest);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Từng km',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text(
                'nhanh nhất km ${fastest.label}',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _SplitBar(row: row),
            if (row != rows.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({required this.row});

  final KmSplitRow row;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    const number = TextStyle(
      fontFamily: 'Barlow Condensed',
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            row.label,
            style: number.copyWith(color: onSurface.withValues(alpha: 0.55)),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: ColoredBox(
              color: onSurface.withValues(alpha: 0.07),
              child: FractionallySizedBox(
                widthFactor: row.widthFactor,
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: row.fastest
                        ? palette.accent
                        : palette.accent.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            formatPace(row.pace).replaceFirst(' /km', ''),
            textAlign: TextAlign.end,
            style: number.copyWith(
              color: row.fastest ? palette.accent : onSurface,
              fontWeight: row.fastest ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
