import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.activities});
  final List<ActivitySummary> activities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final comparison = rollingSevenDayComparison(activities, now);
    final dailyDistances = rollingSevenDayDistances(activities, now);
    final monthSummary = currentMonthSummary(activities, now);
    final goals = ref.watch(trainingGoalsProvider);
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
          child: _SummaryCard(
            comparison: comparison,
            dailyDistances: dailyDistances,
          ),
        ),
        const SizedBox(height: 20),
        _ShareableDashboardCard(
          title: 'RunNow mục tiêu luyện tập',
          child: goals.when(
            data: (item) => _TrainingGoalCard(
              goals: item,
              weekDistanceMeters: comparison.current.distanceMeters,
              monthDistanceMeters: monthSummary.distanceMeters,
              onEdit: () => _editTrainingGoals(context, ref, item),
            ),
            error: (error, stack) => _TrainingGoalCard(
              goals: TrainingGoals.empty,
              weekDistanceMeters: comparison.current.distanceMeters,
              monthDistanceMeters: monthSummary.distanceMeters,
              onEdit: () =>
                  _editTrainingGoals(context, ref, TrainingGoals.empty),
            ),
            loading: () => _TrainingGoalCard(
              goals: TrainingGoals.empty,
              weekDistanceMeters: comparison.current.distanceMeters,
              monthDistanceMeters: monthSummary.distanceMeters,
              onEdit: null,
            ),
          ),
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

Future<void> _editTrainingGoals(
  BuildContext context,
  WidgetRef ref,
  TrainingGoals goals,
) async {
  final weeklyController = TextEditingController(
    text: goals.weeklyDistanceMeters > 0
        ? (goals.weeklyDistanceMeters / 1000).toStringAsFixed(1)
        : '',
  );
  final monthlyController = TextEditingController(
    text: goals.monthlyDistanceMeters > 0
        ? (goals.monthlyDistanceMeters / 1000).toStringAsFixed(1)
        : '',
  );
  final result = await showDialog<TrainingGoals>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.black,
      title: const Text('Mục tiêu luyện tập'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: weeklyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Mục tiêu tuần',
              suffixText: 'km',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: monthlyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Mục tiêu tháng',
              suffixText: 'km',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            TrainingGoals(
              weeklyDistanceMeters: _parseGoalKm(weeklyController.text) * 1000,
              monthlyDistanceMeters:
                  _parseGoalKm(monthlyController.text) * 1000,
            ),
          ),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  weeklyController.dispose();
  monthlyController.dispose();
  if (result == null) return;
  await ref.read(trainingGoalRepositoryProvider).saveGoals(result);
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

class _TrainingGoalCard extends StatelessWidget {
  const _TrainingGoalCard({
    required this.goals,
    required this.weekDistanceMeters,
    required this.monthDistanceMeters,
    required this.onEdit,
  });

  final TrainingGoals goals;
  final double weekDistanceMeters;
  final double monthDistanceMeters;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: const LinearGradient(
        colors: [Color(0xf207172b), Color(0xcc151637), Color(0xa8073260)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag, color: AppColors.red, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'MỤC TIÊU',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Sửa mục tiêu',
                icon: const Icon(Icons.tune, size: 18),
                color: AppColors.blueGlow,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GoalProgressRow(
            label: 'Tuần này',
            currentMeters: weekDistanceMeters,
            goalMeters: goals.weeklyDistanceMeters,
            color: AppColors.red,
          ),
          const SizedBox(height: 14),
          _GoalProgressRow(
            label: 'Tháng này',
            currentMeters: monthDistanceMeters,
            goalMeters: goals.monthlyDistanceMeters,
            color: AppColors.blueGlow,
          ),
        ],
      ),
    );
  }
}

class _GoalProgressRow extends StatelessWidget {
  const _GoalProgressRow({
    required this.label,
    required this.currentMeters,
    required this.goalMeters,
    required this.color,
  });

  final String label;
  final double currentMeters;
  final double goalMeters;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hasGoal = goalMeters > 0;
    final progress = hasGoal ? (currentMeters / goalMeters).clamp(0, 1) : 0.0;
    final percent = hasGoal ? (progress * 100).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              hasGoal
                  ? '${formatDistance(currentMeters)} / ${formatDistance(goalMeters)}'
                  : '${formatDistance(currentMeters)} / chưa đặt',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 14,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0x2600d9ff)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress.toDouble(),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0.55), color],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasGoal ? '$percent% hoàn thành' : 'Bấm icon để đặt mục tiêu',
          style: TextStyle(
            color: hasGoal ? color : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.comparison, required this.dailyDistances});
  final TrainingComparison comparison;
  final List<DailyDistance> dailyDistances;

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
            _SevenDayPulseChart(days: dailyDistances),
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

class _SevenDayPulseChart extends StatelessWidget {
  const _SevenDayPulseChart({required this.days});

  final List<DailyDistance> days;

  @override
  Widget build(BuildContext context) {
    final maxDistance = days.fold<double>(
      0,
      (max, day) => day.distanceMeters > max ? day.distanceMeters : max,
    );
    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _SevenDayBar(
                  day: day,
                  maxDistance: maxDistance,
                  active: day.distanceMeters > 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SevenDayBar extends StatelessWidget {
  const _SevenDayBar({
    required this.day,
    required this.maxDistance,
    required this.active,
  });

  final DailyDistance day;
  final double maxDistance;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ratio = maxDistance <= 0 ? 0.04 : day.distanceMeters / maxDistance;
    final label = _weekdayLabel(day.date);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          day.distanceMeters > 0 ? _compactDistance(day.distanceMeters) : '-',
          style: TextStyle(
            color: active ? Colors.white : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: ratio.clamp(0.06, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: active
                        ? const [AppColors.red, AppColors.blueGlow]
                        : const [Color(0x33ffffff), Color(0x1affffff)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  boxShadow: active
                      ? const [
                          BoxShadow(
                            color: Color(0x6600d9ff),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: const SizedBox(width: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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

String _compactDistance(double meters) =>
    '${(meters / 1000).toStringAsFixed(1)}k';

String _weekdayLabel(DateTime date) => switch (date.weekday) {
  DateTime.monday => 'T2',
  DateTime.tuesday => 'T3',
  DateTime.wednesday => 'T4',
  DateTime.thursday => 'T5',
  DateTime.friday => 'T6',
  DateTime.saturday => 'T7',
  DateTime.sunday => 'CN',
  _ => '',
};

String _comparisonLabel(TrainingComparison comparison) {
  final ratio = comparison.distanceChangeRatio;
  if (ratio == null) return 'Chưa có quãng đường trong 7 ngày trước để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với 7 ngày trước';
}

double _parseGoalKm(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isNegative) return 0;
  return parsed;
}
