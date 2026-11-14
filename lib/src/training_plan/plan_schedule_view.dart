import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'training_plan_models.dart';

/// Thân trang giáo án, dùng chung cho chủ giáo án và người vào xem: tiến độ,
/// khối lượng từng tuần, buổi hôm nay, rồi các buổi của tuần đang chọn.
///
/// Màn chứa nó lo thanh nút dưới đáy (Hỏi Coach, Tham gia). [onToggleDone]
/// null là chỉ xem, không đánh dấu được.
class PlanScheduleView extends StatefulWidget {
  const PlanScheduleView({
    super.key,
    required this.plan,
    required this.today,
    this.coachName,
    this.onOpenDay,
    this.onToggleDone,
  });

  final TrainingPlan plan;
  final DateTime today;

  /// Tên người dựng giáo án, hiện khi người xem không phải chủ.
  final String? coachName;
  final void Function(TrainingDay day)? onOpenDay;
  final void Function(TrainingDay day)? onToggleDone;

  @override
  State<PlanScheduleView> createState() => _PlanScheduleViewState();
}

class _PlanScheduleViewState extends State<PlanScheduleView> {
  late int _week = widget.plan.currentWeek(widget.today);

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final today = widget.today;
    final palette = context.runNowPalette;
    final week = _week.clamp(1, math.max(1, plan.weeks)).toInt();
    final todayDay = plan.days
        .where((d) => _sameDay(d.date, today))
        .firstOrNull;
    final sessions = plan.daysOfWeek(week).where((d) => !d.isRest).toList();
    final theme = plan.weekTheme(week);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Hero(plan: plan, today: today, coachName: widget.coachName),
        const SizedBox(height: 18),
        _WeekVolume(
          plan: plan,
          selected: week,
          current: plan.currentWeek(today),
          onSelect: (w) => setState(() => _week = w),
        ),
        if (todayDay != null) ...[
          const SizedBox(height: 16),
          _TodayCard(
            day: todayDay,
            onOpen: widget.onOpenDay,
            onToggleDone: widget.onToggleDone,
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
          child: Text(
            [
              'TUẦN $week',
              '${_num(plan.weekKm(week))} KM',
              if (theme != null) theme.toUpperCase(),
            ].join(' · '),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ),
        for (final d in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SessionRow(
              day: d,
              isToday: _sameDay(d.date, today),
              onTap: widget.onOpenDay == null
                  ? null
                  : () => widget.onOpenDay!(d),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────── tiến độ

class _Hero extends StatelessWidget {
  const _Hero({required this.plan, required this.today, this.coachName});

  final TrainingPlan plan;
  final DateTime today;
  final String? coachName;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final warm = palette.warmMark;
    final total = plan.totalSessions;
    final done = plan.doneSessions;
    final streak = plan.streak(today);
    final meta = [
      if (plan.goalDistanceKm > 0) '${_num(plan.goalDistanceKm)} km',
      _dm(plan.targetDate),
      'còn ${plan.daysLeft(today)} ngày',
    ].join(' · ');
    final muted = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: palette.textMuted,
    );

    return Row(
      children: [
        Semantics(
          label: 'Đã xong $done trên $total buổi',
          child: ExcludeSemantics(
            child: SizedBox(
              width: 104,
              height: 70,
              child: CustomPaint(
                painter: _TrackRingPainter(
                  ratio: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
                  lane: palette.border,
                  fill: palette.accent,
                  square: palette.isIron,
                ),
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      text: '$done',
                      style: palette.heading(
                        TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: palette.ink,
                        ),
                      ),
                      children: [
                        TextSpan(
                          text: '/$total',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                palette.title(plan.goal),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: palette.heading(
                  TextStyle(
                    fontSize: 19,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: palette.ink,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(meta, style: muted),
              if (streak > 0 || coachName != null) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (coachName != null)
                      Flexible(
                        child: Text(
                          'HLV $coachName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    if (coachName != null && streak > 0)
                      Text(' · ', style: muted),
                    if (streak > 0) ...[
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 15,
                        color: warm,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$streak buổi liền',
                        style: muted.copyWith(
                          color: warm,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Vòng tiến độ hình đường chạy sân vận động, tô dần theo chiều kim đồng hồ.
class _TrackRingPainter extends CustomPainter {
  const _TrackRingPainter({
    required this.ratio,
    required this.lane,
    required this.fill,
    required this.square,
  });

  final bool square;

  final double ratio;
  final Color lane;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final track = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = (square ? StrokeCap.butt : StrokeCap.round)
      ..color = lane;
    canvas.drawPath(track, paint);
    if (ratio <= 0) return;
    final metric = track.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * ratio),
      paint..color = fill,
    );
  }

  @override
  bool shouldRepaint(_TrackRingPainter old) =>
      old.ratio != ratio || old.lane != lane || old.fill != fill;
}

// ───────────────────────────────────────────────────── khối lượng từng tuần

class _WeekVolume extends StatelessWidget {
  const _WeekVolume({
    required this.plan,
    required this.selected,
    required this.current,
    required this.onSelect,
  });

  final TrainingPlan plan;
  final int selected;
  final int current;
  final ValueChanged<int> onSelect;

  static const _order = [
    WorkoutType.easy,
    WorkoutType.long,
    WorkoutType.tempo,
    WorkoutType.interval,
    WorkoutType.race,
  ];
  static const _barHeight = 84.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final warm = palette.warmMark;
    var maxKm = 0.0;
    for (var w = 1; w <= plan.weeks; w++) {
      maxKm = math.max(maxKm, plan.weekKm(w));
    }
    final peak = plan.peakWeek;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: palette.radius(18),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var w = 1; w <= plan.weeks; w++)
            Expanded(
              child: _column(
                context,
                palette,
                warm,
                week: w,
                maxKm: maxKm,
                isPeak: plan.weeks > 2 && w == peak,
              ),
            ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context,
    RunNowPalette palette,
    Color warm, {
    required int week,
    required double maxKm,
    required bool isPeak,
  }) {
    final days = plan.daysOfWeek(week);
    final isRace = days.any((d) => d.type == WorkoutType.race);
    final on = week == selected;
    final km = plan.weekKm(week);
    final tag = isRace ? 'đua' : (isPeak ? 'đỉnh' : '');

    return Semantics(
      button: true,
      selected: on,
      label: 'Tuần $week, ${_num(km)} km',
      child: InkWell(
        key: ValueKey('plan-week-$week'),
        onTap: () => onSelect(week),
        borderRadius: palette.radius(10),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 14,
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isRace ? warm : palette.textMuted,
                  ),
                ),
              ),
              SizedBox(
                height: _barHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: on ? 1 : 0.42,
                    child: ClipRRect(
                      borderRadius: palette.radius(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Buổi nặng nằm trên, nền chạy nhẹ nằm dưới.
                          for (final type in _order.reversed)
                            if (_typeKm(days, type) case final v when v > 0)
                              Container(
                                width: 22,
                                height: maxKm == 0 ? 0 : _barHeight * v / maxKm,
                                color: workoutLoadColor(type, palette),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'T$week',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                  color: on ? palette.ink : palette.textMuted,
                ),
              ),
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  shape: context.runNowPalette.round,
                  color: week == current ? warm : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static double _typeKm(List<TrainingDay> days, WorkoutType type) => days
      .where((d) => d.type == type)
      .fold(0, (sum, d) => sum + (d.distanceKm ?? 0));
}

// ─────────────────────────────────────────────────────────── hôm nay

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day, this.onOpen, this.onToggleDone});

  final TrainingDay day;
  final void Function(TrainingDay)? onOpen;
  final void Function(TrainingDay)? onToggleDone;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final warm = palette.warmMark;
    final night = palette.accentNight;
    const fg = Colors.white;
    final soft = fg.withValues(alpha: 0.68);
    final stats = [
      if (day.distanceKm != null) '${_num(day.distanceKm!)} km',
      if (day.paceHint != null) 'pace ${day.paceHint}',
    ].join(' · ');

    return Material(
      color: night,
      borderRadius: palette.radius(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen == null ? null : () => onOpen!(day),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'HÔM NAY · ${day.type.purposeTag.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: warm,
                      ),
                    ),
                  ),
                  if (!day.isRest)
                    IntensityBars(
                      level: day.type.intensity,
                      color: fg,
                      idle: fg.withValues(alpha: 0.22),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                palette.title(day.title),
                style: palette.heading(
                  TextStyle(
                    fontSize: 25,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: fg,
                  ),
                ),
              ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  stats,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: soft,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.09),
                  borderRadius: palette.radius(12),
                ),
                child: Text.rich(
                  TextSpan(
                    text: 'Để làm gì: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(
                        text: day.purposeText,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: fg,
                  ),
                ),
              ),
              if (!day.isRest && onToggleDone != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: onOpen == null ? null : () => onOpen!(day),
                          style: FilledButton.styleFrom(
                            backgroundColor: fg,
                            foregroundColor: night,
                            // Padding dọc của theme ăn hết 48 pt, cắt chân chữ.
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: palette.radius(15),
                            ),
                          ),
                          icon: Icon(
                            day.done
                                ? Icons.done_all_rounded
                                : Icons.play_arrow_rounded,
                            size: 20,
                          ),
                          label: Text(
                            day.done ? 'Đã xong' : 'Bắt đầu',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: day.done ? 'Bỏ đánh dấu xong' : 'Đánh dấu xong',
                      child: Material(
                        color: day.done ? fg : fg.withValues(alpha: 0.12),
                        borderRadius: palette.radius(15),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey('plan-today-done'),
                          onTap: () => onToggleDone!(day),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.check_rounded,
                              color: day.done ? night : fg,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── một buổi trong tuần

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.day, required this.isToday, this.onTap});

  final TrainingDay day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final warm = palette.warmMark;
    final color = workoutLoadColor(day.type, palette);
    final stats = [
      if (day.distanceKm != null) '${_num(day.distanceKm!)} km',
      if (day.paceHint != null) day.paceHint!,
    ].join(' · ');

    return Material(
      color: palette.glassStart,
      shape: RoundedRectangleBorder(
        borderRadius: palette.radius(14),
        side: BorderSide(color: isToday ? warm : palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 11, 0, 11),
                child: SizedBox(
                  width: 44,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _shortDay(day.date),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isToday ? warm : palette.ink,
                        ),
                      ),
                      Text(
                        _dm(day.date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: day.title,
                          children: [
                            if (stats.isNotEmpty)
                              TextSpan(
                                text: '  $stats',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textMuted,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                          decoration: day.done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.purposeText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
                child: Center(
                  child: day.done
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 22,
                          color: palette.accent,
                          semanticLabel: 'Đã xong',
                        )
                      : IntensityBars(
                          level: day.type.intensity,
                          color: color,
                          idle: palette.border,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Năm vạch cao dần, tô [level] vạch đầu: liếc là biết buổi nặng hay nhẹ.
class IntensityBars extends StatelessWidget {
  const IntensityBars({
    super.key,
    required this.level,
    required this.color,
    required this.idle,
  });

  final int level;
  final Color color;
  final Color idle;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Độ nặng $level trên 5',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 5; i++)
          Container(
            width: 4,
            height: 5.0 + i * 2.6,
            margin: const EdgeInsets.only(left: 2.5),
            decoration: BoxDecoration(
              color: i <= level ? color : idle,
              borderRadius: context.runNowPalette.radius(2),
            ),
          ),
      ],
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _shortDay(DateTime d) =>
    d.weekday == DateTime.sunday ? 'CN' : 'T${d.weekday + 1}';
