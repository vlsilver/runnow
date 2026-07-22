import 'dart:async';

// TODO(runnow): xoa cac widget dashboard legacy sau khi UI Tong quan moi on dinh.
// ignore_for_file: unused_element

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  void _openJournal(BuildContext context) {
    context.push('/profile/journal');
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(userProfileProvider);
    final profileLoading = profileState.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );
    final stravaConnected = ref.watch(stravaConnectionProvider);
    final connectionLoading = ref.watch(stravaConnectionLoadingProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tổng quan'),
        actions: [
          IconButton(
            tooltip: 'Mở nhật ký session',
            onPressed: () => _openJournal(context),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: profileLoading || connectionLoading
          ? const RunNowLoading(
              label: 'Đang tải cá nhân',
              revealDelay: Duration.zero,
            )
          : stravaConnected
          ? ref
                .watch(activitiesProvider)
                .when(
                  data: (items) => _DashboardBody(activities: items),
                  error: (error, stack) =>
                      Center(child: Text('Không thể tải dữ liệu: $error')),
                  loading: () => const RunNowLoading(
                    label: 'Đang tải cá nhân',
                    revealDelay: Duration.zero,
                  ),
                )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Tổng quan',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _ConnectStravaCard(
                  loading: ref.watch(stravaAuthProvider).loading,
                  errorMessage: ref.watch(stravaAuthProvider).errorMessage,
                  onConnect: ref.read(stravaAuthProvider).connect,
                ),
              ],
            ),
    );
  }
}

enum _WeekViewMode { rollingSevenDays, currentWeek }

/// Các card ở Tổng quan có filter (đưa lên navigation bar).
enum DashboardCard { week, power, volume }

/// Card đang ở vùng trên viewport (theo scroll). Null = đang ở card không có
/// filter -> nav ẩn filter đi.
final dashboardActiveCardProvider = StateProvider<DashboardCard?>(
  (ref) => null,
);
final dashboardWeekModeProvider = StateProvider<_WeekViewMode>(
  (ref) => _WeekViewMode.currentWeek,
);
final dashboardPowerRangeProvider = StateProvider<PersonalPowerRange>(
  (ref) => PersonalPowerRange.rollingSevenDays,
);
final dashboardVolumePeriodProvider = StateProvider<TrainingVolumePeriod>(
  (ref) => TrainingVolumePeriod.month,
);
final dashboardVolumeModeProvider = StateProvider<TrainingVolumeChartMode>(
  (ref) => TrainingVolumeChartMode.bar,
);

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({required this.activities});
  final List<ActivitySummary> activities;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  final _scrollKey = GlobalKey();
  final _powerKey = GlobalKey();
  late DateTime _dataDate;
  late List<ActivitySummary> _recent;

  @override
  void initState() {
    super.initState();
    _recomputeData();
  }

  @override
  void didUpdateWidget(covariant _DashboardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activities, widget.activities)) {
      _recomputeData();
    }
  }

  void _recomputeData([DateTime? currentTime]) {
    final now = currentTime ?? DateTime.now();
    _dataDate = DateTime(now.year, now.month, now.day);
    _recent = [...widget.activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = kIsWeb
        ? RunNowWebLayout.isDesktop(context)
        : screenWidth >= 900;
    final now = DateTime.now();
    if (_dataDate.year != now.year ||
        _dataDate.month != now.month ||
        _dataDate.day != now.day) {
      _recomputeData(now);
    }
    final densityRange = ref.watch(dashboardPowerRangeProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(dashboardActiveCardProvider) != DashboardCard.power) {
        ref.read(dashboardActiveCardProvider.notifier).state =
            DashboardCard.power;
      }
    });
    final header = Text(
      'Tổng quan',
      style: Theme.of(
        context,
      ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final stability = _StabilitySnapshot.fromActivities(
      widget.activities,
      now,
      densityRange,
    );
    final overview = _SimpleStatsOverview(
      stability: stability,
      range: densityRange,
    );
    final journalEntry = _JournalEntryCard(
      recent: _recent,
      onTap: () => context.push('/profile/journal'),
    );

    if (wide) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          screenWidth >= RunNowWebLayout.wideBreakpoint ? 18 : 0,
          8,
          screenWidth >= RunNowWebLayout.wideBreakpoint ? 18 : 0,
          32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: overview),
                const SizedBox(width: 18),
                Expanded(child: journalEntry),
              ],
            ),
          ],
        ),
      );
    }

    return ListView(
      key: _scrollKey,
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: header,
        ),
        const SizedBox(height: 12),
        KeyedSubtree(key: _powerKey, child: overview),
        const SizedBox(height: 16),
        journalEntry,
      ],
    );
  }
}

