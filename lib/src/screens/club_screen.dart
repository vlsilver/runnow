import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';
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
          _PastPeriodSection(currentUid: currentUid),
          const SizedBox(height: 20),
          _RankingHeader(range: range),
          const SizedBox(height: 12),
          _SportTabs(
            sport: sport,
            onSelect: (option) =>
                ref.read(clubRankingSportProvider.notifier).state = option,
          ),
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
              const Expanded(child: _SectionTitle('XẾP HẠNG')),
              _RangeSwitch(
                range: range,
                onSelect: (option) =>
                    ref.read(clubRankingRangeProvider.notifier).state = option,
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

/// Tiêu đề mục: chữ in hoa đậm như "XẾP HẠNG".
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Barlow Condensed',
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    );
  }
}

class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({required this.range, required this.onSelect});

  final ClubRankingRange range;
  final ValueChanged<ClubRankingRange> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SegmentTrack(
      radius: 999,
      children: [
        for (final option in ClubRankingRange.values)
          _SegmentButton(
            selected: option == range,
            radius: 999,
            minHeight: 34,
            onTap: () => onSelect(option),
            child: Text(
              option == ClubRankingRange.currentWeek ? 'Tuần' : 'Tháng',
            ),
          ),
      ],
    );
  }
}

class _SportTabs extends StatelessWidget {
  const _SportTabs({required this.sport, required this.onSelect});

  final ClubRankingSport sport;
  final ValueChanged<ClubRankingSport> onSelect;

  @override
  Widget build(BuildContext context) {
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
                onTap: () => onSelect(option),
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
    final light = Theme.of(context).brightness == Brightness.light;
    final foreground = selected
        ? (light ? palette.accentDeep : palette.accent)
        : palette.textMuted;
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
            color: selected ? palette.tint : Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
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
                for (var index = 0; index < ranked.length; index++) ...[
                  _RankingRow(
                    member: ranked[index],
                    sport: sport,
                    isMe: ranked[index].entry.uid == currentUid,
                    gapLabel: ranked[index].entry.uid == currentUid
                        ? clubRankingGapLabel(ranked, index, sport)
                        : null,
                  ),
                  // Backend trao thẻ cho hạng ≤ 10 (rank_card.go), bằng số ở
                  // hạng 10 thì cả nhóm cùng có thẻ.
                  if (ranked[index].rank <= _cardRanks &&
                      index + 1 < ranked.length &&
                      ranked[index + 1].rank > _cardRanks)
                    const _TopTenDivider(),
                ],
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
    final light = Theme.of(context).brightness == Brightness.light;
    final medals = light ? RunNowRankColors.light : RunNowRankColors.dark;
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
                      color: rank <= medals.length
                          ? medals[rank - 1]
                          : rank <= _cardRanks
                          ? (light ? palette.accentDeep : palette.accent)
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

/// Hạng cuối còn được trao thẻ khi chốt kỳ.
const _cardRanks = 10;

class _TopTenDivider extends StatelessWidget {
  const _TopTenDivider();

  @override
  Widget build(BuildContext context) {
    final muted = context.runNowPalette.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: muted.withValues(alpha: 0.35))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Top 10 nhận thẻ khi chốt',
              style: TextStyle(
                color: muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: muted.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}

/// Kỳ và bộ môn của mục Kỳ trước, chọn riêng với bảng đang chạy.
final _pastRangeProvider = StateProvider<ClubRankingRange>(
  (ref) => ClubRankingRange.currentWeek,
);
final _pastSportProvider = StateProvider<ClubRankingSport>(
  (ref) => ClubRankingSport.run,
);

String _lowerFirst(String text) =>
    text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

/// Bảng kỳ vừa hết mà backend đã chốt, với thẻ của top 10. Thẻ úp thì chỉ chủ
/// thẻ lật được; lật rồi thì ai cũng thấy mặt trước.
class _PastPeriodSection extends ConsumerWidget {
  const _PastPeriodSection({required this.currentUid});

  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final range = ref.watch(_pastRangeProvider);
    final sport = ref.watch(_pastSportProvider);
    final period = pastRankingPeriod(DateTime.now(), range);
    final boardId = rankBoardId(period, sport);
    final board = ref.watch(rankBoardProvider(boardId));
    final label = pastRankingPeriodLabel(period);
    // Có bảng là đã chốt, kể cả khi đồng hồ máy còn trước 12:00.
    final closed = board.asData?.value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: _SectionTitle('KỲ TRƯỚC')),
                  _RangeSwitch(
                    range: range,
                    onSelect: (option) =>
                        ref.read(_pastRangeProvider.notifier).state = option,
                  ),
                ],
              ),
              Text(
                '$label · ${closed ? 'đã chốt' : 'đang chốt'}',
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SportTabs(
          sport: sport,
          onSelect: (option) =>
              ref.read(_pastSportProvider.notifier).state = option,
        ),
        const SizedBox(height: 12),
        board.when(
          data: (board) => switch (board) {
            null => _PastNotice(
              title: 'Đang chốt ${_lowerFirst(label)}',
              body: period.closing
                  ? 'Chốt lúc 12:00 hôm nay. Số liệu đồng bộ trước giờ đó '
                        'vẫn được tính.'
                  : 'Bảng chốt và thẻ của top 10 sẽ hiện ở đây.',
            ),
            RankBoard(entries: []) => _PastNotice(
              title: '$label chưa có ai trên bảng',
              body: 'Kỳ này không ai có số nên không có thẻ.',
            ),
            final board => _PastBoard(
              board: board,
              boardId: boardId,
              sport: sport,
              period: period,
              currentUid: currentUid,
            ),
          },
          error: (error, stack) => _PastNotice(
            title: 'Không tải được bảng kỳ trước',
            body: '$error',
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: RunNowLoading(label: 'Đang tải kỳ trước', compact: true),
          ),
        ),
      ],
    );
  }
}

