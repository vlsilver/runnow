import 'package:flutter/material.dart';

import '../theme.dart';
import 'training_plan_models.dart';

/// Màn XÁC NHẬN: coach đề xuất xong thì user đọc ở đây rồi mới quyết.
///
/// Trước đây giáo án ghi thẳng vào coach/current — lịch hiện ra mà không ai
/// biết vì sao lại thế, và một lần bấm là mất giáo án đang tập. Màn này trả
/// lời đúng ba câu trước khi cam kết: coach đề xuất gì, vì sao, và có gì cần
/// lưu ý.
class PlanProposalView extends StatelessWidget {
  const PlanProposalView({
    super.key,
    required this.draft,
    required this.current,
    required this.onConfirm,
    required this.onDiscard,
    this.busy = false,
  });

  final TrainingPlan draft;

  /// Giáo án đang chạy, nếu có — để cảnh báo rõ là xác nhận sẽ thay thế nó.
  final TrainingPlan? current;

  final VoidCallback onConfirm;
  final VoidCallback onDiscard;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final sessions = draft.days.where((d) => !d.isRest).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text(
          'Coach đề xuất',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          draft.goal,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.2,
            color: palette.ink,
          ),
        ),
        if (draft.summary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            draft.summary,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: palette.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 18),

        _FeasibilityChip(feasibility: draft.feasibility),

        const SizedBox(height: 18),
        _NumbersGrid(draft: draft, sessions: sessions),

        if (draft.rationale != null) ...[
          const SizedBox(height: 22),
          _Section(
            title: 'Vì sao lịch này',
            child: Text(
              draft.rationale!,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: palette.ink,
              ),
            ),
          ),
        ],

        if (draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 18),
          _Warnings(warnings: draft.warnings),
        ],

        const SizedBox(height: 22),
        _Section(
          title: 'Khối lượng từng tuần',
          child: _WeeklyVolume(draft: draft),
        ),

        if (current != null) ...[
          const SizedBox(height: 18),
          _ReplaceNotice(current: current!),
        ],

        const SizedBox(height: 26),
        FilledButton(
          onPressed: busy ? null : onConfirm,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: palette.accent,
            foregroundColor:
                Theme.of(context).brightness == Brightness.dark
                ? RunNowDataColors.coachOnAccentDark
                : Colors.white,
          ),
          child: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? RunNowDataColors.coachOnAccentDark
                        : Colors.white,
                  ),
                )
              : Text(
                  current == null ? 'Bắt đầu giáo án' : 'Thay giáo án hiện tại',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: busy ? null : onDiscard,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          child: Text(
            'Bỏ đề xuất này',
            style: TextStyle(fontSize: 15, color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── mức độ khả thi

class _FeasibilityChip extends StatelessWidget {
  const _FeasibilityChip({required this.feasibility});
  final PlanFeasibility feasibility;

  @override
  Widget build(BuildContext context) {
    if (feasibility == PlanFeasibility.unknown) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;

    // Ba mức dùng ba màu loại bài sẵn có, không thêm màu mới vào hệ thống:
    // easy (nhẹ) → vừa sức, tempo → thử thách, race (nặng nhất) → quá sức.
    final color = switch (feasibility) {
      PlanFeasibility.comfortable => workoutTypeColor(WorkoutType.easy, dark: dark),
      PlanFeasibility.challenging => workoutTypeColor(WorkoutType.tempo, dark: dark),
      PlanFeasibility.tooHard => workoutTypeColor(WorkoutType.race, dark: dark),
      PlanFeasibility.unknown => palette.textMuted,
    };
    final note = switch (feasibility) {
      PlanFeasibility.comfortable => 'nằm trong tầm với hiện tại của bạn',
      PlanFeasibility.challenging => 'phải cố, nhưng vẫn an toàn',
      PlanFeasibility.tooHard => 'nền hiện tại chưa đủ — coach đã điều chỉnh',
      PlanFeasibility.unknown => '',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            feasibility.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(fontSize: 13, color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── số liệu chính

class _NumbersGrid extends StatelessWidget {
  const _NumbersGrid({required this.draft, required this.sessions});
  final TrainingPlan draft;
  final int sessions;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final items = <(String, String)>[
      ('Thời gian', '${draft.weeks} tuần'),
      ('Bắt đầu', _dayMonth(draft.startDate)),
      ('Về đích', _dayMonth(draft.targetDate)),
      ('Số buổi chạy', '$sessions buổi'),
      if (draft.totalKm != null) ('Tổng quãng đường', '${_trim(draft.totalKm!)} km'),
      if (draft.targetPaceLabel != null) ('Pace đích', draft.targetPaceLabel!),
      if (draft.goalTimeLabel != null) ('Thời gian đích', draft.goalTimeLabel!),
    ];

    return Container(
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: palette.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    items[i].$1,
                    style: TextStyle(fontSize: 14, color: palette.textMuted),
                  ),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── cảnh báo

class _Warnings extends StatelessWidget {
  const _Warnings({required this.warnings});
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = workoutTypeColor(WorkoutType.tempo, dark: dark);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cần biết trước',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('· ', style: TextStyle(color: palette.textMuted)),
                  Expanded(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── khối lượng tuần

class _WeeklyVolume extends StatelessWidget {
  const _WeeklyVolume({required this.draft});
  final TrainingPlan draft;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final weeks = [
      for (var w = 1; w <= draft.weeks; w++) (w, draft.weekKm(w)),
    ];
    final maxKm = weeks.fold<double>(0, (m, e) => e.$2 > m ? e.$2 : m);

    return Column(
      children: [
        for (final (week, km) in weeks)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    'Tuần $week',
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxKm > 0 ? km / maxKm : 0,
                      minHeight: 8,
                      backgroundColor: palette.border,
                      color: palette.accent,
                    ),
                  ),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${_trim(km)} km',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────── thay giáo án cũ

class _ReplaceNotice extends StatelessWidget {
  const _ReplaceNotice({required this.current});
  final TrainingPlan current;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final done = current.doneSessions;
    final total = current.totalSessions;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 18, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Xác nhận sẽ thay giáo án đang chạy — "${current.goal}", '
              'đã xong $done/$total buổi. Tiến độ đó không giữ lại được.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── phụ trợ

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String _dayMonth(DateTime d) => '${d.day}/${d.month}';
