import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/strava_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/activity_records_card.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/consistency_heatmap.dart';
import 'package:myrun/src/widgets/discipline_card.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
import 'package:myrun/src/widgets/personal_power_card.dart';
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RunNow'),
            Text(
              'YOUR TRAINING SPACE',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.52),
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

/// Các card ở Tổng quan có filter (đưa lên navigation bar).
enum DashboardCard { week, power, volume }

/// Card đang ở vùng trên viewport (theo scroll). Null = đang ở card không có
/// filter -> nav ẩn filter đi.
final dashboardActiveCardProvider = StateProvider<DashboardCard?>(
  (ref) => null,
);
final dashboardWeekModeProvider = StateProvider<_WeekViewMode>(
  (ref) => _WeekViewMode.currentWeek,
);
final dashboardPowerRangeProvider = StateProvider<PersonalPowerRange>(
  (ref) => PersonalPowerRange.rollingSevenDays,
);
final dashboardVolumePeriodProvider = StateProvider<TrainingVolumePeriod>(
  (ref) => TrainingVolumePeriod.month,
);
final dashboardVolumeModeProvider = StateProvider<TrainingVolumeChartMode>(
  (ref) => TrainingVolumeChartMode.bar,
);

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({required this.activities});
  final List<ActivitySummary> activities;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  final _scrollKey = GlobalKey();
  final _weekKey = GlobalKey();
  final _powerKey = GlobalKey();
  final _volumeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveCard());
  }

  /// Xác định card filter nào đang chiếm vùng trên cùng của viewport để nav bar
  /// hiện đúng filter của card đó (null nếu đang là card không có filter).
  void _updateActiveCard() {
    if (!mounted) return;
    final listBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    // Lấy đường ngang ~25% từ trên viewport làm mốc "đang xem"; card filter nào
    // phủ qua mốc này thì nav hiện filter của card đó.
    final threshold =
        listBox.localToGlobal(Offset.zero).dy + listBox.size.height * 0.25;
    DashboardCard? active;
    for (final section in <(GlobalKey, DashboardCard)>[
      (_weekKey, DashboardCard.week),
      (_powerKey, DashboardCard.power),
      (_volumeKey, DashboardCard.volume),
    ]) {
      final box = section.$1.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= threshold && top + box.size.height > threshold) {
        active = section.$2;
        break;
      }
    }
    if (ref.read(dashboardActiveCardProvider) != active) {
      ref.read(dashboardActiveCardProvider.notifier).state = active;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 900;
    final now = DateTime.now();
    final weekMode = ref.watch(dashboardWeekModeProvider);
    final comparison = switch (weekMode) {
      _WeekViewMode.rollingSevenDays => rollingSevenDayComparison(
        widget.activities,
        now,
      ),
      _WeekViewMode.currentWeek => currentWeekComparison(
        widget.activities,
        now,
      ),
    };
    final dailyDistances = switch (weekMode) {
      _WeekViewMode.rollingSevenDays => rollingSevenDayDistances(
        widget.activities,
        now,
      ),
      _WeekViewMode.currentWeek => currentWeekDistances(widget.activities, now),
    };
    final monthSummary = currentMonthSummary(widget.activities, now);
    final discipline = personalDisciplineStats(widget.activities, now);
    final goals = ref.watch(trainingGoalsProvider);
    final header = Text(
      'Tổng quan',
      style: Theme.of(
        context,
      ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final recent = [...widget.activities]
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));

    Widget summaryCard({required bool showControls}) => goals.when(
      data: (item) => _SummaryCard(
        comparison: comparison,
        dailyDistances: dailyDistances,
        goals: item,
        monthDistanceMeters: monthSummary.distanceMeters,
        mode: weekMode,
        onModeChanged: (mode) =>
            ref.read(dashboardWeekModeProvider.notifier).state = mode,
        onEditGoals: () => _editTrainingGoals(context, ref, item),
        showControls: showControls,
      ),
      error: (error, stack) => _SummaryCard(
        comparison: comparison,
        dailyDistances: dailyDistances,
        goals: TrainingGoals.empty,
        monthDistanceMeters: monthSummary.distanceMeters,
        mode: weekMode,
        onModeChanged: (mode) =>
            ref.read(dashboardWeekModeProvider.notifier).state = mode,
        onEditGoals: () =>
            _editTrainingGoals(context, ref, TrainingGoals.empty),
        showControls: showControls,
      ),
      loading: () => _SummaryCard(
        comparison: comparison,
        dailyDistances: dailyDistances,
        goals: TrainingGoals.empty,
        monthDistanceMeters: monthSummary.distanceMeters,
        mode: weekMode,
        onModeChanged: (mode) =>
            ref.read(dashboardWeekModeProvider.notifier).state = mode,
        onEditGoals: null,
        showControls: showControls,
      ),
    );

    Widget powerCard({required bool showControls}) => PersonalPowerCard(
      activities: widget.activities,
      showControls: showControls,
      range: ref.watch(dashboardPowerRangeProvider),
    );

    Widget volumeCard({required bool showControls}) => TrainingVolumeChart(
      activities: widget.activities,
      period: ref.watch(dashboardVolumePeriodProvider),
      mode: ref.watch(dashboardVolumeModeProvider),
      showControls: showControls,
    );

    final recentCard = _RecentActivitiesCard(recent: recent);

    if (wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(dashboardActiveCardProvider) != null) {
          ref.read(dashboardActiveCardProvider.notifier).state = null;
        }
      });
      final columns = screenWidth >= 1320 ? 3 : 2;
      final webColumns = columns == 3
          ? [
              _DashboardWebColumn(
                children: [
                  _ShareableDashboardCard(
                    title: 'RunNow tiến độ tuần',
                    builder: (_) => summaryCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow kỷ luật cá nhân',
                    builder: (_) => DisciplineCard(stats: discipline),
                  ),
                ],
              ),
              _DashboardWebColumn(
                children: [
                  _ShareableDashboardCard(
                    title: 'RunNow personal power',
                    builder: (_) => powerCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow consistency 8 tuần',
                    builder: (_) =>
                        ConsistencyHeatmap(activities: widget.activities),
                  ),
                ],
              ),
              _DashboardWebColumn(
                children: [
                  _ShareableDashboardCard(
                    title: 'RunNow km theo thời gian',
                    builder: (_) => volumeCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow kỷ lục cá nhân',
                    builder: (_) => ActivityRecordsCard(
                      title: 'KỶ LỤC CÁ NHÂN',
                      entries: [
                        for (final activity in widget.activities)
                          ActivityRecordEntry(activity: activity),
                      ],
                    ),
                  ),
                  recentCard,
                ],
              ),
            ]
          : [
              _DashboardWebColumn(
                children: [
                  _ShareableDashboardCard(
                    title: 'RunNow tiến độ tuần',
                    builder: (_) => summaryCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow personal power',
                    builder: (_) => powerCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow kỷ luật cá nhân',
                    builder: (_) => DisciplineCard(stats: discipline),
                  ),
                ],
              ),
              _DashboardWebColumn(
                children: [
                  _ShareableDashboardCard(
                    title: 'RunNow consistency 8 tuần',
                    builder: (_) =>
                        ConsistencyHeatmap(activities: widget.activities),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow km theo thời gian',
                    builder: (_) => volumeCard(showControls: true),
                  ),
                  _ShareableDashboardCard(
                    title: 'RunNow kỷ lục cá nhân',
                    builder: (_) => ActivityRecordsCard(
                      title: 'KỶ LỤC CÁ NHÂN',
                      entries: [
                        for (final activity in widget.activities)
                          ActivityRecordEntry(activity: activity),
                      ],
                    ),
                  ),
                  recentCard,
                ],
              ),
            ];
      return _DashboardWebGrid(columns: webColumns);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _updateActiveCard(),
        );
        return false;
      },
      child: ListView(
        key: _scrollKey,
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 12),
          KeyedSubtree(
            key: _weekKey,
            child: _ShareableDashboardCard(
              title: 'RunNow tiến độ tuần',
              builder: (sharing) => summaryCard(showControls: false),
            ),
          ),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _powerKey,
            child: _ShareableDashboardCard(
              title: 'RunNow personal power',
              builder: (sharing) => powerCard(showControls: false),
            ),
          ),
          const SizedBox(height: 20),
          _ShareableDashboardCard(
            title: 'RunNow consistency 8 tuần',
            builder: (_) => ConsistencyHeatmap(activities: widget.activities),
          ),
          const SizedBox(height: 20),
          _ShareableDashboardCard(
            title: 'RunNow kỷ luật cá nhân',
            builder: (_) => DisciplineCard(stats: discipline),
          ),
          const SizedBox(height: 20),
          _ShareableDashboardCard(
            title: 'RunNow kỷ lục cá nhân',
            builder: (_) => ActivityRecordsCard(
              title: 'KỶ LỤC CÁ NHÂN',
              entries: [
                for (final activity in widget.activities)
                  ActivityRecordEntry(activity: activity),
              ],
            ),
          ),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: _volumeKey,
            child: _ShareableDashboardCard(
              title: 'RunNow km theo thời gian',
              builder: (sharing) => volumeCard(showControls: false),
            ),
          ),
          const SizedBox(height: 20),
          recentCard,
        ],
      ),
    );
  }
}

