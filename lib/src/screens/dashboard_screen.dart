import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/sync.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/consistency_heatmap.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activitiesProvider);
    final sync = ref.watch(syncControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RunNow'),
            Text(
              'YOUR TRAINING SPACE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GlassIconButton(
              tooltip: 'Đồng bộ Strava',
              onPressed: sync.syncing
                  ? null
                  : ref.read(syncControllerProvider).startBackgroundSync,
              icon: sync.syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          ),
        ],
      ),
      body: activities.when(
        data: (items) => _DashboardBody(activities: items, sync: sync),
        error: (error, stack) =>
            Center(child: Text('Không thể tải dữ liệu: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.activities, required this.sync});
  final List<ActivitySummary> activities;
  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final comparison = rollingSevenDayComparison(activities, now);
    final distribution = distanceByActivityKind(
      activities,
      start: startOfRollingSevenDays(now),
      end: endOfToday(now),
    );
    final recent = [...activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Tổng quan',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Text(
          'Nhịp luyện tập từ dữ liệu đã đồng bộ',
          style: TextStyle(color: Colors.white60),
        ),
        if (sync.message != null) ...[
          const SizedBox(height: 8),
          Text(
            sync.message!,
            style: TextStyle(
              color: sync.lastSyncSucceeded
                  ? Theme.of(context).colorScheme.secondary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _SummaryCard(comparison: comparison),
        const SizedBox(height: 20),
        Text(
          'Phân bổ km theo thời gian',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TrainingVolumeChart(
          activities: activities,
          period: TrainingVolumePeriod.month,
          showControls: true,
        ),
        const SizedBox(height: 20),
        ConsistencyHeatmap(activities: activities),
        if (distribution.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ActivityDistribution(items: distribution),
        ],
        const SizedBox(height: 20),
        Text('Gần đây', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Text(
            'Chưa có hoạt động. Bấm đồng bộ để tải nhật ký Strava.',
            style: TextStyle(color: Colors.white60),
          )
        else
          for (var index = 0; index < recent.take(3).length; index++)
            ActivityTile(activity: recent[index], sequence: index + 1),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.comparison});
  final TrainingComparison comparison;

  @override
  Widget build(BuildContext context) {
    final summary = comparison.current;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: const LinearGradient(
        colors: [Color(0xf207172b), Color(0xdb06365c), Color(0xb3151637)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.blueGlow, size: 20),
                const SizedBox(width: 6),
                Text(
                  '7 NGÀY GẦN NHẤT',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ActivityDistribution extends StatelessWidget {
  const _ActivityDistribution({required this.items});

  final List<ActivityKindDistance> items;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(16),
    gradient: const LinearGradient(
      colors: [Color(0xe607172b), Color(0xb3062442)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PHÂN BỔ 7 NGÀY',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _activityKindLabel(item.kind),
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  formatDistance(item.distanceMeters),
                  style: const TextStyle(
                    color: AppColors.blueGlow,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

String _comparisonLabel(TrainingComparison comparison) {
  final ratio = comparison.distanceChangeRatio;
  if (ratio == null) return 'Chưa có quãng đường trong 7 ngày trước để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với 7 ngày trước';
}

String _activityKindLabel(ActivityKind kind) => switch (kind) {
  ActivityKind.run => 'Chạy bộ',
  ActivityKind.trailRun => 'Trail run',
  ActivityKind.virtualRun => 'Virtual run',
  ActivityKind.walk => 'Đi bộ',
  ActivityKind.hike => 'Hiking',
};
