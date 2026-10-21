import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/period_keys.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';

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

class TrainingVolumeChart extends ConsumerStatefulWidget {
  const TrainingVolumeChart({
    required this.uid,
    required this.period,
    this.mode = TrainingVolumeChartMode.bar,
    this.showControls = false,
    this.now,
    super.key,
  });

  /// Chủ của số liệu — biểu đồ đọc `users/{uid}/periodStats` (backend tính
  /// sẵn theo ngày/tuần/tháng) thay vì tải toàn bộ activity thô.
  final String uid;
  final TrainingVolumePeriod period;
  final TrainingVolumeChartMode mode;
  final bool showControls;
  final DateTime? now;

  @override
  ConsumerState<TrainingVolumeChart> createState() =>
      _TrainingVolumeChartState();
}

class _TrainingVolumeChartState extends ConsumerState<TrainingVolumeChart> {
  late TrainingVolumePeriod _period = widget.period;
  late TrainingVolumeChartMode _mode = widget.mode;
  List<PeriodStat> _stats = const [];
  var _fetchSequence = 0;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  @override
  void didUpdateWidget(covariant TrainingVolumeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _period = widget.period;
    if (oldWidget.mode != widget.mode) _mode = widget.mode;
    if (oldWidget.uid != widget.uid ||
        oldWidget.period != widget.period ||
        oldWidget.now != widget.now) {
      _fetchStats();
    }
  }

