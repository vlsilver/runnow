import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'coach_chat_screen.dart';
import 'coach_roster.dart';
import 'training_plan_glyph.dart';
import 'training_plan_models.dart';
import 'training_plan_proposal.dart';
import 'training_plan_repository.dart';
import 'training_plan_states.dart';
import 'training_plan_detail_sheet.dart';

/// "AI Coach" — giáo án do AI sinh, đọc từ users/{uid}/coach/current. 1 giáo án
/// active/user; đổi = ghi đè, xoá = xoá doc (luật enforce ở đây). Là VIEW nhúng
/// (không Scaffold) để đặt vào tab Coach trong màn Kèo.
///
/// Sinh giáo án đi qua HAI bước: coach ghi đề xuất vào coach/draft, màn này
/// hiện [PlanProposalView] kèm lý do, user xác nhận thì mới thành giáo án đang
/// chạy. Bản nháp luôn được ưu tiên hiển thị — có đề xuất treo thì phải quyết
/// xong mới về lại lịch.
class TrainingPlanView extends ConsumerStatefulWidget {
  const TrainingPlanView({super.key});

  @override
  ConsumerState<TrainingPlanView> createState() => _TrainingPlanViewState();
}

class _TrainingPlanViewState extends ConsumerState<TrainingPlanView> {
  bool _generating = false;
  int _genStep = 0;
  bool _forceCreate = false; // muốn đổi/tạo mới dù đang có plan
  bool _dismissedCompleted = false;
  bool _decidingDraft = false; // đang gọi confirm/discard, khoá nút
  DateTime? _genPrevCreatedAt; // createdAt bản nháp trước lúc bấm generate
  Timer? _genTimer;
  Timer? _genTimeout;

  DateTime get _today => DateTime.now();

  @override
  void dispose() {
    _genTimer?.cancel();
    _genTimeout?.cancel();
    super.dispose();
  }

  Future<void> _generate(
    String goal,
    CoachVisibility visibility,
    TrainingPlan? prevDraft,
  ) async {
    setState(() {
      _generating = true;
      _genStep = 0;
      _forceCreate = false;
      _genPrevCreatedAt = prevDraft?.createdAt;
    });
    _genTimer?.cancel();
    var step = 0;
    _genTimer = Timer.periodic(const Duration(milliseconds: 1300), (t) {
      step++;
      if (step >= trainingPlanSteps.length) {
        t.cancel();
        return;
      }
      if (mounted) setState(() => _genStep = step);
    });
    _genTimeout?.cancel();
    _genTimeout = Timer(const Duration(seconds: 45), () {
      if (mounted && _generating) {
        _genTimer?.cancel();
        setState(() => _generating = false);
        _snack('Tạo giáo án lâu hơn dự kiến — thử lại nhé.');
      }
    });
    try {
      await ref
          .read(coachControllerProvider)
          .generate(goal, visibility: visibility);
    } catch (e) {
      if (!mounted) return;
      _genTimer?.cancel();
      _genTimeout?.cancel();
      setState(() => _generating = false);
      _snack('Lỗi tạo giáo án: $e');
    }
  }

  // Bản nháp MỚI về (createdAt khác cái trước lúc generate) → dừng animation.
  void _onDraftChanged(TrainingPlan? draft) {
    if (!_generating) return;
    if (draft != null && draft.createdAt != _genPrevCreatedAt) {
      _genTimer?.cancel();
      _genTimeout?.cancel();
      setState(() {
        _generating = false;
        _dismissedCompleted = false;
      });
    }
  }

