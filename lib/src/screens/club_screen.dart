import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/power_radar_card.dart';

enum _RankingMetric {
  distance,
  time,
  consistency,
  pace,
  longestRun,
  activityCount,
}

enum _RankingRange { rollingSevenDays, currentWeek, currentMonth }

enum _ClubRecapRange { currentWeek, currentMonth }

class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen> {
  _RankingMetric _metric = _RankingMetric.distance;
  _RankingRange _range = _RankingRange.rollingSevenDays;
  _ClubRecapRange _recapRange = _ClubRecapRange.currentMonth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(memberRepositoryProvider).ensureCurrentLeaderboardEntry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    return DefaultTabController(
      length: 4,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Câu lạc bộ'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Xếp hạng'),
              Tab(text: 'Tổng kết'),
              Tab(text: 'Nhật ký'),
              Tab(text: 'Thành viên'),
            ],
          ),
        ),
        body: members.when(
          data: (items) => items.isEmpty
              ? const _EmptyClub()
              : TabBarView(
                  children: [
                    _RankingTab(
                      currentUid: _currentUid(ref),
                      metric: _metric,
                      range: _range,
                      onMetricChanged: (value) =>
                          setState(() => _metric = value),
                      onRangeChanged: (value) => setState(() => _range = value),
                    ),
                    _ClubRecapTab(
                      range: _recapRange,
                      onRangeChanged: (value) =>
                          setState(() => _recapRange = value),
                    ),
                    const _ClubJournalTab(),
                    _MembersTab(members: items, currentUid: _currentUid(ref)),
                  ],
                ),
          error: (error, stack) =>
              Center(child: Text('Không thể tải thành viên: $error')),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  String? _currentUid(WidgetRef ref) {
    return ref
        .watch(firebaseUserProvider)
        .maybeWhen(data: (user) => user?.uid, orElse: () => null);
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.members, required this.currentUid});

  final List<MemberProfile> members;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final publicMembers = members.where((member) => member.isPublic).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: publicMembers.isEmpty
          ? const [
              GlassPanel(
                borderRadius: 22,
                padding: EdgeInsets.all(18),
                child: Text('Chưa có thành viên public.'),
              ),
            ]
          : [
              for (final member in publicMembers)
                _MemberCard(member: member, currentUid: currentUid),
            ],
    );
  }
}