class _SimpleStatsOverview extends StatelessWidget {
  const _SimpleStatsOverview({required this.stability, required this.range});

  final _StabilitySnapshot stability;
  final PersonalPowerRange range;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      gradient: LinearGradient(
        colors: [palette.glassStart, palette.glassEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.track_changes_rounded,
                color: palette.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ĐỘ ỔN ĐỊNH',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                personalPowerRangeLabel(range).toUpperCase(),
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stability.score}',
                style: TextStyle(
                  color: onSurface,
                  fontSize: 58,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'stability',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.48),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            stability.message,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.62),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          _StabilityMetricRow(stability: stability),
          const SizedBox(height: 22),
          _DensitySection(days: stability.days, range: range),
        ],
      ),
    );
  }
}

class _StabilityMetricRow extends StatelessWidget {
  const _StabilityMetricRow({required this.stability});

  final _StabilitySnapshot stability;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactMetric(
            label: 'ACTIVE',
            value: '${(stability.activeRatio * 100).round()}%',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CompactMetric(
            label: 'NHỊP',
            value: '${stability.activityCount}',
            suffix: 'buổi',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CompactMetric(
            label: 'KM',
            value: formatDistance(stability.distanceMeters),
          ),
        ),
      ],
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        border: Border(left: BorderSide(color: palette.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.44),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: value,
              children: [
                if (suffix != null)
                  TextSpan(
                    text: ' $suffix',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.accent,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DensitySection extends StatelessWidget {
  const _DensitySection({required this.days, required this.range});

  final List<_DensityDay> days;
  final PersonalPowerRange range;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final activeDays = days.where((day) => day.distanceMeters > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'MẬT ĐỘ',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.62),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Text(
              '$activeDays/${days.length} ngày',
              style: TextStyle(
                color: context.runNowPalette.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DensityGrid(days: days, range: range),
      ],
    );
  }
}

class _DensityGrid extends StatelessWidget {
  const _DensityGrid({required this.days, required this.range});

  final List<_DensityDay> days;
  final PersonalPowerRange range;

  @override
  Widget build(BuildContext context) {
    final columns = switch (range) {
      PersonalPowerRange.currentMonth => 7,
      PersonalPowerRange.currentWeek ||
      PersonalPowerRange.rollingSevenDays => 7,
    };
    final maxDistance = days.fold<double>(
      0,
      (max, day) => day.distanceMeters > max ? day.distanceMeters : max,
    );
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: days.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        final day = days[index];
        final label = range == PersonalPowerRange.currentMonth
            ? '${day.date.day}'
            : _densityWeekdayLabel(day.date);
        return _DensityCell(day: day, label: label, maxDistance: maxDistance);
      },
    );
  }
}

class _DensityCell extends StatelessWidget {
  const _DensityCell({
    required this.day,
    required this.label,
    required this.maxDistance,
  });

  final _DensityDay day;
  final String label;
  final double maxDistance;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final active = day.distanceMeters > 0;
    final strength = maxDistance <= 0
        ? 0.0
        : (day.distanceMeters / maxDistance).clamp(0.0, 1.0);
    return Tooltip(
      message:
          '${day.date.day}/${day.date.month}: ${(day.distanceMeters / 1000).toStringAsFixed(1)} km',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? Color.lerp(
                  palette.accent.withValues(alpha: 0.28),
                  palette.accent,
                  strength,
                )
              : onSurface.withValues(alpha: 0.045),
          border: Border.all(
            color: active
                ? palette.accent.withValues(alpha: 0.28)
                : onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.ink : onSurface.withValues(alpha: 0.38),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _JournalEntryCard extends StatelessWidget {
  const _JournalEntryCard({required this.recent, required this.onTap});

  final List<ActivitySummary> recent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final latest = recent.isEmpty ? null : recent.first;
    return InkWell(
      onTap: onTap,
      child: GlassPanel(
        borderRadius: 0,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.list_alt_rounded, color: palette.accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nhật ký session',
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latest == null
                        ? 'Chưa có buổi chạy nào.'
                        : '${recent.length} buổi · gần nhất ${formatDistance(latest.distanceMeters)}',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.56),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: onSurface.withValues(alpha: 0.42),
            ),
          ],
        ),
      ),
    );
  }
}

