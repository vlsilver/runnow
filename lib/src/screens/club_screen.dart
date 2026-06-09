import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/power_radar_card.dart';

const _rankingTabIndex = 0;
const _recapTabIndex = 1;

class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_syncActiveSubTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActiveSubTab();
      ref.read(memberRepositoryProvider).ensureCurrentLeaderboardEntry();
    });
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_syncActiveSubTab)
      ..dispose();
    super.dispose();
  }

  void _syncActiveSubTab() {
    final index = _tabController.index;
    if (ref.read(clubActiveSubTabProvider) != index) {
      ref.read(clubActiveSubTabProvider.notifier).state = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Câu lạc bộ'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
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
                controller: _tabController,
                children: [
                  _RankingTab(currentUid: _currentUid(ref)),
                  const _ClubRecapTab(),
                  const _ClubJournalTab(),
                  _MembersTab(members: items, currentUid: _currentUid(ref)),
                ],
              ),
        error: (error, stack) =>
            Center(child: Text('Không thể tải thành viên: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
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
  const _ClubRecapTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(clubRecapRangeProvider);
    final leaderboard = ref.watch(leaderboardEntriesProvider);
    return leaderboard.when(
      data: (items) {
        final entries = items.where((entry) => entry.isPublic).toList();
        if (entries.isEmpty) return const _EmptyRanking();
        final stats = entries
            .map(
              (entry) => switch (range) {
                ClubRecapRange.currentWeek => entry.currentWeek,
                ClubRecapRange.currentMonth => entry.currentMonth,
              },
            )
            .toList();
        final period = switch (range) {
          ClubRecapRange.currentWeek => 'tuần',
          ClubRecapRange.currentMonth => 'tháng',
        };
        final periodTitle = switch (range) {
          ClubRecapRange.currentWeek => 'TUẦN',
          ClubRecapRange.currentMonth => 'THÁNG',
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
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
            _ClubRecordsCard(range: range, periodTitle: periodTitle),
            _InactiveMembersCard(
              entries: [
                for (var index = 0; index < entries.length; index++)
                  if (stats[index].distanceMeters <= 0) entries[index],
              ],
              period: period,
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

class _ClubRecordsCard extends ConsumerWidget {
  const _ClubRecordsCard({required this.range, required this.periodTitle});

  final ClubRecapRange range;
  final String periodTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(clubActivityLogProvider);
    return log.maybeWhen(
      data: (items) {
        final now = DateTime.now();
        final (start, end) = switch (range) {
          ClubRecapRange.currentWeek => (
            startOfCurrentWeek(now),
            startOfCurrentWeek(now).add(const Duration(days: 7)),
          ),
          ClubRecapRange.currentMonth => (
            DateTime(now.year, now.month),
            DateTime(now.year, now.month + 1),
          ),
        };
        final entries = [
          for (final item in items)
            if (!item.activity.startedAt.isBefore(start) &&
                item.activity.startedAt.isBefore(end))
              ActivityRecordEntry(
                activity: item.activity,
                ownerUid: item.member.uid,
                ownerName: item.member.displayName,
                ownerAvatarUrl: item.member.avatarUrl,
              ),
        ];
        if (entries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ActivityRecordsCard(
            title: 'KỶ LỤC CLUB $periodTitle',
            showOwner: true,
            entries: entries,
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _RankingTab extends ConsumerWidget {
  const _RankingTab({required this.currentUid});

  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(clubRankingMetricProvider);
    final range = ref.watch(clubRankingRangeProvider);
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
                final byScore = metric == ClubRankingMetric.pace
                    ? left.score.compareTo(right.score)
                    : right.score.compareTo(left.score);
                if (byScore != 0) return byScore;
                return right.stats.distanceMeters.compareTo(
                  left.stats.distanceMeters,
                );
              });
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (entries.isEmpty)
              const _EmptyRanking()
            else
              _ShareableClubCard(
                title:
                    'RunNow bảng xếp hạng ${_rankingMetricLabel(metric)} ${_rankingRangeLabel(range)}',
                child: _RankingBoardCard(
                  entries: entries,
                  metric: metric,
                  range: range,
                  currentUid: currentUid,
                ),
              ),
          ],
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải bảng xếp hạng: $error')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Filter của club render gộp chung trong navigation bar (cùng [GlassPanel]).
/// Tuỳ tab con đang chọn mà hiện bộ lọc phù hợp: Xếp hạng (dropdown metric +
/// range) hoặc Tổng kết (toggle Tuần/Tháng).
class ClubNavFilter extends ConsumerWidget {
  const ClubNavFilter({required this.branchActive, super.key});

  final bool branchActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = branchActive ? ref.watch(clubActiveSubTabProvider) : -1;
    final Widget child = switch (tab) {
      _rankingTabIndex => const _RankingNavControls(),
      _recapTabIndex => const _RecapToggle(),
      _ => const SizedBox(width: double.infinity),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _RankingNavControls extends ConsumerWidget {
  const _RankingNavControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(clubRankingMetricProvider);
    final range = ref.watch(clubRankingRangeProvider);
    return NavFilterShell(
      child: Row(
        children: [
          Expanded(
            child: NavDropdown<ClubRankingMetric>(
              icon: Icons.leaderboard_outlined,
              value: metric,
              items: const {
                ClubRankingMetric.distance: 'Km',
                ClubRankingMetric.time: 'Thời gian',
                ClubRankingMetric.consistency: 'Đều',
                ClubRankingMetric.pace: 'Pace',
                ClubRankingMetric.longestRun: 'Dài nhất',
                ClubRankingMetric.activityCount: 'Buổi',
              },
              onChanged: (value) =>
                  ref.read(clubRankingMetricProvider.notifier).state = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NavDropdown<ClubRankingRange>(
              icon: Icons.date_range_outlined,
              value: range,
              items: const {
                ClubRankingRange.rollingSevenDays: '7 ngày',
                ClubRankingRange.currentWeek: 'Tuần này',
                ClubRankingRange.currentMonth: 'Tháng này',
              },
              onChanged: (value) =>
                  ref.read(clubRankingRangeProvider.notifier).state = value,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapToggle extends ConsumerWidget {
  const _RecapToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(clubRecapRangeProvider);
    return NavFilterShell(
      child: NavPillToggle<ClubRecapRange>(
        value: range,
        items: const {
          ClubRecapRange.currentWeek: 'Tuần',
          ClubRecapRange.currentMonth: 'Tháng',
        },
        onChanged: (value) =>
            ref.read(clubRecapRangeProvider.notifier).state = value,
      ),
    );
  }
}

class _ShareableClubCard extends StatefulWidget {
  const _ShareableClubCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_ShareableClubCard> createState() => _ShareableClubCardState();
}

class _ShareableClubCardState extends State<_ShareableClubCard> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _sharing ? null : _share,
      child: RepaintBoundary(key: _cardKey, child: widget.child),
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

class _RankingBoardCard extends StatelessWidget {
  const _RankingBoardCard({
    required this.entries,
    required this.metric,
    required this.range,
    required this.currentUid,
  });

  final List<_RankingEntry> entries;
  final ClubRankingMetric metric;
  final ClubRankingRange range;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.emoji_events,
            title: 'BẢNG XẾP HẠNG',
            trailing:
                '${_rankingMetricLabel(metric)} · ${_rankingRangeLabel(range)}',
            color: AppColors.amber,
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < entries.length; index++)
            _RankingCard(
              rank: index + 1,
              entry: entries[index],
              metric: metric,
              currentUid: currentUid,
            ),
        ],
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
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
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

class _InactiveMembersCard extends StatelessWidget {
  const _InactiveMembersCard({required this.entries, required this.period});

  final List<LeaderboardEntry> entries;
  final String period;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.person_off_outlined,
            title: 'CHƯA ACTIVE',
            trailing: '${entries.length} member',
            color: AppColors.amber,
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'Tất cả thành viên public đã có hoạt động trong $period.',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.64),
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final entry in entries) _InactiveMemberPill(entry: entry),
              ],
            ),
        ],
      ),
    );
  }
}

class _InactiveMemberPill extends StatelessWidget {
  const _InactiveMemberPill({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LeaderboardAvatar(entry: entry, size: 30),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
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

List<PowerRadarMetric> _clubPowerMetrics({
  required ClubRecapRange range,
  required int memberCount,
  required double totalDistanceMeters,
  required int totalMovingTimeSeconds,
  required int totalActivities,
  required double activeRate,
  required double? fastestPaceSecondsPerKm,
}) {
  final safeMemberCount = memberCount <= 0 ? 1 : memberCount;
  final weekly = range == ClubRecapRange.currentWeek;
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

class _RankingEntry {
  const _RankingEntry({
    required this.entry,
    required this.stats,
    required this.score,
  });

  factory _RankingEntry.fromLeaderboard(
    LeaderboardEntry entry,
    ClubRankingMetric metric,
    ClubRankingRange range,
  ) {
    final stats = switch (range) {
      ClubRankingRange.rollingSevenDays => entry.rollingSevenDays,
      ClubRankingRange.currentWeek => entry.currentWeek,
      ClubRankingRange.currentMonth => entry.currentMonth,
    };
    final score = switch (metric) {
      ClubRankingMetric.distance => stats.distanceMeters,
      ClubRankingMetric.time => stats.movingTimeSeconds.toDouble(),
      ClubRankingMetric.consistency => stats.activeDays.toDouble(),
      ClubRankingMetric.pace => stats.averagePaceSecondsPerKm ?? double.infinity,
      ClubRankingMetric.longestRun => stats.longestDistanceMeters,
      ClubRankingMetric.activityCount => stats.activityCount.toDouble(),
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
  final ClubRankingMetric metric;
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

String _scoreLabel(_RankingEntry entry, ClubRankingMetric metric) {
  return switch (metric) {
    ClubRankingMetric.distance => formatDistance(entry.stats.distanceMeters),
    ClubRankingMetric.time => formatDuration(entry.stats.movingTimeSeconds),
    ClubRankingMetric.consistency => '${entry.stats.activeDays} ngày',
    ClubRankingMetric.pace => entry.stats.averagePaceSecondsPerKm == null
        ? '--'
        : formatPace(entry.stats.averagePaceSecondsPerKm),
    ClubRankingMetric.longestRun => formatDistance(
      entry.stats.longestDistanceMeters,
    ),
    ClubRankingMetric.activityCount => '${entry.stats.activityCount} buổi',
  };
}

String _rankingMetricLabel(ClubRankingMetric metric) {
  return switch (metric) {
    ClubRankingMetric.distance => 'Km',
    ClubRankingMetric.time => 'Thời gian',
    ClubRankingMetric.consistency => 'Đều',
    ClubRankingMetric.pace => 'Pace',
    ClubRankingMetric.longestRun => 'Dài nhất',
    ClubRankingMetric.activityCount => 'Buổi',
  };
}

String _rankingRangeLabel(ClubRankingRange range) {
  return switch (range) {
    ClubRankingRange.rollingSevenDays => '7 ngày',
    ClubRankingRange.currentWeek => 'Tuần này',
    ClubRankingRange.currentMonth => 'Tháng này',
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