class _ClubJournalTab extends ConsumerWidget {
  const _ClubJournalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(clubActivityLogProvider);
    return log.when(
      data: (items) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: items.isEmpty
            ? const [
                GlassPanel(
                  borderRadius: 22,
                  padding: EdgeInsets.all(18),
                  child: Text('Chưa có hoạt động public trong club.'),
                ),
              ]
            : [
                for (var index = 0; index < items.length; index++)
                  ActivityTile(
                    activity: items[index].activity,
                    sequence: index + 1,
                    ownerUid: items[index].member.uid,
                    memberName: items[index].member.displayName,
                    memberAvatarUrl: items[index].member.avatarUrl,
                  ),
              ],
      ),
      error: (error, stack) =>
          Center(child: Text('Không thể tải nhật ký club: $error')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ClubRecapTab extends ConsumerWidget {
  const _ClubRecapTab({required this.range, required this.onRangeChanged});

  final _ClubRecapRange range;
  final ValueChanged<_ClubRecapRange> onRangeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardEntriesProvider);
    return leaderboard.when(
      data: (items) {
        final entries = items.where((entry) => entry.isPublic).toList();
        if (entries.isEmpty) return const _EmptyRanking();
        final stats = entries
            .map(
              (entry) => switch (range) {
                _ClubRecapRange.currentWeek => entry.currentWeek,
                _ClubRecapRange.currentMonth => entry.currentMonth,
              },
            )
            .toList();
        final period = switch (range) {
          _ClubRecapRange.currentWeek => 'tuần',
          _ClubRecapRange.currentMonth => 'tháng',
        };
        final periodTitle = switch (range) {
          _ClubRecapRange.currentWeek => 'TUẦN',
          _ClubRecapRange.currentMonth => 'THÁNG',
        };
        final totalDistance = stats.fold<double>(
          0,
          (sum, item) => sum + item.distanceMeters,
        );
        final totalTime = stats.fold<int>(
          0,
          (sum, item) => sum + item.movingTimeSeconds,
        );
        final totalActivities = stats.fold<int>(
          0,
          (sum, item) => sum + item.activityCount,
        );
        final activeMembers = stats
            .where((item) => item.distanceMeters > 0)
            .length;
        final activeRate = entries.isEmpty
            ? 0.0
            : activeMembers / entries.length;
        final fastestPace = _fastestPace(stats);
        final longestRun = stats.fold<double>(
          0,
          (max, item) => item.longestDistanceMeters > max
              ? item.longestDistanceMeters
              : max,
        );
        final topActiveDays = stats.fold<int>(
          0,
          (max, item) => item.activeDays > max ? item.activeDays : max,
        );
        final powerMetrics = _clubPowerMetrics(
          range: range,
          memberCount: entries.length,
          totalDistanceMeters: totalDistance,
          totalMovingTimeSeconds: totalTime,
          totalActivities: totalActivities,
          activeRate: activeRate,
          fastestPaceSecondsPerKm: fastestPace,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            _ClubRecapRangeControl(value: range, onChanged: onRangeChanged),
            const SizedBox(height: 14),
            _ClubSummaryCard(
              title: 'TỔNG KẾT $periodTitle',
              totalDistanceMeters: totalDistance,
              totalMovingTimeSeconds: totalTime,
              totalActivities: totalActivities,
              activeMembers: activeMembers,
              memberCount: entries.length,
            ),
            const SizedBox(height: 14),
            PowerRadarCard(
              title: 'CLUB POWER $periodTitle',
              metrics: powerMetrics,
              powerScore: averagePowerScore(powerMetrics),
            ),
            const SizedBox(height: 14),
            _ClubSignalCard(
              periodTitle: periodTitle,
              activeRate: activeRate,
              fastestPace: fastestPace,
              longestRun: longestRun,
              topActiveDays: topActiveDays,
              onActiveRateTap: () => _showContributionSheet(
                context,
                title: 'Thành viên active',
                items: _contributionItems(
                  entries,
                  range,
                  score: (stats) => stats.distanceMeters > 0 ? 1 : 0,
                  value: (stats) => stats.distanceMeters > 0 ? 'Active' : '--',
                ),
              ),
              onTopActiveTap: () => _showContributionSheet(
                context,
                title: 'Ngày active từng thành viên',
                items: _contributionItems(
                  entries,
                  range,
                  score: (stats) => stats.activeDays.toDouble(),
                  value: (stats) => '${stats.activeDays} ngày',
                ),
              ),
              onPaceTap: () => _showContributionSheet(
                context,
                title: 'Pace từng thành viên',
                items: _contributionItems(
                  entries,
                  range,
                  score: (stats) => stats.fastestPaceSecondsPerKm == null
                      ? 0
                      : 1 / stats.fastestPaceSecondsPerKm!,
                  value: (stats) => formatPace(stats.fastestPaceSecondsPerKm),
                ),
              ),
              onLongestRunTap: () => _showContributionSheet(
                context,
                title: 'Run dài nhất từng thành viên',
                items: _contributionItems(
                  entries,
                  range,
                  score: (stats) => stats.longestDistanceMeters,
                  value: (stats) => formatDistance(stats.longestDistanceMeters),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _ClubConsistencySpreadCard(
              period: period,
              zeroDays: stats.where((item) => item.activeDays == 0).length,
              oneDay: stats.where((item) => item.activeDays == 1).length,
              twoDays: stats.where((item) => item.activeDays == 2).length,
              threePlusDays: stats.where((item) => item.activeDays >= 3).length,
              memberCount: entries.length,
              onTap: (minimumDays, maximumDays) => _showContributionSheet(
                context,
                title: 'Độ phủ active',
                items: _contributionItems(
                  entries,
                  range,
                  score: (stats) {
                    final days = stats.activeDays;
                    final inRange =
                        days >= minimumDays &&
                        (maximumDays == null || days <= maximumDays);
                    return inRange ? days.toDouble().clamp(1, 99) : 0;
                  },
                  value: (stats) => '${stats.activeDays} ngày',
                ),
              ),
            ),
          ],
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải tổng kết: $error')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ClubSignalCard extends StatelessWidget {
  const _ClubSignalCard({
    required this.periodTitle,
    required this.activeRate,
    required this.fastestPace,
    required this.longestRun,
    required this.topActiveDays,
    required this.onActiveRateTap,
    required this.onTopActiveTap,
    required this.onPaceTap,
    required this.onLongestRunTap,
  });

  final String periodTitle;
  final double activeRate;
  final double? fastestPace;
  final double longestRun;
  final int topActiveDays;
  final VoidCallback onPaceTap;
  final VoidCallback onActiveRateTap;
  final VoidCallback onTopActiveTap;
  final VoidCallback onLongestRunTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.auto_graph,
            title: 'DẤU HIỆU $periodTitle',
            trailing: '${(activeRate * 100).round()}% active',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RecapStat(
                  label: 'ACTIVE RATE',
                  value: '${(activeRate * 100).round()}%',
                  color: _clubChartColor(1),
                  onTap: onActiveRateTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecapStat(
                  label: 'TOP ACTIVE',
                  value: '$topActiveDays ngày',
                  color: _clubChartColor(0.9),
                  onTap: onTopActiveTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RecapStat(
                  label: 'PACE NHANH',
                  value: formatPace(fastestPace),
                  color: _clubChartColor(1),
                  onTap: onPaceTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecapStat(
                  label: 'RUN DÀI',
                  value: formatDistance(longestRun),
                  color: _clubChartColor(0.9),
                  onTap: onLongestRunTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankingTab extends ConsumerWidget {
  const _RankingTab({
    required this.currentUid,
    required this.metric,
    required this.range,
    required this.onMetricChanged,
    required this.onRangeChanged,
  });

  final String? currentUid;
  final _RankingMetric metric;
  final _RankingRange range;
  final ValueChanged<_RankingMetric> onMetricChanged;
  final ValueChanged<_RankingRange> onRangeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboard = ref.watch(leaderboardEntriesProvider);
    return leaderboard.when(
      data: (items) {
        final entries =
            items
                .where((entry) => entry.isPublic)
                .map(
                  (entry) =>
                      _RankingEntry.fromLeaderboard(entry, metric, range),
                )
                .toList()
              ..sort((left, right) {
                final byScore = metric == _RankingMetric.pace
                    ? left.score.compareTo(right.score)
                    : right.score.compareTo(left.score);
                if (byScore != 0) return byScore;
                return right.stats.distanceMeters.compareTo(
                  left.stats.distanceMeters,
                );
              });
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            _RankingControls(
              metric: metric,
              range: range,
              onMetricChanged: onMetricChanged,
              onRangeChanged: onRangeChanged,
            ),
            const SizedBox(height: 14),
            if (entries.isEmpty)
              const _EmptyRanking()
            else
              for (var index = 0; index < entries.length; index++)
                _RankingCard(
                  rank: index + 1,
                  entry: entries[index],
                  metric: metric,
                  currentUid: currentUid,
                ),
          ],
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải bảng xếp hạng: $error')),
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Text('Xếp hạng', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          _RankingControls(
            metric: metric,
            range: range,
            onMetricChanged: onMetricChanged,
            onRangeChanged: onRangeChanged,
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _RankingControls extends StatelessWidget {
  const _RankingControls({
    required this.metric,
    required this.range,
    required this.onMetricChanged,
    required this.onRangeChanged,
  });

  final _RankingMetric metric;
  final _RankingRange range;
  final ValueChanged<_RankingMetric> onMetricChanged;
  final ValueChanged<_RankingRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: _ControlDropdown<_RankingMetric>(
              icon: Icons.leaderboard_outlined,
              value: metric,
              items: const {
                _RankingMetric.distance: 'Km',
                _RankingMetric.time: 'Thời gian',
                _RankingMetric.consistency: 'Đều',
                _RankingMetric.pace: 'Pace',
                _RankingMetric.longestRun: 'Dài nhất',
                _RankingMetric.activityCount: 'Buổi',
              },
              onChanged: onMetricChanged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ControlDropdown<_RankingRange>(
              icon: Icons.date_range_outlined,
              value: range,
              items: const {
                _RankingRange.rollingSevenDays: '7 ngày',
                _RankingRange.currentWeek: 'Tuần này',
                _RankingRange.currentMonth: 'Tháng này',
              },
              onChanged: onRangeChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClubRecapRangeControl extends StatelessWidget {
  const _ClubRecapRangeControl({required this.value, required this.onChanged});

  final _ClubRecapRange value;
  final ValueChanged<_ClubRecapRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.all(5),
      child: SegmentedButton<_ClubRecapRange>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
        segments: const [
          ButtonSegment(
            value: _ClubRecapRange.currentWeek,
            label: Text('Tuần'),
          ),
          ButtonSegment(
            value: _ClubRecapRange.currentMonth,
            label: Text('Tháng'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.single),
      ),
    );
  }
}

class _ClubSummaryCard extends StatelessWidget {
  const _ClubSummaryCard({
    required this.title,
    required this.totalDistanceMeters,
    required this.totalMovingTimeSeconds,
    required this.totalActivities,
    required this.activeMembers,
    required this.memberCount,
  });

  final String title;
  final double totalDistanceMeters;
  final int totalMovingTimeSeconds;
  final int totalActivities;
  final int activeMembers;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xfff9fbff), Color(0xffe8f0f8)]
            : const [Color(0xe607172b), Color(0xaa071426)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2, color: AppColors.blueGlow, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.66),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                '$activeMembers/$memberCount active',
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blueGlow.withValues(alpha: 0.18),
                  blurRadius: 26,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: Text(
              formatDistance(totalDistanceMeters),
              style: TextStyle(
                color: onSurface,
                fontSize: 42,
                fontWeight: FontWeight.w900,
                height: 0.95,
                shadows: [
                  Shadow(
                    color: AppColors.blueGlow.withValues(alpha: 0.38),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RecapStat(
                  label: 'THỜI GIAN',
                  value: formatDuration(totalMovingTimeSeconds),
                  color: _clubChartColor(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecapStat(
                  label: 'SỐ BUỔI',
                  value: '$totalActivities',
                  color: _clubChartColor(0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecapStat extends StatelessWidget {
  const _RecapStat({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isLight ? const Color(0xffeef4fb) : const Color(0x36020812),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.14),
              blurRadius: 18,
              spreadRadius: -10,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.52),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: color.withValues(alpha: 0.36),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubMetricBarData {
  const _ClubMetricBarData({
    required this.label,
    required this.score,
    required this.value,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final double score;
  final String value;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;
}

class _ClubMetricBarRow extends StatelessWidget {
  const _ClubMetricBarRow({required this.row, required this.maxScore});

  final _ClubMetricBarData row;
  final double maxScore;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ratio = maxScore <= 0 ? 0.0 : (row.score / maxScore).clamp(0.12, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: row.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.58),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  row.value,
                  style: TextStyle(
                    color: row.color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (row.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                row.subtitle!,
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: onSurface.withValues(alpha: 0.09)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: ratio.toDouble(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              row.color.withValues(alpha: 0.45),
                              row.color,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClubConsistencySpreadCard extends StatelessWidget {
  const _ClubConsistencySpreadCard({
    required this.period,
    required this.zeroDays,
    required this.oneDay,
    required this.twoDays,
    required this.threePlusDays,
    required this.memberCount,
    required this.onTap,
  });

  final String period;
  final int zeroDays;
  final int oneDay;
  final int twoDays;
  final int threePlusDays;
  final int memberCount;
  final void Function(int minimumDays, int? maximumDays) onTap;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _ClubMetricBarData(
        label: '0 NGÀY',
        score: zeroDays.toDouble(),
        value: '$zeroDays',
        color: _clubChartColor(0.45),
        subtitle: 'chưa chạy trong $period',
        onTap: () => onTap(0, 0),
      ),
      _ClubMetricBarData(
        label: '1 NGÀY',
        score: oneDay.toDouble(),
        value: '$oneDay',
        color: _clubChartColor(0.7),
        subtitle: 'đã có nhịp',
        onTap: () => onTap(1, 1),
      ),
      _ClubMetricBarData(
        label: '2 NGÀY',
        score: twoDays.toDouble(),
        value: '$twoDays',
        color: _clubChartColor(0.85),
        subtitle: 'duy trì tốt',
        onTap: () => onTap(2, 2),
      ),
      _ClubMetricBarData(
        label: '3+ NGÀY',
        score: threePlusDays.toDouble(),
        value: '$threePlusDays',
        color: _clubChartColor(1),
        subtitle: 'rất đều',
        onTap: () => onTap(3, null),
      ),
    ];
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.grid_view_rounded,
            title: 'ĐỘ PHỦ ACTIVE',
            trailing: '$memberCount member',
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _ClubMetricBarRow(row: row, maxScore: memberCount.toDouble()),
            if (row != rows.last) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ClubSectionHeader extends StatelessWidget {
  const _ClubSectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
    this.color = AppColors.blueGlow,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.66),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _ControlDropdown<T> extends StatelessWidget {
  const _ControlDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        isDense: true,
        value: value,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        dropdownColor: isLight
            ? const Color(0xfff8fbff)
            : const Color(0xff071426),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.blueGlow),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: (value) {
          if (value == null) return;
          onChanged(value);
        },
      ),
    );
  }
}

class _ContributionItem {
  const _ContributionItem({
    required this.entry,
    required this.score,
    required this.value,
  });

  final LeaderboardEntry entry;
  final double score;
  final String value;
}

List<PowerRadarMetric> _clubPowerMetrics({
  required _ClubRecapRange range,
  required int memberCount,
  required double totalDistanceMeters,
  required int totalMovingTimeSeconds,
  required int totalActivities,
  required double activeRate,
  required double? fastestPaceSecondsPerKm,
}) {
  final safeMemberCount = memberCount <= 0 ? 1 : memberCount;
  final weekly = range == _ClubRecapRange.currentWeek;
  final volumeTargetKm = safeMemberCount * (weekly ? 15.0 : 60.0);
  final loadTargetSeconds = safeMemberCount * (weekly ? 3 * 3600 : 12 * 3600);
  final averageDistanceMeters = totalActivities == 0
      ? 0.0
      : totalDistanceMeters / totalActivities;

  return [
    PowerRadarMetric(
      label: 'VOLUME',
      value: formatDistance(totalDistanceMeters),
      score: powerScoreRatio(totalDistanceMeters / 1000, volumeTargetKm),
      color: AppColors.blueGlow,
    ),
    PowerRadarMetric(
      label: 'ACTIVE',
      value: '${(activeRate * 100).round()}%',
      score: activeRate.clamp(0.0, 1.0).toDouble(),
      color: AppColors.amber,
    ),
    PowerRadarMetric(
      label: 'LOAD',
      value: formatDuration(totalMovingTimeSeconds),
      score: powerScoreRatio(
        totalMovingTimeSeconds.toDouble(),
        loadTargetSeconds.toDouble(),
      ),
      color: AppColors.red,
    ),
    PowerRadarMetric(
      label: 'AVG',
      value: formatDistance(averageDistanceMeters),
      score: powerScoreRatio(averageDistanceMeters / 1000, 5),
      color: const Color(0xff8b5cf6),
    ),
    PowerRadarMetric(
      label: 'TỐC',
      value: formatPace(fastestPaceSecondsPerKm),
      score: powerSpeedScore(fastestPaceSecondsPerKm),
      color: const Color(0xff22c55e),
    ),
  ];
}

double? _fastestPace(List<LeaderboardStats> stats) {
  double? fastest;
  for (final item in stats) {
    final pace = item.fastestPaceSecondsPerKm;
    if (pace == null || !pace.isFinite || pace <= 0) continue;
    if (fastest == null || pace < fastest) fastest = pace;
  }
  return fastest;
}

List<_ContributionItem> _contributionItems(
  List<LeaderboardEntry> entries,
  _ClubRecapRange range, {
  required double Function(LeaderboardStats stats) score,
  required String Function(LeaderboardStats stats) value,
}) {
  return entries
      .map((entry) {
        final stats = _recapStatsFor(entry, range);
        return _ContributionItem(
          entry: entry,
          score: score(stats),
          value: value(stats),
        );
      })
      .where((item) => item.score.isFinite && item.score > 0)
      .toList()
    ..sort((left, right) => right.score.compareTo(left.score));
}

LeaderboardStats _recapStatsFor(LeaderboardEntry entry, _ClubRecapRange range) {
  return switch (range) {
    _ClubRecapRange.currentWeek => entry.currentWeek,
    _ClubRecapRange.currentMonth => entry.currentMonth,
  };
}

Future<void> _showContributionSheet(
  BuildContext context, {
  required String title,
  required List<_ContributionItem> items,
}) {
  final maxScore = items.fold<double>(
    0,
    (max, item) => item.score > max ? item.score : max,
  );
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: GlassPanel(
        borderRadius: 24,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClubSectionHeader(
              icon: Icons.analytics_outlined,
              title: title.toUpperCase(),
              trailing: '${items.length} member',
              color: AppColors.amber,
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Text(
                'Chưa có đóng góp trong mục này.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _ContributionRow(item: items[index], maxScore: maxScore),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.item, required this.maxScore});

  final _ContributionItem item;
  final double maxScore;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ratio = maxScore <= 0
        ? 0.0
        : (item.score / maxScore).clamp(0.08, 1.0);
    return Row(
      children: [
        _LeaderboardAvatar(entry: item.entry, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    item.value,
                    style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: onSurface.withValues(alpha: 0.09)),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio.toDouble(),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0x66ffd166), AppColors.amber],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankingEntry {
  const _RankingEntry({
    required this.entry,
    required this.stats,
    required this.score,
  });

  factory _RankingEntry.fromLeaderboard(
    LeaderboardEntry entry,
    _RankingMetric metric,
    _RankingRange range,
  ) {
    final stats = switch (range) {
      _RankingRange.rollingSevenDays => entry.rollingSevenDays,
      _RankingRange.currentWeek => entry.currentWeek,
      _RankingRange.currentMonth => entry.currentMonth,
    };
    final score = switch (metric) {
      _RankingMetric.distance => stats.distanceMeters,
      _RankingMetric.time => stats.movingTimeSeconds.toDouble(),
      _RankingMetric.consistency => stats.activeDays.toDouble(),
      _RankingMetric.pace => stats.fastestPaceSecondsPerKm ?? double.infinity,
      _RankingMetric.longestRun => stats.longestDistanceMeters,
      _RankingMetric.activityCount => stats.activityCount.toDouble(),
    };
    return _RankingEntry(entry: entry, stats: stats, score: score);
  }

  final LeaderboardEntry entry;
  final LeaderboardStats stats;
  final double score;
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.rank,
    required this.entry,
    required this.metric,
    required this.currentUid,
  });

  final int rank;
  final _RankingEntry entry;
  final _RankingMetric metric;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final member = entry.entry;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (member.uid == currentUid) {
            context.go('/');
            return;
          }
          context.push('/club/${member.uid}');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Row(
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 9),
              _LeaderboardAvatar(entry: member, size: 40),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _scoreLabel(entry, metric),
                style: TextStyle(
                  color: onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.42);
    final color = switch (rank) {
      1 => AppColors.amber,
      2 => AppColors.blueGlow,
      3 => AppColors.red,
      _ => muted,
    };
    final icon = switch (rank) {
      1 => Icons.emoji_events,
      2 => Icons.military_tech,
      3 => Icons.workspace_premium,
      _ => null,
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(11),
      ),
      child: icon == null
          ? Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            )
          : Icon(icon, color: color, size: 18),
    );
  }
}

class _EmptyClub extends StatelessWidget {
  const _EmptyClub();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassPanel(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_2_outlined, size: 42),
              const SizedBox(height: 12),
              Text(
                'Chưa có thành viên',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Khi có người đăng nhập Google, hồ sơ câu lạc bộ sẽ xuất hiện ở đây.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.currentUid});

  final MemberProfile member;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final isMe = currentUid == member.uid;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 18,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: member.isPublic
            ? () {
                if (isMe) {
                  context.go('/');
                  return;
                }
                context.push('/club/${member.uid}');
              }
            : null,
        child: Row(
          children: [
            _MemberAvatar(member: member, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 8),
                        const _MiniChip(
                          label: 'Bạn',
                          color: AppColors.blueGlow,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  _VisibilityPill(isPublic: member.isPublic),
                ],
              ),
            ),
            if (member.isPublic)
              Icon(
                Icons.chevron_right,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.42),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRanking extends StatelessWidget {
  const _EmptyRanking();

  @override
  Widget build(BuildContext context) {
    return const GlassPanel(
      borderRadius: 22,
      padding: EdgeInsets.all(18),
      child: Text('Chưa có thành viên public để xếp hạng.'),
    );
  }
}

String _scoreLabel(_RankingEntry entry, _RankingMetric metric) {
  return switch (metric) {
    _RankingMetric.distance => formatDistance(entry.stats.distanceMeters),
    _RankingMetric.time => formatDuration(entry.stats.movingTimeSeconds),
    _RankingMetric.consistency => '${entry.stats.activeDays} ngày',
    _RankingMetric.pace =>
      entry.stats.fastestPaceSecondsPerKm == null
          ? '--'
          : formatPace(entry.stats.fastestPaceSecondsPerKm),
    _RankingMetric.longestRun => formatDistance(
      entry.stats.longestDistanceMeters,
    ),
    _RankingMetric.activityCount => '${entry.stats.activityCount} buổi',
  };
}

class _LeaderboardAvatar extends StatelessWidget {
  const _LeaderboardAvatar({required this.entry, this.size = 58});

  final LeaderboardEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = entry.avatarUrl;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.blueGlow, AppColors.red],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x3300d9ff), blurRadius: 18)],
      ),
      padding: const EdgeInsets.all(2),
      child: CircleAvatar(
        backgroundColor: Colors.black,
        backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        child: avatarUrl == null
            ? Text(
                entry.displayName.characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              )
            : null,
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member, this.size = 58});

  final MemberProfile member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = member.avatarUrl;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [AppColors.blueGlow, AppColors.red],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x3300d9ff), blurRadius: 18)],
      ),
      padding: const EdgeInsets.all(2),
      child: CircleAvatar(
        backgroundColor: Colors.black,
        backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        child: avatarUrl == null
            ? Text(
                member.displayName.characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              )
            : null,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _VisibilityPill extends StatelessWidget {
  const _VisibilityPill({required this.isPublic});

  final bool isPublic;

  @override
  Widget build(BuildContext context) {
    final color = isPublic
        ? AppColors.blueGlow
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.36);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPublic ? Icons.public : Icons.lock_outline,
          color: color,
          size: 16,
        ),
        const SizedBox(width: 6),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isPublic ? 0.7 : 0.45),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

Color _clubChartColor(double opacity) {
  return AppColors.blueGlow.withValues(alpha: opacity);
}
