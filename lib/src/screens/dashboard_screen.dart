import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/strava_client.dart';
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
      if (!StravaClient.instance.isSignedIn) return;
      ref.read(syncControllerProvider).startBackgroundSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final profileState = ref.watch(userProfileProvider);
    final profileLoading = profileState.maybeWhen(
      loading: () => true,
      orElse: () => false,
    );
    final stravaConnected = ref.watch(stravaConnectionProvider);
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
          if (stravaConnected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SyncAction(
                syncing: sync.syncing,
                synced: sync.lastSyncSucceeded,
                onPressed: () => ref
                    .read(syncControllerProvider)
                    .startBackgroundSync(force: true),
              ),
            ),
        ],
      ),
      body: profileLoading
          ? const Center(child: CircularProgressIndicator())
          : stravaConnected
          ? ref
                .watch(activitiesProvider)
                .when(
                  data: (items) => _DashboardBody(activities: items),
                  error: (error, stack) =>
                      Center(child: Text('Không thể tải dữ liệu: $error')),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Tổng quan',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _ConnectStravaCard(
                  loading: ref.watch(stravaAuthProvider).loading,
                  errorMessage: ref.watch(stravaAuthProvider).errorMessage,
                  onConnect: ref.read(stravaAuthProvider).connect,
                ),
              ],
            ),
    );
  }
}

