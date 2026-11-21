import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'coach_chat_screen.dart';
import 'coach_roster.dart';
import 'plan_schedule_view.dart';
import 'plan_share.dart';
import 'training_plan_detail_sheet.dart';
import 'training_plan_models.dart';
import 'training_plan_repository.dart';
import 'training_plan_screen.dart';

/// Chi tiết một giáo án AI Coach mở từ card trên feed Kèo.
///
/// - Giáo án CỦA MÌNH (owner) → nhúng lại [TrainingPlanView] (hub đầy đủ: xem
///   lịch, tick, hỏi coach, đổi/xoá).
/// - Giáo án PUBLIC của người khác → bản xem đọc-là-chính + nút Tham gia / Rời.
class CoachDetailScreen extends ConsumerWidget {
  const CoachDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final async = ref.watch(coachPlanByIdProvider(planId));

    return async.when(
      loading: () => Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(backgroundColor: palette.background, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(backgroundColor: palette.background, elevation: 0),
        body: Center(child: Text('Lỗi tải giáo án: $e')),
      ),
      data: (plan) {
        // Slot giáo án của CHÍNH MÌNH nhưng chưa có → mở hub để tạo mới
        // (EmptyPlanState → generate → draft → xác nhận), đúng đường "/coach/{uid}".
        if (plan == null && planId == uid) {
          return Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              title: const Text('AI Coach'),
              backgroundColor: palette.background,
              elevation: 0,
            ),
            body: const SafeArea(bottom: false, child: TrainingPlanView()),
          );
        }
        if (plan == null) {
          return Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(backgroundColor: palette.background, elevation: 0),
            body: Center(
              child: Text(
                'Giáo án không còn tồn tại.',
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          );
        }
        // Của mình → mở hub đầy đủ (đọc coachPlanProvider bên trong).
        if (plan.isOwner(uid)) {
          return Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.background,
              elevation: 0,
              actions: [
                if (plan.visibility.isPublic)
                  CoachFollowersButton(
                    plan: plan,
                    members:
                        ref.watch(membersProvider).value ??
                        const <MemberProfile>[],
                    currentUid: uid,
                  ),
                IconButton(
                  tooltip: 'Khoe giáo án',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => showPlanShare(
                    context,
                    plan: plan,
                    currentUid: uid,
                    today: DateTime.now(),
                  ),
                ),
                PopupMenuButton<_OwnerAction>(
                  tooltip: 'Thêm',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (action) => switch (action) {
                    _OwnerAction.visibility => _toggleVisibility(
                      context,
                      ref,
                      plan,
                    ),
                    _OwnerAction.end => _confirmEnd(context, ref, plan),
                    _OwnerAction.delete => confirmDeleteCoachPlan(
                      context,
                      ref,
                      plan,
                    ),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _OwnerAction.visibility,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          plan.visibility.isPublic
                              ? Icons.lock_rounded
                              : Icons.groups_rounded,
                        ),
                        title: Text(
                          plan.visibility.isPublic
                              ? 'Chuyển riêng tư'
                              : 'Công khai cho nhóm',
                        ),
                      ),
                    ),
                    if (!plan.isOver(DateTime.now()))
                      const PopupMenuItem(
                        value: _OwnerAction.end,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_rounded),
                          title: Text('Kết thúc giáo án'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: _OwnerAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Xoá giáo án'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: const SafeArea(bottom: false, child: TrainingPlanView()),
          );
        }
        // Của người khác → xem read-only + tham gia.
        return _PublicCoachDetail(plan: plan, currentUid: uid);
      },
    );
  }
}

enum _OwnerAction { visibility, end, delete }

/// Hỏi lại rồi kết thúc giáo án của mình. Khác xoá: lịch và tiến độ của mọi
/// người vẫn còn, giáo án chỉ rời "Kèo đang chạy".
void _confirmEnd(BuildContext context, WidgetRef ref, TrainingPlan plan) {
  final messenger = ScaffoldMessenger.of(context);
  final others = (plan.participantCount - 1).clamp(0, 9999);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Kết thúc giáo án?'),
      content: Text(
        others > 0
            ? 'Giáo án rời Kèo đang chạy của bạn và $others người đang theo. '
                  'Lịch và tiến độ vẫn giữ.'
            : 'Giáo án rời Kèo đang chạy. Lịch và tiến độ vẫn giữ.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            try {
              await ref.read(coachControllerProvider).end(plan.id);
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Không kết thúc được: $e')),
              );
            }
          },
          child: const Text('Kết thúc'),
        ),
      ],
    ),
  );
}

