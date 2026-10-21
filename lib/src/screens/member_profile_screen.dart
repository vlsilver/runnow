import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/journal_screen.dart' show StepTimelineRow;
import 'package:myrun/src/screens/step_day_detail_screen.dart';
import 'package:myrun/src/screens/journey_hub_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/discipline_card.dart';
import 'package:myrun/src/widgets/glass.dart';
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
        if (context.mounted) context.go('/profile');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final profile = ref.watch(memberProfileProvider(uid));
    return Scaffold(
      appBar: AppBar(title: const Text('Tổng quan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: profile.when(
            data: (member) {
              if (member == null) {
                return const Center(child: Text('Không tìm thấy thành viên.'));
              }
              if (!member.isPublic) return _PrivateMember(member: member);
              return JourneyHubScreen(memberUid: uid, member: member);
            },
            error: (error, stack) =>
                Center(child: Text('Không thể tải hồ sơ: $error')),
            loading: () => const RunNowLoading(label: 'Đang tải cá nhân'),
          ),
        ),
      ),
    );
  }
}

class MemberJournalScreen extends ConsumerWidget {
  const MemberJournalScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref
        .watch(firebaseUserProvider)
        .maybeWhen(data: (user) => user?.uid, orElse: () => null);
    if (currentUid == uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/profile/journal');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final profileState = ref.watch(memberProfileProvider(uid));
    final activitiesState = ref.watch(memberActivitiesProvider(uid));
    final memberStepDays =
        ref.watch(memberStepDaysProvider(uid)).asData?.value ??
        const <StepDay>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: profileState.when(
            data: (member) {
              if (member == null) {
                return const Center(child: Text('Không tìm thấy thành viên.'));
              }
              if (!member.isPublic) return _PrivateMember(member: member);
              return activitiesState.when(
                data: (activities) {
                  if (activities.isEmpty && memberStepDays.isEmpty) {
                    return const Center(
                      child: Text('Thành viên này chưa có hoạt động public.'),
                    );
                  }
                  // Trộn buổi chạy + thẻ bước thành 1 timeline giảm dần — GIỐNG
                  // nhật ký của mình, chỉ đổi nguồn sang member đang xem.
                  final rows =
                      <_MemberJournalRow>[
                        for (final a in activities) _MemberJournalRow.activity(a),
                        for (final d in memberStepDays) _MemberJournalRow.step(d),
                      ]..sort((x, y) => y.sortAt.compareTo(x.sortAt));
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 110),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final act = rows[index].activity;
                      return RepaintBoundary(
                        child: act != null
                            ? ActivityTile(activity: act, ownerUid: uid)
                            // Member: mở chi tiết theo giờ ĐÃ LƯU (controller null
                            // → không đọc live Health máy này; ngày chưa lưu thì
                            // biểu đồ rỗng). recentDays = các thẻ bước đang xem.
                            : StepTimelineRow(
                                day: rows[index].step!,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StepDayDetailScreen(
                                      day: rows[index].step!,
                                      recentDays: memberStepDays,
                                    ),
                                  ),
                                ),
                              ),
                      );
                    },
                  );
                },
                error: (error, stack) =>
                    Center(child: Text('Không thể tải nhật ký: $error')),
                loading: () => const RunNowLoading(label: 'Đang tải nhật ký'),
              );
            },
            error: (error, stack) =>
                Center(child: Text('Không thể tải hồ sơ: $error')),
            loading: () => const RunNowLoading(label: 'Đang tải nhật ký'),
          ),
        ),
      ),
    );
  }
}

/// 1 dòng trong nhật ký member: hoặc buổi CHẠY, hoặc thẻ BƯỚC của 1 ngày.
class _MemberJournalRow {
  _MemberJournalRow.activity(this.activity) : step = null;
  _MemberJournalRow.step(this.step) : activity = null;
  final ActivitySummary? activity;
  final StepDay? step;

