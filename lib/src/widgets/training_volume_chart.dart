import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

enum TrainingVolumePeriod { week, month, quarter, year, eightWeeks }

enum TrainingVolumeChartMode { bar, line }

extension on TrainingVolumeChartMode {
  String get label => switch (this) {
    TrainingVolumeChartMode.bar => 'Cột',
    TrainingVolumeChartMode.line => 'Line',
  };
}

extension on TrainingVolumePeriod {
  String get label => switch (this) {
    TrainingVolumePeriod.week => 'Tuần',
    TrainingVolumePeriod.month => 'Tháng',
    TrainingVolumePeriod.quarter => 'Quý',
    TrainingVolumePeriod.year => 'Năm',
    TrainingVolumePeriod.eightWeeks => '8 tuần',
  };
}

class TrainingVolumeChart extends StatefulWidget {
  const TrainingVolumeChart({
    required this.activities,
    required this.period,
    this.mode = TrainingVolumeChartMode.bar,
    this.showControls = false,
    this.now,
    super.key,
  });

  final List<ActivitySummary> activities;
  final TrainingVolumePeriod period;
  final TrainingVolumeChartMode mode;
  final bool showControls;
  final DateTime? now;

  @override
  State<TrainingVolumeChart> createState() => _TrainingVolumeChartState();
}

class _TrainingVolumeChartState extends State<TrainingVolumeChart> {
  late TrainingVolumePeriod _period = widget.period;
  late TrainingVolumeChartMode _mode = widget.mode;

  @override
  void didUpdateWidget(covariant TrainingVolumeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _period = widget.period;
    if (oldWidget.mode != widget.mode) _mode = widget.mode;
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _buildBuckets(
      widget.now ?? DateTime.now(),
      widget.activities,
      _period,
    );
    final maxDistance = buckets.fold<double>(
      0,
      (maximum, bucket) => math.max(maximum, bucket.distanceKm),
    );
    final maxY = math.max(maxDistance * 1.25, 1).toDouble();
    final totalDistance = buckets.fold<double>(
      0,
      (sum, bucket) => sum + bucket.distanceKm,
    );
    final totalActivities = buckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.activityCount,
    );
    final activeBuckets = buckets.where((bucket) => bucket.distanceKm > 0);
    final strongest = activeBuckets.isEmpty
        ? null
        : activeBuckets.reduce(
            (left, right) => left.distanceKm >= right.distanceKm ? left : right,
          );
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      gradient: const LinearGradient(
        colors: [Color(0xe607172b), Color(0xb3062442)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'QUÃNG ĐƯỜNG',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              Text(
                _periodLabel(_period),
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (widget.showControls) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CompactSelector<TrainingVolumeChartMode>(
                    label: 'KIỂU',
                    value: _mode,
                    items: TrainingVolumeChartMode.values,
                    itemLabel: (mode) => mode.label,
                    onChanged: (mode) => setState(() => _mode = mode),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSelector<TrainingVolumePeriod>(
                    label: 'RANGE',
                    value: _period,
                    items: const [
                      TrainingVolumePeriod.month,
                      TrainingVolumePeriod.quarter,
                      TrainingVolumePeriod.year,
                    ],
                    itemLabel: (period) => period.label,
                    onChanged: (period) => setState(() => _period = period),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _ChartStat(
                label: 'TỔNG',
                value: '${totalDistance.toStringAsFixed(1)} km',
              ),
              const SizedBox(width: 22),
              _ChartStat(label: 'SỐ BUỔI', value: '$totalActivities'),
              const SizedBox(width: 22),
              _ChartStat(
                label: 'CAO NHẤT',
                value: strongest == null
                    ? '--'
                    : '${strongest.distanceKm.toStringAsFixed(1)} km',
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 190,
            child: _mode == TrainingVolumeChartMode.bar
                ? _VolumeBarChart(buckets: buckets, maxY: maxY, period: _period)
                : _VolumeLineChart(buckets: buckets, maxY: maxY),
          ),
        ],
      ),
    );
  }
}

class _VolumeBarChart extends StatelessWidget {
  const _VolumeBarChart({
    required this.buckets,
    required this.maxY,
    required this.period,
  });