  void _fetchStats() {
    if (widget.uid.isEmpty) return;
    final now = widget.now ?? DateTime.now();
    final range = _statsRange(now, _period);
    final sequence = ++_fetchSequence;
    ref
        .read(memberRepositoryProvider)
        .listMemberPeriodStats(
          widget.uid,
          periodType: range.type,
          fromKey: range.fromKey,
          toKeyInclusive: range.toKeyInclusive,
        )
        .then((stats) {
          if (!mounted || sequence != _fetchSequence) return;
          setState(() => _stats = stats);
        })
        .catchError((Object _) {
          // Giữ nguyên số liệu đang hiện (hoặc chart rỗng) khi query lỗi.
        });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final now = widget.now ?? DateTime.now();
    final buckets = _buildBuckets(now, _stats, _period);
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
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
      gradient: LinearGradient(
        colors: [palette.glassStart, palette.glassEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'QUÃNG ĐƯỜNG',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              Text(
                _periodLabel(_period),
                style: TextStyle(
                  color: palette.accent,
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
                    onChanged: (period) {
                      setState(() => _period = period);
                      _fetchStats();
                    },
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
    final palette = context.runNowPalette;
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _gridData(context, maxY),
        titlesData: _titlesData(context, maxY: maxY, buckets: buckets),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => palette.backgroundDeep,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final bucket = buckets[group.x];
              return BarTooltipItem(
                '${bucket.label}\n'
                '${bucket.distanceKm.toStringAsFixed(2)} km\n'
                '${bucket.activityCount} buổi',
                TextStyle(
                  color: palette.foreground,
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
                  color: palette.accent.withValues(
                    alpha: buckets[index].isCurrent ? 1 : 0.58,
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
    final palette = context.runNowPalette;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(buckets.length - 1, 1).toDouble(),
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: _gridData(context, maxY),
        titlesData: _titlesData(context, maxY: maxY, buckets: buckets),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => palette.backgroundDeep,
            getTooltipItems: (spots) => spots.map((spot) {
              final index = spot.x.round().clamp(0, buckets.length - 1);
              final bucket = buckets[index];
              return LineTooltipItem(
                '${bucket.label}\n${bucket.distanceKm.toStringAsFixed(2)} km',
                TextStyle(
                  color: palette.foreground,
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
            color: palette.accent,
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
                  palette.accent.withValues(alpha: 0.24),
                  palette.accent.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

FlGridData _gridData(BuildContext context, double maxY) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return FlGridData(
    drawVerticalLine: false,
    horizontalInterval: math.max(maxY / 3, 1).toDouble(),
    getDrawingHorizontalLine: (_) =>
        FlLine(color: onSurface.withValues(alpha: 0.14), strokeWidth: 1),
  );
}

FlTitlesData _titlesData(
  BuildContext context, {
  required double maxY,
  required List<_TrainingBucket> buckets,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
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
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.54),
              fontSize: 10,
            ),
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
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.66),
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
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final selected = await showNavSelectMenu<T>(
          context: context,
          value: value,
          items: {for (final item in items) item: itemLabel(item)},
        );
        if (selected != null) onChanged(selected);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: onSurface.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.52),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  itemLabel(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: palette.accent,
              ),
            ],
          ),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.54),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Khoảng periodStats cần tải cho từng tab: tab tuần đọc doc theo ngày, tab
/// 8 tuần đọc theo tuần, các tab còn lại đều đọc theo tháng (quý/năm không
/// lưu riêng — tự cộng từ tháng khi dựng bucket).
({String type, String fromKey, String toKeyInclusive}) _statsRange(
  DateTime now,
  TrainingVolumePeriod period,
) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  return switch (period) {
    TrainingVolumePeriod.week => (
      type: 'day',
      fromKey: dayKey(weekStart),
      toKeyInclusive: dayKey(weekStart.add(const Duration(days: 6))),
    ),
    TrainingVolumePeriod.eightWeeks => (
      type: 'week',
      fromKey: weekKey(weekStart.subtract(const Duration(days: 49))),
      toKeyInclusive: weekKey(today),
    ),
    TrainingVolumePeriod.month => (
      type: 'month',
      fromKey: monthKey(today.addMonth(-11)),
      toKeyInclusive: monthKey(today),
    ),
    TrainingVolumePeriod.quarter => (
      type: 'month',
      fromKey: monthKey(_quarterStart(today).addMonth(-21)),
      toKeyInclusive: monthKey(today),
    ),
    // Năm cần toàn bộ lịch sử — chặn dưới bằng key nhỏ tuỳ ý trước khi app
    // tồn tại; số document tháng tối đa chỉ 12/năm nên vẫn rất nhỏ.
    TrainingVolumePeriod.year => (
      type: 'month',
      fromKey: '2000-01',
      toKeyInclusive: monthKey(today),
    ),
  };
}

List<_TrainingBucket> _buildBuckets(
  DateTime now,
  List<PeriodStat> stats,
  TrainingVolumePeriod period,
) {
  final byKey = {for (final stat in stats) stat.periodKey: stat};
  return switch (period) {
    TrainingVolumePeriod.week => _weekBuckets(now, byKey),
    TrainingVolumePeriod.month => _monthBuckets(now, byKey),
    TrainingVolumePeriod.quarter => _quarterBuckets(now, byKey),
    TrainingVolumePeriod.year => _yearBuckets(now, byKey),
    TrainingVolumePeriod.eightWeeks => _eightWeekBuckets(now, byKey),
  };
}

List<_TrainingBucket> _eightWeekBuckets(
  DateTime now,
  Map<String, PeriodStat> byKey,
) {
  final today = DateTime(now.year, now.month, now.day);
  final currentWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final firstWeekStart = currentWeekStart.subtract(const Duration(days: 49));
  return [
    for (var index = 0; index < 8; index++)
      _bucket(
        label: index == 7 ? 'NAY' : 'T-${7 - index}',
        stat: byKey[weekKey(firstWeekStart.add(Duration(days: index * 7)))],
        isCurrent: index == 7,
      ),
  ];
}

List<_TrainingBucket> _quarterBuckets(
  DateTime now,
  Map<String, PeriodStat> byKey,
) {
  final today = DateTime(now.year, now.month, now.day);
  final currentQuarterStart = _quarterStart(today);
  final firstQuarterStart = currentQuarterStart.addMonth(-21);
  return [
    for (var index = 0; index < 8; index++)
      _summedBucket(
        label: _formatQuarter(firstQuarterStart.addMonth(index * 3)),
        stats: [
          for (var month = 0; month < 3; month++)
            byKey[monthKey(firstQuarterStart.addMonth(index * 3 + month))],
        ],
        isCurrent: index == 7,
      ),
  ];
}

List<_TrainingBucket> _yearBuckets(
  DateTime now,
  Map<String, PeriodStat> byKey,
) {
  // Năm đầu tiên suy từ key tháng nhỏ nhất có dữ liệu (key dạng `yyyy-MM`
  // nên 4 ký tự đầu là năm).
  final firstYear = byKey.isEmpty
      ? now.year
      : byKey.keys
            .map((key) => int.tryParse(key.substring(0, 4)) ?? now.year)
            .reduce(math.min);
  final bucketCount = math.max(now.year - firstYear + 1, 1);
  return [
    for (var index = 0; index < bucketCount; index++)
      _summedBucket(
        label: '${firstYear + index}',
        stats: [
          for (var month = 1; month <= 12; month++)
            byKey[monthKey(DateTime(firstYear + index, month))],
        ],
        isCurrent: firstYear + index == now.year,
      ),
  ];
}

List<_TrainingBucket> _weekBuckets(
  DateTime now,
  Map<String, PeriodStat> byKey,
) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: today.weekday - 1));
  const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return [
    for (var index = 0; index < 7; index++)
      _bucket(
        label: labels[index],
        stat: byKey[dayKey(start.add(Duration(days: index)))],
        isCurrent: start.add(Duration(days: index)) == today,
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
  Map<String, PeriodStat> byKey,
) {
  final firstMonth = DateTime(now.year, now.month - 11);
  return [
    for (var index = 0; index < 12; index++)
      _bucket(
        label: _formatMonth(firstMonth.addMonth(index)),
        stat: byKey[monthKey(firstMonth.addMonth(index))],
        isCurrent: index == 11,
      ),
  ];
}

_TrainingBucket _bucket({
  required String label,
  required PeriodStat? stat,
  required bool isCurrent,
}) {
  return _TrainingBucket(
    label: label,
    distanceKm: (stat?.stats.distanceMeters ?? 0) / 1000,
    activityCount: stat?.stats.activityCount ?? 0,
    isCurrent: isCurrent,
  );
}

/// Bucket gộp nhiều kỳ tháng (quý = 3 tháng, năm = 12 tháng) — quãng đường
/// và số buổi cộng dồn được vì các tháng không chồng lấn nhau.
_TrainingBucket _summedBucket({
  required String label,
  required List<PeriodStat?> stats,
  required bool isCurrent,
}) {
  var distanceMeters = 0.0;
  var activityCount = 0;
  for (final stat in stats) {
    distanceMeters += stat?.stats.distanceMeters ?? 0;
    activityCount += stat?.stats.activityCount ?? 0;
  }
  return _TrainingBucket(
    label: label,
    distanceKm: distanceMeters / 1000,
    activityCount: activityCount,
    isCurrent: isCurrent,
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
