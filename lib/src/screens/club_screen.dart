import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';


class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktopWeb = RunNowWebLayout.isDesktop(context);
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
          Expanded(child: _RankingTab(currentUid: _currentUid(ref))),
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

class _RankingTab extends ConsumerWidget {
  const _RankingTab({required this.currentUid});

  final String? currentUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(clubRankingMetricProvider);
    final range = ref.watch(clubRankingRangeProvider);
    // Watch CẢ 3 nguồn → chuyển metric (Km↔Bước↔chạy) TỨC THÌ, không get lại.
    // Provider keepAlive + được prefetch lúc khởi động app (xem coordinator) nên
    // mở tab Club là có sẵn, khỏi chờ round-trip. Số vẫn tươi (fetch từ server);
    // pull-to-refresh để lấy mới. Bước = bảng RIÊNG; Km = TỔNG (chạy+đi bộ) gộp.
    final runBoard = ref.watch(leaderboardEntriesProvider);
    final stepBoard = ref.watch(stepLeaderboardProvider);
    final totalBoard = ref.watch(totalKmLeaderboardProvider);
    final swimBoard = ref.watch(swimLeaderboardProvider);
    final gymBoard = ref.watch(gymLeaderboardProvider);
    final leaderboard = switch (metric) {
      ClubRankingMetric.steps => stepBoard,
      ClubRankingMetric.distance => totalBoard,
      ClubRankingMetric.swim => swimBoard,
      ClubRankingMetric.gym => gymBoard,
      _ => runBoard,
    };

    // Toggle Tổng km ↔ Bước chân giờ nằm TRONG card, ngay dưới tiêu đề BXH.
    // Card luôn render (kể cả rỗng) để toggle luôn hiện — switch lại được khi
    // bảng đang xem trống. Các metric chạy khác (pace/dài nhất/buổi…) ở dropdown.
    return leaderboard.when(
      data: (items) {
        final entries = _sortedRankingEntries(items, metric, range);
        return RefreshIndicator(
          // Get 1 lần (không live) → KÉO-để-làm-mới: nạp lại + đợi nguồn đang xem.
          onRefresh: () async {
            // Invalidate nguồn ĐỌC gốc: leaderboardEntries (chạy) + docs bước
            // (chia sẻ cho Bước & Tổng km) → cả 3 bảng tự tính lại từ server.
            ref.invalidate(leaderboardEntriesProvider);
            ref.invalidate(stepLeaderboardDocsProvider);
            ref.invalidate(leaderboardDocsProvider); // Bơi + Gym
            await ref.read(switch (metric) {
              ClubRankingMetric.steps => stepLeaderboardProvider.future,
              ClubRankingMetric.distance => totalKmLeaderboardProvider.future,
              ClubRankingMetric.swim => swimLeaderboardProvider.future,
              ClubRankingMetric.gym => gymLeaderboardProvider.future,
              _ => leaderboardEntriesProvider.future,
            });
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
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
          ),
        );
      },
      error: (error, stack) =>
          Center(child: Text('Không thể tải bảng xếp hạng: $error')),
      loading: () => const RunNowLoading(label: 'Đang tải tổng kết'),
    );
  }
}

/// Toggle NHỎ GỌN switch nhanh Tổng km ↔ Bước chân (2 BXH chính) — đặt ngay dưới
/// tiêu đề "BẢNG XẾP HẠNG". "Bước" = metric steps; còn lại (km/pace/dài nhất…) coi
/// là phía "Tổng km". Co theo nội dung (không kéo full-width) cho gọn.
class _LeaderboardTypeToggle extends ConsumerWidget {
  const _LeaderboardTypeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metric = ref.watch(clubRankingMetricProvider);
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;

    // "Tổng km" đại diện phía CHẠY (gồm pace/dài nhất/buổi… ở dropdown) → sáng khi
    // metric KHÔNG phải steps/swim/gym. Các nút còn lại sáng khi trúng đúng metric.
    Widget seg(ClubRankingMetric target, IconData icon, String label) {
      final highlighted = target == ClubRankingMetric.distance
          ? (metric != ClubRankingMetric.steps &&
                metric != ClubRankingMetric.swim &&
                metric != ClubRankingMetric.gym)
          : metric == target;
      return GestureDetector(
        onTap: metric == target
            ? null
            : () => ref.read(clubRankingMetricProvider.notifier).state = target,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: highlighted ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: highlighted ? onAccent : palette.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? onAccent : palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ClubRankingMetric.distance, Icons.directions_run_rounded, 'Km'),
          seg(ClubRankingMetric.steps, Icons.directions_walk_rounded, 'Bước'),
          seg(ClubRankingMetric.swim, Icons.pool_rounded, 'Bơi'),
          seg(ClubRankingMetric.gym, Icons.fitness_center_rounded, 'Gym'),
        ],
      ),
    );
  }
}

