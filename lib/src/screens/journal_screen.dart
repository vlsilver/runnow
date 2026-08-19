import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/health_sync.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/screens/step_day_detail_screen.dart';
import 'package:myrun/src/steps_format.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNearBottom);
    // Trả về ngay nếu đã có cache từ lần vào trước trong phiên này (xem
    // JournalController) — chỉ lần đầu tiên mới thật sự chờ Firestore.
    Future.microtask(() => ref.read(journalControllerProvider).ensureLoaded());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNearBottom)
      ..dispose();
    super.dispose();
  }

  void _loadMoreWhenNearBottom() {
    final position = _scrollController.position;
    if (position.extentAfter < 700) {
      ref.read(journalControllerProvider).loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nhắc kết nối Strava đã có sẵn ở Cài đặt — không lặp lại banner này ở
    // đây nữa, tránh watch thêm profile/Strava-status chỉ để hiện 1 card.
    final journal = ref.watch(journalControllerProvider);
    // Số bước theo ngày (Apple Health, chỉ iOS) — GỘP THẲNG vào timeline nhật ký
    // như một loại thẻ khác, không tách tab. Lỗi/đang tải → coi như rỗng để không
    // phá danh sách buổi chạy (vd rules stepDays chưa deploy).
    final stepDays =
        ref.watch(myStepDaysProvider).asData?.value ?? const <StepDay>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Nhật ký')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(syncControllerProvider).startBackgroundSync(force: true);
          await ref.read(journalControllerProvider).loadFirstPage();
        },
        child: journal.loadingInitial
            ? const _JournalLoadingList()
            : _JournalPagedList(
                controller: _scrollController,
                rows: _mergeJournalRows(
                  items: journal.items,
                  stepDays: stepDays,
                  hasMore: journal.hasMore,
                ),
                error: journal.error,
                hasMore: journal.hasMore,
                loadingMore: journal.loadingMore,
                onRetry: () =>
                    ref.read(journalControllerProvider).loadNextPage(),
                onStepTap: _openStepDetail,
              ),
      ),
    );
  }

  /// Bấm một ngày bước → mở TRANG chi tiết (tổng + mục tiêu + chỉ số + biểu đồ
  /// theo giờ). Truyền các ngày gần đây để trang tính so-sánh 7 ngày.
  void _openStepDetail(StepDay day) {
    HealthSyncController controller;
    try {
      controller = ref.read(healthSyncProvider);
    } catch (_) {
      return; // demo mode / không có Health — im lặng, không mở gì.
    }
    final recent =
        ref.read(myStepDaysProvider).asData?.value ?? const <StepDay>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StepDayDetailScreen(
          controller: controller,
          day: day,
          recentDays: recent,
        ),
      ),
    );
  }
}

/// Một dòng trong timeline nhật ký: hoặc buổi CHẠY, hoặc TỔNG BƯỚC của một ngày.
sealed class _JournalRow {
  DateTime get sortAt;
}

class _ActivityJournalRow extends _JournalRow {
  _ActivityJournalRow(this.entry);
  final JournalActivityEntry entry;
  @override
  DateTime get sortAt => entry.activity.startedAt;
}

class _StepJournalRow extends _JournalRow {
  _StepJournalRow(this.day);
  final StepDay day;
  @override
  DateTime get sortAt => _stepSortAt(day.date);
}

/// Mốc xếp của thẻ bước = CUỐI ngày (local) → tổng-bước-ngày nổi lên đầu ngày đó
/// (phía trên các buổi chạy cùng ngày) trong danh sách giảm dần theo thời gian.
DateTime _stepSortAt(String key) {
  final d = DateTime.tryParse(key);
  if (d == null) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime(d.year, d.month, d.day, 23, 59, 59);
}

/// Trộn buổi chạy + thẻ bước thành 1 timeline giảm dần. Khi CÒN trang chưa tải,
/// chỉ chèn thẻ bước có ngày ≥ buổi chạy cũ nhất đang hiện — buổi cũ hơn lộ dần
/// khi cuộn, tránh reflow (thẻ bước cũ bị đẩy khi trang sau về). Tải hết → chèn hết.
List<_JournalRow> _mergeJournalRows({
  required List<JournalActivityEntry> items,
  required List<StepDay> stepDays,
  required bool hasMore,
}) {
  String? cutoff;
  if (hasMore && items.isNotEmpty) {
    final oldest = items.last.activity.startedAt.toLocal();
    cutoff =
        '${oldest.year.toString().padLeft(4, '0')}-'
        '${oldest.month.toString().padLeft(2, '0')}-'
        '${oldest.day.toString().padLeft(2, '0')}';
  }
  final steps = cutoff == null
      ? stepDays
      : [
          for (final d in stepDays)
            if (d.date.compareTo(cutoff) >= 0) d,
        ];
  return <_JournalRow>[
    ...items.map(_ActivityJournalRow.new),
    ...steps.map(_StepJournalRow.new),
  ]..sort((a, b) => b.sortAt.compareTo(a.sortAt));
}

