import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/discipline_card.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/personal_power_card.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

class MemberProfileScreen extends ConsumerWidget {
  const MemberProfileScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref
        .watch(firebaseUserProvider)
        .maybeWhen(data: (user) => user?.uid, orElse: () => null);
    if (currentUid == uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/settings/profile');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final profile = ref.watch(memberProfileProvider(uid));
    return Scaffold(
      appBar: AppBar(title: const Text('Tổng quan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: profile.when(
            data: (member) {
              if (member == null) {
                return const Center(child: Text('Không tìm thấy thành viên.'));
              }
              if (!member.isPublic) return _PrivateMember(member: member);
              return ref
                  .watch(memberActivitiesProvider(uid))
                  .when(
                    data: (activities) => _MemberDashboard(
                      uid: uid,
                      member: member,
                      activities: activities,
                    ),
                    error: (error, stack) =>
                        Center(child: Text('Không thể tải hoạt động: $error')),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                  );
            },
            error: (error, stack) =>
                Center(child: Text('Không thể tải hồ sơ: $error')),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}

enum _MemberFilterSection { power, volume }

class _MemberDashboard extends StatefulWidget {
  const _MemberDashboard({
    required this.uid,
    required this.member,
    required this.activities,
  });

  final String uid;
  final MemberProfile member;
  final List<ActivitySummary> activities;

  @override
  State<_MemberDashboard> createState() => _MemberDashboardState();
}

class _MemberDashboardState extends State<_MemberDashboard> {
  final _scrollKey = GlobalKey();
  final _powerKey = GlobalKey();
  final _volumeKey = GlobalKey();
  var _powerRange = PersonalPowerRange.rollingSevenDays;
  var _volumePeriod = TrainingVolumePeriod.month;
  var _volumeMode = TrainingVolumeChartMode.bar;
  _MemberFilterSection? _activeFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveFilter());
  }

  void _updateActiveFilter() {
    if (!mounted) return;
    final listBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    final threshold =
        listBox.localToGlobal(Offset.zero).dy + listBox.size.height * 0.28;
    _MemberFilterSection? active;
    for (final section in <(GlobalKey, _MemberFilterSection)>[
      (_powerKey, _MemberFilterSection.power),
      (_volumeKey, _MemberFilterSection.volume),
    ]) {
      final box = section.$1.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= threshold && top + box.size.height > threshold) {
        active = section.$2;
        break;
      }
    }
    if (_activeFilter != active) setState(() => _activeFilter = active);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final comparison = rollingSevenDayComparison(widget.activities, now);
    final dailyDistances = rollingSevenDayDistances(widget.activities, now);
    final month = currentMonthSummary(widget.activities, now);
    final discipline = personalDisciplineStats(widget.activities, now);
    final recent = [...widget.activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = NotificationListener<ScrollNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateActiveFilter(),
        );
        return false;
      },
      child: ListView(
        key: _scrollKey,
        padding: EdgeInsets.fromLTRB(0, 8, 0, wide ? 40 : 132),
        children: [
          _MemberHeader(member: widget.member),
          const SizedBox(height: 14),
          _MemberSummaryCard(
            comparison: comparison,
            dailyDistances: dailyDistances,
            month: month,
          ),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _powerKey,
            child: PersonalPowerCard(
              activities: widget.activities,
              range: _powerRange,
              onRangeChanged: (value) => setState(() => _powerRange = value),
              showControls: wide,
            ),
          ),
          const SizedBox(height: 20),
          DisciplineCard(stats: discipline, activities: widget.activities),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _volumeKey,
            child: TrainingVolumeChart(
              activities: widget.activities,
              period: _volumePeriod,
              mode: _volumeMode,
              showControls: wide,
            ),
          ),
          const SizedBox(height: 20),
          Text('Gần đây', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (recent.isEmpty)
            const Text('Thành viên này chưa có hoạt động public.')
          else ...[
            ActivityRecordsCard(
              title: 'BEST BOARD',
              entries: [
                for (final activity in widget.activities)
                  ActivityRecordEntry(activity: activity, ownerUid: widget.uid),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < recent.take(10).length; index++)
              ActivityTile(
                activity: recent[index],
                sequence: index + 1,
                ownerUid: widget.uid,
              ),
          ],
        ],
      ),
    );
    if (wide) return list;
    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          left: 14,
          right: 14,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _MemberPinnedFilter(
                key: ValueKey(_activeFilter),
                section: _activeFilter,
                powerRange: _powerRange,
                volumePeriod: _volumePeriod,
                volumeMode: _volumeMode,
                onPowerRangeChanged: (value) =>
                    setState(() => _powerRange = value),
                onVolumePeriodChanged: (value) =>
                    setState(() => _volumePeriod = value),
                onVolumeModeChanged: (value) =>
                    setState(() => _volumeMode = value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemberPinnedFilter extends StatelessWidget {
  const _MemberPinnedFilter({
    required this.section,
    required this.powerRange,
    required this.volumePeriod,
    required this.volumeMode,
    required this.onPowerRangeChanged,
    required this.onVolumePeriodChanged,
    required this.onVolumeModeChanged,
    super.key,
  });

  final _MemberFilterSection? section;
  final PersonalPowerRange powerRange;
  final TrainingVolumePeriod volumePeriod;
  final TrainingVolumeChartMode volumeMode;
  final ValueChanged<PersonalPowerRange> onPowerRangeChanged;
  final ValueChanged<TrainingVolumePeriod> onVolumePeriodChanged;
  final ValueChanged<TrainingVolumeChartMode> onVolumeModeChanged;

  @override
  Widget build(BuildContext context) {
    if (section == null) return const SizedBox.shrink();
    return GlassPanel(
      borderRadius: 12,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: NavFilterShell(
        child: switch (section!) {
          _MemberFilterSection.power => NavPillToggle<PersonalPowerRange>(
            value: powerRange,
            items: const {
              PersonalPowerRange.currentWeek: 'Tuần',
              PersonalPowerRange.rollingSevenDays: '7 ngày',
              PersonalPowerRange.currentMonth: 'Tháng',
            },
            onChanged: onPowerRangeChanged,
          ),
          _MemberFilterSection.volume => Row(
            children: [
              Expanded(
                child: NavDropdown<TrainingVolumeChartMode>(
                  icon: Icons.show_chart_rounded,
                  value: volumeMode,
                  items: const {
                    TrainingVolumeChartMode.bar: 'Cột',
                    TrainingVolumeChartMode.line: 'Line',
                  },
                  onChanged: onVolumeModeChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NavDropdown<TrainingVolumePeriod>(
                  icon: Icons.date_range_outlined,
                  value: volumePeriod,
                  items: const {
                    TrainingVolumePeriod.month: 'Tháng',
                    TrainingVolumePeriod.quarter: 'Quý',
                    TrainingVolumePeriod.year: 'Năm',
                  },
                  onChanged: onVolumePeriodChanged,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _PrivateMember extends StatelessWidget {
  const _PrivateMember({required this.member});

  final MemberProfile member;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
      children: [
        _MemberHeader(member: member),
        const SizedBox(height: 14),
        const GlassPanel(
          borderRadius: 0,
          padding: EdgeInsets.all(18),
          child: Text('Thành viên này đang để hồ sơ private.'),
        ),
      ],
    );
  }
}

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({required this.member});

  final MemberProfile member;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = member.avatarUrl;
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: palette.secondary.withValues(alpha: 0.18),
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? Text(
                    member.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'MEMBER DASHBOARD',
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
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

class _MemberSummaryCard extends StatelessWidget {
  const _MemberSummaryCard({
    required this.comparison,
    required this.dailyDistances,
    required this.month,
  });

  final TrainingComparison comparison;
  final List<DailyDistance> dailyDistances;
  final TrainingSummary month;

  @override
  Widget build(BuildContext context) {
    final summary = comparison.current;
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
                Text(
                  '7 NGÀY',
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SevenDayMiniChart(days: dailyDistances),
            const SizedBox(height: 18),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _Metric(
                  label: 'Quãng đường',
                  value: formatDistance(summary.distanceMeters),
                ),
                _Metric(
                  label: 'Thời gian',
                  value: formatDuration(summary.movingTimeSeconds),
                ),
                _Metric(label: 'Số buổi', value: '${summary.activityCount}'),
                _Metric(
                  label: 'Pace TB',
                  value: formatPace(summary.paceSecondsPerKm),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _comparisonLabel(comparison),
              style: TextStyle(
                color: palette.secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MonthMetric(
                    label: 'Tháng này',
                    value: formatDistance(month.distanceMeters),
                  ),
                ),
                Expanded(
                  child: _MonthMetric(
                    label: 'Thời gian tháng',
                    value: formatDuration(month.movingTimeSeconds),
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

class _SevenDayMiniChart extends StatelessWidget {
  const _SevenDayMiniChart({required this.days});

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
                child: _SevenDayMiniBar(day: day, maxDistance: maxDistance),
              ),
            ),
        ],
      ),
    );
  }
}

class _SevenDayMiniBar extends StatelessWidget {
  const _SevenDayMiniBar({required this.day, required this.maxDistance});

  final DailyDistance day;
  final double maxDistance;

  @override
  Widget build(BuildContext context) {
    final active = day.distanceMeters > 0;
    final ratio = maxDistance <= 0 ? 0.04 : day.distanceMeters / maxDistance;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final palette = context.runNowPalette;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          active ? _compactDistance(day.distanceMeters) : '-',
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
          _weekdayLabel(day.date),
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
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final palette = context.runNowPalette;
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: onSurface.withValues(alpha: 0.62)),
          ),
          Text(
            value,
            style: TextStyle(
              color: palette.accent,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthMetric extends StatelessWidget {
  const _MonthMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: onSurface.withValues(alpha: 0.52))),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

String _comparisonLabel(TrainingComparison comparison) {
  final ratio = comparison.distanceChangeRatio;
  if (ratio == null) return 'Chưa có quãng đường 7 ngày trước để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với 7 ngày trước';
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
