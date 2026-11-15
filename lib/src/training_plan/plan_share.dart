import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../share.dart';
import '../theme.dart';
import 'plan_schedule_view.dart';
import 'training_plan_models.dart';

/// Link mở giáo án trên web 3i.
Uri planLink(String planId) =>
    Uri.parse('${AppConfig.webBaseUrl}/coach/${Uri.encodeComponent(planId)}');

/// Câu gửi kèm ảnh giáo án: mục tiêu, kèm số buổi đã xong nếu người khoe đang
/// theo giáo án. Giáo án riêng tư thì không kèm link, vì người nhận mở ra cũng
/// không xem được.
String planShareCaption(TrainingPlan plan, String? uid) {
  final line = plan.hasJoined(uid)
      ? '${plan.goal}: ${plan.doneSessions}/${plan.totalSessions} buổi'
      : plan.goal;
  return plan.visibility.isPublic ? '$line\n${planLink(plan.id)}' : line;
}

/// Mở sheet xem trước ảnh giáo án rồi mới khoe. Web không gửi được file nên
/// chỉ gửi chữ.
Future<void> showPlanShare(
  BuildContext context, {
  required TrainingPlan plan,
  required String? currentUid,
  required DateTime today,
  String? coachName,
}) async {
  final caption = planShareCaption(plan, currentUid);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-giao-an.png',
    label: 'Khoe giáo án',
    card: TrainingPlanPoster(plan: plan, today: today, coachName: coachName),
  );
}

/// Ảnh dọc 3:4 để khoe giáo án: phần trăm buổi đã xong, mục tiêu, khối lượng
/// từng tuần, buổi chạy sắp tới.
/// Vừa khít khổ Story; số buổi đã xong là của người đang xem.
class TrainingPlanPoster extends StatelessWidget {
  const TrainingPlanPoster({
    super.key,
    required this.plan,
    required this.today,
    this.coachName,
  });

  final TrainingPlan plan;
  final DateTime today;

  /// Tên người dựng giáo án, hiện khi người khoe không phải chủ.
  final String? coachName;

  static const size = Size(360, 480);

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final total = plan.totalSessions;
    final done = plan.doneSessions;
    final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final streak = plan.streak(today);
    final next = plan.nextSession(today);
    final muted = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: palette.textMuted,
    );
    final label = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
      color: palette.textMuted,
    );
    final meta = [
      if (plan.goalDistanceKm > 0) '${_num(plan.goalDistanceKm)} km',
      _dm(plan.targetDate),
      if (!plan.isOver(today)) 'còn ${plan.daysLeft(today)} ngày',
    ].join(' · ');

    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: palette.radius(20),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      coachName == null
                          ? 'GIÁO ÁN AI'
                          : 'HLV ${coachName!.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: label,
                    ),
                  ),
                  Text(
                    'TUẦN ${plan.currentWeek(today)}/${plan.weeks}',
                    style: label,
                  ),
                ],
              ),
              // Số phần trăm lấy hết chỗ còn lại và tự co khi kiểu chữ cao hơn,
              // để tên hai dòng không đẩy tràn ảnh.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        (ratio * 100).toStringAsFixed(0),
                        style: palette.heading(
                          TextStyle(
                            color: palette.accent,
                            fontSize: 104,
                            height: 0.86,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -4,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                          '%',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                palette.title(plan.goal),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: palette.heading(
                  TextStyle(
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: palette.ink,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$done/$total buổi',
                style: muted.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                borderRadius: palette.radius(999),
                backgroundColor: palette.border,
                color: palette.accent,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ),
                  if (streak > 0) ...[
                    Text(' · ', style: muted),
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 17,
                      color: palette.warmMark,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '$streak buổi liền',
                      style: muted.copyWith(
                        color: palette.warmMark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _WeekBars(plan: plan, current: plan.currentWeek(today)),
              if (next != null) ...[
                const SizedBox(height: 14),
                // Cùng thẻ nền đêm với mục Hôm nay của màn giáo án.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: palette.accentNight,
                    borderRadius: palette.radius(14),
                  ),
                  child: SessionHeadline(
                    day: next,
                    when: _sameDay(next.date, today)
                        ? 'HÔM NAY'
                        : '${_shortDay(next.date)} ${_dm(next.date)}',
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

/// Khối lượng từng tuần, chồng theo loại bài như màn giáo án. Tuần chưa tới
/// thì mờ đi.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.plan, required this.current});

  final TrainingPlan plan;
  final int current;

  static const _order = [
    WorkoutType.race,
    WorkoutType.interval,
    WorkoutType.tempo,
    WorkoutType.long,
    WorkoutType.easy,
  ];
  static const _height = 40.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    var maxKm = 0.0;
    for (var w = 1; w <= plan.weeks; w++) {
      maxKm = math.max(maxKm, plan.weekKm(w));
    }
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var w = 1; w <= plan.weeks; w++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: w <= current ? 1 : 0.42,
                  child: ClipRRect(
                    borderRadius: palette.radius(5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final type in _order)
                          if (_typeKm(w, type) case final km when km > 0)
                            Container(
                              height: maxKm == 0 ? 0 : _height * km / maxKm,
                              color: workoutLoadColor(type, palette),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _typeKm(int week, WorkoutType type) => plan.days
      .where((d) => d.week == week && d.type == type)
      .fold<double>(0, (s, d) => s + (d.distanceKm ?? 0));
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _dm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _shortDay(DateTime d) =>
    d.weekday == DateTime.sunday ? 'CN' : 'T${d.weekday + 1}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