class _PastNotice extends StatelessWidget {
  const _PastNotice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.runNowPalette.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastBoard extends ConsumerWidget {
  const _PastBoard({
    required this.board,
    required this.boardId,
    required this.sport,
    required this.period,
    required this.currentUid,
  });

  final RankBoard board;
  final String boardId;
  final ClubRankingSport sport;
  final PastRankingPeriod period;
  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final entries = board.entries;
    final leader = entries.first;
    final leaderCard = ref
        .watch(rankCardProvider((uid: leader.uid, boardId: boardId)))
        .asData
        ?.value;
    final mine = entries.indexWhere((entry) => entry.uid == currentUid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PastFan(
          entries: entries.take(3).toList(),
          boardId: boardId,
          currentUid: currentUid,
        ),
        const SizedBox(height: 10),
        Text(
          leader.displayName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Text(
          [
            rankTitle(leader.rank),
            clubRankingValueLabel(leader.score, sport),
            if (leaderCard != null)
              leaderCard.revealed ? 'thẻ đã lật' : 'thẻ còn úp',
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _PastTopCardsScreen(
                  entries: entries,
                  boardId: boardId,
                  title: pastRankingPeriodLabel(period),
                  sport: sport,
                  currentUid: currentUid,
                ),
              ),
            ),
            child: Text('Xem cả top ${entries.length} thẻ'),
          ),
        ),
        if (mine >= 0)
          _MyPastCardRow(
            entries: entries,
            index: mine,
            boardId: boardId,
            sport: sport,
            month: period.range == ClubRankingRange.currentMonth,
          ),
      ],
    );
  }
}

/// Ba thẻ đầu xếp quạt: hạng 2 bên trái, hạng 1 giữa, hạng 3 bên phải.
class _PastFan extends StatelessWidget {
  const _PastFan({
    required this.entries,
    required this.boardId,
    required this.currentUid,
  });

  final List<RankBoardEntry> entries;
  final String boardId;
  final String? currentUid;

  static const _centerWidth = 132.0;
  static const _sideWidth = 108.0;

  Widget _tile(RankBoardEntry entry, double width) => _PastCardTile(
    entry: entry,
    boardId: boardId,
    width: width,
    mine: entry.uid == currentUid,
  );

  @override
  Widget build(BuildContext context) {
    final height =
        _centerWidth * achievementCardSize.height / achievementCardSize.width;
    return SizedBox(
      height: height + 16,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (entries.length > 1)
            Transform.translate(
              offset: const Offset(-92, 22),
              child: Transform.rotate(
                angle: -0.14,
                child: _tile(entries[1], _sideWidth),
              ),
            ),
          if (entries.length > 2)
            Transform.translate(
              offset: const Offset(92, 22),
              child: Transform.rotate(
                angle: 0.14,
                child: _tile(entries[2], _sideWidth),
              ),
            ),
          _tile(entries[0], _centerWidth),
        ],
      ),
    );
  }
}

/// Một thẻ của bảng đã chốt: mặt trước khi chủ đã lật, mặt sau khi còn úp.
class _PastCardTile extends ConsumerWidget {
  const _PastCardTile({
    required this.entry,
    required this.boardId,
    required this.width,
    required this.mine,
  });

