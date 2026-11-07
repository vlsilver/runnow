/// Số liệu trang Hồ sơ, dựng từ `periodStats` (backend tính sẵn). Chỉ dùng
/// phần chạy ([PeriodStat.run]) nên pace và kỷ lục không bị đi bộ kéo.
///
/// Hàm thuần: [ProfileStatsData.today] là ngày local của thiết bị, cùng lịch
/// với `period_keys.dart`.
library;

import 'dart:math' as math;

import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/period_keys.dart';
import 'package:myrun/src/training_power.dart';

enum ProfilePeriod { day, week, month, year }

enum ProfileMetric { distance, time, pace }

const _zero = LeaderboardStats(
  distanceMeters: 0,
  movingTimeSeconds: 0,
  activityCount: 0,
  activeDays: 0,
  longestDistanceMeters: 0,
  fastestPaceSecondsPerKm: null,
);

/// Mục tiêu số ngày chạy, vẽ thành vạch trên cột Đều đặn.
const weeklyGoalDays = 3;
const monthlyGoalDays = 12;
const yearlyGoalDays = 150;

/// Lưới Đều đặn kỳ Ngày: 5 tuần, thứ 2 đầu hàng.
const consistencyGridWeeks = 5;

/// Biểu đồ Tiến bộ kỳ Ngày: 14 ngày gần nhất, so với 14 ngày trước đó.
const progressDayCount = 14;

DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Các khoảng doc `day` trang Hồ sơ cần, mỗi phần tử là (từ, tới) tính cả hai
/// đầu: đủ cho lưới 5 tuần, 28 ngày của biểu đồ Ngày, cùng kỳ tuần và tháng
/// trước; thêm tháng này của năm ngoái cho cùng kỳ năm trước.
List<(String, String)> profileDayRanges(DateTime today) {
  final t = _date(today);
  final gridStart = t.subtract(
    Duration(days: t.weekday - 1 + 7 * (consistencyGridWeeks - 1)),
  );
  final progressStart = t.subtract(
    const Duration(days: 2 * progressDayCount - 1),
  );
  final prevMonthStart = DateTime(t.year, t.month - 1, 1);
  final from = [
    gridStart,
    progressStart,
    prevMonthStart,
  ].reduce((a, b) => a.isBefore(b) ? a : b);
  final lastYearMonth = DateTime(t.year - 1, t.month, 1);
  final lastYearDay = DateTime(
    t.year - 1,
    t.month,
    math.min(t.day, _daysInMonth(t.year - 1, t.month)),
  );
  return [
    (dayKey(from), dayKey(t)),
    (dayKey(lastYearMonth), dayKey(lastYearDay)),
  ];
}

/// periodStats đã tải, theo key của từng loại kỳ.
class ProfileStatsData {
  ProfileStatsData({
    required DateTime today,
    required this.days,
    required this.weeks,
    required this.months,
  }) : today = _date(today);

  final DateTime today;
  final Map<String, LeaderboardStats> days;
  final Map<String, LeaderboardStats> weeks;
  final Map<String, LeaderboardStats> months;

  late final LeaderboardStats lifetime = combineLeaderboardStats(months.values);

  bool get isEmpty => lifetime.activityCount == 0;

  /// Tháng đầu tiên có buổi chạy, dạng `2024-03`.
  String? get firstMonthKey {
    final keys =
        months.entries
            .where((e) => e.value.activityCount > 0)
            .map((e) => e.key)
            .toList()
          ..sort();
    return keys.isEmpty ? null : keys.first;
  }

  LeaderboardStats _day(DateTime d) => days[dayKey(d)] ?? _zero;

  LeaderboardStats _sumDays(DateTime from, DateTime toInclusive) {
    final out = <LeaderboardStats>[];
    for (
      var d = _date(from);
      !d.isAfter(toInclusive);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      out.add(_day(d));
    }
    return combineLeaderboardStats(out);
  }

  LeaderboardStats _year(int year) => combineLeaderboardStats(
    months.entries.where((e) => e.key.startsWith('$year-')).map((e) => e.value),
  );

