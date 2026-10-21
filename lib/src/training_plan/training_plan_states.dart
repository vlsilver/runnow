import 'package:flutter/material.dart';

import '../theme.dart';
import 'training_plan_models.dart';

/// Các bước pipeline sinh giáo án — tô checklist ở [GeneratingState].
const trainingPlanSteps = <String>[
  'Đọc lịch sử chạy của bạn',
  'Ước lượng phong độ hiện tại',
  'Dựng lịch tập theo mục tiêu',
  'Cá nhân hoá lời khuyên từng buổi',
];

/// (1d-a) AI đang tạo giáo án. [step] 0..3 tô tiến độ checklist (mô tả pipeline,
/// không phải progress-bar realtime).
class GeneratingState extends StatelessWidget {
  const GeneratingState({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final progress = ((step + 1) / trainingPlanSteps.length).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AnalyzingCoachIcon(),
          const SizedBox(height: 22),
          Text(
            'Đang phân tích lịch sử chạy của bạn',
            style: TextStyle(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Khoảng 20 giây. Bạn cứ để máy đây, xong tôi báo.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.textMuted),
          ),
          const SizedBox(height: 26),
          for (var i = 0; i < trainingPlanSteps.length; i++) ...[
            _StepRow(
              label: trainingPlanSteps[i],
              state: i < step
                  ? _StepState.done
                  : (i == step ? _StepState.running : _StepState.pending),
            ),
            if (i != trainingPlanSteps.length - 1) const SizedBox(height: 13),
          ],
          const SizedBox(height: 26),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: palette.border,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon coach lúc đang phân tích: sparkle lấp lánh (scale) + xoay nhẹ qua lại +
/// quầng sáng accent đập theo nhịp — báo "đang nghĩ", không đứng im.
class _AnalyzingCoachIcon extends StatefulWidget {
  const _AnalyzingCoachIcon();

  @override
  State<_AnalyzingCoachIcon> createState() => _AnalyzingCoachIconState();
}

class _AnalyzingCoachIconState extends State<_AnalyzingCoachIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final p = curved.value; // 0..1 đi–về mượt
        return Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.08 + 0.10 * p),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.10 + 0.22 * p),
                blurRadius: 12 + 20 * p,
                spreadRadius: 1 + 2 * p,
              ),
            ],
          ),
          child: Transform.rotate(
            angle: (p - 0.5) * 0.18,
            child: Transform.scale(scale: 0.88 + 0.20 * p, child: child),
          ),
        );
      },
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 34,
        color: palette.accentDeep,
      ),
    );
  }
}

enum _StepState { done, running, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget mark;
    switch (state) {
      case _StepState.done:
        mark = Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: palette.accent, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded,
              size: 13, color: dark ? RunNowDataColors.coachOnAccentDark : Colors.white),
        );
      case _StepState.running:
        mark = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.accent),
        );
      case _StepState.pending:
        mark = Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: palette.border, width: 1.5),
          ),
        );
    }
    return Row(
      children: [
        mark,
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: state == _StepState.running ? FontWeight.w700 : FontWeight.w500,
            color: state == _StepState.pending ? palette.textMuted : palette.ink,
          ),
        ),
      ],
    );
  }
}

/// (1d-b) Chưa có giáo án. Chọn 1 gợi ý mục tiêu rồi tạo.
class EmptyPlanState extends StatefulWidget {
  const EmptyPlanState({super.key, required this.onGenerate});
  final void Function(String goal, CoachVisibility visibility) onGenerate;

  @override
  State<EmptyPlanState> createState() => _EmptyPlanStateState();
}

