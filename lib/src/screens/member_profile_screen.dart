import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/consistency_heatmap.dart';
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
        if (context.mounted) context.go('/');
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
                loading: () => const Center(child: CircularProgressIndicator()),
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

class _MemberDashboard extends StatelessWidget {
  const _MemberDashboard({
    required this.uid,
    required this.member,
    required this.activities,
  });

  final String uid;
  final MemberProfile member;
  final List<ActivitySummary> activities;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final comparison = rollingSevenDayComparison(activities, now);
    final dailyDistances = rollingSevenDayDistances(activities, now);
    final month = currentMonthSummary(activities, now);
    final discipline = personalDisciplineStats(activities, now);
    final recent = [...activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _MemberHeader(member: member),
        const SizedBox(height: 14),
        _MemberSummaryCard(
          comparison: comparison,
          dailyDistances: dailyDistances,
          month: month,
        ),
        const SizedBox(height: 20),
        PersonalPowerCard(activities: activities),
        const SizedBox(height: 20),
        DisciplineCard(stats: discipline),
        const SizedBox(height: 20),
        ConsistencyHeatmap(activities: activities),
        const SizedBox(height: 20),
        TrainingVolumeChart(
          activities: activities,
          period: TrainingVolumePeriod.month,
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
              for (final activity in activities)
                ActivityRecordEntry(activity: activity, ownerUid: uid),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < recent.take(10).length; index++)
            ActivityTile(
              activity: recent[index],
              sequence: index + 1,
              ownerUid: uid,
            ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        _MemberHeader(member: member),
        const SizedBox(height: 14),
        const GlassPanel(
          borderRadius: 22,
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
    return GlassPanel(
      borderRadius: 28,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.blueGlow.withValues(alpha: 0.18),
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
                const Text(
                  'MEMBER DASHBOARD',
                  style: TextStyle(
                    color: AppColors.blueGlow,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd1d8e1), Color(0xffdde3ea)]
            : const [Color(0xf207172b), Color(0xdb06365c), Color(0xb3151637)],
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
                const Icon(Icons.bolt, color: AppColors.blueGlow, size: 20),
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
                const Text(
                  '7 NGÀY',
                  style: TextStyle(
                    color: AppColors.blueGlow,
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
              style: const TextStyle(
                color: AppColors.blueGlow,
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          active ? _compactDistance(day.distanceMeters) : '-',
          style: TextStyle(
            color: active ? onSurface : onSurface.withValues(alpha: 0.35),
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
                  gradient: LinearGradient(
                    colors: active
                        ? const [AppColors.red, AppColors.blueGlow]
                        : [
                            onSurface.withValues(alpha: 0.12),
                            onSurface.withValues(alpha: 0.06),
                          ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  boxShadow: active
                      ? const [
                          BoxShadow(
                            color: Color(0x6600d9ff),
                            blurRadius: 14,
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
              color: onSurface,
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
