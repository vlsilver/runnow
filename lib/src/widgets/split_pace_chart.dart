import 'package:flutter/material.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/theme.dart';

class SplitPaceChart extends StatelessWidget {
  const SplitPaceChart({required this.splits, super.key});

  final List<Map<String, dynamic>> splits;

  @override
  Widget build(BuildContext context) {
    final entries = splits.map(_SplitEntry.fromMap).whereType<_SplitEntry>();
    final items = entries.toList();
    if (items.isEmpty) {
      return const Text('Không có dữ liệu splits.');
    }
    final fastest = items.map((item) => item.pace).reduce(_min);
    final slowest = items.map((item) => item.pace).reduce(_max);
    final average =
        items.fold<double>(0, (sum, item) => sum + item.pace) / items.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [AppColors.black, Color(0xff062442)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PACE THEO KM',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                'TB ${formatPace(average)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final item in items) ...[
            _SplitBar(item: item, fastestPace: fastest, slowestPace: slowest),
            if (item != items.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
          const Row(
            children: [
              _LegendDot(color: AppColors.red),
              SizedBox(width: 6),
              Text(
                'Nhanh nhất',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SizedBox(width: 16),
              _LegendDot(color: AppColors.blue),
              SizedBox(width: 6),
              Text(
                'Pace từng km',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _min(double left, double right) => left < right ? left : right;
  double _max(double left, double right) => left > right ? left : right;
}

class _SplitBar extends StatelessWidget {
  const _SplitBar({
    required this.item,
    required this.fastestPace,
    required this.slowestPace,
  });

  final _SplitEntry item;
  final double fastestPace;
  final double slowestPace;

  @override
  Widget build(BuildContext context) {
    final range = slowestPace - fastestPace;
    final paceScore = range == 0 ? 1.0 : (slowestPace - item.pace) / range;
    final widthFactor = 0.42 + (paceScore * 0.58);
    final isFastest = item.pace == fastestPace;
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            'K${item.index}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: ColoredBox(
              color: Colors.white12,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: isFastest ? AppColors.red : AppColors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text(
            formatPace(item.pace).replaceFirst(' /km', ''),
            textAlign: TextAlign.end,
            style: TextStyle(
              color: isFastest ? const Color(0xffff8a80) : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: const SizedBox.square(dimension: 8),
    );
  }
}

class _SplitEntry {
  const _SplitEntry({required this.index, required this.pace});

  static _SplitEntry? fromMap(Map<String, dynamic> split) {
    final distance = (split['distanceMeters'] as num?)?.toDouble() ?? 0;
    final seconds = (split['movingTimeSeconds'] as num?)?.toInt() ?? 0;
    if (distance <= 0 || seconds <= 0) return null;
    return _SplitEntry(
      index: '${split['split'] ?? '-'}',
      pace: seconds / (distance / 1000),
    );
  }

  final String index;
  final double pace;
}