  /// Mốc xếp: buổi chạy = lúc bắt đầu; thẻ bước = CUỐI ngày (nổi lên đầu ngày đó).
  DateTime get sortAt {
    final a = activity;
    if (a != null) return a.startedAt;
    final d = DateTime.tryParse(step!.date);
    if (d == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }
}

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
  var _powerRange = PersonalPowerRange.rollingSevenDays;
  final _volumePeriod = TrainingVolumePeriod.month;
  final _volumeMode = TrainingVolumeChartMode.bar;
  late TrainingComparison _comparison;
  late List<DailyDistance> _dailyDistances;
  late TrainingSummary _month;
  late DisciplineStats _discipline;
  late List<ActivitySummary> _recent;
  late DateTime _analyticsDay;

  @override
  void initState() {
    super.initState();
    _recomputeAnalytics();
  }

  @override
  void didUpdateWidget(covariant _MemberDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activities, widget.activities)) {
      _recomputeAnalytics();
    }
  }

  void _recomputeAnalytics() {
    final now = DateTime.now();
    _analyticsDay = DateTime(now.year, now.month, now.day);
    _comparison = rollingSevenDayComparison(widget.activities, now);
    _dailyDistances = rollingSevenDayDistances(widget.activities, now);
    _month = currentMonthSummary(widget.activities, now);
    _discipline = personalDisciplineStats(widget.activities, now);
    _recent = [...widget.activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
  }

  void _refreshAnalyticsAfterDateChange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (today != _analyticsDay) _recomputeAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    _refreshAnalyticsAfterDateChange();
    final comparison = _comparison;
    final dailyDistances = _dailyDistances;
    final month = _month;
    final discipline = _discipline;
    final recent = _recent;
    final wide = RunNowWebLayout.isDesktop(context);
    if (wide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
        children: [
          _MemberHeader(member: widget.member),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _MemberSummaryCard(
                      comparison: comparison,
                      dailyDistances: dailyDistances,
                      month: month,
                    ),
                    const SizedBox(height: 20),
                    PersonalPowerCard(
                      activities: widget.activities,
                      range: _powerRange,
                      onRangeChanged: (value) =>
                          setState(() => _powerRange = value),
                      showControls: true,
                    ),
                    const SizedBox(height: 20),
                    DisciplineCard(
                      stats: discipline,
                      activities: widget.activities,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TrainingVolumeChart(
                      uid: widget.uid,
                      period: _volumePeriod,
                      mode: _volumeMode,
                      showControls: true,
                    ),
                    const SizedBox(height: 20),
                    ActivityRecordsCard(
                      title: 'BEST BOARD',
                      entries: [
                        for (final activity in widget.activities)
                          ActivityRecordEntry(
                            activity: activity,
                            ownerUid: widget.uid,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Gần đây',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (recent.isEmpty)
                      const Text('Thành viên này chưa có hoạt động public.')
                    else
                      for (
                        var index = 0;
                        index < recent.take(6).length;
                        index++
                      )
                        ActivityTile(
                          activity: recent[index],
                          ownerUid: widget.uid,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }
    // Control range/period nằm INLINE trong card (showControls: true) — bỏ thanh
    // filter PIN ở đáy (nhìn như nav-filter dính lại khi mở từ Club). Giống hệt
    // layout desktop bên trên.
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 40),
      children: [
        _MemberHeader(member: widget.member),
        const SizedBox(height: 14),
        _MemberSummaryCard(
          comparison: comparison,
          dailyDistances: dailyDistances,
          month: month,
        ),
        const SizedBox(height: 20),
        PersonalPowerCard(
          activities: widget.activities,
          range: _powerRange,
          onRangeChanged: (value) => setState(() => _powerRange = value),
          showControls: true,
        ),
        const SizedBox(height: 20),
        DisciplineCard(stats: discipline, activities: widget.activities),
        const SizedBox(height: 20),
        TrainingVolumeChart(
          uid: widget.uid,
          period: _volumePeriod,
          mode: _volumeMode,
          showControls: true,
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
            ActivityTile(activity: recent[index], ownerUid: widget.uid),
        ],
      ],
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
            backgroundImage: avatarUrl == null
                ? null
                : cachedAvatarImage(context, avatarUrl, 60),
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
