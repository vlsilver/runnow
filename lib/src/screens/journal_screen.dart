import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
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
                items: journal.items,
                error: journal.error,
                hasMore: journal.hasMore,
                loadingMore: journal.loadingMore,
                onRetry: () =>
                    ref.read(journalControllerProvider).loadNextPage(),
              ),
      ),
    );
  }
}

class _JournalPagedList extends StatelessWidget {
  const _JournalPagedList({
    required this.controller,
    required this.items,
    required this.error,
    required this.hasMore,
    required this.loadingMore,
    required this.onRetry,
  });

  final ScrollController controller;
  final List<JournalActivityEntry> items;
  final Object? error;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
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
        if (constraints.maxWidth >= 920) {
          return GridView.builder(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 620,
              mainAxisExtent: 210,
              crossAxisSpacing: 18,
              mainAxisSpacing: 4,
            ),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return _JournalPaginationFooter(
                  error: error,
                  hasMore: hasMore,
                  loadingMore: loadingMore,
                  onRetry: onRetry,
                );
              }
              return RepaintBoundary(
                child: ActivityTile(
                  activity: items[index].activity,
                  preferredStravaActivityId:
                      items[index].preferredStravaActivityId,
                ),
              );
            },
          );
        }
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.symmetric(vertical: 16),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return _JournalPaginationFooter(
                error: error,
                hasMore: hasMore,
                loadingMore: loadingMore,
                onRetry: onRetry,
              );
            }
            return RepaintBoundary(
              child: ActivityTile(
                activity: items[index].activity,
                preferredStravaActivityId:
                    items[index].preferredStravaActivityId,
              ),
            );
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
