import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/nav_filter.dart';

class RunContractCreateScreen extends ConsumerStatefulWidget {
  const RunContractCreateScreen({this.initialDraft, super.key});

  final RunContractDraft? initialDraft;

  @override
  ConsumerState<RunContractCreateScreen> createState() =>
      _RunContractCreateScreenState();
}

class _RunContractCreateScreenState
    extends ConsumerState<RunContractCreateScreen> {
  late RunContractDraft _draft;
  final _titleController = TextEditingController();
  var _step = 0;
  bool _working = false;
  String? _error;
  RunContractPreview? _preview;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? RunContractDraft.weekly10k();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(runContractAnalyticsProvider)
            .log('contract_create_started')
            .ignore();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _defaultTitle(RunContractDraft draft) {
    final period = switch (draft.period) {
      RunContractPeriodType.weekly => 'tuần này',
      RunContractPeriodType.today => 'hôm nay',
      RunContractPeriodType.tomorrow => 'ngày mai',
      RunContractPeriodType.custom => 'theo lịch',
    };
    return switch (draft.metric) {
      RunContractMetric.distance =>
        'Kèo ${draft.targetValue.toStringAsFixed(draft.targetValue % 1 == 0 ? 0 : 1)}km $period',
      RunContractMetric.longestRun =>
        'Kèo chạy dài ${draft.targetValue.toStringAsFixed(draft.targetValue % 1 == 0 ? 0 : 1)}km $period',
      RunContractMetric.activityCount =>
        'Kèo ${draft.targetValue.toInt()} buổi $period',
      RunContractMetric.activeDays =>
        'Kèo ${draft.targetValue.toInt()} ngày active $period',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chốt kèo'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: switch (_step) {
          0 => _templates(),
          1 => _visibility(),
          _ => _confirmation(),
        },
      ),
    );
  }

  Widget _templates() => ListView(
    key: const ValueKey('templates'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
    children: [
      Text(
        'Bạn muốn chốt kèo gì?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 14),
      _TemplateTile(
        icon: Icons.route_rounded,
        title: '10km tuần này',
        subtitle: 'Tính từ Thứ Hai 00:00',
        onTap: () => _select(RunContractDraft.weekly10k()),
      ),
      _TemplateTile(
        icon: Icons.repeat_rounded,
        title: '3 buổi tuần này',
        subtitle: 'Mỗi Strava Run hợp lệ tính là một buổi',
        onTap: () => _select(
          RunContractDraft.weekly10k().copyWith(
            template: RunContractTemplate.weekly3Runs,
            metric: RunContractMetric.activityCount,
            targetValue: 3,
          ),
        ),
      ),
      _TemplateTile(
        icon: Icons.straighten_rounded,
        title: 'Chạy dài 5km tuần này',
        subtitle: 'Một buổi chạy đủ xa là được cứu',
        onTap: () => _select(
          RunContractDraft.weekly10k().copyWith(
            template: RunContractTemplate.custom,
            metric: RunContractMetric.longestRun,
            targetValue: 5,
          ),
        ),
      ),
      _TemplateTile(
        icon: Icons.today_rounded,
        title: '2km hôm nay',
        subtitle: 'Deadline 23:59 hôm nay (giờ máy)',
        onTap: _selectToday,
      ),
      _TemplateTile(
        icon: Icons.tune_rounded,
        title: 'Tự tạo',
        subtitle: 'Km, số buổi, ngày active hoặc chạy dài nhất',
        onTap: _showCustom,
      ),
    ],
  );

  Widget _visibility() => ListView(
    key: const ValueKey('visibility'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
    children: [
      Text(
        'Đặt tên kèo',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _titleController,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Tên kèo',
          hintText: 'VD: Kèo 10km cuối tuần',
          helperText: 'Ngắn gọn 5–10 từ',
          counterText: '',
        ),
      ),
      const SizedBox(height: 22),
      Text(
        'Ai thấy kèo này?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      RadioGroup<RunContractVisibility>(
        groupValue: _draft.visibility,
        onChanged: (value) {
          if (value != null) {
            setState(() => _draft = _draft.copyWith(visibility: value));
          }
        },
        child: Column(
          children: [
            RadioListTile<RunContractVisibility>(
              value: RunContractVisibility.club,
              title: const Text('Public trong Club'),
              subtitle: const Text(
                'Thành viên thấy mục tiêu, tiến độ và trạng thái. Không chia sẻ live location.',
              ),
            ),
            RadioListTile<RunContractVisibility>(
              value: RunContractVisibility.private,
              title: const Text('Chỉ mình tôi'),
              subtitle: const Text('Kèo không xuất hiện trong Club.'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Quay lại'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _prepareConfirmation,
              child: const Text('Tiếp tục'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _confirmation() {
    final period = contractPeriodForDraft(_draft, DateTime.now());
    return ListView(
      key: const ValueKey('confirmation'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        Text('Xác nhận kèo', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 14),
        GlassPanel(
          borderRadius: 0,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_titleController.text.trim().isNotEmpty)
                _ConfirmRow('Tên kèo', _titleController.text.trim()),
              _ConfirmRow('Mục tiêu', _targetLabel()),
              _ConfirmRow(
                'Tính từ',
                DateFormat('dd/MM · HH:mm').format(period.startAt),
              ),
              _ConfirmRow(
                'Deadline',
                DateFormat('dd/MM · HH:mm').format(
                  period.endAtExclusive.subtract(const Duration(seconds: 1)),
                ),
              ),
              _ConfirmRow(
                'Hiển thị',
                _draft.visibility == RunContractVisibility.club
                    ? 'Public trong Club'
                    : 'Chỉ mình tôi',
              ),
              _ConfirmRow('Nguồn', 'Strava Run · không tính manual'),
              if ((_preview?.progress.value ?? 0) > 0)
                _ConfirmRow(
                  'Đã được tính',
                  _previewLabel(_preview!.progress.value),
                  highlight: true,
                ),
              if (_preview?.hardTarget == true)
                const _ConfirmRow(
                  'Lưu ý',
                  'Mục tiêu cao hơn 150% trung bình 4 tuần gần nhất.',
                  highlight: true,
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _working ? null : () => setState(() => _step = 1),
                child: const Text('Quay lại'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _working ? null : _create,
                child: _working
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Chốt kèo'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _selectToday() async {
    var period = RunContractPeriodType.today;
    if (isLateToday(DateTime.now())) {
      final tomorrow = await _showLateTodayDialog();
      if (tomorrow == null) return;
      if (tomorrow) period = RunContractPeriodType.tomorrow;
    }
    _select(
      RunContractDraft.weekly10k().copyWith(
        template: RunContractTemplate.today2k,
        targetValue: 2,
        period: period,
      ),
    );
  }

  void _select(RunContractDraft draft) {
    ref
        .read(runContractAnalyticsProvider)
        .log('contract_template_selected', draft: draft)
        .ignore();
    // Gợi ý tên kèo ngắn; người dùng có thể sửa ở bước sau.
    if (_titleController.text.trim().isEmpty) {
      _titleController.text = _defaultTitle(draft);
    }
    setState(() {
      _draft = draft;
      _step = 1;
      _error = null;
    });
  }

  Future<void> _showCustom() async {
    var metric = RunContractMetric.distance;
    var period = RunContractPeriodType.weekly;
    var target = _defaultTargetFor(metric);
    DateTime? customStart;
    DateTime? customEnd;
    final draft = await showModalBottomSheet<RunContractDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final palette = context.runNowPalette;
          final periodLabel = switch (period) {
            RunContractPeriodType.today => 'hôm nay',
            RunContractPeriodType.custom => 'khoảng đã chọn',
            _ => 'tuần này',
          };
          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              10,
              18,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tự tạo kèo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Chọn chỉ số, khung thời gian và mục tiêu cần đạt.',
                  style: TextStyle(color: palette.textMuted, height: 1.4),
                ),
                const SizedBox(height: 18),
                const _SheetLabel('Chỉ số'),
                const SizedBox(height: 8),
                NavPillToggle<RunContractMetric>(
                  value: metric,
                  items: {
                    for (final value in RunContractMetric.values)
                      value: runContractMetricLabel(value),
                  },
                  onChanged: (value) => setSheetState(() {
                    metric = value;
                    target = _defaultTargetFor(value);
                  }),
                ),
                const SizedBox(height: 16),
                const _SheetLabel('Khung thời gian'),
                const SizedBox(height: 8),
                NavPillToggle<RunContractPeriodType>(
                  value: period,
                  items: const {
                    RunContractPeriodType.today: 'Hôm nay',
                    RunContractPeriodType.weekly: 'Tuần này',
                    RunContractPeriodType.custom: 'Tùy chỉnh',
                  },
                  onChanged: (value) => setSheetState(() {
                    period = value;
                    if (value == RunContractPeriodType.custom) {
                      final today = _today();
                      customStart ??= today;
                      customEnd ??= today.add(const Duration(days: 7));
                    }
                  }),
                ),
                if (period == RunContractPeriodType.custom) ...[
                  const SizedBox(height: 10),
                  _DateTimeTile(
                    label: 'Ngày bắt đầu',
                    value: customStart,
                    onTap: () async {
                      final picked = await _pickDate(
                        initial: customStart ?? _today(),
                        firstDate: _today(),
                      );
                      if (picked == null) return;
                      setSheetState(() {
                        customStart = picked;
                        if (customEnd == null || !customEnd!.isAfter(picked)) {
                          customEnd = picked.add(const Duration(days: 1));
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  _DateTimeTile(
                    label: 'Ngày kết thúc',
                    // customEnd là mốc loại trừ (00:00 hôm sau) nên hiển thị lùi
                    // 1 ngày để đúng ngày kết thúc người dùng đã chọn.
                    value: customEnd?.subtract(const Duration(days: 1)),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final start = customStart ?? _today();
                      final lastDay = customEnd == null
                          ? start
                          : customEnd!.subtract(const Duration(days: 1));
                      final picked = await _pickDate(
                        initial: lastDay,
                        firstDate: start,
                      );
                      if (picked == null) return;
                      final end = picked.add(const Duration(days: 1));
                      if (!end.isAfter(start)) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Ngày kết thúc phải từ ngày bắt đầu trở đi.',
                            ),
                          ),
                        );
                        return;
                      }
                      setSheetState(() => customEnd = end);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                const _SheetLabel('Mục tiêu'),
                const SizedBox(height: 8),
                _GoalStepper(
                  value: target,
                  unit: _metricUnit(metric),
                  onChanged: (value) => setSheetState(() => target = value),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final quick in _quickTargets(metric))
                      _QuickTargetChip(
                        label: _quickTargetLabel(metric, quick),
                        selected: target == quick,
                        onTap: () => setSheetState(() => target = quick),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _GoalSummary(
                  text: metric == RunContractMetric.longestRun
                      ? 'Chạy đủ ${_quickTargetLabel(metric, target)} trong '
                            '1 lần chạy để được cứu'
                      : 'Chạy đủ ${_quickTargetLabel(metric, target)} trong '
                            '$periodLabel để được cứu',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      RunContractDraft(
                        template: RunContractTemplate.custom,
                        metric: metric,
                        targetValue: target,
                        period: period,
                        visibility: RunContractVisibility.club,
                        customStart: period == RunContractPeriodType.custom
                            ? customStart
                            : null,
                        customEnd: period == RunContractPeriodType.custom
                            ? customEnd
                            : null,
                      ),
                    ),
                    child: const Text('Tiếp tục'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (draft == null) return;
    final validation = draft.validate();
    if (validation != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(validation)));
      }
      return;
    }
    if (draft.period == RunContractPeriodType.today &&
        isLateToday(DateTime.now())) {
      final tomorrow = await _showLateTodayDialog();
      if (tomorrow == null) return;
      _select(
        tomorrow
            ? draft.copyWith(period: RunContractPeriodType.tomorrow)
            : draft,
      );
      return;
    }
    _select(draft);
  }

  Future<bool?> _showLateTodayDialog() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hôm nay không còn nhiều thời gian'),
      content: const Text(
        'Bạn vẫn có thể chốt hôm nay, nhưng chốt ngày mai sẽ hợp lý hơn.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vẫn chốt hôm nay'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Chốt kèo ngày mai'),
        ),
      ],
    ),
  );

  /// Hôm nay lúc 00:00 giờ máy.
  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Chỉ chọn ngày (00:00). [firstDate] chặn không cho chọn quá khứ.
  Future<DateTime?> _pickDate({
    required DateTime initial,
    required DateTime firstDate,
  }) async {
    final floor = DateTime(firstDate.year, firstDate.month, firstDate.day);
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(floor) ? floor : initial,
      firstDate: floor,
      lastDate: DateTime(floor.year + 1, 12, 31),
    );
    if (date == null) return null;
    return DateTime(date.year, date.month, date.day);
  }

  Future<void> _prepareConfirmation() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      ref
          .read(runContractAnalyticsProvider)
          .log('contract_visibility_selected', draft: _draft)
          .ignore();
      final preview = await ref
          .read(runContractControllerProvider)
          .preview(_draft);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _step = 2;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final title = _titleController.text.trim();
      final draft = title.isEmpty ? _draft : _draft.copyWith(title: title);
      final id = await ref.read(runContractControllerProvider).create(draft);
      ref
          .read(runContractAnalyticsProvider)
          .log('contract_created', draft: _draft)
          .ignore();
      if (mounted) context.go('/contracts/$id');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _targetLabel() => _previewLabel(_draft.targetValue);

  String _previewLabel(double value) => switch (_draft.metric) {
    RunContractMetric.distance || RunContractMetric.longestRun =>
      '${value.toStringAsFixed(1)} km',
    RunContractMetric.activityCount => '${value.toInt()} buổi',
    RunContractMetric.activeDays => '${value.toInt()} ngày',
  };
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        borderRadius: 20,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.6),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _metricUnit(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance || RunContractMetric.longestRun => 'km',
  RunContractMetric.activityCount => 'buổi',
  RunContractMetric.activeDays => 'ngày',
};

double _defaultTargetFor(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => 10,
  RunContractMetric.longestRun => 5,
  RunContractMetric.activityCount => 3,
  RunContractMetric.activeDays => 3,
};

List<double> _quickTargets(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => const [3, 5, 10, 15, 21],
  RunContractMetric.longestRun => const [3, 5, 10, 21],
  RunContractMetric.activityCount => const [2, 3, 4, 5],
  RunContractMetric.activeDays => const [2, 3, 4, 5],
};

String _quickTargetLabel(RunContractMetric metric, double value) {
  final number = value % 1 == 0 ? value.toInt().toString() : value.toString();
  return '$number ${_metricUnit(metric)}';
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      color: context.runNowPalette.textMuted,
    ),
  );
}

/// Ô chọn ngày + giờ cho khung thời gian tùy chỉnh.
class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: palette.tint,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(Icons.event_rounded, size: 18, color: palette.accentDeep),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: palette.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                value == null ? 'Chọn' : DateFormat('EEE, dd/MM').format(value!),
                style: TextStyle(fontWeight: FontWeight.w800, color: onSurface),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bộ tăng/giảm mục tiêu (− số + đơn vị) — giống mockup "Tạo kèo".
class _GoalStepper extends StatelessWidget {
  const _GoalStepper({
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final double value;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final display = value % 1 == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          _StepBtn(
            icon: Icons.remove_rounded,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  display,
                  style: TextStyle(
                    fontSize: 34,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unit.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _StepBtn(
            icon: Icons.add_rounded,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Material(
      color: palette.glassStart,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: onTap == null ? palette.textMuted : palette.accentDeep,
          ),
        ),
      ),
    );
  }
}

/// Dòng tóm tắt kèo dưới bộ chọn mục tiêu.
class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, size: 18, color: palette.accentDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTargetChip extends StatelessWidget {
  const _QuickTargetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.glassStart,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected
                ? palette.glassStart
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 105, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlight ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      ],
    ),
  );
}
