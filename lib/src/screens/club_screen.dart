import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Câu lạc bộ')),
      body: _RankingTab(currentUid: _currentUid(ref)),
    );
  }

  String? _currentUid(WidgetRef ref) {
    return ref
        .watch(firebaseUserProvider)
        .maybeWhen(data: (user) => user?.uid, orElse: () => null);
  }
}

/// Nguồn của từng bảng. Chạy/Đi bộ và Bước chân dùng chung một lần đọc
/// stepLeaderboardEntries; Đạp xe đọc leaderboardEntries.
FutureProvider<List<LeaderboardEntry>> _boardFor(ClubRankingSport sport) {
  return switch (sport) {
    ClubRankingSport.run => totalKmLeaderboardProvider,
    ClubRankingSport.steps => stepLeaderboardProvider,
    ClubRankingSport.bike => bikeLeaderboardProvider,
  };
}

class _RankingTab extends ConsumerWidget {
  const _RankingTab({required this.currentUid});

  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = ref.watch(clubRankingSportProvider);
    final range = ref.watch(clubRankingRangeProvider);
    // Provider keepAlive + prefetch lúc mở app (xem coordinator) nên đổi bộ môn
    // là có số ngay. Header và tab nằm ngoài `when` để vẫn đổi được khi bảng
    // đang tải hay lỗi.
    final board = ref.watch(_boardFor(sport));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(stepLeaderboardDocsProvider);
        ref.invalidate(leaderboardDocsProvider);
        await ref.read(_boardFor(sport).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _RankingHeader(range: range),
          const SizedBox(height: 12),
          _SportTabs(sport: sport),
          const SizedBox(height: 12),
          board.when(
            data: (items) {
              final ranked = rankClubMembers(items, sport, range);
              return _ShareableClubCard(
                title:
                    '3i bảng xếp hạng ${_sportLabel(sport)} ${_rangeLabel(range)}',
                child: _RankingList(
                  ranked: ranked,
                  sport: sport,
                  range: range,
                  currentUid: currentUid,
                ),
              );
            },
            error: (error, stack) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Không thể tải bảng xếp hạng: $error',
                textAlign: TextAlign.center,
              ),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: RunNowLoading(
                label: 'Đang tải bảng xếp hạng',
                compact: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Text(
              _notRankedHint(sport),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.runNowPalette.textMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiêu đề, nút Tuần/Tháng cùng một hàng; thời gian còn lại của kỳ ở dòng dưới.
class _RankingHeader extends ConsumerWidget {
  const _RankingHeader({required this.range});

  final ClubRankingRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'XẾP HẠNG',
                  style: TextStyle(
                    fontFamily: 'Barlow Condensed',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              _SegmentTrack(
                radius: 999,
                children: [
                  for (final option in ClubRankingRange.values)
                    _SegmentButton(
                      selected: option == range,
                      radius: 999,
                      minHeight: 34,
                      onTap: () =>
                          ref.read(clubRankingRangeProvider.notifier).state =
                              option,
                      child: Text(
                        option == ClubRankingRange.currentWeek
                            ? 'Tuần'
                            : 'Tháng',
                      ),
                    ),
                ],
              ),
            ],
          ),
          Text(
            clubRankingTimeLeftLabel(DateTime.now(), range),
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SportTabs extends ConsumerWidget {
  const _SportTabs({required this.sport});

  final ClubRankingSport sport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SegmentTrack(
        radius: 16,
        children: [
          for (final option in ClubRankingSport.values)
            Expanded(
              child: _SegmentButton(
                selected: option == sport,
                radius: 12,
                minHeight: 44,
                onTap: () =>
                    ref.read(clubRankingSportProvider.notifier).state = option,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SportIcon(sport: option, size: 16),
                      const SizedBox(width: 6),
                      Text(_sportLabel(option)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentTrack extends StatelessWidget {
  const _SegmentTrack({required this.radius, required this.children});

  final double radius;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.selected,
    required this.radius,
    required this.minHeight,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final double radius;
  final double minHeight;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final light = Theme.of(context).brightness == Brightness.light;
    final foreground = selected ? onSurface : palette.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: minHeight, minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Nền tối thì thẻ được chọn sáng hơn rãnh, nền sáng thì là mặt
            // giấy trắng nổi trên rãnh xám.
            color: selected
                ? (light
                      ? palette.glassStart
                      : onSurface.withValues(alpha: 0.14))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: selected && light
                ? const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _SportIcon extends StatelessWidget {
  const _SportIcon({required this.sport, required this.size});

  final ClubRankingSport sport;
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (sport) {
      ClubRankingSport.run => Icon(Icons.directions_run_rounded, size: size),
      ClubRankingSport.bike => Icon(Icons.directions_bike_rounded, size: size),
      // Material không có icon dấu chân; dùng hình người đi bộ thì lẫn với
      // tab Chạy/Đi bộ.
      ClubRankingSport.steps => CustomPaint(
        size: Size.square(size),
        painter: _FootprintsPainter(IconTheme.of(context).color!),
      ),
    };
  }
}

class _FootprintsPainter extends CustomPainter {
  const _FootprintsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.scale(size.width / 24);
    void sole(Offset center, double tilt) {
      canvas
        ..save()
        ..translate(center.dx, center.dy)
        ..rotate(tilt)
        ..drawOval(
          Rect.fromCenter(center: Offset.zero, width: 6, height: 10),
          paint,
        )
        ..restore();
    }

    sole(const Offset(8, 12), -0.21);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(9.4, 19.6), width: 4.4, height: 3.6),
      paint,
    );
    sole(const Offset(16.4, 7), 0.21);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(15.2, 14.6),
        width: 4.4,
        height: 3.6,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_FootprintsPainter oldDelegate) =>
      oldDelegate.color != color;
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

class _RankingList extends StatelessWidget {
  const _RankingList({
    required this.ranked,
    required this.sport,
    required this.range,
    required this.currentUid,
  });

  final List<ClubRankedMember> ranked;
  final ClubRankingSport sport;
  final ClubRankingRange range;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ranked.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: Center(
                child: Text(
                  _emptyText(sport, range),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textMuted),
                ),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < ranked.length; index++)
                  _RankingRow(
                    member: ranked[index],
                    sport: sport,
                    isMe: ranked[index].entry.uid == currentUid,
                    gapLabel: ranked[index].entry.uid == currentUid
                        ? clubRankingGapLabel(ranked, index, sport)
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.member,
    required this.sport,
    required this.isMe,
    required this.gapLabel,
  });

  final ClubRankedMember member;
  final ClubRankingSport sport;
  final bool isMe;
  final String? gapLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rankColors = Theme.of(context).brightness == Brightness.dark
        ? RunNowRankColors.dark
        : RunNowRankColors.light;
    final rank = member.rank;
    final (value, unit) = _splitValueLabel(
      clubRankingValueLabel(member.score, sport),
    );
    final entry = member.entry;
    return Container(
      margin: isMe ? const EdgeInsets.symmetric(horizontal: 6) : null,
      decoration: isMe
          ? BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () =>
            context.push(isMe ? '/journal' : '/club/${entry.uid}/journal'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMe ? 8 : 14),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: rank <= rankColors.length
                          ? rankColors[rank - 1]
                          : onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _FlatMemberAvatar(member: entry, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 6),
                              _MiniChip(label: 'Bạn', color: palette.secondary),
                            ],
                          ],
                        ),
                        if (gapLabel != null)
                          Text(
                            gapLabel!,
                            style: TextStyle(
                              color: palette.accentDeep,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: TextStyle(
                          color: onSurface,
                          fontFamily: 'Barlow Condensed',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (unit.isNotEmpty)
                        TextSpan(
                          text: ' $unit',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
      backgroundImage: avatarUrl == null
          ? null
          : cachedAvatarImage(context, avatarUrl, size),
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

/// Màu phẳng ổn định theo uid cho avatar chưa có ảnh.
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

/// "19.41 km" -> ("19.41", "km") để số đậm, đơn vị nhạt.
(String, String) _splitValueLabel(String label) {
  final index = label.lastIndexOf(' ');
  if (index <= 0) return (label, '');
  return (label.substring(0, index), label.substring(index + 1));
}

String _sportLabel(ClubRankingSport sport) {
  return switch (sport) {
    ClubRankingSport.run => 'Chạy/Đi bộ',
    ClubRankingSport.steps => 'Bước chân',
    ClubRankingSport.bike => 'Đạp xe',
  };
}

String _rangeLabel(ClubRankingRange range) {
  return switch (range) {
    ClubRankingRange.currentWeek => 'tuần này',
    ClubRankingRange.currentMonth => 'tháng này',
  };
}

String _emptyText(ClubRankingSport sport, ClubRankingRange range) {
  final period = range == ClubRankingRange.currentWeek
      ? 'Tuần này'
      : 'Tháng này';
  return switch (sport) {
    ClubRankingSport.run => '$period chưa ai có km chạy hay đi bộ.',
    ClubRankingSport.steps => '$period chưa ai có bước chân.',
    ClubRankingSport.bike => '$period chưa ai đạp xe.',
  };
}

String _notRankedHint(ClubRankingSport sport) {
  return switch (sport) {
    ClubRankingSport.run => 'Chưa có km nào trong kỳ thì chưa vào bảng.',
    ClubRankingSport.steps => 'Chưa có bước nào trong kỳ thì chưa vào bảng.',
    ClubRankingSport.bike => 'Chưa đạp km nào trong kỳ thì chưa vào bảng.',
  };
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