  final List<_TrainingBucket> buckets;
  final double maxY;
  final TrainingVolumePeriod period;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _gridData(maxY),
        titlesData: _titlesData(maxY: maxY, buckets: buckets),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.black,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bucket = buckets[group.x];
              return BarTooltipItem(
                '${bucket.label}\n'
                '${bucket.distanceKm.toStringAsFixed(2)} km\n'
                '${bucket.activityCount} buổi',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var index = 0; index < buckets.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: buckets[index].distanceKm,
                  width: period == TrainingVolumePeriod.week ? 18 : 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: buckets[index].isCurrent
                        ? [AppColors.red, const Color(0xffff5a5f)]
                        : [AppColors.blue, const Color(0xff35a7ff)],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _VolumeLineChart extends StatelessWidget {
  const _VolumeLineChart({required this.buckets, required this.maxY});

  final List<_TrainingBucket> buckets;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(buckets.length - 1, 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: _gridData(maxY),
        titlesData: _titlesData(maxY: maxY, buckets: buckets),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => AppColors.black,
            getTooltipItems: (spots) => spots.map((spot) {
              final index = spot.x.round().clamp(0, buckets.length - 1);
              final bucket = buckets[index];
              return LineTooltipItem(
                '${bucket.label}\n${bucket.distanceKm.toStringAsFixed(2)} km',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var index = 0; index < buckets.length; index++)
                FlSpot(index.toDouble(), buckets[index].distanceKm),
            ],
            color: AppColors.blueGlow,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            curveSmoothness: 0.28,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.blueGlow.withValues(alpha: 0.24),
                  AppColors.blueGlow.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

FlGridData _gridData(double maxY) {
  return FlGridData(
    drawVerticalLine: false,
    horizontalInterval: math.max(maxY / 3, 1).toDouble(),
    getDrawingHorizontalLine: (_) =>
        const FlLine(color: Colors.white24, strokeWidth: 1),
  );
}

FlTitlesData _titlesData({
  required double maxY,
  required List<_TrainingBucket> buckets,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 42,
        interval: math.max(maxY / 3, 1).toDouble(),
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            '${value.toStringAsFixed(0)} km',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 46,
        getTitlesWidget: (value, meta) {
          final index = value.round();
          if ((value - index).abs() > 0.001 ||
              index < 0 ||
              index >= buckets.length ||
              !_shouldShowLabel(index, buckets.length)) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Transform.rotate(
              angle: -0.55,
              alignment: Alignment.topCenter,
              child: Text(
                buckets[index].label,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

bool _shouldShowLabel(int index, int length) {
  if (length <= 7) return true;
  final step = (length / 4).ceil();
  return index == 0 || index == length - 1 || index % step == 0;
}

class _CompactSelector<T> extends StatelessWidget {
  const _CompactSelector({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x52020812),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.black,
                  iconEnabledColor: AppColors.blueGlow,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  items: [
                    for (final item in items)
                      DropdownMenuItem<T>(
                        value: item,
                        child: Text(itemLabel(item)),
                      ),
                  ],
                  onChanged: (item) {
                    if (item != null) onChanged(item);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartStat extends StatelessWidget {
  const _ChartStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

List<_TrainingBucket> _buildBuckets(
  DateTime now,
  List<ActivitySummary> activities,
  TrainingVolumePeriod period,
) {
  return switch (period) {
    TrainingVolumePeriod.week => _weekBuckets(now, activities),
    TrainingVolumePeriod.month => _monthBuckets(now, activities),
    TrainingVolumePeriod.quarter => _quarterBuckets(now, activities),
    TrainingVolumePeriod.year => _yearBuckets(now, activities),
    TrainingVolumePeriod.eightWeeks => _eightWeekBuckets(now, activities),
  };
}

List<_TrainingBucket> _eightWeekBuckets(
  DateTime now,
  List<ActivitySummary> activities,
) {
  final today = DateTime(now.year, now.month, now.day);
  final currentWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final firstWeekStart = currentWeekStart.subtract(const Duration(days: 49));
  return [
    for (var index = 0; index < 8; index++)
      _bucket(
        label: index == 7 ? 'NAY' : 'T-${7 - index}',
        start: firstWeekStart.add(Duration(days: index * 7)),
        end: firstWeekStart.add(Duration(days: (index + 1) * 7)),
        today: today,
        activities: activities,
      ),
  ];
}

List<_TrainingBucket> _quarterBuckets(
  DateTime now,
  List<ActivitySummary> activities,
) {
  final today = DateTime(now.year, now.month, now.day);
  final currentQuarterStart = _quarterStart(today);
  final firstQuarterStart = currentQuarterStart.addMonth(-21);
  return [
    for (var index = 0; index < 8; index++)
      _bucket(
        label: _formatQuarter(firstQuarterStart.addMonth(index * 3)),
        start: firstQuarterStart.addMonth(index * 3),
        end: firstQuarterStart.addMonth((index + 1) * 3),
        today: today,
        activities: activities,
      ),
  ];
}

List<_TrainingBucket> _yearBuckets(
  DateTime now,
  List<ActivitySummary> activities,
) {
  final today = DateTime(now.year, now.month, now.day);
  final firstYear = activities.isEmpty
      ? now.year
      : activities.map((activity) => activity.startedAt.year).reduce(math.min);
  final bucketCount = math.max(now.year - firstYear + 1, 1);
  return [
    for (var index = 0; index < bucketCount; index++)
      _bucket(
        label: '${firstYear + index}',
        start: DateTime(firstYear + index),
        end: DateTime(firstYear + index + 1),
        today: today,
        activities: activities,
      ),
  ];
}

List<_TrainingBucket> _weekBuckets(
  DateTime now,
  List<ActivitySummary> activities,
) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: today.weekday - 1));
  const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return [
    for (var index = 0; index < 7; index++)
      _bucket(
        label: labels[index],
        start: start.add(Duration(days: index)),
        end: start.add(Duration(days: index + 1)),
        today: today,
        activities: activities,
      ),
  ];
}

String _periodLabel(TrainingVolumePeriod period) {
  return switch (period) {
    TrainingVolumePeriod.week => 'THEO NGÀY',
    TrainingVolumePeriod.month => 'THEO TUẦN',
    TrainingVolumePeriod.quarter => 'THEO TUẦN',
    TrainingVolumePeriod.year => 'THEO THÁNG',
    TrainingVolumePeriod.eightWeeks => 'THEO TUẦN',
  };
}

extension on DateTime {
  DateTime addMonth(int offset) => DateTime(year, month + offset);
}

List<_TrainingBucket> _monthBuckets(
  DateTime now,
  List<ActivitySummary> activities,
) {
  final today = DateTime(now.year, now.month, now.day);
  final firstMonth = DateTime(now.year, now.month - 11);
  return [
    for (var index = 0; index < 12; index++)
      _bucket(
        label: _formatMonth(firstMonth.addMonth(index)),
        start: firstMonth.addMonth(index),
        end: firstMonth.addMonth(index + 1),
        today: today,
        activities: activities,
      ),
  ];
}

_TrainingBucket _bucket({
  required String label,
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required List<ActivitySummary> activities,
}) {
  final items = activities.where(
    (activity) =>
        !activity.startedAt.isBefore(start) && activity.startedAt.isBefore(end),
  );
  return _TrainingBucket(
    label: label,
    distanceKm:
        items.fold<double>(0, (sum, item) => sum + item.distanceMeters) / 1000,
    activityCount: items.length,
    isCurrent: !today.isBefore(start) && today.isBefore(end),
  );
}

class _TrainingBucket {
  const _TrainingBucket({
    required this.label,
    required this.distanceKm,
    required this.activityCount,
    required this.isCurrent,
  });

  final String label;
  final double distanceKm;
  final int activityCount;
  final bool isCurrent;
}

DateTime _quarterStart(DateTime date) {
  final startMonth = (((date.month - 1) ~/ 3) * 3) + 1;
  return DateTime(date.year, startMonth);
}

String _formatMonth(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _formatQuarter(DateTime date) {
  final quarter = ((date.month - 1) ~/ 3) + 1;
  return 'Q$quarter/${date.year}';
}