class _StabilitySnapshot {
  const _StabilitySnapshot({
    required this.score,
    required this.activeRatio,
    required this.activityCount,
    required this.distanceMeters,
    required this.days,
    required this.message,
  });

  final int score;
  final double activeRatio;
  final int activityCount;
  final double distanceMeters;
  final List<_DensityDay> days;
  final String message;

  factory _StabilitySnapshot.fromActivities(
    List<ActivitySummary> activities,
    DateTime now,
    PersonalPowerRange range,
  ) {
    final period = _densityPeriod(now, range);
    final days = [
      for (var index = 0; index < period.dayCount; index++)
        _DensityDay(date: period.start.add(Duration(days: index))),
    ];
    final totals = {for (final day in days) _statsDay(day.date): 0.0};
    var activityCount = 0;
    var distanceMeters = 0.0;
    for (final activity in activities) {
      if (activity.startedAt.isBefore(period.start) ||
          !activity.startedAt.isBefore(period.end)) {
        continue;
      }
      final day = _statsDay(activity.startedAt);
      totals[day] = (totals[day] ?? 0) + activity.distanceMeters;
      activityCount++;
      distanceMeters += activity.distanceMeters;
    }
    final filledDays = [
      for (final day in days)
        _DensityDay(
          date: day.date,
          distanceMeters: totals[_statsDay(day.date)] ?? 0,
        ),
    ];
    final activeDays = filledDays.where((day) => day.distanceMeters > 0).length;
    final activeRatio = filledDays.isEmpty
        ? 0.0
        : activeDays / filledDays.length;
    final streak = _densityCurrentStreak(filledDays);
    final streakTarget = range == PersonalPowerRange.currentMonth ? 6.0 : 3.0;
    final rhythmTarget = range == PersonalPowerRange.currentMonth ? 12.0 : 3.0;
    final score =
        ((activeRatio.clamp(0.0, 1.0) * 0.45) +
                ((streak / streakTarget).clamp(0.0, 1.0) * 0.35) +
                ((activityCount / rhythmTarget).clamp(0.0, 1.0) * 0.20))
            .round()
            .clamp(0, 100);
    return _StabilitySnapshot(
      score: score,
      activeRatio: activeRatio,
      activityCount: activityCount,
      distanceMeters: distanceMeters,
      days: filledDays,
      message: _stabilityMessage(score),
    );
  }
}

class _DensityDay {
  const _DensityDay({required this.date, this.distanceMeters = 0});

  final DateTime date;
  final double distanceMeters;
}

({DateTime start, DateTime end, int dayCount}) _densityPeriod(
  DateTime now,
  PersonalPowerRange range,
) {
  final today = _statsDay(now);
  return switch (range) {
    PersonalPowerRange.currentWeek => (
      start: startOfCurrentWeek(now),
      end: startOfCurrentWeek(now).add(const Duration(days: 7)),
      dayCount: 7,
    ),
    PersonalPowerRange.rollingSevenDays => (
      start: today.subtract(const Duration(days: 6)),
      end: today.add(const Duration(days: 1)),
      dayCount: 7,
    ),
    PersonalPowerRange.currentMonth => (
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1),
      dayCount: DateTime(
        now.year,
        now.month + 1,
      ).difference(DateTime(now.year, now.month)).inDays,
    ),
  };
}

int _densityCurrentStreak(List<_DensityDay> days) {
  var streak = 0;
  for (final day in days.reversed) {
    if (day.distanceMeters <= 0) break;
    streak++;
  }
  return streak;
}

DateTime _statsDay(DateTime date) => DateTime(date.year, date.month, date.day);

String _densityWeekdayLabel(DateTime date) {
  return switch (date.weekday) {
    DateTime.monday => 'T2',
    DateTime.tuesday => 'T3',
    DateTime.wednesday => 'T4',
    DateTime.thursday => 'T5',
    DateTime.friday => 'T6',
    DateTime.saturday => 'T7',
    _ => 'CN',
  };
}

String _stabilityMessage(int score) {
  if (score >= 82) return 'Nhịp chạy rất chắc. Giữ đều, đừng vội tăng tải.';
  if (score >= 60) {
    return 'Nền ổn định đang hình thành. Chỉ cần đều thêm một chút.';
  }
  if (score >= 35) return 'Có tín hiệu tốt, nhưng mật độ còn thưa.';
  return 'Bắt đầu bằng những buổi ngắn. Điều cần xây là nhịp.';
}

class _DashboardWebGrid extends StatelessWidget {
  const _DashboardWebGrid({required this.columns});

