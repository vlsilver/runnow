import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/stream_sampling.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

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
          _TrainingChartCard(series: item),
          if (item != series.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class HeartRateZoneChart extends StatelessWidget {
  const HeartRateZoneChart({required this.streams, super.key});

  final Map<String, List<double>> streams;

  @override
  Widget build(BuildContext context) {
    final zones = heartRateZoneDurations(
      heartRates: streams['heartrate'],
      times: streams['time'],
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
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      gradient: const LinearGradient(
        colors: [Color(0xe607172b), Color(0xaa2b0713)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: AppColors.red, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'TIME IN HEART ZONES',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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
            ],
          ),
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
      ),
    );
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
                style: const TextStyle(color: Colors.white38, fontSize: 10),
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
                  const ColoredBox(color: Color(0x2600d9ff)),
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
            style: const TextStyle(
              color: Colors.white70,
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
  const _TrainingChartCard({required this.series});

  final _ChartSeries series;

  @override
  State<_TrainingChartCard> createState() => _TrainingChartCardState();
}

class _TrainingChartCardState extends State<_TrainingChartCard> {
  _ChartMode _mode = _ChartMode.line;
  _DistanceRange _range = _DistanceRange.meters250;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
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
      gradient: const LinearGradient(
        colors: [Color(0xe607172b), Color(0xaa062442)],
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
                  Container(
                    width: 3,
                    height: 26,
                    decoration: BoxDecoration(
                      color: series.color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      series.label,
                      style: TextStyle(
                        color: series.color,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    series.unit,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                      Row(
                        children: [
                          Expanded(
                            child: _CompactSelector<_ChartMode>(
                              label: 'KIỂU',
                              value: _mode,
                              items: _ChartMode.values,
                              itemLabel: (mode) => mode.label,
                              onChanged: (mode) => setState(() => _mode = mode),
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
                      const Padding(
                        padding: EdgeInsets.only(left: 52),
                        child: Text(
                          'Quãng đường đã chạy',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
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
        gridData: _gridData(yInterval: yInterval, xInterval: xInterval),
        titlesData: _titlesData(
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
        gridData: _gridData(yInterval: yInterval, xInterval: xInterval),
        titlesData: _titlesData(
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x52020812),
        border: Border.all(color: AppColors.glassBorder),
        borderRadius: BorderRadius.circular(6),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

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
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ChartSeries {
  const _ChartSeries({
    required this.label,
    required this.unit,
    required this.color,
    required this.values,
    required this.distances,
    required this.normalize,
    required this.accept,
    required this.format,
    required this.formatAxis,
  });

  factory _ChartSeries.pace(List<double> speeds, List<double>? distances) {
    return _ChartSeries(
      label: 'Pace',
      unit: 'PHÚT / KM',
      color: const Color(0xffff8f00),
      values: speeds,
      distances: distances,
      normalize: (speed) => 1000 / speed,
      accept: (speed) => speed >= 0.8,
      format: _formatPace,
      formatAxis: _formatPaceAxis,
    );
  }

  factory _ChartSeries.heartRate(List<double> values, List<double>? distances) {
    return _ChartSeries(
      label: 'Nhịp tim',
      unit: 'BPM',
      color: AppColors.red,
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
      color: AppColors.blue,
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
      color: AppColors.amber,
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
      color: const Color(0xff9c6cff),
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
  final Color color;
  final List<double> values;
  final List<double>? distances;
  final double Function(double value) normalize;
  final bool Function(double value) accept;
  final String Function(double value) format;
  final String Function(double value) formatAxis;

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

FlGridData _gridData({required double yInterval, required double xInterval}) {
  return FlGridData(
    horizontalInterval: yInterval,
    verticalInterval: xInterval,
    getDrawingHorizontalLine: (_) =>
        const FlLine(color: Colors.white24, strokeWidth: 1),
    getDrawingVerticalLine: (_) =>
        const FlLine(color: Colors.white12, strokeWidth: 1),
  );
}

FlTitlesData _titlesData({
  required _ChartSeries series,
  required double yInterval,
  required double xInterval,
  List<FlSpot>? barPoints,
}) {
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
            style: const TextStyle(color: Colors.white54, fontSize: 11),
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
              style: const TextStyle(color: Colors.white54, fontSize: 11),
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