Future<void> _toggleVisibility(
  BuildContext context,
  WidgetRef ref,
  TrainingPlan plan,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final others = plan.participantCount - 1;
  // Công khai → Riêng tư chỉ khi CHƯA có ai khác theo — kẻo họ
  // bị kẹt (không tick/rời được khi giáo án riêng tư).
  if (plan.visibility.isPublic && others > 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Còn $others người đang theo — chuyển Riêng tư được '
          'khi họ rời hết. Công khai → Riêng tư chỉ khi một mình bạn.',
        ),
      ),
    );
    return;
  }
  final next = plan.visibility.isPublic
      ? CoachVisibility.private
      : CoachVisibility.club;
  try {
    await ref.read(coachControllerProvider).setVisibility(plan.id, next);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          next.isPublic
              ? 'Đã chuyển Công khai — lên feed, cả nhóm tham gia được.'
              : 'Đã chuyển Riêng tư — chỉ mình bạn thấy.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Không đổi được: $e')));
  }
}

class _PublicCoachDetail extends ConsumerStatefulWidget {
  const _PublicCoachDetail({required this.plan, required this.currentUid});

  final TrainingPlan plan;
  final String? currentUid;

  @override
  ConsumerState<_PublicCoachDetail> createState() => _PublicCoachDetailState();
}

class _PublicCoachDetailState extends ConsumerState<_PublicCoachDetail> {
  bool _busy = false;

  Future<void> _toggleJoin(bool joined) async {
    setState(() => _busy = true);
    try {
      final coach = ref.read(coachControllerProvider);
      await (joined ? coach.leave(widget.plan.id) : coach.join(widget.plan.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thực hiện được: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleDone(TrainingPlan plan, TrainingDay day) => ref
      .read(coachControllerProvider)
      .toggleDone(plan.id, plan.days.indexOf(day), !day.done);

  void _openDay(TrainingPlan plan, TrainingDay day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => TrainingDaySheet(
        day: day,
        plan: plan,
        onToggleDone: () {
          _toggleDone(plan, day);
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final plan = widget.plan;
    final uid = widget.currentUid;
    final joined = plan.hasJoined(uid);
    final over = plan.isOver(DateTime.now());
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final ownerName =
        members
            .where((m) => m.uid == plan.ownerUid)
            .map((m) => m.displayName)
            .firstOrNull ??
        'HLV 3i';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        actions: [
          CoachFollowersButton(plan: plan, members: members, currentUid: uid),
          IconButton(
            tooltip: 'Khoe giáo án',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showPlanShare(
              context,
              plan: plan,
              currentUid: uid,
              today: DateTime.now(),
              coachName: ownerName,
            ),
          ),
          if (joined)
            IconButton(
              tooltip: 'Hỏi Coach',
              icon: const Icon(Icons.forum_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CoachChatScreen(planId: plan.id),
                ),
              ),
            ),
        ],
      ),
      // Chưa tham gia thì chỉ xem lịch; tham gia rồi mới mở buổi và đánh dấu.
      body: SafeArea(
        child: PlanScheduleView(
          plan: plan,
          today: DateTime.now(),
          coachName: ownerName,
          onOpenDay: joined ? (d) => _openDay(plan, d) : null,
          onToggleDone: joined ? (d) => _toggleDone(plan, d) : null,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: FilledButton(
            onPressed: _busy || (over && !joined)
                ? null
                : () => _toggleJoin(joined),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: joined ? palette.glassStart : palette.accent,
              foregroundColor: joined
                  ? palette.ink
                  : (Theme.of(context).brightness == Brightness.dark
                        ? RunNowDataColors.coachOnAccentDark
                        : Colors.white),
            ),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    joined
                        ? 'Rời giáo án'
                        : over
                        ? 'Giáo án đã kết thúc'
                        : 'Tham gia giáo án',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