  Future<void> _decideDraft({required bool accept}) async {
    setState(() => _decidingDraft = true);
    try {
      final coach = ref.read(coachControllerProvider);
      await (accept ? coach.confirmDraft() : coach.discardDraft());
      if (mounted) setState(() => _dismissedCompleted = false);
    } catch (e) {
      if (mounted) _snack(accept ? 'Không xác nhận được: $e' : 'Không bỏ được: $e');
    } finally {
      if (mounted) setState(() => _decidingDraft = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _openDay(TrainingPlan plan, TrainingDay day) {
    final index = plan.days.indexOf(day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => TrainingDaySheet(
        day: day,
        plan: plan,
        onToggleDone: () {
          ref.read(coachControllerProvider).toggleDone(plan.id, index, !day.done);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  void _openCoachChat(String planId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CoachChatScreen(planId: planId)),
    );
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá giáo án?'),
        content: const Text('Giáo án hiện tại sẽ bị xoá, không hoàn tác được.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ref.read(coachControllerProvider).delete();
            },
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(coachDraftProvider, (_, next) => _onDraftChanged(next.value));
    final async = ref.watch(coachPlanProvider);
    final draft = ref.watch(coachDraftProvider).value;
    return _body(async, draft);
  }

  Widget _body(AsyncValue<TrainingPlan?> async, TrainingPlan? draft) {
    if (_generating) {
      return SingleChildScrollView(child: GeneratingState(step: _genStep));
    }
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Lỗi tải giáo án: $e', textAlign: TextAlign.center),
        ),
      ),
      data: (plan) {
        // Đề xuất đang treo thì phải quyết trước — không cho nó nằm im
        // trong khi user tiếp tục dùng lịch cũ rồi quên mất.
        if (draft != null) {
          return PlanProposalView(
            draft: draft,
            current: plan,
            busy: _decidingDraft,
            onConfirm: () => _decideDraft(accept: true),
            onDiscard: () => _decideDraft(accept: false),
          );
        }
        if (_forceCreate || plan == null) {
          return SingleChildScrollView(
            child: EmptyPlanState(
              onGenerate: (g, vis) => _generate(g, vis, draft),
            ),
          );
        }
        if (plan.completed && !_dismissedCompleted) {
          return SingleChildScrollView(
            child: CompletedPlanState(
              plan: plan,
              onNext: () => setState(() => _forceCreate = true),
              onReview: () => setState(() => _dismissedCompleted = true),
            ),
          );
        }
        return _mainContent(plan);
      },
    );
  }

  Widget _mainContent(TrainingPlan plan) {
    final today = _today;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            children: [
              _GoalHeader(plan: plan, today: today),
              const SizedBox(height: 20),
              _SessionProgress(plan: plan),
              // Giáo án công khai: chủ nhóm thấy ai đang theo + tiến độ từng người.
              if (plan.visibility.isPublic) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CoachRoster(
                    plan: plan,
                    members: ref.watch(membersProvider).value ??
                        const <MemberProfile>[],
                    currentUid: ref.watch(firebaseUserProvider).value?.uid,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _TodaySpotlight(
                plan: plan,
                today: today,
                onToggleDone: (d) => ref
                    .read(coachControllerProvider)
                    .toggleDone(plan.id, plan.days.indexOf(d), !d.done),
                onOpen: (d) => _openDay(plan, d),
              ),
              const SizedBox(height: 8),
              for (var w = 1; w <= plan.weeks; w++)
                _WeekSection(
                  plan: plan,
                  week: w,
                  today: today,
                  onTapDay: (d) => _openDay(plan, d),
                  initiallyExpanded: w == plan.currentWeek(today),
                ),
            ],
          ),
        ),
        // Actions pin đáy — luôn với tay tới khi cuộn lịch.
        _CoachActionBar(
          onAsk: () => _openCoachChat(plan.id),
          onDelete: _confirmDelete,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── Goal header

class _GoalHeader extends StatelessWidget {
  const _GoalHeader({required this.plan, required this.today});
  final TrainingPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final left = plan.daysLeft(today);
    final title = plan.goalDistanceKm > 0
        ? '${_trimNum(plan.goalDistanceKm)} km'
        : plan.goal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 44,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    color: palette.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_fullDate(plan.targetDate)} · còn $left ngày',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StreakChip(count: plan.streak(today)),
        ],
      ),
    );
  }
}