class _DashboardWebGrid extends StatelessWidget {
  const _DashboardWebGrid({required this.columns});

  final List<Widget> columns;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < columns.length; index++) ...[
            Expanded(child: columns[index]),
            if (index != columns.length - 1) const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}

class _DashboardWebColumn extends StatelessWidget {
  const _DashboardWebColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _RecentActivitiesCard extends StatelessWidget {
  const _RecentActivitiesCard({required this.recent});

  final List<ActivitySummary> recent;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      borderRadius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GẦN ĐÂY',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.62),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text(
              'Chưa có hoạt động. Bấm đồng bộ để tải nhật ký Strava.',
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            )
          else
            for (var index = 0; index < recent.take(4).length; index++)
              ActivityTile(activity: recent[index], sequence: index + 1),
        ],
      ),
    );
  }
}

/// Filter của Tổng quan render gộp trong navigation bar, tự đổi theo card đang
/// được scroll tới ([dashboardActiveCardProvider]).
class DashboardNavFilter extends ConsumerWidget {
  const DashboardNavFilter({
    required this.branchActive,
    this.showFallback = false,
    super.key,
  });

  final bool branchActive;
  final bool showFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCard = ref.watch(dashboardActiveCardProvider);
    final card = branchActive
        ? activeCard ?? (showFallback ? DashboardCard.week : null)
        : null;
    final Widget child = switch (card) {
      DashboardCard.week => const _WeekModeNavControl(),
      DashboardCard.power => const _PowerRangeNavControl(),
      DashboardCard.volume => const _VolumeNavControl(),
      null => const SizedBox(width: double.infinity),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _WeekModeNavControl extends ConsumerWidget {
  const _WeekModeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: NavPillToggle<_WeekViewMode>(
        value: ref.watch(dashboardWeekModeProvider),
        items: const {
          _WeekViewMode.currentWeek: 'Tuần này',
          _WeekViewMode.rollingSevenDays: '7 ngày',
        },
        onChanged: (value) =>
            ref.read(dashboardWeekModeProvider.notifier).state = value,
      ),
    );
  }
}