List<_RankingEntry> _sortedRankingEntries(
  List<LeaderboardEntry> items,
  ClubRankingMetric metric,
  ClubRankingRange range,
) {
  return items
      .where((entry) => entry.isPublic)
      .map((entry) => _RankingEntry.fromLeaderboard(entry, metric, range))
      .toList()
    ..sort((left, right) {
      final byScore = metric == ClubRankingMetric.pace
          ? left.score.compareTo(right.score)
          : right.score.compareTo(left.score);
      if (byScore != 0) return byScore;
      return right.stats.distanceMeters.compareTo(left.stats.distanceMeters);
    });
}

/// Filter của club render gộp chung trong navigation bar (cùng [GlassPanel]).
/// Tuỳ tab con đang chọn mà hiện bộ lọc phù hợp: Xếp hạng (dropdown metric +
/// range) hoặc Tổng kết (toggle Tuần/Tháng).

/// Filter của club render gộp chung trong navigation bar (cùng [GlassPanel]).
/// Chỉ còn đúng 1 tab (Xếp hạng) nên luôn hiện bộ lọc metric + khoảng thời
/// gian, không cần switch theo tab con nữa.
class ClubNavFilter extends ConsumerWidget {
  const ClubNavFilter({required this.branchActive, super.key});

  final bool branchActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!branchActive) return const SizedBox.shrink();
    return const SizedBox(height: 42, child: _RankingNavControls());
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
                ClubRankingMetric.distance: 'Tổng km',
                ClubRankingMetric.time: 'Thời gian',
                ClubRankingMetric.consistency: 'Đều',
                ClubRankingMetric.pace: 'Pace',
                ClubRankingMetric.longestRun: 'Dài nhất',
                ClubRankingMetric.activityCount: 'Buổi',
                ClubRankingMetric.steps: 'Bước chân',
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
          const SizedBox(height: 10),
          // Toggle nhỏ gọn Tổng km ↔ Bước chân, canh trái ngay dưới tiêu đề BXH.
          const _LeaderboardTypeToggle(),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'Chưa có thành viên public để xếp hạng.',
                style: TextStyle(color: palette.textMuted),
              ),
            )
          else ...[
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
        ],
      ),
    );
  }
}

/// Bục top 3: hạng nhì bên trái, hạng nhất giữa (avatar to nhất), hạng ba bên
/// phải — thay cho danh sách phẳng cũ để làm nổi bật 3 vị trí đầu. Bấm vào
/// một slot mở profile của thành viên đó (trừ khi đó là chính mình).
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
    // Bấm vào 1 slot podium đi thẳng vào profile thành viên đó — không còn
    // mở popup chúc mừng ở đây nữa (popup chúc mừng giờ tự hiện riêng cho
    // đúng người đạt hạng, xem `ref.listen` trong `_RankingTab`).
    // Bấm 1 người trên BXH → THẲNG nhật ký (list buổi chạy) của họ. Chính mình
    // → nhật ký của mình.
    void onTap(_RankingEntry entry) {
      final uid = entry.entry.uid;
      context.push(
        uid == currentUid ? '/profile/journal' : '/club/$uid/journal',
      );
    }

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
                          onTap: () => onTap(second),
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
                          onTap: () => onTap(first),
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
                          onTap: () => onTap(third),
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
                          onTap: () => onTap(second),
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
                          onTap: () => onTap(first),
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
                          onTap: () => onTap(third),
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
      ClubRankingMetric.steps => stats.steps.toDouble(),
      ClubRankingMetric.swim => stats.distanceMeters, // km bơi
      ClubRankingMetric.gym => stats.movingTimeSeconds.toDouble(), // phút gym
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
          onTap: () => context.push(
            isMe ? '/profile/journal' : '/club/${member.uid}/journal',
          ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
    ClubRankingMetric.steps =>
      '${entry.stats.steps.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')} bước',
    ClubRankingMetric.swim => formatDistance(entry.stats.distanceMeters),
    ClubRankingMetric.gym => formatDuration(entry.stats.movingTimeSeconds),
  };
}

String _rankingMetricLabel(ClubRankingMetric metric) {
  return switch (metric) {
    ClubRankingMetric.distance => 'Tổng km',
    ClubRankingMetric.time => 'Thời gian',
    ClubRankingMetric.consistency => 'Đều',
    ClubRankingMetric.pace => 'Pace',
    ClubRankingMetric.longestRun => 'Dài nhất',
    ClubRankingMetric.activityCount => 'Buổi',
    ClubRankingMetric.steps => 'Bước chân',
    ClubRankingMetric.swim => 'Bơi',
    ClubRankingMetric.gym => 'Gym',
  };
}

String _rankingRangeLabel(ClubRankingRange range) {
  return switch (range) {
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
        backgroundImage: avatarUrl == null
            ? null
            : cachedAvatarImage(context, avatarUrl, size),
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

