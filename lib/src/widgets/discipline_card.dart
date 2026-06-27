import 'package:flutter/material.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class DisciplineCard extends StatelessWidget {
  const DisciplineCard({required this.stats, super.key});

  final DisciplineStats stats;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd2d9e2)]
            : const [Color(0xe607172b), Color(0xaa071426)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department,
                color: AppColors.red,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'KỶ LUẬT CÁ NHÂN',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.66),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                _disciplineGrade(stats.activeRatio),
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.activeDays}',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '/ 30 ngày có hoạt động',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.58),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DisciplineTimeline(days: stats.days),
          const SizedBox(height: 16),
          _DisciplineMetricGrid(stats: stats),
        ],
      ),
    );
  }
}

class _DisciplineMetricGrid extends StatelessWidget {
  const _DisciplineMetricGrid({required this.stats});

  final DisciplineStats stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _DisciplineMetricData(
        label: 'CHUỖI NGÀY',
        value: '${stats.currentDayStreak}',
        suffix: 'ngày',
        color: AppColors.red,
      ),
      _DisciplineMetricData(
        label: 'CHUỖI TUẦN',
        value: '${stats.weeklyStreak}',
        suffix: 'tuần',
        color: AppColors.blueGlow,
      ),
      _DisciplineMetricData(
        label: 'PACE NHANH',
        value: formatPace(stats.fastestPaceSecondsPerKm),
        color: AppColors.amber,
      ),
      _DisciplineMetricData(
        label: 'DÀI NHẤT',
        value: formatDistance(stats.longestDistanceMeters),
        color: AppColors.blue,
      ),
      _DisciplineMetricData(
        label: 'NHỊP / TUẦN',
        value: stats.averageActivitiesPerWeek.toStringAsFixed(1),
        suffix: 'buổi',
        color: const Color(0xff9c6cff),
      ),
      _DisciplineMetricData(
        label: 'TỔNG 30 NGÀY',
        value: formatDistance(stats.totalDistanceMeters),
        color: AppColors.blueGlow,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.55,
      ),
      itemBuilder: (context, index) => _DisciplineMetric(item: items[index]),
    );
  }
}

class _DisciplineTimeline extends StatelessWidget {
  const _DisciplineTimeline({required this.days});

  final List<DisciplineDay> days;

  @override
  Widget build(BuildContext context) {
    final maxDistance = days.fold<double>(
      0,
      (max, day) => day.distanceMeters > max ? day.distanceMeters : max,
    );
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: _DisciplineCell(day: day, maxDistance: maxDistance),
            ),
          ),
      ],
    );
  }
}

class _DisciplineCell extends StatelessWidget {
  const _DisciplineCell({required this.day, required this.maxDistance});

  final DisciplineDay day;
  final double maxDistance;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final strength = maxDistance <= 0 ? 0.0 : day.distanceMeters / maxDistance;
    final color = day.active
        ? Color.lerp(AppColors.red, AppColors.blueGlow, strength)!
        : onSurface.withValues(alpha: 0.1);
    return Tooltip(
      message:
          '${day.date.day}/${day.date.month}: '
          '${formatDistance(day.distanceMeters)}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: day.active ? 28 : 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          boxShadow: day.active
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _DisciplineMetricData {
  const _DisciplineMetricData({
    required this.label,
    required this.value,
    required this.color,
    this.suffix,
  });

  final String label;
  final String value;
  final String? suffix;
  final Color color;
}

class _DisciplineMetric extends StatelessWidget {
  const _DisciplineMetric({required this.item});

  final _DisciplineMetricData item;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xffd8dee6) : const Color(0x36020812),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.52),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                color: onSurface,
                fontFamily: 'Exo 2',
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              children: [
                TextSpan(
                  text: item.value,
                  style: TextStyle(color: item.color),
                ),
                if (item.suffix != null)
                  TextSpan(
                    text: ' ${item.suffix}',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _disciplineGrade(double ratio) {
  if (ratio >= 0.5) return 'CONSISTENT';
  if (ratio >= 0.25) return 'BUILDING';
  return 'RESTART';
}
