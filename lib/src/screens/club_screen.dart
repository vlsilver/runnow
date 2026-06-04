import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

enum _RankingMetric { distance, time, consistency }

enum _RankingRange { rollingSevenDays, currentWeek, currentMonth }

class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});

  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen> {
  _RankingMetric _metric = _RankingMetric.distance;
  _RankingRange _range = _RankingRange.rollingSevenDays;

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
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Câu lạc bộ'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Xếp hạng'),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        for (final member in members)
          _MemberCard(member: member, currentUid: currentUid),
      ],
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
                final byScore = right.score.compareTo(left.score);
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
              publicCount: entries.length,
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
            publicCount: null,
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
    required this.publicCount,
    required this.onMetricChanged,
    required this.onRangeChanged,
  });

  final _RankingMetric metric;
  final _RankingRange range;
  final int? publicCount;
  final ValueChanged<_RankingMetric> onMetricChanged;
  final ValueChanged<_RankingRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _ControlDropdown<_RankingMetric>(
              icon: Icons.leaderboard_outlined,
              value: metric,
              items: const {
                _RankingMetric.distance: 'Km',
                _RankingMetric.time: 'Thời gian',
                _RankingMetric.consistency: 'Đều đặn',
              },
              onChanged: onMetricChanged,
            ),
          ),
          const SizedBox(width: 10),
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
          if (publicCount != null) ...[
            const SizedBox(width: 8),
            _PublicCountBadge(count: publicCount!),
          ],
        ],
      ),
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
        value: value,
        borderRadius: BorderRadius.circular(16),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        dropdownColor: isLight
            ? const Color(0xfff8fbff)
            : const Color(0xff071426),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem<T>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.blueGlow),
                  const SizedBox(width: 8),
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

class _PublicCountBadge extends StatelessWidget {
  const _PublicCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blueGlow.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Text(
          '$count',
          style: const TextStyle(
            color: AppColors.blueGlow,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
      ),
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
      margin: const EdgeInsets.only(bottom: 10),
      borderRadius: 20,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (member.uid == currentUid) {
            context.go('/');
            return;
          }
          context.push('/club/${member.uid}');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 10),
              _LeaderboardAvatar(entry: member, size: 46),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _scoreLabel(entry, metric),
                style: TextStyle(
                  color: onSurface,
                  fontSize: 18,
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
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: icon == null
          ? Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            )
          : Icon(icon, color: color, size: 20),
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