  final List<Widget> columns;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < columns.length; index++) ...[
            Expanded(child: columns[index]),
            if (index != columns.length - 1) const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}

class _DashboardWebColumn extends StatelessWidget {
  const _DashboardWebColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _RecentActivitiesCard extends StatelessWidget {
  const _RecentActivitiesCard({required this.recent});

  final List<ActivitySummary> recent;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'GẦN ĐÂY',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/profile/journal'),
                child: const Text('Xem nhật ký'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text(
              'Chưa có hoạt động. Bấm đồng bộ để tải nhật ký Strava.',
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            )
          else
            for (var index = 0; index < recent.take(4).length; index++)
              ActivityTile(activity: recent[index], sequence: index + 1),
        ],
      ),
    );
  }
}

/// Filter của Tổng quan render gộp trong navigation bar, tự đổi theo card đang
/// được scroll tới ([dashboardActiveCardProvider]).
class DashboardNavFilter extends ConsumerWidget {
  const DashboardNavFilter({
    required this.branchActive,
    this.showFallback = false,
    super.key,
  });

  final bool branchActive;
  final bool showFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCard = ref.watch(dashboardActiveCardProvider);
    final card = branchActive
        ? activeCard ?? (showFallback ? DashboardCard.power : null)
        : null;
    final Widget child = switch (card) {
      DashboardCard.week => const _WeekModeNavControl(),
      DashboardCard.power => const _PowerRangeNavControl(),
      DashboardCard.volume => const _VolumeNavControl(),
      null => const SizedBox(width: double.infinity),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _WeekModeNavControl extends ConsumerWidget {
  const _WeekModeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: NavPillToggle<_WeekViewMode>(
        value: ref.watch(dashboardWeekModeProvider),
        items: const {
          _WeekViewMode.currentWeek: 'Tuần này',
          _WeekViewMode.rollingSevenDays: '7 ngày',
        },
        onChanged: (value) =>
            ref.read(dashboardWeekModeProvider.notifier).state = value,
      ),
    );
  }
}

class _PowerRangeNavControl extends ConsumerWidget {
  const _PowerRangeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: NavPillToggle<PersonalPowerRange>(
        value: ref.watch(dashboardPowerRangeProvider),
        items: const {
          PersonalPowerRange.currentWeek: 'Tuần',
          PersonalPowerRange.rollingSevenDays: '7 ngày',
          PersonalPowerRange.currentMonth: 'Tháng',
        },
        onChanged: (value) =>
            ref.read(dashboardPowerRangeProvider.notifier).state = value,
      ),
    );
  }
}

