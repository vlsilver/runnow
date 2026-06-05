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
    super.key,
  });

  final List<ActivitySummary> activities;
  final String title;
  final bool showControls;

  @override
  State<PersonalPowerCard> createState() => _PersonalPowerCardState();
}

class _PersonalPowerCardState extends State<PersonalPowerCard> {
  var _range = PersonalPowerRange.rollingSevenDays;

  @override
  Widget build(BuildContext context) {
    final metrics = personalPowerMetricsForRange(
      widget.activities,
      DateTime.now(),
      _range,
    );
    return PowerRadarCard(
      title: '${widget.title} ${personalPowerRangeLabel(_range).toUpperCase()}',
      metrics: metrics,
      powerScore: averagePowerScore(metrics),
      controls: widget.showControls
          ? _PersonalPowerRangeControl(
              value: _range,
              onChanged: (value) => setState(() => _range = value),
            )
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xffeef4fb) : const Color(0x36020812),
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
              if (states.contains(WidgetState.selected)) return AppColors.red;
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) return Colors.white;
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