class _PowerRangeNavControl extends ConsumerWidget {
  const _PowerRangeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: NavPillToggle<PersonalPowerRange>(
        value: ref.watch(dashboardPowerRangeProvider),
        items: const {
          PersonalPowerRange.currentWeek: 'Tuần',
          PersonalPowerRange.rollingSevenDays: '7 ngày',
          PersonalPowerRange.currentMonth: 'Tháng',
        },
        onChanged: (value) =>
            ref.read(dashboardPowerRangeProvider.notifier).state = value,
      ),
    );
  }
}

class _VolumeNavControl extends ConsumerWidget {
  const _VolumeNavControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavFilterShell(
      child: Row(
        children: [
          Expanded(
            child: NavDropdown<TrainingVolumeChartMode>(
              icon: Icons.show_chart_rounded,
              value: ref.watch(dashboardVolumeModeProvider),
              items: const {
                TrainingVolumeChartMode.bar: 'Cột',
                TrainingVolumeChartMode.line: 'Line',
              },
              onChanged: (value) =>
                  ref.read(dashboardVolumeModeProvider.notifier).state = value,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NavDropdown<TrainingVolumePeriod>(
              icon: Icons.date_range_outlined,
              value: ref.watch(dashboardVolumePeriodProvider),
              items: const {
                TrainingVolumePeriod.month: 'Tháng',
                TrainingVolumePeriod.quarter: 'Quý',
                TrainingVolumePeriod.year: 'Năm',
              },
              onChanged: (value) =>
                  ref.read(dashboardVolumePeriodProvider.notifier).state =
                      value,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _editTrainingGoals(
  BuildContext context,
  WidgetRef ref,
  TrainingGoals goals,
) async {
  final result = await showModalBottomSheet<TrainingGoals>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TrainingGoalsSheet(goals: goals),
  );
  if (result == null) return;
  await ref.read(trainingGoalRepositoryProvider).saveGoals(result);
}

class _TrainingGoalsSheet extends StatefulWidget {
  const _TrainingGoalsSheet({required this.goals});

  final TrainingGoals goals;

  @override
  State<_TrainingGoalsSheet> createState() => _TrainingGoalsSheetState();
}

class _TrainingGoalsSheetState extends State<_TrainingGoalsSheet> {
  late final TextEditingController _weeklyController;
  late final TextEditingController _monthlyController;

  @override
  void initState() {
    super.initState();
    _weeklyController = TextEditingController(
      text: widget.goals.weeklyDistanceMeters > 0
          ? (widget.goals.weeklyDistanceMeters / 1000).toStringAsFixed(1)
          : '',
    );
    _monthlyController = TextEditingController(
      text: widget.goals.monthlyDistanceMeters > 0
          ? (widget.goals.monthlyDistanceMeters / 1000).toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        gradient: LinearGradient(
          colors: isLight
              ? const [Color(0xffe2e6ed), Color(0xffd2d9e2)]
              : const [Color(0xf207172b), Color(0xe0062442), Color(0xcc151637)],
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
                  color: onSurface.withValues(alpha: 0.24),
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
                    color: onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GoalInputField(
              controller: _weeklyController,
              label: 'Tuần',
              hint: 'VD: 15',
            ),
            const SizedBox(height: 10),
            _GoalInputField(
              controller: _monthlyController,
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
                            _parseGoalKm(_weeklyController.text) * 1000,
                        monthlyDistanceMeters:
                            _parseGoalKm(_monthlyController.text) * 1000,
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
    );
  }
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Mục tiêu $label',
        hintText: hint,
        suffixText: 'km',
        filled: true,
        fillColor: isLight ? const Color(0xffd8dee6) : const Color(0x52020812),
        labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.64)),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.34)),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd3dae3)]
            : const [Color(0xf207172b), Color(0xd4062442), Color(0xb3151637)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: AppColors.blueGlow),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'KẾT NỐI STRAVA',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Đồng bộ hoạt động chạy vào tài khoản Google hiện tại để xem tiến độ, nhật ký và bảng xếp hạng.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.68)),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              hasGoal
                  ? '${formatDistance(currentMeters)} / ${formatDistance(goalMeters)}'
                  : '${formatDistance(currentMeters)} / chưa đặt',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.64),
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
                ColoredBox(color: AppColors.blueGlow.withValues(alpha: 0.14)),
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
            color: hasGoal ? color : onSurface.withValues(alpha: 0.36),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        colors: isLight
            ? const [Color(0xffe2e6ed), Color(0xffd1d8e1), Color(0xffdde3ea)]
            : const [Color(0xf207172b), Color(0xdb06365c), Color(0xb3151637)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: onSurface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.blueGlow, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'TIẾN ĐỘ TUẦN',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.64),
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
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _Metric(
                  label: 'Quãng đường',
                  value: formatDistance(summary.distanceMeters),
                  color: AppColors.blueGlow,
                ),
                _Metric(
                  label: 'Thời gian',
                  value: formatDuration(summary.movingTimeSeconds),
                  color: Colors.white,
                ),
                _Metric(
                  label: 'Số buổi',
                  value: '${summary.activityCount}',
                  color: AppColors.amber,
                ),
                _Metric(
                  label: 'Pace TB',
                  value: formatPace(summary.paceSecondsPerKm),
                  color: AppColors.red,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight ? const Color(0x1408172b) : const Color(0x52020812),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
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
              color: selected ? Colors.white : onSurface.withValues(alpha: 0.6),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          day.distanceMeters > 0 ? _compactDistance(day.distanceMeters) : '-',
          style: TextStyle(
            color: active ? onSurface : onSurface.withValues(alpha: 0.35),
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
                        : [
                            onSurface.withValues(alpha: 0.12),
                            onSurface.withValues(alpha: 0.06),
                          ],
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
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.52),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withValues(alpha: 0.58)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isLight
                    ? Theme.of(context).colorScheme.onSurface
                    : color,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
