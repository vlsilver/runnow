import 'package:flutter/material.dart';

import '../theme.dart';
import 'training_plan_glyph.dart';
import 'training_plan_models.dart';

/// Sheet chi tiết 1 buổi (1c) — mở khi tap 1 ngày trong lịch/spotlight.
class TrainingDaySheet extends StatelessWidget {
  const TrainingDaySheet({
    super.key,
    required this.day,
    required this.plan,
    required this.onToggleDone,
  });

  final TrainingDay day;
  final TrainingPlan plan;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tColor = workoutTypeColor(day.type, dark: dark);
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    final bg = dark ? RunNowDataColors.coachSheetDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Row(
            children: [
              _TypePill(type: day.type, color: tColor),
              const Spacer(),
              Text(
                'Tuần ${day.week} · ${day.label} ${_dm(day.date)}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  day.title,
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: palette.ink,
                  ),
                ),
              ),
              if (day.done) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, size: 24, color: palette.accent),
              ],
            ],
          ),
          if (!day.isRest) ...[
            const SizedBox(height: 16),
            _StatsGrid(day: day, palette: palette),
          ],
          if (day.detail != null) ...[
            const SizedBox(height: 16),
            _SectionLabel('CHI TIẾT BÀI', palette: palette),
            const SizedBox(height: 8),
            _DetailBox(text: day.detail!, color: tColor, palette: palette, dark: dark),
          ],
          if (day.note != null) ...[
            const SizedBox(height: 16),
            _CoachTip(text: day.note!, palette: palette, dark: dark),
          ],
          if (day.matchedActivityId != null) ...[
            const SizedBox(height: 16),
            _MatchedCard(day: day, palette: palette, dark: dark),
          ],
          const SizedBox(height: 20),
          if (!day.isRest && !day.done)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Bắt đầu chạy',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: onToggleDone,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.ink,
                        side: BorderSide(color: palette.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Đánh dấu xong',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type, required this.color});
  final WorkoutType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkoutGlyph(type: type, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            '${type.label} · ${type.element}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.day, required this.palette});
  final TrainingDay day;
  final RunNowPalette palette;

  @override
  Widget build(BuildContext context) {
    final dur = _durationEstimate(day);
    final cells = <(String, String)>[
      if (day.distanceKm != null) ('Cự ly', '${_trim(day.distanceKm!)} km'),
      if (day.paceHint != null) ('Pace mục tiêu', '${day.paceHint}/km'),
      if (dur != null) ('Thời lượng', dur),
    ];
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i != 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: palette.glassStart,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cells[i].$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cells[i].$2,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.palette});
  final String text;
  final RunNowPalette palette;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: palette.textMuted,
        ),
      );
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({
    required this.text,
    required this.color,
    required this.palette,
    required this.dark,
  });
  final String text;
  final Color color;
  final RunNowPalette palette;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.10 : 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
      );
}

class _CoachTip extends StatelessWidget {
  const _CoachTip({required this.text, required this.palette, required this.dark});
  final String text;
  final RunNowPalette palette;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: dark ? 0.09 : 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.accent.withValues(alpha: dark ? 0.20 : 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: palette.accentDeep),
                const SizedBox(width: 6),
                Text(
                  'LỜI KHUYÊN HLV',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: palette.accentDeep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.55, color: palette.ink),
            ),
          ],
        ),
      );
}

class _MatchedCard extends StatelessWidget {
  const _MatchedCard({required this.day, required this.palette, required this.dark});
  final TrainingDay day;
  final RunNowPalette palette;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.check_rounded,
                color: dark ? RunNowDataColors.coachOnAccentDark : Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ĐÃ KHỚP BUỔI CHẠY THẬT',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: palette.accentDeep,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_dm(day.date)} · ${_trim(day.distanceKm ?? 0)} km'
                    '${day.paceHint != null ? ' · ${day.paceHint}/km' : ''}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      );
}

// helpers
String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String? _durationEstimate(TrainingDay day) {
  final km = day.distanceKm;
  final pace = day.paceHint;
  if (km == null || pace == null) return null;
  final parts = pace.split(':');
  if (parts.length != 2) return null;
  final sec = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  if (sec == 0) return null;
  final total = (km * sec).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m phút';
}