/// Thẻ TỔNG BƯỚC của một ngày trong timeline nhật ký — có rail mốc thời gian
/// (khớp [ActivityTile]) với chấm hình người đi bộ để phân biệt với buổi chạy.
class _StepTimelineRow extends StatelessWidget {
  const _StepTimelineRow({required this.day, required this.onTap});

  final StepDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    final date = DateTime.tryParse(day.date);
    final pct = ((day.steps / stepDailyGoal) * 100).round();
    final reached = day.steps >= stepDailyGoal;
    // Km THẬT (Walking + Running Distance) nếu có; không thì ước lượng từ bước.
    final kmLabel = day.distanceMeters > 0
        ? stepKmFromMeters(day.distanceMeters)
        : '≈ ${stepDistanceKm(day.steps)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Column(
              children: [
                Text(
                  date == null ? '--' : date.day.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  date == null ? '' : stepMonthShort(date.month),
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.48),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.32),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.directions_walk_rounded,
                    size: 13,
                    color: onAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassPanel(
              borderRadius: 8,
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.directions_walk_rounded,
                              size: 16,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Bước chân',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: palette.ink,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              stepThousands(day.steps),
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: palette.ink,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'bước',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (day.steps / stepDailyGoal).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: palette.accent.withValues(
                              alpha: 0.12,
                            ),
                            valueColor: AlwaysStoppedAnimation(palette.accent),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (reached) ...[
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: palette.accent,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              reached ? 'Đạt mục tiêu' : '$pct% mục tiêu',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: reached
                                    ? palette.accent
                                    : palette.textMuted,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              kmLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Timeline gộp buổi chạy + thẻ bước. Một cột duy nhất cho mọi bề rộng; màn rộng
/// canh giữa (max 640) thay vì lưới 2 cột — thẻ chạy/thẻ bước cao thấp khác nhau.
class _JournalPagedList extends StatelessWidget {
  const _JournalPagedList({
    required this.controller,
    required this.rows,
    required this.error,
    required this.hasMore,
    required this.loadingMore,
    required this.onRetry,
    required this.onStepTap,
  });

  final ScrollController controller;
  final List<_JournalRow> rows;
  final Object? error;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onRetry;
  final ValueChanged<StepDay> onStepTap;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                error == null
                    ? 'Chưa có hoạt động.'
                    : 'Không thể tải nhật ký: $error',
              ),
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth > 640
            ? (constraints.maxWidth - 640) / 2
            : 12.0;
        return ListView.builder(
          controller: controller,
          padding: EdgeInsets.fromLTRB(side, 16, side, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index >= rows.length) {
              return _JournalPaginationFooter(
                error: error,
                hasMore: hasMore,
                loadingMore: loadingMore,
                onRetry: onRetry,
              );
            }
            final row = rows[index];
            final Widget child = switch (row) {
              _ActivityJournalRow(:final entry) => ActivityTile(
                activity: entry.activity,
                preferredStravaActivityId: entry.preferredStravaActivityId,
              ),
              _StepJournalRow(:final day) => _StepTimelineRow(
                day: day,
                onTap: () => onStepTap(day),
              ),
            };
            return RepaintBoundary(child: child);
          },
        );
      },
    );
  }
}

class _JournalPaginationFooter extends StatelessWidget {
  const _JournalPaginationFooter({
    required this.error,
    required this.hasMore,
    required this.loadingMore,
    required this.onRetry,
  });

  final Object? error;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: OutlinedButton(
          onPressed: onRetry,
          child: const Text('Tải tiếp'),
        ),
      );
    }
    if (!hasMore) {
      return const SizedBox(height: 28);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
      child: Center(
        child: loadingMore
            ? const RunNowLoading(compact: true, label: 'Đang tải thêm')
            : const SizedBox(height: 42),
      ),
    );
  }
}

class _JournalLoadingList extends StatelessWidget {
  const _JournalLoadingList();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: [
        Row(
          children: [
            const RunNowLoading(compact: true, label: 'Đang tải nhật ký'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Đang tải 30 hoạt động gần nhất',
                style: TextStyle(
                  color: onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < 5; index++)
          _JournalSkeletonTile(accent: palette.accent, index: index),
      ],
    );
  }
}

class _JournalSkeletonTile extends StatelessWidget {
  const _JournalSkeletonTile({required this.accent, required this.index});

  final Color accent;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final faded = onSurface.withValues(alpha: 0.12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.glassStart.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonLine(width: 140 + index * 8, color: faded),
                        const SizedBox(height: 10),
                        _SkeletonLine(width: 110, color: faded),
                      ],
                    ),
                  ),
                  _SkeletonLine(width: 58, height: 20, color: faded),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _SkeletonMetric(color: faded)),
                  const SizedBox(width: 10),
                  Expanded(child: _SkeletonMetric(color: faded)),
                  const SizedBox(width: 10),
                  Expanded(child: _SkeletonMetric(color: faded)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonMetric extends StatelessWidget {
  const _SkeletonMetric({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const SizedBox(height: 58),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 12,
  });

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