/// Thanh action pin đáy màn Coach: nút Hỏi Coach (rộng) + đổi + xoá. Luôn với
/// tay tới, không trôi mất khi cuộn lịch.
class _CoachActionBar extends StatelessWidget {
  const _CoachActionBar({required this.onAsk, required this.onDelete});
  final VoidCallback onAsk;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(child: _AskCoachButton(onTap: onAsk)),
              const SizedBox(width: 8),
              _IconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Xoá giáo án',
                onTap: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút icon-only (có tooltip) cho actions của Coach. Primary = nền accent.
/// Nút chính "Hỏi Coach" — pill accent rộng, có nhãn (việc user hay làm nhất).
class _AskCoachButton extends StatelessWidget {
  const _AskCoachButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    return Material(
      color: palette.accent,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_rounded, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                'Hỏi Coach về giáo án',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút icon-only phụ (đổi / xoá) — nền glass, viền nhẹ, có tooltip.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 46,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, size: 20, color: palette.ink),
          ),
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fire = workoutTypeColor(WorkoutType.interval, dark: dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: fire.withValues(alpha: dark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 15, color: fire),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fire,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────── Session progress

class _SessionProgress extends StatelessWidget {
  const _SessionProgress({required this.plan});
  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final total = plan.totalSessions;
    final done = plan.doneSessions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                Expanded(
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: i < done
                          ? palette.accent
                          : palette.border.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                if (i != total - 1) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$done',
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '/$total buổi',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 12.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── Today spotlight

class _TodaySpotlight extends StatelessWidget {
  const _TodaySpotlight({
    required this.plan,
    required this.today,
    required this.onToggleDone,
    required this.onOpen,
  });
  final TrainingPlan plan;
  final DateTime today;
  final void Function(TrainingDay) onToggleDone;
  final void Function(TrainingDay) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Ngày hôm nay (bất kỳ loại — kể cả nghỉ).
    TrainingDay? day;
    for (final d in plan.days) {
      if (d.date.year == today.year &&
          d.date.month == today.month &&
          d.date.day == today.day) {
        day = d;
        break;
      }
    }
    if (day == null) return const SizedBox.shrink();
    final d = day;
    final tColor = workoutTypeColor(d.type, dark: dark);
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GestureDetector(
        onTap: () => onOpen(d),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.7, -1),
              end: const Alignment(0.7, 1),
              colors: [
                tColor.withValues(alpha: dark ? 0.22 : 0.16),
                (dark ? Colors.white : Colors.white).withValues(
                  alpha: dark ? 0.045 : 0.65,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: tColor.withValues(alpha: dark ? 0.26 : 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    d.isRest ? 'HÔM NAY NGHỈ' : 'HÔM NAY',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: tColor,
                    ),
                  ),
                  const Spacer(),
                  WorkoutGlyph(type: d.type, color: tColor, size: 26),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                d.title,
                style: TextStyle(
                  fontSize: 30,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  color: palette.ink,
                ),
              ),
              if (!d.isRest) ...[
                const SizedBox(height: 16),
                _StatRow(day: d, palette: palette),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () => onOpen(d),
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: onAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text(
                            'Bắt đầu',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _SquareButton(
                      icon: d.done ? Icons.check_rounded : Icons.check,
                      active: d.done,
                      palette: palette,
                      onTap: () => onToggleDone(d),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  d.note ?? 'Để chân nghỉ, mai chạy tiếp.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.day, required this.palette});
  final TrainingDay day;
  final RunNowPalette palette;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      if (day.distanceKm != null) (_trimNum(day.distanceKm!), 'km'),
      if (day.paceHint != null) (day.paceHint!, '/km'),
      if (day.detail != null && day.type == WorkoutType.interval)
        (_restSeconds(day.detail!) ?? '', 's nghỉ'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i != 0)
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: palette.border,
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                items[i].$1,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                items[i].$2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.active,
    required this.palette,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final RunNowPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: active
          ? palette.accent
          : (dark ? Colors.white.withValues(alpha: 0.07) : Colors.white),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            icon,
            size: 20,
            color: active
                ? (dark ? RunNowDataColors.coachOnAccentDark : Colors.white)
                : palette.textMuted,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────── Week schedule (4a)

class _WeekSection extends StatefulWidget {
  const _WeekSection({
    required this.plan,
    required this.week,
    required this.today,
    required this.onTapDay,
    required this.initiallyExpanded,
  });
  final TrainingPlan plan;
  final int week;
  final DateTime today;
  final void Function(TrainingDay) onTapDay;
  final bool initiallyExpanded;

  @override
  State<_WeekSection> createState() => _WeekSectionState();
}

class _WeekSectionState extends State<_WeekSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final plan = widget.plan;
    final week = widget.week;
    // Chỉ hiện buổi TẬP — ngày nghỉ không cần chiếm chỗ.
    final days = plan.daysOfWeek(week).where((d) => !d.isRest).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    final done = days.where((d) => d.done).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bấm để mở/đóng tuần.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(left: 2, top: 2, bottom: 10),
              child: Row(
                children: [
                  Text(
                    'TUẦN $week',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_trimNum(plan.weekKm(week))} km',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.accentDeep,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$done/${days.length} buổi',
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Danh sách theo ngày — chỉ dựng khi mở.
          if (_expanded)
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.glassStart,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i != 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: palette.border.withValues(alpha: 0.5),
                        ),
                      _DayRow(
                        day: days[i],
                        isToday: _sameDay(days[i].date, widget.today),
                        onTap: () => widget.onTapDay(days[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Một NGÀY trong lịch — dạng dòng. Ngày tập nổi (icon + tên + km/pace + tick);
/// ngày nghỉ mờ, mảnh. Hôm nay tô nền màu loại bài + pill "HÔM NAY".
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.isToday, required this.onTap});
  final TrainingDay day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tColor = workoutTypeColor(day.type, dark: dark);
    final rest = day.isRest;

    return InkWell(
      onTap: onTap,
      child: Container(
        color:
            isToday ? tColor.withValues(alpha: dark ? 0.16 : 0.09) : null,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: rest ? 10 : 12),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Text(
                day.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: rest ? palette.textMuted : palette.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (rest)
              SizedBox(
                width: 30,
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tColor.withValues(alpha: dark ? 0.18 : 0.13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: WorkoutGlyph(type: day.type, color: tColor, size: 17),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: rest
                  ? Text(
                      'Nghỉ',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: palette.textMuted,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                          ),
                        ),
                        if (day.distanceKm != null || day.paceHint != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (day.distanceKm != null)
                                '${_trimNum(day.distanceKm!)} km',
                              if (day.paceHint != null) '${day.paceHint}/km',
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: palette.textMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            _trailing(palette, tColor, dark),
          ],
        ),
      ),
    );
  }

  Widget _trailing(RunNowPalette palette, Color tColor, bool dark) {
    if (day.isRest) return const SizedBox.shrink();
    if (day.done) {
      return Icon(Icons.check_circle_rounded, size: 21, color: palette.accent);
    }
    if (isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: tColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'HÔM NAY',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: Colors.white,
          ),
        ),
      );
    }
    return Icon(Icons.radio_button_unchecked_rounded,
        size: 20, color: palette.border);
  }
}

// ─────────────────────────────────────────────────────────────── helpers

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _fullDate(DateTime d) {
  final wd = switch (d.weekday) {
    DateTime.monday => 'Thứ 2',
    DateTime.tuesday => 'Thứ 3',
    DateTime.wednesday => 'Thứ 4',
    DateTime.thursday => 'Thứ 5',
    DateTime.friday => 'Thứ 6',
    DateTime.saturday => 'Thứ 7',
    _ => 'Chủ nhật',
  };
  return '$wd ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

String? _restSeconds(String detail) {
  final m = RegExp(r'nghỉ\s*(\d+)\s*s').firstMatch(detail);
  return m?.group(1);
}
