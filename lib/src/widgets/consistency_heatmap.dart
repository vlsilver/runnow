import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class ConsistencyHeatmap extends StatelessWidget {
  const ConsistencyHeatmap({required this.activities, this.now, super.key});

  final List<ActivitySummary> activities;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final days = _heatmapDays(now ?? DateTime.now(), activities);
    final maxDistance = days.fold<double>(
      0,
      (maximum, day) => math.max(maximum, day.distanceMeters),
    );
    final activeDays = days.where((day) => day.distanceMeters > 0).length;
    final streak = _activeWeekStreak(days);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd3dae3)]
            : const [Color(0xe607172b), Color(0xb3062442)],
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
                'CONSISTENCY',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Text(
                '8 TUẦN',
                style: TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeatmapStat(label: 'NGÀY HOẠT ĐỘNG', value: '$activeDays'),
              const SizedBox(width: 28),
              _HeatmapStat(label: 'STREAK', value: '$streak tuần'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Column(
                  children: [
                    _DayLabel('T2'),
                    _DayLabel('T4'),
                    _DayLabel('T6'),
                    _DayLabel('CN'),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var week = 0; week < 8; week++)
                      Column(
                        children: [
                          for (var day = 0; day < 7; day++)
                            _HeatmapCell(
                              day: days[(week * 7) + day],
                              maxDistance: maxDistance,
                            ),
                        ],
                      ),
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

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({required this.day, required this.maxDistance});

  final _HeatmapDay day;
  final double maxDistance;

  @override
  Widget build(BuildContext context) {
    final strength = maxDistance <= 0 ? 0.0 : day.distanceMeters / maxDistance;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message:
          '${day.date.day}/${day.date.month}: '
          '${(day.distanceMeters / 1000).toStringAsFixed(1)} km',
      child: Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: day.distanceMeters <= 0
              ? onSurface.withValues(alpha: 0.06)
              : Color.lerp(
                  AppColors.blue.withValues(alpha: 0.5),
                  AppColors.blueGlow,
                  strength,
                ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: onSurface.withValues(alpha: 0.12)),
        ),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        fontSize: 10,
      ),
    ),
  );
}

class _HeatmapStat extends StatelessWidget {
  const _HeatmapStat({required this.label, required this.value});

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

List<_HeatmapDay> _heatmapDays(DateTime now, List<ActivitySummary> activities) {
  final today = DateTime(now.year, now.month, now.day);
  final currentWeekStart = today.subtract(Duration(days: today.weekday - 1));
  final firstDay = currentWeekStart.subtract(const Duration(days: 49));
  return [
    for (var index = 0; index < 56; index++)
      _HeatmapDay(
        date: firstDay.add(Duration(days: index)),
        distanceMeters: activities
            .where(
              (activity) => _sameDay(
                activity.startedAt,
                firstDay.add(Duration(days: index)),
              ),
            )
            .fold(0, (sum, activity) => sum + activity.distanceMeters),
      ),
  ];
}

int _activeWeekStreak(List<_HeatmapDay> days) {
  var streak = 0;
  for (var week = 7; week >= 0; week--) {
    final start = week * 7;
    final active = days
        .skip(start)
        .take(7)
        .any((day) => day.distanceMeters > 0);
    if (!active) break;
    streak++;
  }
  return streak;
}

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

class _HeatmapDay {
  const _HeatmapDay({required this.date, required this.distanceMeters});

  final DateTime date;
  final double distanceMeters;
}