class _EmptyPlanStateState extends State<EmptyPlanState> {
  // Gợi ý điền nhanh vào ô nhập — user sửa/thêm tuỳ ý.
  static const _suggestions = [
    'Chạy 5km trong 3 tuần',
    'Chạy 10km trong 6 tuần',
    'Half Marathon trong 10 tuần',
    'Chạy đều 3 buổi/tuần',
  ];
  final _goalCtrl = TextEditingController();
  CoachVisibility _visibility = CoachVisibility.private;

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  void _fill(String s) {
    setState(() {
      _goalCtrl.text = s;
      _goalCtrl.selection = TextSelection.collapsed(offset: s.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    final canGenerate = _goalCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PlanTeaser(),
          const SizedBox(height: 24),
          Text(
            'Đặt mục tiêu của bạn',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tả mục tiêu bằng lời của bạn — cự ly, thời gian, pace mong muốn, '
            'ngày rảnh trong tuần… AI dựng giáo án cá nhân theo đó + lịch sử chạy của bạn.',
            style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _goalCtrl,
            onChanged: (_) => setState(() {}),
            minLines: 3,
            maxLines: 4,
            style: TextStyle(color: palette.ink, fontSize: 14, height: 1.45),
            decoration: InputDecoration(
              hintText:
                  'vd: Muốn chạy 21km trong 8 tuần, pace tầm 6:00/km, rảnh Thứ 3 · Thứ 5 · Thứ 7…',
              hintStyle: TextStyle(
                color: palette.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
              filled: true,
              fillColor: palette.glassStart,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'GỢI Ý NHANH',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _suggestions)
                GestureDetector(
                  onTap: () => _fill(s),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: palette.glassStart,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'AI DÀNH CHO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _VisibilityChoice(
                icon: Icons.lock_rounded,
                label: 'Riêng tư',
                hint: 'Chỉ mình bạn',
                selected: _visibility == CoachVisibility.private,
                onTap: () =>
                    setState(() => _visibility = CoachVisibility.private),
              ),
              const SizedBox(width: 10),
              _VisibilityChoice(
                icon: Icons.groups_rounded,
                label: 'Công khai',
                hint: 'Cả nhóm cùng theo',
                selected: _visibility == CoachVisibility.club,
                onTap: () => setState(() => _visibility = CoachVisibility.club),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: canGenerate
                  ? () => widget.onGenerate(_goalCtrl.text.trim(), _visibility)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: onAccent,
                disabledBackgroundColor: palette.border,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17)),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Tạo giáo án cho tôi',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ô chọn riêng tư / công khai ở màn tạo giáo án.
class _VisibilityChoice extends StatelessWidget {
  const _VisibilityChoice({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : palette.glassStart,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? palette.accent : palette.textMuted,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: selected ? palette.accent : palette.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(fontSize: 11.5, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minh hoạ nhỏ ở màn empty: các buổi tăng tải dần rồi tới ngày về đích, màu
/// theo loại bài. Thuần trang trí.
class _PlanTeaser extends StatelessWidget {
  const _PlanTeaser();

  static const _bars = <(WorkoutType, double)>[
    (WorkoutType.easy, 26),
    (WorkoutType.tempo, 40),
    (WorkoutType.rest, 18),
    (WorkoutType.long, 50),
    (WorkoutType.easy, 30),
    (WorkoutType.interval, 46),
    (WorkoutType.race, 62),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in _bars) ...[
            Container(
              width: 22,
              height: b.$2,
              decoration: BoxDecoration(
                color: workoutTypeColor(b.$1, dark: dark)
                    .withValues(alpha: b.$1.isRest ? 0.28 : 0.9),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

/// (1d-c) Hoàn thành cả giáo án.
class CompletedPlanState extends StatelessWidget {
  const CompletedPlanState({
    super.key,
    required this.plan,
    required this.onNext,
    required this.onReview,
  });
  final TrainingPlan plan;
  final VoidCallback onNext;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    final totalKm = plan.days.fold<double>(
        0, (s, d) => s + (d.done ? (d.distanceKm ?? 0) : 0));
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 11,
                    backgroundColor: palette.border,
                    color: palette.accent,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('100%',
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: palette.ink)),
                    Text('Trọn giáo án',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: palette.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '${_trim(plan.goalDistanceKm)} km, đúng hẹn.',
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bạn hoàn thành trọn vẹn giáo án. Chân đã sẵn cho mục tiêu mới.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.textMuted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _stat(palette, '${plan.doneSessions}/${plan.totalSessions}', 'buổi'),
              const SizedBox(width: 8),
              _stat(palette, _trim(totalKm), 'km tổng'),
              const SizedBox(width: 8),
              _stat(palette, '${plan.weeks}', 'tuần'),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: onAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
              ),
              child: const Text('Đặt mục tiêu tiếp theo',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onReview,
            child: Text('Xem lại giáo án',
                style: TextStyle(color: palette.textMuted, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _stat(RunNowPalette palette, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: palette.glassStart,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted)),
            ],
          ),
        ),
      );
}

String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
