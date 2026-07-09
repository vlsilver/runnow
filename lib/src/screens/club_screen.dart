import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/power_radar_card.dart';
import 'package:myrun/src/widgets/route_map.dart';

const _rankingTabIndex = 0;
const _recapTabIndex = 1;
const _clubRailBreakpoint = 760.0;

const _clubSections = <_ClubSection>[
  _ClubSection(
    label: 'Xếp hạng',
    icon: Icons.emoji_events_outlined,
    selectedIcon: Icons.emoji_events_rounded,
  ),
  _ClubSection(
    label: 'Tổng kết',
    icon: Icons.donut_large_outlined,
    selectedIcon: Icons.donut_large_rounded,
  ),
  _ClubSection(
    label: 'Đang chạy',
    icon: Icons.sensors_outlined,
    selectedIcon: Icons.sensors_rounded,
  ),
  _ClubSection(
    label: 'Nhật ký',
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline_rounded,
  ),
  _ClubSection(
    label: 'Thành viên',
    icon: Icons.groups_2_outlined,
    selectedIcon: Icons.groups_2_rounded,
  ),
];

class _ClubSection {
  const _ClubSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  var _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      animationDuration: Duration.zero,
    )..addListener(_syncActiveSubTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncActiveSubTab();
      unawaited(_ensureCurrentLeaderboardEntry());
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
    if (mounted && _activeTabIndex != index) {
      setState(() => _activeTabIndex = index);
    }
    if (ref.read(clubActiveSubTabProvider) != index) {
      ref.read(clubActiveSubTabProvider.notifier).state = index;
    }
  }

  Future<void> _ensureCurrentLeaderboardEntry() async {
    try {
      await ref.read(memberRepositoryProvider).ensureCurrentLeaderboardEntry();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[ClubScreen] Could not refresh leaderboard: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider);
    final desktopWeb = RunNowWebLayout.isDesktop(context);
    final showSideRail =
        desktopWeb ||
        (!kIsWeb && MediaQuery.sizeOf(context).width >= _clubRailBreakpoint);
    return Scaffold(
      appBar: AppBar(title: const Text('Câu lạc bộ')),
      body: Column(
        children: [
          if (desktopWeb)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                height: 42,
                child: ClubNavFilter(branchActive: true),
              ),
            ),
          Expanded(
            child: members.when(
              data: (items) => items.isEmpty
                  ? const _EmptyClub()
                  : _ClubSectionLayout(
                      showSideRail: showSideRail,
                      selectedIndex: _activeTabIndex,
                      controller: _tabController,
                      onSelect: (index) => _tabController.index = index,
                      children: [
                        _RankingTab(currentUid: _currentUid(ref)),
                        const _ClubRecapTab(),
                        const _ClubLiveTab(),
                        const _ClubJournalTab(),
                        _MembersTab(
                          members: items,
                          currentUid: _currentUid(ref),
                        ),
                      ],
                    ),
              error: (error, stack) =>
                  Center(child: Text('Không thể tải thành viên: $error')),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }

  String? _currentUid(WidgetRef ref) {
    return ref
        .watch(firebaseUserProvider)
        .maybeWhen(data: (user) => user?.uid, orElse: () => null);
  }
}

class _ClubBottomTabBar extends StatelessWidget {
  const _ClubBottomTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TabBar(
            controller: controller,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            tabs: [
              for (final section in _clubSections)
                Tab(
                  height: 50,
                  icon: Tooltip(
                    message: section.label,
                    child: Semantics(
                      label: section.label,
                      button: true,
                      child: Icon(section.icon, size: 24),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubSectionLayout extends StatelessWidget {
  const _ClubSectionLayout({
    required this.showSideRail,
    required this.selectedIndex,
    required this.controller,
    required this.onSelect,
    required this.children,
  });

  final bool showSideRail;
  final int selectedIndex;
  final TabController controller;
  final ValueChanged<int> onSelect;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final content = _LazyClubStack(
      selectedIndex: selectedIndex,
      children: children,
    );
    if (!showSideRail) {
      return Column(
        children: [
          Expanded(child: content),
          _ClubBottomTabBar(controller: controller),
        ],
      );
    }
    return Row(
      children: [
        _ClubSideRail(selectedIndex: selectedIndex, onSelect: onSelect),
        Expanded(child: content),
      ],
    );
  }
}

class _LazyClubStack extends StatefulWidget {
  const _LazyClubStack({required this.selectedIndex, required this.children});

  final int selectedIndex;
  final List<Widget> children;

  @override
  State<_LazyClubStack> createState() => _LazyClubStackState();
}

class _LazyClubStackState extends State<_LazyClubStack> {
  final _visited = <int>{};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.selectedIndex);
  }

  @override
  void didUpdateWidget(covariant _LazyClubStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.selectedIndex,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          TickerMode(
            enabled: index == widget.selectedIndex,
            child: _visited.contains(index)
                ? RepaintBoundary(child: widget.children[index])
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class _ClubSideRail extends StatelessWidget {
  const _ClubSideRail({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 72,
      margin: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        minWidth: 72,
        groupAlignment: -0.72,
        labelType: NavigationRailLabelType.none,
        backgroundColor: Colors.transparent,
        useIndicator: true,
        indicatorColor: accent.withValues(alpha: 0.2),
        selectedIconTheme: IconThemeData(color: accent, size: 25),
        unselectedIconTheme: IconThemeData(
          color: onSurface.withValues(alpha: 0.58),
          size: 23,
        ),
        destinations: [
          for (final section in _clubSections)
            NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
            ),
        ],
      ),
    );
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
                borderRadius: 0,
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

class _ClubLiveTab extends ConsumerStatefulWidget {
  const _ClubLiveTab();

  @override
  ConsumerState<_ClubLiveTab> createState() => _ClubLiveTabState();
}

class _ClubLiveTabState extends ConsumerState<_ClubLiveTab> {
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(clubLiveSessionsProvider);
    return sessions.when(
      data: (items) {
        final now = DateTime.now();
        final activeItems = items
            .where((session) => !session.isExpired(now))
            .toList();
        if (activeItems.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: const [
              GlassPanel(
                borderRadius: 0,
                padding: EdgeInsets.all(18),
                child: Text('Chưa có thành viên nào đang chạy live.'),
              ),
            ],
          );
        }
        final wide = MediaQuery.sizeOf(context).width >= 980;
        if (!wide) {
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            itemBuilder: (context, index) => _LiveSessionCard(
              session: activeItems[index],
              onTap: () => _openLiveSession(context, activeItems[index]),
            ),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemCount: activeItems.length,
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 520,
            mainAxisExtent: 178,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: activeItems.length,
          itemBuilder: (context, index) => _LiveSessionCard(
            session: activeItems[index],
            onTap: () => _openLiveSession(context, activeItems[index]),
          ),
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải live tracking: $error')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }

  Future<void> _openLiveSession(
    BuildContext context,
    LiveTrackingSession session,
  ) {
    final now = DateTime.now();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LiveAvatar(session: session, size: 42),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          _liveFreshnessLabel(session, now),
                          style: TextStyle(
                            color: context.runNowPalette.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (session.routePreview.length >= 2)
                RouteMap.fromRoutePoints(
                  points: session.routePreview,
                  height: MediaQuery.sizeOf(context).height * 0.52,
                )
              else
                const GlassPanel(
                  borderRadius: 18,
                  padding: EdgeInsets.all(18),
                  child: Text('Đang chờ route preview đủ điểm.'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LiveMetric(
                      label: 'KM',
                      value: formatDistance(session.distanceMeters),
                    ),
                  ),
                  Expanded(
                    child: _LiveMetric(
                      label: 'TIME',
                      value: formatDuration(session.movingTimeSeconds),
                    ),
                  ),
                  Expanded(
                    child: _LiveMetric(
                      label: 'PACE',
                      value: formatPace(session.averagePaceSecondsPerKm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.session, required this.onTap});

  final LiveTrackingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale = session.isStale(now);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final palette = context.runNowPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: GlassPanel(
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
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
                _LiveAvatar(session: session, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _liveFreshnessLabel(session, now),
                        style: TextStyle(
                          color: stale ? palette.tertiary : palette.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  session.status == LiveTrackingStatus.paused
                      ? Icons.pause_circle_filled_rounded
                      : Icons.sensors_rounded,
                  color: stale ? palette.tertiary : palette.secondary,
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _LiveMetric(
                    label: 'KM',
                    value: formatDistance(session.distanceMeters),
                  ),
                ),
                Expanded(
                  child: _LiveMetric(
                    label: 'TIME',
                    value: formatDuration(session.movingTimeSeconds),
                  ),
                ),
                Expanded(
                  child: _LiveMetric(
                    label: 'PACE',
                    value: formatPace(session.averagePaceSecondsPerKm),
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

class _LiveAvatar extends StatelessWidget {
  const _LiveAvatar({required this.session, required this.size});

  final LiveTrackingSession session;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = session.ownerAvatarUrl;
    final palette = context.runNowPalette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.secondary, width: 2),
        boxShadow: [
          BoxShadow(
            color: palette.secondary.withValues(alpha: 0.28),
            blurRadius: 14,
          ),
        ],
      ),
      child: CircleAvatar(
        backgroundColor: palette.accentDeep,
        backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        child: avatarUrl == null
            ? Text(
                session.ownerName.trim().isEmpty
                    ? '?'
                    : session.ownerName.trim().substring(0, 1).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              )
            : null,
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.glassEnd,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.54),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _liveFreshnessLabel(LiveTrackingSession session, DateTime now) {
  final age = now.difference(session.updatedAt);
  final status = session.status == LiveTrackingStatus.paused
      ? 'PAUSED'
      : session.isStale(now)
      ? 'STALE'
      : 'LIVE';
  final seconds = age.inSeconds.clamp(0, 999);
  return '$status · ${seconds}s trước';
}

class _ClubJournalTab extends ConsumerWidget {
  const _ClubJournalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(clubActivityLogProvider);
    return log.when(
      data: (items) {
        if (items.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              GlassPanel(
                borderRadius: 0,
                padding: EdgeInsets.all(18),
                child: Text('Chưa có hoạt động public trong club.'),
              ),
            ],
          );
        }
        final wide = MediaQuery.sizeOf(context).width >= 980;
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              for (var index = 0; index < items.length; index++)
                ActivityTile(
                  activity: items[index].activity,
                  sequence: index + 1,
                  ownerUid: items[index].member.uid,
                  memberName: items[index].member.displayName,
                  memberAvatarUrl: items[index].member.avatarUrl,
                ),
            ],
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 560,
            mainAxisExtent: 178,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => ActivityTile(
            activity: items[index].activity,
            sequence: index + 1,
            ownerUid: items[index].member.uid,
            memberName: items[index].member.displayName,
            memberAvatarUrl: items[index].member.avatarUrl,
          ),
        );
      },
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
        final summaryCard = _ClubSummaryCard(
          title: 'TỔNG KẾT $periodTitle',
          totalDistanceMeters: totalDistance,
          totalMovingTimeSeconds: totalTime,
          totalActivities: totalActivities,
          activeMembers: activeMembers,
          memberCount: entries.length,
        );
        final powerCard = PowerRadarCard(
          title: 'CLUB POWER $periodTitle',
          metrics: powerMetrics,
          powerScore: averagePowerScore(powerMetrics),
        );
        final recordsCard = _ClubRecordsCard(
          range: range,
          periodTitle: periodTitle,
        );
        final inactiveCard = _InactiveMembersCard(
          entries: [
            for (var index = 0; index < entries.length; index++)
              if (stats[index].distanceMeters <= 0) entries[index],
          ],
          period: period,
        );
        final wide = MediaQuery.sizeOf(context).width >= 980;
        if (wide) {
          return _ClubWebGrid(
            columns: [
              _ClubWebColumn(children: [summaryCard, recordsCard]),
              _ClubWebColumn(children: [powerCard, inactiveCard]),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          children: [
            summaryCard,
            const SizedBox(height: 14),
            powerCard,
            const SizedBox(height: 14),
            recordsCard,
            inactiveCard,
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

class _ClubWebGrid extends StatelessWidget {
  const _ClubWebGrid({required this.columns});

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

class _ClubWebColumn extends StatelessWidget {
  const _ClubWebColumn({required this.children});

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
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
          children: [
            if (entries.isEmpty)
              const _EmptyRanking()
            else
              _ShareableClubCard(
                title:
                    '3i bảng xếp hạng ${_rankingMetricLabel(metric)} ${_rankingRangeLabel(range)}',
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
    if (!branchActive) return const SizedBox.shrink();
    final tab = ref.watch(clubActiveSubTabProvider);
    final Widget child = switch (tab) {
      _rankingTabIndex => const _RankingNavControls(
        key: ValueKey('ranking-filter'),
      ),
      _recapTabIndex => const _RecapToggle(key: ValueKey('recap-filter')),
      _ => const SizedBox(
        key: ValueKey('empty-filter'),
        width: double.infinity,
      ),
    };
    return SizedBox(
      height: 42,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 100),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: child,
      ),
    );
  }
}

class _RankingNavControls extends ConsumerWidget {
  const _RankingNavControls({super.key});

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
  const _RecapToggle({super.key});

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
    final palette = context.runNowPalette;
    final podium = entries.take(3).toList();
    final rest = entries.skip(3).toList();
    final topScore = entries.isEmpty ? 0.0 : entries.first.score;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.emoji_events,
            title: 'BẢNG XẾP HẠNG',
            trailing:
                '${_rankingMetricLabel(metric)} · ${_rankingRangeLabel(range)}',
            color: palette.tertiary,
          ),
          const SizedBox(height: 12),
          if (podium.isNotEmpty)
            _RankingPodium(
              entries: podium,
              metric: metric,
              range: range,
              currentUid: currentUid,
            ),
          for (var index = 0; index < rest.length; index++)
            _RankingCard(
              rank: index + 4,
              entry: rest[index],
              metric: metric,
              currentUid: currentUid,
              topScore: topScore,
            ),
        ],
      ),
    );
  }
}

/// Bục top 3: hạng nhì bên trái, hạng nhất giữa (avatar to nhất), hạng ba bên
/// phải — thay cho danh sách phẳng cũ để làm nổi bật 3 vị trí đầu. Bấm vào
/// một slot mở popup chúc mừng riêng cho thành viên đó.
class _RankingPodium extends StatelessWidget {
  const _RankingPodium({
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
    final palette = context.runNowPalette;
    final first = entries.isNotEmpty ? entries[0] : null;
    final second = entries.length > 1 ? entries[1] : null;
    final third = entries.length > 2 ? entries[2] : null;
    void onTap(int rank, _RankingEntry entry) => _showRankCelebration(
      context,
      entry: entry,
      rank: rank,
      metric: metric,
      range: range,
    );
    // Mỗi cột bọc trong SizedBox cùng chiều cao cố định + Align bottomCenter —
    // ép tên/điểm số (hàng trên) và đáy bệ (hàng dưới) luôn thẳng hàng tuyệt
    // đối giữa 3 cột, không phụ thuộc vào cách Row tự tính cross-axis khi 3
    // cột có nội dung cao thấp khác nhau (nguồn gốc lỗi lệch trước đó).
    const figureZoneHeight = 182.0;
    const standZoneHeight = 66.0;
    Widget zone(double height, Widget? child) => SizedBox(
      height: height,
      child: child == null
          ? null
          : Align(alignment: Alignment.bottomCenter, child: child),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
      child: Column(
        children: [
          // Hình đại diện/tên/điểm số căn theo cỡ avatar (chỉ hạng 1 to hơn) —
          // tách riêng khỏi bệ phía dưới để tên/điểm số luôn ngang hàng nhau,
          // không bị lệch theo chiều cao bệ (vốn khác nhau giữa các hạng).
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: zone(
                  figureZoneHeight,
                  second == null
                      ? null
                      : _PodiumFigure(
                          rank: 2,
                          entry: second,
                          metric: metric,
                          avatarSize: 66,
                          onTap: () => onTap(2, second),
                        ),
                ),
              ),
              Expanded(
                child: zone(
                  figureZoneHeight,
                  first == null
                      ? null
                      : _PodiumFigure(
                          rank: 1,
                          entry: first,
                          metric: metric,
                          avatarSize: 88,
                          onTap: () => onTap(1, first),
                        ),
                ),
              ),
              Expanded(
                child: zone(
                  figureZoneHeight,
                  third == null
                      ? null
                      : _PodiumFigure(
                          rank: 3,
                          entry: third,
                          metric: metric,
                          avatarSize: 66,
                          onTap: () => onTap(3, third),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: zone(
                  standZoneHeight,
                  second == null
                      ? null
                      : _PodiumStand(
                          rank: 2,
                          rankColor: palette.secondary,
                          onTap: () => onTap(2, second),
                        ),
                ),
              ),
              Expanded(
                child: zone(
                  standZoneHeight,
                  first == null
                      ? null
                      : _PodiumStand(
                          rank: 1,
                          rankColor: palette.tertiary,
                          onTap: () => onTap(1, first),
                        ),
                ),
              ),
              Expanded(
                child: zone(
                  standZoneHeight,
                  third == null
                      ? null
                      : _PodiumStand(
                          rank: 3,
                          rankColor: palette.accent,
                          onTap: () => onTap(3, third),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PodiumFigure extends StatelessWidget {
  const _PodiumFigure({
    required this.rank,
    required this.entry,
    required this.metric,
    required this.avatarSize,
    required this.onTap,
  });

  final int rank;
  final _RankingEntry entry;
  final ClubRankingMetric metric;
  final double avatarSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rankColor = switch (rank) {
      1 => palette.tertiary,
      2 => palette.secondary,
      _ => palette.accent,
    };
    final member = entry.entry;
    final (value, unit) = _splitScoreLabel(_scoreLabel(entry, metric));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rank == 1)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text('👑', style: TextStyle(fontSize: 20)),
            ),
          Container(
            width: avatarSize,
            height: avatarSize,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: rankColor),
            child: _LeaderboardAvatar(entry: member, size: avatarSize - 6),
          ),
          const SizedBox(height: 8),
          Text(
            member.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: rank == 1 ? rankColor : onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: rank == 1 ? 18 : 15,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
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

/// Bệ podium bên dưới mỗi slot — cao thấp theo hạng (nhất cao nhất) để tạo
/// đúng hiệu ứng bục 3 bậc, huy hiệu hạng (dạng huy chương + ru-băng) nằm
/// ngay trong bệ. Bấm vào cũng mở popup chúc mừng như bấm vào hình đại diện.
class _PodiumStand extends StatelessWidget {
  const _PodiumStand({
    required this.rank,
    required this.rankColor,
    required this.onTap,
  });

  final int rank;
  final Color rankColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final standHeight = switch (rank) {
      1 => 66.0,
      2 => 48.0,
      _ => 38.0,
    };
    // Chiều rộng huy chương phải chừa đủ margin so với chiều cao bệ (huy
    // chương có tỉ lệ cố định 220:300 theo file SVG gốc) — hạng càng thấp bệ
    // càng ngắn nên huy chương phải nhỏ dần theo, tránh tràn khung như bản
    // vẽ tay (CustomPainter) trước đây.
    final medalWidth = switch (rank) {
      1 => 38.0,
      2 => 26.0,
      _ => 19.0,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: standHeight,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            rankColor.withValues(alpha: 0.16),
            palette.glassStart,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
            top: BorderSide(color: rankColor.withValues(alpha: 0.5), width: 2),
          ),
        ),
        child: _Medal(rank: rank, width: medalWidth),
      ),
    );
  }
}

/// Huy chương thật (vàng/bạc/đồng) từ `assets/medals/` — thay hoàn toàn cho
/// bản vẽ tay bằng CustomPainter trước đó.
class _Medal extends StatelessWidget {
  const _Medal({required this.rank, required this.width});

  final int rank;
  final double width;

  static const _assetByRank = {
    1: 'assets/medals/medal-gold.svg',
    2: 'assets/medals/medal-silver.svg',
    3: 'assets/medals/medal-bronze.svg',
  };

  @override
  Widget build(BuildContext context) {
    // Tỉ lệ gốc của file SVG là 220:300 (rộng:cao).
    return SvgPicture.asset(
      _assetByRank[rank] ?? _assetByRank[3]!,
      width: width,
      height: width * 300 / 220,
    );
  }
}

void _showRankCelebration(
  BuildContext context, {
  required _RankingEntry entry,
  required int rank,
  required ClubRankingMetric metric,
  required ClubRankingRange range,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) =>
        _RankCelebrationDialog(entry: entry, rank: rank, metric: metric, range: range),
  );
}

/// Popup chúc mừng — bấm vào một slot trên podium (hạng 1-3) sẽ mở popup này,
/// chúc mừng đúng thành viên vừa bấm (không chỉ riêng "bạn").
class _RankCelebrationDialog extends StatefulWidget {
  const _RankCelebrationDialog({
    required this.entry,
    required this.rank,
    required this.metric,
    required this.range,
  });

  final _RankingEntry entry;
  final int rank;
  final ClubRankingMetric metric;
  final ClubRankingRange range;

  @override
  State<_RankCelebrationDialog> createState() =>
      _RankCelebrationDialogState();
}

class _RankCelebrationDialogState extends State<_RankCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rankColor = switch (widget.rank) {
      1 => palette.tertiary,
      2 => palette.secondary,
      _ => palette.accent,
    };
    final member = widget.entry.entry;
    final scoreLabel = _scoreLabel(widget.entry, widget.metric);
    final rangeLabel = _rankingRangeLabel(widget.range);
    final callName = _callName(member.displayName);
    final (greeting, rankLabel) = switch (widget.rank) {
      1 => ('Xuất sắc, $callName!', 'HẠNG NHẤT'),
      2 => ('Rất tốt, $callName!', 'HẠNG NHÌ'),
      _ => ('Giữ vững, $callName!', 'HẠNG BA'),
    };
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -40,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    _CelebrationBurst(progress: _controller.value, color: rankColor),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 30),
            padding: const EdgeInsets.fromLTRB(26, 34, 26, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [palette.glassStart, palette.glassEnd],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Medal(rank: widget.rank, width: 100),
                const SizedBox(height: 6),
                Text(
                  '$rankLabel · $rangeLabel',
                  style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  greeting,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: widget.rank == 1
                            ? 'Đang dẫn đầu Câu lạc bộ với '
                            : 'Đang đứng thứ ${widget.rank} với ',
                      ),
                      TextSpan(
                        text: scoreLabel,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: onSurface.withValues(alpha: 0.68)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: rankColor,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Đã xem',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: GlassIconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hiệu ứng pháo hoa nhẹ (không confetti sặc sỡ) phía sau huy chương — vài
/// chấm nhỏ toả ra rồi mờ dần, lặp lại liên tục khi popup còn mở.
class _CelebrationBurst extends StatelessWidget {
  const _CelebrationBurst({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const _particles = [
    (angle: -2.0, distance: 46.0, delay: 0.0),
    (angle: -1.2, distance: 58.0, delay: 0.15),
    (angle: -0.5, distance: 50.0, delay: 0.3),
    (angle: 0.3, distance: 60.0, delay: 0.05),
    (angle: 1.0, distance: 52.0, delay: 0.4),
    (angle: 1.7, distance: 44.0, delay: 0.2),
    (angle: 2.6, distance: 56.0, delay: 0.35),
    (angle: 3.4, distance: 48.0, delay: 0.1),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final particle in _particles)
            _dot(particle.angle, particle.distance, particle.delay),
        ],
      ),
    );
  }

  Widget _dot(double angle, double distance, double delay) {
    final t = ((progress - delay) % 1.0 + 1.0) % 1.0;
    final eased = Curves.easeOut.transform(t);
    final dx = math.cos(angle) * distance * eased;
    final dy = math.sin(angle) * distance * eased;
    final opacity = (1 - eased).clamp(0.0, 1.0) * 0.75;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

/// Tên gọi thân mật để chúc mừng — lấy từ CUỐI cụm tên (theo cách người Việt
/// thường gọi nhau, vd "Trần Hữu Dần" → "Dần"); tên 1 từ (nickname) giữ nguyên.
String _callName(String displayName) {
  final parts = displayName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? displayName : parts.last;
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
              Icon(Icons.groups_2, color: palette.accent, size: 20),
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
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatDistance(totalDistanceMeters),
            style: TextStyle(
              color: palette.accent,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              height: 0.95,
              shadows: [
                Shadow(
                  color: palette.secondary.withValues(alpha: 0.38),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RecapStat(
                  label: 'THỜI GIAN',
                  value: formatDuration(totalMovingTimeSeconds),
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecapStat(
                  label: 'SỐ BUỔI',
                  value: '$totalActivities',
                  color: palette.accent,
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.72), width: 2),
        ),
      ),
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
          const SizedBox(height: 5),
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
                Shadow(color: color.withValues(alpha: 0.28), blurRadius: 10),
              ],
            ),
          ),
        ],
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
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 0,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClubSectionHeader(
            icon: Icons.person_off_outlined,
            title: 'CHƯA ACTIVE',
            trailing: '${entries.length} member',
            color: palette.tertiary,
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
    this.color,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final resolvedColor = color ?? context.runNowPalette.secondary;
    return Row(
      children: [
        Icon(icon, color: resolvedColor, size: 18),
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
    ),
    PowerRadarMetric(
      label: 'ACTIVE',
      value: '${(activeRate * 100).round()}%',
      score: activeRate.clamp(0.0, 1.0).toDouble(),
    ),
    PowerRadarMetric(
      label: 'LOAD',
      value: formatDuration(totalMovingTimeSeconds),
      score: powerScoreRatio(
        totalMovingTimeSeconds.toDouble(),
        loadTargetSeconds.toDouble(),
      ),
    ),
    PowerRadarMetric(
      label: 'AVG',
      value: formatDistance(averageDistanceMeters),
      score: powerScoreRatio(averageDistanceMeters / 1000, 5),
    ),
    PowerRadarMetric(
      label: 'TỐC',
      value: formatPace(fastestPaceSecondsPerKm),
      score: powerSpeedScore(fastestPaceSecondsPerKm),
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
      ClubRankingMetric.pace =>
        stats.averagePaceSecondsPerKm ?? double.infinity,
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
    required this.topScore,
  });

  final int rank;
  final _RankingEntry entry;
  final ClubRankingMetric metric;
  final String? currentUid;
  final double topScore;

  @override
  Widget build(BuildContext context) {
    final member = entry.entry;
    final isMe = member.uid == currentUid;
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ratio = _relativeRatio(entry.score, topScore, metric);
    final (value, unit) = _splitScoreLabel(_scoreLabel(entry, metric));
    final barColor = isMe ? palette.accent : _flatMemberColor(member.uid);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: isMe
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.accent.withValues(alpha: 0.45)),
            )
          : null,
      child: GlassPanel(
        borderRadius: 16,
        gradient: isMe
            ? LinearGradient(
                colors: [
                  Color.alphaBlend(
                    palette.accent.withValues(alpha: 0.14),
                    palette.glassStart,
                  ),
                  Color.alphaBlend(
                    palette.accent.withValues(alpha: 0.14),
                    palette.glassEnd,
                  ),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isMe) {
              context.go('/');
              return;
            }
            context.push('/club/${member.uid}');
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _FlatMemberAvatar(member: member, size: 36),
                const SizedBox(width: 10),
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
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            _MiniChip(label: 'Bạn', color: palette.secondary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 4,
                          backgroundColor: onSurface.withValues(alpha: 0.09),
                          color: barColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: ' $unit',
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatMemberAvatar extends StatelessWidget {
  const _FlatMemberAvatar({required this.member, required this.size});

  final LeaderboardEntry member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = member.avatarUrl;
    final color = _flatMemberColor(member.uid);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
      child: avatarUrl == null
          ? Text(
              member.displayName.characters.first.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            )
          : null,
    );
  }
}

/// Màu phẳng ổn định theo uid — dùng chung cho avatar và thanh progress của
/// cùng 1 thành viên trong danh sách xếp hạng (hạng 4+).
const _flatMemberPalette = [
  RunNowDataColors.cadence,
  RunNowDataColors.energy,
  RunNowDataColors.pace,
  RunNowDataColors.elevation,
  RunNowDataColors.zone3,
  RunNowDataColors.zone4,
  RunNowDataColors.heart,
];

Color _flatMemberColor(String uid) =>
    _flatMemberPalette[uid.hashCode.abs() % _flatMemberPalette.length];

/// Tách "giá trị" và "đơn vị" từ chuỗi đã format sẵn (vd "19.41 km" ->
/// ("19.41", "km")) để hiện đậm/nhạt khác nhau như trên bục xếp hạng.
(String, String) _splitScoreLabel(String label) {
  final index = label.lastIndexOf(' ');
  if (index <= 0) return (label, '');
  return (label.substring(0, index), label.substring(index + 1));
}

/// Tỉ lệ so với người dẫn đầu, dùng cho thanh progress trong danh sách xếp
/// hạng. Với pace (thấp hơn là tốt hơn) tỉ lệ được đảo ngược so với các
/// metric còn lại (cao hơn là tốt hơn).
double _relativeRatio(double score, double topScore, ClubRankingMetric metric) {
  if (metric == ClubRankingMetric.pace) {
    if (score <= 0 || !score.isFinite || topScore <= 0) return 0;
    return (topScore / score).clamp(0.0, 1.0);
  }
  if (topScore <= 0 || !topScore.isFinite) return 0;
  return (score / topScore).clamp(0.0, 1.0);
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
    final palette = context.runNowPalette;
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
                        _MiniChip(label: 'Bạn', color: palette.secondary),
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
      borderRadius: 0,
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
    ClubRankingMetric.pace =>
      entry.stats.averagePaceSecondsPerKm == null
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
    final palette = context.runNowPalette;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [palette.secondary, palette.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
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
    final palette = context.runNowPalette;
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [palette.secondary, palette.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
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
        ? context.runNowPalette.secondary
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