  int get _firstYear {
    final key = firstMonthKey;
    return key == null ? today.year : int.parse(key.substring(0, 4));
  }

  ConsistencyView consistency(ProfilePeriod period) => switch (period) {
    ProfilePeriod.day => _dayConsistency(),
    ProfilePeriod.week => _barConsistency(
      bars: [
        for (var i = 11; i >= 0; i--)
          _bar(
            weeks[weekKey(today.subtract(Duration(days: 7 * i)))],
            cap: i == 0 ? today.weekday : 7,
            label: weekKey(
              today.subtract(Duration(days: 7 * i)),
            ).split('W').last,
            current: i == 0,
          ),
      ],
      unit: 'tuần',
      range: '12 tuần qua',
      goal: weeklyGoalDays,
    ),
    ProfilePeriod.month => _barConsistency(
      bars: [
        for (var i = 11; i >= 0; i--)
          _monthBar(DateTime(today.year, today.month - i, 1), current: i == 0),
      ],
      unit: 'tháng',
      range: '12 tháng qua',
      goal: monthlyGoalDays,
    ),
    ProfilePeriod.year => _yearConsistency(),
  };

  ConsistencyBar _bar(
    LeaderboardStats? stats, {
    required int cap,
    required String label,
    required bool current,
  }) => ConsistencyBar(
    activeDays: stats?.activeDays ?? 0,
    capDays: cap,
    label: label,
    current: current,
  );

  ConsistencyBar _monthBar(DateTime month, {required bool current}) => _bar(
    months[monthKey(month)],
    cap: current ? today.day : _daysInMonth(month.year, month.month),
    label: 'T${month.month}',
    current: current,
  );

  ConsistencyView _dayConsistency() {
    final start = today.subtract(
      Duration(days: today.weekday - 1 + 7 * (consistencyGridWeeks - 1)),
    );
    final cells = [
      for (var i = 0; i < 7 * consistencyGridWeeks; i++)
        () {
          final d = DateTime(start.year, start.month, start.day + i);
          return ConsistencyCell(
            date: d,
            distanceMeters: _day(d).distanceMeters,
            future: d.isAfter(today),
            today: d == today,
          );
        }(),
    ];
    final past = cells.where((c) => !c.future).toList();
    final active = past.where((c) => c.distanceMeters > 0).length;
    var best = 0;
    var run = 0;
    for (final c in past) {
      run = c.distanceMeters > 0 ? run + 1 : 0;
      best = math.max(best, run);
    }
    final streak = _trailingStreak(
      past.map((c) => c.distanceMeters > 0).toList(),
    );
    return ConsistencyView(
      range: '$consistencyGridWeeks tuần qua',
      headline: '$active/${past.length} ngày có chạy',
      sub: 'Chuỗi hiện tại $streak ngày · dài nhất $best ngày',
      cells: cells,
    );
  }

  ConsistencyView _barConsistency({
    required List<ConsistencyBar> bars,
    required String unit,
    required String range,
    required int goal,
  }) {
    final hit = bars.where((b) => b.activeDays > 0).length;
    final streak = _trailingStreak(bars.map((b) => b.activeDays > 0).toList());
    final done = bars.where((b) => !b.current).toList();
    final avg = done.isEmpty
        ? 0.0
        : done.fold<int>(0, (s, b) => s + b.activeDays) / done.length;
    return ConsistencyView(
      range: range,
      headline: '$hit/${bars.length} $unit có chạy',
      sub: 'Chuỗi $streak $unit · trung bình ${profileDecimal(avg)} ngày/$unit',
      bars: bars,
      goalDays: goal,
      goalLabel: '$goal ngày/$unit',
    );
  }

