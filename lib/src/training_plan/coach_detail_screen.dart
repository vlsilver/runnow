import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'coach_chat_screen.dart';
import 'coach_roster.dart';
import 'training_plan_glyph.dart';
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
              title: Text(plan.goal),
              backgroundColor: palette.background,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: plan.visibility.isPublic
                      ? 'Công khai — chạm để chuyển riêng tư'
                      : 'Riêng tư — chạm để công khai',
                  icon: Icon(
                    plan.visibility.isPublic
                        ? Icons.groups_rounded
                        : Icons.lock_rounded,
                  ),
                  onPressed: () async {
                    final next = plan.visibility.isPublic
                        ? CoachVisibility.private
                        : CoachVisibility.club;
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref
                          .read(coachControllerProvider)
                          .setVisibility(plan.id, next);
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
                      messenger.showSnackBar(
                        SnackBar(content: Text('Không đổi được: $e')),
                      );
                    }
                  },
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
      await (joined
          ? coach.leave(widget.plan.id)
          : coach.join(widget.plan.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thực hiện được: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final plan = widget.plan;
    final uid = widget.currentUid;
    final joined = plan.hasJoined(uid);
    final members = ref.watch(membersProvider).value ?? const <MemberProfile>[];
    final ownerName = members
            .where((m) => m.uid == plan.ownerUid)
            .map((m) => m.displayName)
            .firstOrNull ??
        'HLV 3i';

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(plan.goal),
        backgroundColor: palette.background,
        elevation: 0,
        actions: [
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _summary(palette, plan, ownerName, joined),
            const SizedBox(height: 14),
            CoachRoster(plan: plan, members: members, currentUid: uid),
            const SizedBox(height: 20),
            if (joined)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Chạm vào một buổi để đánh dấu bạn đã hoàn thành.',
                  style: TextStyle(fontSize: 12.5, color: palette.textMuted),
                ),
              ),
            for (var w = 1; w <= plan.weeks; w++) ...[
              _WeekBlock(
                plan: plan,
                week: w,
                initiallyExpanded: w == plan.currentWeek(DateTime.now()),
                onToggle: joined
                    ? (index, done) => ref
                          .read(coachControllerProvider)
                          .toggleDone(plan.id, index, done)
                    : null,
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: FilledButton(
            onPressed: _busy ? null : () => _toggleJoin(joined),
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
                    joined ? 'Rời giáo án' : 'Tham gia giáo án',
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

  Widget _summary(
    RunNowPalette palette,
    TrainingPlan plan,
    String ownerName,
    bool joined,
  ) {
    final total = plan.totalSessions;
    final done = joined ? plan.doneSessions : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        color: palette.glassStart,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.summary.isEmpty ? 'Giáo án ${plan.weeks} tuần' : plan.summary,
            style: TextStyle(fontSize: 15, height: 1.45, color: palette.ink),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(palette, '${plan.weeks}', 'tuần'),
              _stat(palette, '$total', 'buổi'),
              _stat(palette, '${plan.participantCount}', 'người theo'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.person_rounded, size: 15, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                'HLV: $ownerName',
                style: TextStyle(fontSize: 13, color: palette.textMuted),
              ),
              if (joined) ...[
                const Spacer(),
                Text(
                  'Bạn đã xong $done/$total buổi',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(RunNowPalette palette, String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: palette.ink,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: palette.textMuted)),
      ],
    ),
  );
}

/// Một tuần trong lịch. Read-only khi chưa tham gia; đã tham gia thì chạm vào
/// buổi để tick tiến độ của chính mình ([onToggle] nhận index toàn cục + done).
class _WeekBlock extends StatefulWidget {
  const _WeekBlock({
    required this.plan,
    required this.week,
    this.onToggle,
    this.initiallyExpanded = false,
  });

  final TrainingPlan plan;
  final int week;
  final void Function(int index, bool done)? onToggle;
  final bool initiallyExpanded;

  @override
  State<_WeekBlock> createState() => _WeekBlockState();
}

class _WeekBlockState extends State<_WeekBlock> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final plan = widget.plan;
    final week = widget.week;
    // Chỉ hiện buổi tập — ngày nghỉ ẩn đi.
    final days = plan.daysOfWeek(week).where((d) => !d.isRest).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    final weekKm = plan.weekKm(week);
    final done = days.where((d) => d.done).length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 12, _expanded ? 8 : 12),
              child: Row(
                children: [
                  Text(
                    'Tuần $week',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (weekKm > 0)
                    Text(
                      '${weekKm.toStringAsFixed(weekKm % 1 == 0 ? 0 : 1)} km',
                      style: TextStyle(fontSize: 13, color: palette.textMuted),
                    ),
                  const Spacer(),
                  if (widget.onToggle != null)
                    Text(
                      '$done/${days.length}',
                      style: TextStyle(fontSize: 12.5, color: palette.textMuted),
                    ),
                  const SizedBox(width: 4),
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
          if (_expanded)
            for (var i = 0; i < days.length; i++) ...[
              Divider(height: 1, color: palette.border),
              _dayRow(context, palette, dark, days[i], plan.days.indexOf(days[i])),
            ],
        ],
      ),
    );
  }

  Widget _dayRow(
    BuildContext context,
    RunNowPalette palette,
    bool dark,
    TrainingDay day,
    int index,
  ) {
    final color = workoutTypeColor(day.type, dark: dark);
    final interactive = widget.onToggle != null && !day.isRest;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              day.label,
              style: TextStyle(fontSize: 12.5, color: palette.textMuted),
            ),
          ),
          SizedBox(
            width: 30,
            child: Center(
              child: day.isRest
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.textMuted.withValues(alpha: 0.5),
                      ),
                    )
                  : WorkoutGlyph(type: day.type, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: day.isRest ? palette.textMuted : palette.ink,
                  ),
                ),
                if (!day.isRest &&
                    (day.distanceKm != null || day.paceHint != null))
                  Text(
                    [
                      if (day.distanceKm != null)
                        '${day.distanceKm!.toStringAsFixed(day.distanceKm! % 1 == 0 ? 0 : 1)} km',
                      if (day.paceHint != null) 'pace ${day.paceHint}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: palette.textMuted),
                  ),
              ],
            ),
          ),
          if (interactive)
            Icon(
              day.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 24,
              color: day.done ? palette.accent : palette.border,
            ),
        ],
      ),
    );
    if (!interactive) return row;
    return InkWell(
      onTap: () => widget.onToggle!(index, !day.done),
      child: row,
    );
  }
}