  final RankBoardEntry entry;
  final String boardId;
  final double width;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref
        .watch(rankCardProvider((uid: entry.uid, boardId: boardId)))
        .asData
        ?.value;
    final size = Size(
      width,
      width * achievementCardSize.height / achievementCardSize.width,
    );
    if (card == null) return SizedBox.fromSize(size: size);
    return Semantics(
      button: true,
      label: card.revealed
          ? 'Thẻ ${rankTitle(card.rank)} của ${entry.displayName}'
          : 'Thẻ úp của ${entry.displayName}',
      child: GestureDetector(
        onTap: () => _openPastCard(context, card, mine: mine),
        child: GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(
            data: rankCardData(card),
            back: !card.revealed,
          ),
        ),
      ),
    );
  }
}

void _openPastCard(BuildContext context, RankCard card, {required bool mine}) {
  if (card.revealed) {
    showRankCardViewer(context, card, canShare: mine);
  } else if (mine) {
    _flipRankCard(context, card);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Thẻ còn úp, chờ ${card.displayName} lật.')),
    );
  }
}

/// Thẻ đang gửi lệnh lật; chạm lần hai trong lúc chờ thì bỏ qua, vì rules từ
/// chối lần ghi thứ hai và sẽ báo lỗi dù thẻ đã lật.
final _flipping = <String>{};

/// Ghi revealedAt rồi mở thẻ ở mặt úp để chủ tự lật trong màn xem.
Future<void> _flipRankCard(BuildContext context, RankCard card) async {
  if (!_flipping.add(card.boardId)) return;
  try {
    await revealRankCard(card.uid, card.boardId);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không lật được thẻ: $error')));
    }
    return;
  } finally {
    _flipping.remove(card.boardId);
  }
  if (!context.mounted) return;
  await showRankCardViewer(context, card, faceDown: true, canShare: true);
}

/// "thiếu 1,2 km để lên hạng 3" hay, khi dẫn đầu, "hơn hạng 2 tới 4,5 km".
String? _pastGapLabel(
  List<RankBoardEntry> entries,
  int index,
  ClubRankingSport sport,
) {
  final me = entries[index];
  for (var i = index - 1; i >= 0; i--) {
    if (entries[i].score > me.score) {
      final gap = clubRankingValueLabel(entries[i].score - me.score, sport);
      return 'thiếu $gap để lên hạng ${entries[i].rank}';
    }
  }
  for (var i = index + 1; i < entries.length; i++) {
    if (entries[i].score < me.score) {
      final gap = clubRankingValueLabel(me.score - entries[i].score, sport);
      return 'hơn hạng ${entries[i].rank} tới $gap';
    }
  }
  return null;
}

class _MyPastCardRow extends ConsumerWidget {
  const _MyPastCardRow({
    required this.entries,
    required this.index,
    required this.boardId,
    required this.sport,
    required this.month,
  });

  final List<RankBoardEntry> entries;
  final int index;
  final String boardId;
  final ClubRankingSport sport;
  final bool month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final me = entries[index];
    final card = ref
        .watch(rankCardProvider((uid: me.uid, boardId: boardId)))
        .asData
        ?.value;
    final period = month ? 'tháng' : 'tuần';
    final gap = _pastGapLabel(entries, index, sport);
    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.rank == 1
                      ? 'Bạn là quán quân $period'
                      : 'Bạn về hạng ${me.rank}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [clubRankingValueLabel(me.score, sport), ?gap].join(' · '),
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
                if (card != null && !card.revealed)
                  Text(
                    'Thẻ của bạn đang úp',
                    style: TextStyle(color: palette.accentDeep, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (card != null)
            card.revealed
                ? OutlinedButton(
                    onPressed: () =>
                        showRankCardViewer(context, card, canShare: true),
                    child: const Text('Xem thẻ'),
                  )
                : FilledButton(
                    onPressed: () => _flipRankCard(context, card),
                    child: const Text('Lật thẻ'),
                  ),
        ],
      ),
    );
  }
}

/// Cả top 10 của một bảng đã chốt.
class _PastTopCardsScreen extends StatelessWidget {
  const _PastTopCardsScreen({
    required this.entries,
    required this.boardId,
    required this.title,
    required this.sport,
    required this.currentUid,
  });

  final List<RankBoardEntry> entries;
  final String boardId;
  final String title;
  final ClubRankingSport sport;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final muted = context.runNowPalette.textMuted;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const gutter = 16.0;
          final width = (constraints.maxWidth - gutter * 3) / 2;
          return ListView(
            padding: const EdgeInsets.all(gutter),
            children: [
              Wrap(
                spacing: gutter,
                runSpacing: 20,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          _PastCardTile(
                            entry: entry,
                            boardId: boardId,
                            width: width,
                            mine: entry.uid == currentUid,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '#${entry.rank} ${entry.displayName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            clubRankingValueLabel(entry.score, sport),
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
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