enum _WeekViewMode { rollingSevenDays, currentWeek }

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({required this.activities});
  final List<ActivitySummary> activities;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  _WeekViewMode _weekViewMode = _WeekViewMode.rollingSevenDays;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final comparison = switch (_weekViewMode) {
      _WeekViewMode.rollingSevenDays => rollingSevenDayComparison(
        widget.activities,
        now,
      ),
      _WeekViewMode.currentWeek => currentWeekComparison(
        widget.activities,
        now,
      ),
    };
    final dailyDistances = switch (_weekViewMode) {
      _WeekViewMode.rollingSevenDays => rollingSevenDayDistances(
        widget.activities,
        now,
      ),
      _WeekViewMode.currentWeek => currentWeekDistances(widget.activities, now),
    };
    final monthSummary = currentMonthSummary(widget.activities, now);
    final goals = ref.watch(trainingGoalsProvider);
    final header = Text(
      'Tổng quan',
      style: Theme.of(
        context,
      ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final recent = [...widget.activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        header,
        const SizedBox(height: 12),
        _ShareableDashboardCard(
          title: 'RunNow tiến độ tuần',
          builder: (sharing) => goals.when(
            data: (item) => _SummaryCard(
              comparison: comparison,
              dailyDistances: dailyDistances,
              goals: item,
              monthDistanceMeters: monthSummary.distanceMeters,
              mode: _weekViewMode,
              onModeChanged: (mode) => setState(() => _weekViewMode = mode),
              onEditGoals: () => _editTrainingGoals(context, ref, item),
              showControls: !sharing,
            ),
            error: (error, stack) => _SummaryCard(
              comparison: comparison,
              dailyDistances: dailyDistances,
              goals: TrainingGoals.empty,
              monthDistanceMeters: monthSummary.distanceMeters,
              mode: _weekViewMode,
              onModeChanged: (mode) => setState(() => _weekViewMode = mode),
              onEditGoals: () =>
                  _editTrainingGoals(context, ref, TrainingGoals.empty),
              showControls: !sharing,
            ),
            loading: () => _SummaryCard(
              comparison: comparison,
              dailyDistances: dailyDistances,
              goals: TrainingGoals.empty,
              monthDistanceMeters: monthSummary.distanceMeters,
              mode: _weekViewMode,
              onModeChanged: (mode) => setState(() => _weekViewMode = mode),
              onEditGoals: null,
              showControls: !sharing,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _ShareableDashboardCard(
          title: 'RunNow consistency 8 tuần',
          builder: (_) => ConsistencyHeatmap(activities: widget.activities),
        ),
        const SizedBox(height: 20),
        _ShareableDashboardCard(
          title: 'RunNow km theo thời gian',
          builder: (sharing) => TrainingVolumeChart(
            activities: widget.activities,
            period: TrainingVolumePeriod.month,
            showControls: !sharing,
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
  final result = await showModalBottomSheet<TrainingGoals>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        gradient: const LinearGradient(
          colors: [Color(0xf207172b), Color(0xe0062442), Color(0xcc151637)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.flag, color: AppColors.red),
                const SizedBox(width: 8),
                Text(
                  'Mục tiêu luyện tập',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GoalInputField(
              controller: weeklyController,
              label: 'Tuần',
              hint: 'VD: 15',
            ),
            const SizedBox(height: 10),
            _GoalInputField(
              controller: monthlyController,
              label: 'Tháng',
              hint: 'VD: 60',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      TrainingGoals(
                        weeklyDistanceMeters:
                            _parseGoalKm(weeklyController.text) * 1000,
                        monthlyDistanceMeters:
                            _parseGoalKm(monthlyController.text) * 1000,
                      ),
                    ),
                    child: const Text('Lưu'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  weeklyController.dispose();
  monthlyController.dispose();
  if (result == null) return;
  await ref.read(trainingGoalRepositoryProvider).saveGoals(result);
}

class _GoalInputField extends StatelessWidget {
  const _GoalInputField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Mục tiêu $label',
        hintText: hint,
        suffixText: 'km',
        filled: true,
        fillColor: const Color(0x52020812),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white30),
        suffixStyle: const TextStyle(color: AppColors.blueGlow),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x3300d9ff)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blueGlow),
        ),
      ),
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
  const _ShareableDashboardCard({required this.title, required this.builder});

  final String title;
  final Widget Function(bool sharing) builder;

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
      child: RepaintBoundary(key: _cardKey, child: widget.builder(_sharing)),
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

class _ConnectStravaCard extends StatelessWidget {
  const _ConnectStravaCard({
    required this.loading,
    required this.errorMessage,
    required this.onConnect,
  });

  final bool loading;
  final String? errorMessage;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: const LinearGradient(
        colors: [Color(0xf207172b), Color(0xd4062442), Color(0xb3151637)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.link, color: AppColors.blueGlow),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'KẾT NỐI STRAVA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Đồng bộ hoạt động chạy vào tài khoản Google hiện tại để xem tiến độ, nhật ký và bảng xếp hạng.',
            style: TextStyle(color: Colors.white70),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(errorMessage!, style: const TextStyle(color: AppColors.red)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: loading ? null : onConnect,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(loading ? 'Đang kết nối...' : 'Kết nối Strava'),
            ),
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
  const _SummaryCard({
    required this.comparison,
    required this.dailyDistances,
    required this.goals,
    required this.monthDistanceMeters,
    required this.mode,
    required this.onModeChanged,
    required this.onEditGoals,
    required this.showControls,
  });

  final TrainingComparison comparison;
  final List<DailyDistance> dailyDistances;
  final TrainingGoals goals;
  final double monthDistanceMeters;
  final _WeekViewMode mode;
  final ValueChanged<_WeekViewMode> onModeChanged;
  final VoidCallback? onEditGoals;
  final bool showControls;

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
                const Expanded(
                  child: Text(
                    'TIẾN ĐỘ TUẦN',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (showControls)
                  IconButton(
                    onPressed: onEditGoals,
                    tooltip: 'Sửa mục tiêu',
                    icon: const Icon(Icons.tune, size: 18),
                    color: AppColors.blueGlow,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (showControls) ...[
              const SizedBox(height: 10),
              _WeekViewToggle(value: mode, onChanged: onModeChanged),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                _weekModeLabel(mode),
                style: const TextStyle(
                  color: AppColors.blueGlow,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
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
              _comparisonLabel(comparison, mode),
              style: const TextStyle(
                color: AppColors.blueGlow,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _GoalProgressRow(
              label: _weekGoalLabel(mode),
              currentMeters: summary.distanceMeters,
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
      ),
    );
  }
}

class _WeekViewToggle extends StatelessWidget {
  const _WeekViewToggle({required this.value, required this.onChanged});

  final _WeekViewMode value;
  final ValueChanged<_WeekViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x52020812),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _WeekViewOption(
              label: '7 ngày gần nhất',
              selected: value == _WeekViewMode.rollingSevenDays,
              onTap: () => onChanged(_WeekViewMode.rollingSevenDays),
            ),
            _WeekViewOption(
              label: 'Tuần này',
              selected: value == _WeekViewMode.currentWeek,
              onTap: () => onChanged(_WeekViewMode.currentWeek),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekViewOption extends StatelessWidget {
  const _WeekViewOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.red : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
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

String _weekGoalLabel(_WeekViewMode mode) => switch (mode) {
  _WeekViewMode.rollingSevenDays => 'Mục tiêu tuần',
  _WeekViewMode.currentWeek => 'Tuần này',
};

String _weekModeLabel(_WeekViewMode mode) => switch (mode) {
  _WeekViewMode.rollingSevenDays => '7 ngày gần nhất',
  _WeekViewMode.currentWeek => 'Tuần này',
};

String _comparisonLabel(TrainingComparison comparison, _WeekViewMode mode) {
  final ratio = comparison.distanceChangeRatio;
  final previousLabel = switch (mode) {
    _WeekViewMode.rollingSevenDays => '7 ngày trước',
    _WeekViewMode.currentWeek => 'tuần trước',
  };
  if (ratio == null) return 'Chưa có quãng đường $previousLabel để so sánh';
  final percent = (ratio * 100).round();
  final prefix = percent > 0 ? '+' : '';
  return '$prefix$percent% quãng đường so với $previousLabel';
}

double _parseGoalKm(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed.isNaN || parsed.isNegative) return 0;
  return parsed;
}