  ConsistencyView _yearConsistency() {
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays + 1;
    final bars = [
      for (var y = _firstYear; y <= today.year; y++)
        _bar(
          _year(y),
          cap: y == today.year
              ? dayOfYear
              : DateTime(y + 1, 1, 1).difference(DateTime(y, 1, 1)).inDays,
          label: '$y',
          current: y == today.year,
        ),
    ];
    final now = bars.last.activeDays;
    final perWeek = profileDecimal(now / dayOfYear * 7);
    final lastYear = bars.length > 1 ? bars[bars.length - 2].activeDays : null;
    return ConsistencyView(
      range: 'Từ năm $_firstYear',
      headline: '$now ngày chạy năm nay',
      sub: lastYear == null
          ? 'Trung bình $perWeek ngày/tuần'
          : 'Năm ngoái $lastYear ngày · trung bình $perWeek ngày/tuần',
      bars: bars,
      goalDays: yearlyGoalDays,
      goalLabel: '$yearlyGoalDays ngày',
    );
  }

  ProgressView progress(ProfilePeriod period) {
    switch (period) {
      case ProfilePeriod.day:
        final points = [
          for (var i = progressDayCount - 1; i >= 0; i--)
            () {
              final d = DateTime(today.year, today.month, today.day - i);
              return ProgressPoint(
                label: '${d.day}',
                stats: _day(d),
                current: i == 0,
              );
            }(),
        ];
        return ProgressView(
          range: '$progressDayCount ngày qua',
          caption:
              'Tổng $progressDayCount ngày, so với $progressDayCount '
              'ngày trước',
          points: points,
          current: combineLeaderboardStats(points.map((p) => p.stats)),
          previous: _sumDays(
            today.subtract(const Duration(days: 2 * progressDayCount - 1)),
            today.subtract(const Duration(days: progressDayCount)),
          ),
        );
      case ProfilePeriod.week:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final points = [
          for (var i = 11; i >= 0; i--)
            () {
              final key = weekKey(today.subtract(Duration(days: 7 * i)));
              return ProgressPoint(
                label: key.split('W').last,
                stats: weeks[key] ?? _zero,
                current: i == 0,
              );
            }(),
        ];
        return ProgressView(
          range: '12 tuần qua',
          caption: 'Tuần này, so với cùng kỳ tuần trước',
          points: points,
          current: points.last.stats,
          previous: _sumDays(
            monday.subtract(const Duration(days: 7)),
            today.subtract(const Duration(days: 7)),
          ),
        );
      case ProfilePeriod.month:
        final points = [
          for (var i = 11; i >= 0; i--)
            () {
              final m = DateTime(today.year, today.month - i, 1);
              return ProgressPoint(
                label: 'T${m.month}',
                stats: months[monthKey(m)] ?? _zero,
                current: i == 0,
              );
            }(),
        ];
        final prev = DateTime(today.year, today.month - 1, 1);
        return ProgressView(
          range: '12 tháng qua',
          caption: 'Tháng này, so với cùng kỳ tháng trước',
          points: points,
          current: points.last.stats,
          previous: _sumDays(
            prev,
            DateTime(
              prev.year,
              prev.month,
              math.min(today.day, _daysInMonth(prev.year, prev.month)),
            ),
          ),
        );
      case ProfilePeriod.year:
        final points = [
          for (var y = _firstYear; y <= today.year; y++)
            ProgressPoint(
              label: '$y',
              stats: _year(y),
              current: y == today.year,
            ),
        ];
        final last = today.year - 1;
        return ProgressView(
          range: 'Từ năm $_firstYear',
          caption: 'Năm nay, so với cùng kỳ năm trước',
          points: points,
          current: points.last.stats,
          previous: combineLeaderboardStats([
            for (var m = 1; m < today.month; m++)
              months[monthKey(DateTime(last, m, 1))] ?? _zero,
            _sumDays(
              DateTime(last, today.month, 1),
              DateTime(
                last,
                today.month,
                math.min(today.day, _daysInMonth(last, today.month)),
              ),
            ),
          ]),
        );
    }
  }
}

/// Số kỳ liên tiếp có chạy tính từ cuối. Kỳ cuối (đang diễn ra) chưa chạy thì
/// không làm đứt chuỗi.
int _trailingStreak(List<bool> active) {
  var i = active.length - 1;
  if (i >= 0 && !active[i]) i--;
  var streak = 0;
  for (; i >= 0 && active[i]; i--) {
    streak++;
  }
  return streak;
}

