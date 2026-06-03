import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/consistency_heatmap.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(syncControllerProvider).startBackgroundSync();
    });
  }

  @override
  Widget build(BuildContext context) {
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
            child: _SyncAction(
              syncing: sync.syncing,
              synced: sync.lastSyncSucceeded,
              onPressed: ref.read(syncControllerProvider).startBackgroundSync,
            ),
          ),
        ],
      ),
      body: activities.when(
        data: (items) => _DashboardBody(activities: items),
        error: (error, stack) =>
            Center(child: Text('Không thể tải dữ liệu: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.activities});
  final List<ActivitySummary> activities;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final comparison = rollingSevenDayComparison(activities, now);
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
        const SizedBox(height: 12),
        _ShareableDashboardCard(
          title: 'RunNow 7 ngày gần nhất',
          child: _SummaryCard(comparison: comparison),
        ),
        const SizedBox(height: 20),
        _ShareableDashboardCard(
          title: 'RunNow consistency 8 tuần',
          child: ConsistencyHeatmap(activities: activities),
        ),
        const SizedBox(height: 20),
        _ShareableDashboardCard(
          title: 'RunNow km theo thời gian',
          child: TrainingVolumeChart(
            activities: activities,
            period: TrainingVolumePeriod.month,
            showControls: true,
          ),
        ),
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

class _SyncAction extends StatefulWidget {
  const _SyncAction({
    required this.syncing,
    required this.synced,
    required this.onPressed,
  });

  final bool syncing;
  final bool synced;
  final VoidCallback onPressed;

  @override
  State<_SyncAction> createState() => _SyncActionState();
}

class _SyncActionState extends State<_SyncAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _SyncAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncing != widget.syncing) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (widget.syncing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.syncing
        ? RotationTransition(turns: _controller, child: const Icon(Icons.sync))
        : Icon(widget.synced ? Icons.check : Icons.sync);
    return GlassIconButton(
      tooltip: 'Đồng bộ Strava',
      onPressed: widget.syncing ? null : widget.onPressed,
      icon: icon,
    );
  }
}

class _ShareableDashboardCard extends StatefulWidget {
  const _ShareableDashboardCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_ShareableDashboardCard> createState() =>
      _ShareableDashboardCardState();
}

class _ShareableDashboardCardState extends State<_ShareableDashboardCard> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RepaintBoundary(key: _cardKey, child: widget.child),
        Positioned(
          top: 8,
          right: 8,
          child: Builder(
            builder: (buttonContext) => _DashboardShareButton(
              sharing: _sharing,
              onPressed: () => _share(buttonContext),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _share(BuildContext buttonContext) async {
    setState(() => _sharing = true);
    try {
      await shareDashboardCard(
        cardKey: _cardKey,
        shareButtonContext: buttonContext,
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

class _DashboardShareButton extends StatelessWidget {
  const _DashboardShareButton({required this.sharing, required this.onPressed});

  final bool sharing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xbf020812),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: sharing ? null : onPressed,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: sharing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share, size: 18),
          ),
        ),
      ),
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

String _comparisonLabel(TrainingComparison comparison) {
  final ratio = comparison.distanceChangeRatio;
  if (ratio == null) return 'Chưa có quãng đường trong 7 ngày trước để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với 7 ngày trước';
}