class _VolumeNavControl extends ConsumerWidget {
  const _VolumeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: Row(
        children: [
          Expanded(
            child: NavDropdown<TrainingVolumeChartMode>(
              icon: Icons.show_chart_rounded,
              value: ref.watch(dashboardVolumeModeProvider),
              items: const {
                TrainingVolumeChartMode.bar: 'Cột',
                TrainingVolumeChartMode.line: 'Line',
              },
              onChanged: (value) =>
                  ref.read(dashboardVolumeModeProvider.notifier).state = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NavDropdown<TrainingVolumePeriod>(
              icon: Icons.date_range_outlined,
              value: ref.watch(dashboardVolumePeriodProvider),
              items: const {
                TrainingVolumePeriod.month: 'Tháng',
                TrainingVolumePeriod.quarter: 'Quý',
                TrainingVolumePeriod.year: 'Năm',
              },
              onChanged: (value) =>
                  ref.read(dashboardVolumePeriodProvider.notifier).state =
                      value,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _editTrainingGoals(
  BuildContext context,
  WidgetRef ref,
  TrainingGoals goals,
) async {
  final result = await showModalBottomSheet<TrainingGoals>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TrainingGoalsSheet(goals: goals),
  );
  if (result == null) return;
  await ref.read(trainingGoalRepositoryProvider).saveGoals(result);
}

class _TrainingGoalsSheet extends StatefulWidget {
  const _TrainingGoalsSheet({required this.goals});

  final TrainingGoals goals;

  @override
  State<_TrainingGoalsSheet> createState() => _TrainingGoalsSheetState();
}

class _TrainingGoalsSheetState extends State<_TrainingGoalsSheet> {
  late final TextEditingController _weeklyController;
  late final TextEditingController _monthlyController;

  @override
  void initState() {
    super.initState();
    _weeklyController = TextEditingController(
      text: widget.goals.weeklyDistanceMeters > 0
          ? (widget.goals.weeklyDistanceMeters / 1000).toStringAsFixed(1)
          : '',
    );
    _monthlyController = TextEditingController(
      text: widget.goals.monthlyDistanceMeters > 0
          ? (widget.goals.monthlyDistanceMeters / 1000).toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        gradient: LinearGradient(
          colors: [palette.glassStart, palette.glassEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.flag, color: palette.accent),
                const SizedBox(width: 8),
                Text(
                  'Mục tiêu luyện tập',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GoalInputField(
              controller: _weeklyController,
              label: 'Tuần',
              hint: 'VD: 15',
            ),
            const SizedBox(height: 10),
            _GoalInputField(
              controller: _monthlyController,
              label: 'Tháng',
              hint: 'VD: 60',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      TrainingGoals(
                        weeklyDistanceMeters:
                            _parseGoalKm(_weeklyController.text) * 1000,
                        monthlyDistanceMeters:
                            _parseGoalKm(_monthlyController.text) * 1000,
                      ),
                    ),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalInputField extends StatelessWidget {
  const _GoalInputField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Mục tiêu $label',
        hintText: hint,
        suffixText: 'km',
        filled: true,
        fillColor: palette.glassStart,
        labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.64)),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.34)),
        suffixStyle: TextStyle(color: palette.secondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.gridMajor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.secondary),
        ),
      ),
    );
  }
}

class _ShareableDashboardCard extends StatefulWidget {
  const _ShareableDashboardCard({required this.title, required this.builder});

  final String title;
  final Widget Function(bool sharing) builder;

  @override
  State<_ShareableDashboardCard> createState() =>
      _ShareableDashboardCardState();
}

class _ShareableDashboardCardState extends State<_ShareableDashboardCard> {
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

class _ConnectStravaCard extends StatelessWidget {
  const _ConnectStravaCard({
    required this.loading,
    required this.errorMessage,
    required this.onConnect,
  });

  final bool loading;
  final String? errorMessage;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: [palette.glassStart, palette.glassEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link, color: palette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'KẾT NỐI STRAVA',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Đồng bộ hoạt động chạy vào tài khoản Google hiện tại để xem tiến độ, nhật ký và bảng xếp hạng.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.68)),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onConnect,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(loading ? 'Đang kết nối...' : 'Kết nối Strava'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalProgressRow extends StatelessWidget {
  const _GoalProgressRow({
    required this.label,
    required this.currentMeters,
    required this.goalMeters,
    required this.color,
  });

  final String label;
  final double currentMeters;
  final double goalMeters;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasGoal = goalMeters > 0;
    final progress = hasGoal ? (currentMeters / goalMeters).clamp(0, 1) : 0.0;
    final percent = hasGoal ? (progress * 100).round() : 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              hasGoal
                  ? '${formatDistance(currentMeters)} / ${formatDistance(goalMeters)}'
                  : '${formatDistance(currentMeters)} / chưa đặt',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.64),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 14,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: onSurface.withValues(alpha: 0.12)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.toDouble(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.55), color],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasGoal ? '$percent% hoàn thành' : 'Bấm icon để đặt mục tiêu',
          style: TextStyle(
            color: hasGoal ? color : onSurface.withValues(alpha: 0.36),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.comparison,
    required this.dailyDistances,
    required this.goals,
    required this.monthDistanceMeters,
    required this.mode,
    required this.onModeChanged,
    required this.onEditGoals,
    required this.showControls,
  });

  final TrainingComparison comparison;
  final List<DailyDistance> dailyDistances;
  final TrainingGoals goals;
  final double monthDistanceMeters;
  final _WeekViewMode mode;
  final ValueChanged<_WeekViewMode> onModeChanged;
  final VoidCallback? onEditGoals;
  final bool showControls;

  @override
  Widget build(BuildContext context) {
    final summary = comparison.current;
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      gradient: LinearGradient(
        colors: [palette.glassStart, palette.glassEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: onSurface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: palette.secondary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'TIẾN ĐỘ TUẦN',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.64),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (showControls)
                  IconButton(
                    onPressed: onEditGoals,
                    tooltip: 'Sửa mục tiêu',
                    icon: const Icon(Icons.tune, size: 18),
                    color: palette.secondary,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (showControls) ...[
              const SizedBox(height: 10),
              _WeekViewToggle(value: mode, onChanged: onModeChanged),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                _weekModeLabel(mode),
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SevenDayPulseChart(days: dailyDistances),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 20,
              mainAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                _Metric(
                  label: 'Quãng đường',
                  value: formatDistance(summary.distanceMeters),
                  color: palette.accent,
                ),
                _Metric(
                  label: 'Thời gian',
                  value: formatDuration(summary.movingTimeSeconds),
                  color: palette.accent,
                ),
                _Metric(
                  label: 'Số buổi',
                  value: '${summary.activityCount}',
                  color: palette.accent,
                ),
                _Metric(
                  label: 'Pace TB',
                  value: formatPace(summary.paceSecondsPerKm),
                  color: palette.accent,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _comparisonLabel(comparison, mode),
              style: TextStyle(
                color: palette.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _GoalProgressRow(
              label: _weekGoalLabel(mode),
              currentMeters: summary.distanceMeters,
              goalMeters: goals.weeklyDistanceMeters,
              color: palette.accent,
            ),
            const SizedBox(height: 14),
            _GoalProgressRow(
              label: 'Tháng này',
              currentMeters: monthDistanceMeters,
              goalMeters: goals.monthlyDistanceMeters,
              color: palette.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekViewToggle extends StatelessWidget {
  const _WeekViewToggle({required this.value, required this.onChanged});

  final _WeekViewMode value;
  final ValueChanged<_WeekViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WeekViewOption(
          label: '7 ngày gần nhất',
          selected: value == _WeekViewMode.rollingSevenDays,
          onTap: () => onChanged(_WeekViewMode.rollingSevenDays),
        ),
        _WeekViewOption(
          label: 'Tuần này',
          selected: value == _WeekViewMode.currentWeek,
          onTap: () => onChanged(_WeekViewMode.currentWeek),
        ),
      ],
    );
  }
}

class _WeekViewOption extends StatelessWidget {
  const _WeekViewOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? accent : onSurface.withValues(alpha: 0.52),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SevenDayPulseChart extends StatelessWidget {
  const _SevenDayPulseChart({required this.days});

  final List<DailyDistance> days;

  @override
  Widget build(BuildContext context) {
    final maxDistance = days.fold<double>(
      0,
      (max, day) => day.distanceMeters > max ? day.distanceMeters : max,
    );
    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _SevenDayBar(
                  day: day,
                  maxDistance: maxDistance,
                  active: day.distanceMeters > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SevenDayBar extends StatelessWidget {
  const _SevenDayBar({
    required this.day,
    required this.maxDistance,
    required this.active,
  });

  final DailyDistance day;
  final double maxDistance;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ratio = maxDistance <= 0 ? 0.04 : day.distanceMeters / maxDistance;
    final label = _weekdayLabel(day.date);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final palette = context.runNowPalette;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          day.distanceMeters > 0 ? _compactDistance(day.distanceMeters) : '-',
          style: TextStyle(
            color: active ? palette.accent : onSurface.withValues(alpha: 0.35),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: ratio.clamp(0.06, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: active
                      ? palette.accent
                      : onSurface.withValues(alpha: 0.08),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: palette.accent.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: const SizedBox(width: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.52),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Container(width: 2, height: 34, color: color.withValues(alpha: 0.72)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
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

String _compactDistance(double meters) =>
    '${(meters / 1000).toStringAsFixed(1)}k';

String _weekdayLabel(DateTime date) => switch (date.weekday) {
  DateTime.monday => 'T2',
  DateTime.tuesday => 'T3',
  DateTime.wednesday => 'T4',
  DateTime.thursday => 'T5',
  DateTime.friday => 'T6',
  DateTime.saturday => 'T7',
  DateTime.sunday => 'CN',
  _ => '',
};

String _weekGoalLabel(_WeekViewMode mode) => switch (mode) {
  _WeekViewMode.rollingSevenDays => 'Mục tiêu tuần',
  _WeekViewMode.currentWeek => 'Tuần này',
};

String _weekModeLabel(_WeekViewMode mode) => switch (mode) {
  _WeekViewMode.rollingSevenDays => '7 ngày gần nhất',
  _WeekViewMode.currentWeek => 'Tuần này',
};

String _comparisonLabel(TrainingComparison comparison, _WeekViewMode mode) {
  final ratio = comparison.distanceChangeRatio;
  final previousLabel = switch (mode) {
    _WeekViewMode.rollingSevenDays => '7 ngày trước',
    _WeekViewMode.currentWeek => 'tuần trước',
  };
  if (ratio == null) return 'Chưa có quãng đường $previousLabel để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với $previousLabel';
}

double _parseGoalKm(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isNegative) return 0;
  return parsed;
}
