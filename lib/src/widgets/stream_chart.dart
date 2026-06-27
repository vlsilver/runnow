import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/stream_sampling.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';

enum _ChartMode { line, bar }

extension on _ChartMode {
  String get label => switch (this) {
    _ChartMode.line => 'Line',
    _ChartMode.bar => 'Cột',
  };
}

enum _DistanceRange {
  meters100(100, '100m'),
  meters250(250, '250m'),
  meters500(500, '500m'),
  kilometer(1000, '1km');

  const _DistanceRange(this.meters, this.label);

  final double meters;
  final String label;
}

class StreamChart extends StatelessWidget {
  const StreamChart({required this.streams, super.key});

  final Map<String, List<double>> streams;

  @override
  Widget build(BuildContext context) {
    final distances = streams['distance'];
    final energyKilojoules = cumulativeEnergyKilojoules(
      watts: streams['watts'],
      times: streams['time'],
    );
    final series = <_ChartSeries>[
      if (streams['velocity_smooth']?.isNotEmpty == true)
        _ChartSeries.pace(streams['velocity_smooth']!, distances),
      if (streams['heartrate']?.isNotEmpty == true)
        _ChartSeries.heartRate(streams['heartrate']!, distances),
      if (streams['altitude']?.isNotEmpty == true)
        _ChartSeries.altitude(streams['altitude']!, distances),
      if (streams['cadence']?.isNotEmpty == true)
        _ChartSeries.cadence(streams['cadence']!, distances),
      if (energyKilojoules.length > 1)
        _ChartSeries.energy(energyKilojoules, distances),
    ];
    if (series.isEmpty) {
      return const Text('Không có dữ liệu biểu đồ cho hoạt động này.');
    }
    return Column(
      children: [
        for (final item in series) ...[
          _ShareableTelemetryCard(
            title: 'RunNow ${item.label}',
            builder: (sharing) =>
                _TrainingChartCard(series: item, shareMode: sharing),
          ),
          if (item != series.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class HeartRateZoneChart extends StatefulWidget {
  const HeartRateZoneChart({required this.streams, super.key});

  final Map<String, List<double>> streams;

  @override
  State<HeartRateZoneChart> createState() => _HeartRateZoneChartState();
}

class _HeartRateZoneChartState extends State<HeartRateZoneChart> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final zones = heartRateZoneDurations(
      heartRates: widget.streams['heartrate'],
      times: widget.streams['time'],
    );
    final activeZones = zones.where((zone) => zone.seconds > 0).toList();
    if (activeZones.isEmpty) return const SizedBox.shrink();
    final totalSeconds = activeZones.fold<double>(
      0,
      (sum, zone) => sum + zone.seconds,
    );
    final maxSeconds = zones.fold<double>(
      0,
      (max, item) => item.seconds > max ? item.seconds : max,
    );
    return _ShareableTelemetryCard(
      title: 'RunNow heart zones',
      builder: (sharing) => GlassPanel(
        padding: const EdgeInsets.all(16),
        gradient: LinearGradient(
          colors: isLight
              ? const [Color(0xffe2e6ed), Color(0xffd4dbe3)]
              : const [Color(0xe607172b), Color(0xaa2b0713)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: AppColors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'TIME IN HEART ZONES',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    Text(
                      formatDuration(totalSeconds.round()),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!sharing) ...[
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: AppColors.blueGlow,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      children: [
                        const SizedBox(height: 14),
                        for (final zone in zones) ...[
                          _HeartRateZoneRow(
                            zone: zone,
                            totalSeconds: totalSeconds,
                            maxSeconds: maxSeconds,
                          ),
                          if (zone != zones.last) const SizedBox(height: 10),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareableTelemetryCard extends StatefulWidget {
  const _ShareableTelemetryCard({required this.title, required this.builder});

  final String title;
  final Widget Function(bool sharing) builder;

  @override
  State<_ShareableTelemetryCard> createState() =>
      _ShareableTelemetryCardState();
}

class _ShareableTelemetryCardState extends State<_ShareableTelemetryCard> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _sharing ? null : _share,
      child: RepaintBoundary(key: _cardKey, child: widget.builder(_sharing)),
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    HapticFeedback.mediumImpact();
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await shareDashboardCard(
        cardKey: _cardKey,
        shareOriginContext: context,
        title: widget.title,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể chia sẻ: $error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

class _HeartRateZoneRow extends StatelessWidget {
  const _HeartRateZoneRow({
    required this.zone,
    required this.totalSeconds,
    required this.maxSeconds,
  });

  final HeartRateZoneDuration zone;
  final double totalSeconds;
  final double maxSeconds;

  @override
  Widget build(BuildContext context) {
    final percent = totalSeconds <= 0 ? 0 : zone.seconds / totalSeconds;
    final widthFactor = maxSeconds <= 0 ? 0 : zone.seconds / maxSeconds;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zone.label,
                style: TextStyle(
                  color: zone.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                zone.rangeLabel,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.42),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 14,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: AppColors.blueGlow.withValues(alpha: 0.14)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: widthFactor.clamp(0, 1).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            zone.color.withValues(alpha: 0.52),
                            zone.color,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(
            '${formatDuration(zone.seconds.round())} · ${(percent * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.68),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrainingChartCard extends StatefulWidget {
  const _TrainingChartCard({required this.series, required this.shareMode});

  final _ChartSeries series;
  final bool shareMode;

  @override
  State<_TrainingChartCard> createState() => _TrainingChartCardState();
}

class _TrainingChartCardState extends State<_TrainingChartCard> {
  _ChartMode _mode = _ChartMode.bar;
  _DistanceRange _range = _DistanceRange.meters250;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.series.defaultExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final points = series.points(_range);
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }
    final values = points.map((point) => point.y).toList();
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final average =
        values.reduce((left, right) => left + right) / values.length;
    final range = math.max(max - min, 1);
    final chartMin = min - (range * 0.12);
    final chartMax = max + (range * 0.12);
    final yInterval = math.max((chartMax - chartMin) / 2, 1).toDouble();
    final maxX = math.max(points.last.x, 0.1);
    final xInterval = math.max(maxX / 2, 0.1).toDouble();
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd3dae3)]
            : const [Color(0xe607172b), Color(0xaa062442)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(series.icon, color: series.color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      series.label,
                      style: TextStyle(
                        color: series.color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  Text(
                    series.unit,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (!widget.shareMode) ...[
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.blueGlow,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _Stat(label: 'TB', value: series.format(average)),
                          const SizedBox(width: 20),
                          _Stat(label: 'MIN', value: series.format(min)),
                          const SizedBox(width: 20),
                          _Stat(label: 'MAX', value: series.format(max)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!widget.shareMode) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _CompactSelector<_ChartMode>(
                                label: 'KIỂU',
                                value: _mode,
                                items: _ChartMode.values,
                                itemLabel: (mode) => mode.label,
                                onChanged: (mode) =>
                                    setState(() => _mode = mode),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactSelector<_DistanceRange>(
                                label: 'RANGE',
                                value: _range,
                                items: _DistanceRange.values,
                                itemLabel: (range) => range.label,
                                onChanged: (range) =>
                                    setState(() => _range = range),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ] else
                        const SizedBox(height: 4),
                      SizedBox(
                        height: 190,
                        child: _mode == _ChartMode.line
                            ? _LineTrainingChart(
                                series: series,
                                points: points,
                                chartMin: chartMin,
                                chartMax: chartMax,
                                yInterval: yInterval,
                                xInterval: xInterval,
                              )
                            : _BarTrainingChart(
                                series: series,
                                points: points,
                                chartMin: chartMin,
                                chartMax: chartMax,
                                yInterval: yInterval,
                                xInterval: xInterval,
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 52),
                        child: Text(
                          'Quãng đường đã chạy',
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.52),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _LineTrainingChart extends StatelessWidget {
  const _LineTrainingChart({
    required this.series,
    required this.points,
    required this.chartMin,
    required this.chartMax,
    required this.yInterval,
    required this.xInterval,
  });

  final _ChartSeries series;
  final List<FlSpot> points;
  final double chartMin;
  final double chartMax;
  final double yInterval;
  final double xInterval;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: math.max(points.last.x, 0.1),
        minY: chartMin,
        maxY: chartMax,
        borderData: FlBorderData(show: false),
        gridData: _gridData(
          context,
          yInterval: yInterval,
          xInterval: xInterval,
        ),
        titlesData: _titlesData(
          context,
          series: series,
          yInterval: yInterval,
          xInterval: xInterval,
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => AppColors.black,
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    series.format(spot.y),
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            color: series.color,
            barWidth: 3,
            isCurved: true,
            preventCurveOverShooting: true,
            curveSmoothness: 0.36,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  series.color.withValues(alpha: 0.24),
                  series.color.withValues(alpha: 0.02),
                ],
              ),
            ),
            spots: points,
          ),
        ],
      ),
    );
  }
}

class _BarTrainingChart extends StatelessWidget {
  const _BarTrainingChart({
    required this.series,
    required this.points,
    required this.chartMin,
    required this.chartMax,
    required this.yInterval,
    required this.xInterval,
  });

  final _ChartSeries series;
  final List<FlSpot> points;
  final double chartMin;
  final double chartMax;
  final double yInterval;
  final double xInterval;

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        minY: chartMin,
        maxY: chartMax,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: _gridData(
          context,
          yInterval: yInterval,
          xInterval: xInterval,
        ),
        titlesData: _titlesData(
          context,
          series: series,
          yInterval: yInterval,
          xInterval: xInterval,
          barPoints: points,
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.black,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                series.format(rod.toY),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        barGroups: [
          for (var index = 0; index < points.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  fromY: chartMin,
                  toY: points[index].y,
                  width: math.max(4, math.min(12, 160 / points.length)),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      series.color.withValues(alpha: 0.35),
                      series.color,
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
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
    final isLight = Theme.of(context).brightness == Brightness.light;
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
          color: isLight ? const Color(0xffd8dee6) : const Color(0x52020812),
          border: Border.all(
            color: isLight ? const Color(0x2208172b) : AppColors.glassBorder,
          ),
          borderRadius: BorderRadius.circular(6),
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
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

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
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _ChartSeries {
  const _ChartSeries({
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.values,
    required this.distances,
    required this.normalize,
    required this.accept,
    required this.format,
    required this.formatAxis,
    this.defaultExpanded = false,
  });

  factory _ChartSeries.pace(List<double> speeds, List<double>? distances) {
    return _ChartSeries(
      label: 'Pace',
      unit: 'PHÚT / KM',
      icon: Icons.speed_rounded,
      color: const Color(0xff5bc8ff),
      values: speeds,
      distances: distances,
      normalize: (speed) => 1000 / speed,
      accept: (speed) => speed >= 0.8,
      format: _formatPace,
      formatAxis: _formatPaceAxis,
      defaultExpanded: true,
    );
  }

  factory _ChartSeries.heartRate(List<double> values, List<double>? distances) {
    return _ChartSeries(
      label: 'Nhịp tim',
      unit: 'BPM',
      icon: Icons.favorite_rounded,
      color: const Color(0xff2f8dff),
      values: values,
      distances: distances,
      normalize: (value) => value,
      accept: (value) => value > 0,
      format: (value) => '${value.round()} bpm',
      formatAxis: (value) => '${value.round()}',
    );
  }

  factory _ChartSeries.altitude(List<double> values, List<double>? distances) {
    return _ChartSeries(
      label: 'Cao độ',
      unit: 'MÉT',
      icon: Icons.terrain_rounded,
      color: const Color(0xff7c9bef),
      values: values,
      distances: distances,
      normalize: (value) => value,
      accept: (_) => true,
      format: (value) => '${value.round()} m',
      formatAxis: (value) => '${value.round()}',
    );
  }

  factory _ChartSeries.cadence(List<double> values, List<double>? distances) {
    return _ChartSeries(
      label: 'Cadence',
      unit: 'RPM',
      icon: Icons.directions_walk_rounded,
      color: const Color(0xff58b0d8),
      values: values,
      distances: distances,
      normalize: (value) => value,
      accept: (value) => value > 0,
      format: (value) => '${value.round()} rpm',
      formatAxis: (value) => '${value.round()}',
    );
  }

  factory _ChartSeries.energy(List<double> values, List<double>? distances) {
    return _ChartSeries(
      label: 'Năng lượng',
      unit: 'KJ',
      icon: Icons.bolt_rounded,
      color: const Color(0xff8f7fe0),
      values: values,
      distances: distances,
      normalize: (value) => value,
      accept: (value) => value >= 0,
      format: (value) => '${value.toStringAsFixed(1)} kJ',
      formatAxis: (value) => value.toStringAsFixed(1),
    );
  }

  final String label;
  final String unit;
  final IconData icon;
  final Color color;
  final List<double> values;
  final List<double>? distances;
  final double Function(double value) normalize;
  final bool Function(double value) accept;
  final String Function(double value) format;
  final String Function(double value) formatAxis;
  final bool defaultExpanded;

  List<FlSpot> points(_DistanceRange range) {
    final samples = standardizeDistanceSeries(
      distances: distances,
      values: values,
      intervalMeters: range.meters,
      accept: accept,
    );
    return [
      for (final sample in samples)
        FlSpot(sample.distanceMeters / 1000, normalize(sample.value)),
    ];
  }

  String formatDistance(double value) => '${value.toStringAsFixed(1)} km';
}

FlGridData _gridData(
  BuildContext context, {
  required double yInterval,
  required double xInterval,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return FlGridData(
    horizontalInterval: yInterval,
    verticalInterval: xInterval,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: onSurface.withValues(alpha: 0.14), strokeWidth: 1),
    getDrawingVerticalLine: (_) =>
        FlLine(color: onSurface.withValues(alpha: 0.08), strokeWidth: 1),
  );
}

FlTitlesData _titlesData(
  BuildContext context, {
  required _ChartSeries series,
  required double yInterval,
  required double xInterval,
  List<FlSpot>? barPoints,
}) {
  final onSurface = Theme.of(context).colorScheme.onSurface;
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 52,
        interval: yInterval,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            series.formatAxis(value),
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
        reservedSize: 24,
        interval: barPoints == null ? xInterval : 1,
        getTitlesWidget: (value, meta) {
          final distance = barPoints == null
              ? _lineAxisDistance(value, meta)
              : barAxisDistance(value, barPoints);
          if (distance == null) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(
              series.formatDistance(distance),
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.54),
                fontSize: 10,
              ),
            ),
          );
        },
      ),
    ),
  );
}

double? _lineAxisDistance(double value, TitleMeta meta) {
  const tolerance = 0.001;
  final middle = meta.max / 2;
  if ((value - meta.min).abs() < tolerance) return meta.min;
  if ((value - middle).abs() < tolerance) return middle;
  if ((value - meta.max).abs() < tolerance) return meta.max;
  return null;
}

@visibleForTesting
double? barAxisDistance(double value, List<FlSpot> points) {
  final index = value.round();
  if ((value - index).abs() > 0.001 || index < 0 || index >= points.length) {
    return null;
  }
  final middle = (points.length - 1) ~/ 2;
  if (index != 0 && index != middle && index != points.length - 1) return null;
  return points[index].x;
}

String _formatPace(double seconds) => formatPace(seconds);

String _formatPaceAxis(double seconds) =>
    formatPace(seconds).replaceFirst(' /km', '');

class HeartRateZoneDuration {
  const HeartRateZoneDuration({
    required this.label,
    required this.rangeLabel,
    required this.color,
    required this.seconds,
  });

  final String label;
  final String rangeLabel;
  final Color color;
  final double seconds;
}

@visibleForTesting
List<HeartRateZoneDuration> heartRateZoneDurations({
  required List<double>? heartRates,
  required List<double>? times,
}) {
  if (heartRates == null || heartRates.isEmpty) return const [];
  final secondsByZone = List<double>.filled(_heartRateZones.length, 0);
  for (var index = 0; index < heartRates.length; index++) {
    final heartRate = heartRates[index];
    if (heartRate <= 0) continue;
    final duration = _sampleDurationSeconds(times, index);
    if (duration <= 0) continue;
    final zoneIndex = _heartRateZoneIndex(heartRate);
    secondsByZone[zoneIndex] += duration;
  }
  return [
    for (var index = 0; index < _heartRateZones.length; index++)
      HeartRateZoneDuration(
        label: _heartRateZones[index].label,
        rangeLabel: _heartRateZones[index].rangeLabel,
        color: _heartRateZones[index].color,
        seconds: secondsByZone[index],
      ),
  ];
}

double _sampleDurationSeconds(List<double>? times, int index) {
  if (times == null || times.isEmpty) return 1;
  if (index < times.length - 1) {
    return math.max(times[index + 1] - times[index], 0);
  }
  if (index > 0 && index < times.length) {
    return math.max(times[index] - times[index - 1], 0);
  }
  return 1;
}

int _heartRateZoneIndex(double heartRate) {
  for (var index = 0; index < _heartRateZones.length; index++) {
    if (heartRate < _heartRateZones[index].upperExclusiveBpm) return index;
  }
  return _heartRateZones.length - 1;
}

const _heartRateZones = [
  _HeartRateZone('Z1', '<130 bpm', Color(0xff00d9ff), 130),
  _HeartRateZone('Z2', '130-149', Color(0xff19d27f), 150),
  _HeartRateZone('Z3', '150-169', Color(0xffffd166), 170),
  _HeartRateZone('Z4', '170-184', Color(0xffff8f00), 185),
  _HeartRateZone('Z5', '185+', AppColors.red, double.infinity),
];

class _HeartRateZone {
  const _HeartRateZone(
    this.label,
    this.rangeLabel,
    this.color,
    this.upperExclusiveBpm,
  );

  final String label;
  final String rangeLabel;
  final Color color;
  final double upperExclusiveBpm;
}