class ConsistencyCell {
  const ConsistencyCell({
    required this.date,
    required this.distanceMeters,
    required this.future,
    required this.today,
  });

  final DateTime date;
  final double distanceMeters;
  final bool future;
  final bool today;
}

class ConsistencyBar {
  const ConsistencyBar({
    required this.activeDays,
    required this.capDays,
    required this.label,
    required this.current,
  });

  final int activeDays;

  /// Số ngày của kỳ; kỳ đang diễn ra thì là số ngày đã qua.
  final int capDays;
  final String label;
  final bool current;
}

class ConsistencyView {
  const ConsistencyView({
    required this.range,
    required this.headline,
    required this.sub,
    this.cells = const [],
    this.bars = const [],
    this.goalDays = 0,
    this.goalLabel = '',
  });

  final String range;
  final String headline;
  final String sub;

  /// Chỉ kỳ Ngày.
  final List<ConsistencyCell> cells;

  /// Tuần, Tháng, Năm.
  final List<ConsistencyBar> bars;
  final int goalDays;
  final String goalLabel;
}

class ProgressPoint {
  const ProgressPoint({
    required this.label,
    required this.stats,
    required this.current,
  });

  final String label;
  final LeaderboardStats stats;
  final bool current;
}

class ProgressView {
  const ProgressView({
    required this.range,
    required this.caption,
    required this.points,
    required this.current,
    required this.previous,
  });

  final String range;
  final String caption;
  final List<ProgressPoint> points;
  final LeaderboardStats current;

  /// Cùng kỳ trước, tính tới cùng ngày.
  final LeaderboardStats previous;
}

/// Giá trị để vẽ cột: km, giờ, hoặc pace giây/km (null khi không chạy).
double? metricValue(LeaderboardStats stats, ProfileMetric metric) =>
    switch (metric) {
      ProfileMetric.distance => stats.distanceMeters / 1000,
      ProfileMetric.time => stats.movingTimeSeconds / 3600,
      ProfileMetric.pace => stats.averagePaceSecondsPerKm,
    };

String formatMetric(LeaderboardStats stats, ProfileMetric metric) =>
    switch (metric) {
      ProfileMetric.distance =>
        '${profileDecimal(stats.distanceMeters / 1000)} km',
      ProfileMetric.time => profileHours(stats.movingTimeSeconds),
      ProfileMetric.pace => formatPace(stats.averagePaceSecondsPerKm),
    };

/// So với cùng kỳ trước. null khi kỳ trước không có gì để so.
({String text, bool better})? metricDelta(
  LeaderboardStats current,
  LeaderboardStats previous,
  ProfileMetric metric,
) {
  if (metric == ProfileMetric.pace) {
    final cur = current.averagePaceSecondsPerKm;
    final prev = previous.averagePaceSecondsPerKm;
    if (cur == null || prev == null) return null;
    final diff = (prev - cur).round();
    final mmss =
        '${diff.abs() ~/ 60}:${(diff.abs() % 60).toString().padLeft(2, '0')}';
    if (diff == 0) return (text: 'bằng kỳ trước', better: true);
    return diff > 0
        ? (text: 'nhanh hơn $mmss', better: true)
        : (text: 'chậm hơn $mmss', better: false);
  }
  final cur = metricValue(current, metric)!;
  final prev = metricValue(previous, metric)!;
  if (prev <= 0) return null;
  final pct = ((cur - prev) / prev * 100).round();
  return (text: '${pct >= 0 ? '+' : '−'}${pct.abs()}%', better: pct >= 0);
}

/// Một chữ số thập phân, dấu phẩy: `29,6`.
String profileDecimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Số nguyên có dấu chấm ngăn nghìn: `2.248`.
String profileInt(num v) {
  final s = v.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// Giờ chạy: `2h05`.
String profileHours(int seconds) {
  final minutes = (seconds / 60).round();
  return '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';
}

/// `2024-03` → `03/2024`.
String profileMonthLabel(String monthKey) {
  final parts = monthKey.split('-');
  return parts.length == 2 ? '${parts[1]}/${parts[0]}' : monthKey;
}
