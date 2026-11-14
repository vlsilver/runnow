import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme.dart';
import 'coach_chat_screen.dart';
import 'plan_schedule_view.dart';
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
    final coach = ref.read(coachControllerProvider);
    return Column(
      children: [
        Expanded(
          child: PlanScheduleView(
            plan: plan,
            today: _today,
            onOpenDay: (d) => _openDay(plan, d),
            onToggleDone: (d) =>
                coach.toggleDone(plan.id, plan.days.indexOf(d), !d.done),
          ),
        ),
        // Nút pin đáy — luôn với tay tới khi cuộn lịch.
        _CoachActionBar(onAsk: () => _openCoachChat(plan.id)),
      ],
    );
  }
}

/// Hỏi lại rồi xoá giáo án của mình. Giáo án công khai thì báo group trước.
void confirmDeleteCoachPlan(
BuildContext context,
WidgetRef ref,
TrainingPlan plan,
) {
  // Số người khác đang theo (không tính chủ) — để cảnh báo hậu quả khi xoá.
  final others = (plan.participantCount - 1).clamp(0, 9999);
  final warn = others > 0
      ? 'Có $others người khác đang theo giáo án này — họ sẽ mất giáo án và '
            'tiến độ. 3i sẽ báo group. Không hoàn tác được.'
      : 'Giáo án hiện tại sẽ bị xoá, không hoàn tác được.';
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xoá giáo án?'),
      content: Text(warn),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            // Giáo án công khai → 3i bot báo group đã gỡ (enqueue kèm goal
            // TRƯỚC khi xoá để khỏi race đọc doc đã mất).
            if (plan.visibility.isPublic) {
              ref
                  .read(runNowApiClientProvider)
                  .announceCoachRemoved(goal: plan.goal)
                  .ignore();
            }
            ref.read(coachControllerProvider).delete();
          },
          child: const Text('Xoá'),
        ),
      ],
    ),
  );
}

/// Thanh pin đáy màn Coach: nút Hỏi Coach. Luôn với tay tới, không trôi mất
/// khi cuộn lịch. Xoá giáo án nằm ở menu ⋯ trên AppBar.
class _CoachActionBar extends StatelessWidget {
  const _CoachActionBar({required this.onAsk});
  final VoidCallback onAsk;

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
          child: _AskCoachButton(onTap: onAsk),
        ),
      ),
    );
  }
}

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
