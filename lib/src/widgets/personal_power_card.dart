import 'package:flutter/material.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/power_radar_card.dart';

class PersonalPowerCard extends StatefulWidget {
  const PersonalPowerCard({
    required this.activities,
    this.title = 'PERSONAL POWER',
    this.showControls = true,
    this.range,
    this.onRangeChanged,
    super.key,
  });

  final List<ActivitySummary> activities;
  final String title;
  final bool showControls;

  /// Khi được cấp, card hiển thị theo range ngoài (controlled) — dùng cho
  /// trường hợp filter nằm ở navigation bar. Bỏ trống thì card tự quản lý.
  final PersonalPowerRange? range;
  final ValueChanged<PersonalPowerRange>? onRangeChanged;

  @override
  State<PersonalPowerCard> createState() => _PersonalPowerCardState();
}

class _PersonalPowerCardState extends State<PersonalPowerCard> {
  var _internalRange = PersonalPowerRange.rollingSevenDays;
  late DateTime _metricsDate;
  late PersonalPowerRange _metricsRange;
  late List<ActivitySummary> _metricsActivities;
  late List<PowerRadarMetric> _metrics;

  PersonalPowerRange get _range => widget.range ?? _internalRange;

  @override
  void initState() {
    super.initState();
    _recomputeMetrics();
  }

  @override
  void didUpdateWidget(covariant PersonalPowerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activities, widget.activities) ||
        oldWidget.range != widget.range) {
      _recomputeMetrics();
    }
  }

  void _recomputeMetrics([DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    _metricsDate = DateTime(now.year, now.month, now.day);
    _metricsRange = _range;
    _metricsActivities = widget.activities;
    _metrics = personalPowerMetricsForRange(widget.activities, now, _range);
  }

  void _setRange(PersonalPowerRange value) {
    widget.onRangeChanged?.call(value);
    if (widget.range == null) {
      setState(() {
        _internalRange = value;
        _recomputeMetrics();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (!identical(_metricsActivities, widget.activities) ||
        _metricsRange != _range ||
        _metricsDate.year != now.year ||
        _metricsDate.month != now.month ||
        _metricsDate.day != now.day) {
      _recomputeMetrics(now);
    }
    return PowerRadarCard(
      title: '${widget.title} ${personalPowerRangeLabel(_range).toUpperCase()}',
      metrics: _metrics,
      powerScore: averagePowerScore(_metrics),
      controls: widget.showControls
          ? _PersonalPowerRangeControl(value: _range, onChanged: _setRange)
          : null,
    );
  }
}

class _PersonalPowerRangeControl extends StatelessWidget {
  const _PersonalPowerRangeControl({
    required this.value,
    required this.onChanged,
  });

  final PersonalPowerRange value;
  final ValueChanged<PersonalPowerRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<PersonalPowerRange>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return palette.accent;
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return palette.glassStart;
              }
              return Theme.of(context).colorScheme.onSurface;
            }),
            side: WidgetStateProperty.all(BorderSide.none),
          ),
          segments: const [
            ButtonSegment(
              value: PersonalPowerRange.currentWeek,
              label: Text('Tuần'),
            ),
            ButtonSegment(
              value: PersonalPowerRange.rollingSevenDays,
              label: Text('7 ngày'),
            ),
            ButtonSegment(
              value: PersonalPowerRange.currentMonth,
              label: Text('Tháng'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.single),
        ),
      ),
    );
  }
}
