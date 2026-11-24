import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/power_radar_card.dart';

enum PersonalPowerRange { currentWeek, rollingSevenDays, currentMonth }

/// Gộp nhiều `LeaderboardStats` (mỗi cái ứng 1 tháng periodStats) theo đúng
/// quy tắc backend đã định nghĩa: các số cộng dồn được thì sum, riêng
/// longest/fastest thì MAX/MIN vì cộng dồn không có ý nghĩa.
LeaderboardStats combineLeaderboardStats(Iterable<LeaderboardStats> items) {
  var distance = 0.0;
  var movingTime = 0;
  var activityCount = 0;
  var activeDays = 0;
  var longestDistance = 0.0;
  double? fastestPace;
  var elevation = 0.0;
  for (final item in items) {
    distance += item.distanceMeters;
    movingTime += item.movingTimeSeconds;
    activityCount += item.activityCount;
    activeDays += item.activeDays;
    if (item.longestDistanceMeters > longestDistance) {
      longestDistance = item.longestDistanceMeters;
    }
    final pace = item.fastestPaceSecondsPerKm;
    if (pace != null &&
        pace > 0 &&
        (fastestPace == null || pace < fastestPace)) {
      fastestPace = pace;
    }
    elevation += item.elevationGainMeters;
  }
  return LeaderboardStats(
    distanceMeters: distance,
    movingTimeSeconds: movingTime,
    activityCount: activityCount,
    activeDays: activeDays,
    longestDistanceMeters: longestDistance,
    fastestPaceSecondsPerKm: fastestPace,
    elevationGainMeters: elevation,
  );
}

List<PowerRadarMetric> personalPowerMetricsForRange(
  List<ActivitySummary> activities,
  DateTime now,
  PersonalPowerRange range,
) {
  final period = _personalPowerPeriod(now, range);
  final stats = _powerStats(activities, period.start, period.end);
  return _personalPowerMetrics(
    range: range,
    activeRatio: stats.activeRatio,
    activityCount: stats.activityCount,
    totalDistanceMeters: stats.totalDistanceMeters,
    movingTimeSeconds: stats.movingTimeSeconds,
    fastestPaceSecondsPerKm: stats.fastestPaceSecondsPerKm,
  );
}

List<PowerRadarMetric> personalPowerMetricsFromStats(
  LeaderboardStats stats,
  PersonalPowerRange range,
) {
  final period = _personalPowerPeriod(DateTime.now(), range);
  final activeRatio = period.dayCount <= 0
      ? 0.0
      : stats.activeDays / period.dayCount;
  return _personalPowerMetrics(
    range: range,
    activeRatio: activeRatio,
    activityCount: stats.activityCount,
    totalDistanceMeters: stats.distanceMeters,
    movingTimeSeconds: stats.movingTimeSeconds,
    fastestPaceSecondsPerKm: stats.fastestPaceSecondsPerKm,
  );
}

List<PowerRadarMetric> _personalPowerMetrics({
  required PersonalPowerRange range,
  required double activeRatio,
  required int activityCount,
  required double totalDistanceMeters,
  required int movingTimeSeconds,
  required double? fastestPaceSecondsPerKm,
}) {
  final volumeTargetKm = switch (range) {
    PersonalPowerRange.currentMonth => 40.0,
    PersonalPowerRange.currentWeek ||
    PersonalPowerRange.rollingSevenDays => 15.0,
  };
  final loadTargetSeconds = switch (range) {
    PersonalPowerRange.currentMonth => 12 * 3600,
    PersonalPowerRange.currentWeek ||
    PersonalPowerRange.rollingSevenDays => 3 * 3600,
  };
  final avgDistanceMeters = activityCount == 0
      ? 0.0
      : totalDistanceMeters / activityCount;

  return [
    PowerRadarMetric(
      label: 'VOLUME',
      value: formatDistance(totalDistanceMeters),
      score: powerScoreRatio(totalDistanceMeters / 1000, volumeTargetKm),
    ),
    PowerRadarMetric(
      label: 'ACTIVE',
      value: '${(activeRatio * 100).round()}%',
      score: activeRatio.clamp(0.0, 1.0).toDouble(),
    ),
    PowerRadarMetric(
      label: 'LOAD',
      value: formatDuration(movingTimeSeconds),
      score: powerScoreRatio(
        movingTimeSeconds.toDouble(),
        loadTargetSeconds.toDouble(),
      ),
    ),
    PowerRadarMetric(
      label: 'AVG',
      value: formatDistance(avgDistanceMeters),
      score: powerScoreRatio(avgDistanceMeters / 1000, 5),
    ),
    PowerRadarMetric(
      label: 'TỐC',
      value: formatPace(fastestPaceSecondsPerKm),
      score: powerSpeedScore(fastestPaceSecondsPerKm),
    ),
  ];
}

String personalPowerRangeLabel(PersonalPowerRange range) {
  return switch (range) {
    PersonalPowerRange.currentWeek => 'Tuần',
    PersonalPowerRange.rollingSevenDays => '7 ngày',
    PersonalPowerRange.currentMonth => 'Tháng',
  };
}

int averagePowerScore(List<PowerRadarMetric> metrics) {
  if (metrics.isEmpty) return 0;
  final score = metrics.fold<double>(0, (sum, item) => sum + item.score);
  return (score / metrics.length * 100).round();
}

double powerScoreRatio(double value, double target) {
  if (!value.isFinite || !target.isFinite || target <= 0) return 0;
  return (value / target).clamp(0.0, 1.0).toDouble();
}

double powerSpeedScore(double? paceSecondsPerKm) {
  if (paceSecondsPerKm == null ||
      !paceSecondsPerKm.isFinite ||
      paceSecondsPerKm <= 0) {
    return 0;
  }
  const elite = 300.0;
  const relaxed = 540.0;
  return ((relaxed - paceSecondsPerKm) / (relaxed - elite))
      .clamp(0.0, 1.0)
      .toDouble();
}

({DateTime start, DateTime end, int dayCount}) _personalPowerPeriod(
  DateTime now,
  PersonalPowerRange range,
) {
  final today = _day(now);
  return switch (range) {
    PersonalPowerRange.currentWeek => (
      start: startOfCurrentWeek(now),
      end: startOfCurrentWeek(now).add(const Duration(days: 7)),
      dayCount: 7,
    ),
    PersonalPowerRange.rollingSevenDays => (
      start: today.subtract(const Duration(days: 6)),
      end: today.add(const Duration(days: 1)),
      dayCount: 7,
    ),
    PersonalPowerRange.currentMonth => (
      start: DateTime(now.year, now.month),
      end: DateTime(now.year, now.month + 1),
      dayCount: DateTime(
        now.year,
        now.month + 1,
      ).difference(DateTime(now.year, now.month)).inDays,
    ),
  };
}

_PowerStats _powerStats(
  List<ActivitySummary> activities,
  DateTime start,
  DateTime end,
) {
  var totalDistance = 0.0;
  var movingTime = 0;
  var activityCount = 0;
  double? fastestPace;
  final activeDays = <DateTime>{};
  for (final activity in activities) {
    if (activity.startedAt.isBefore(start) ||
        !activity.startedAt.isBefore(end)) {
      continue;
    }
    totalDistance += activity.distanceMeters;
    movingTime += activity.movingTimeSeconds;
    activityCount++;
    activeDays.add(_day(activity.startedAt));
    final pace = activity.paceSecondsPerKm;
    if (pace != null &&
        pace > 0 &&
        (fastestPace == null || pace < fastestPace)) {
      fastestPace = pace;
    }
  }
  final dayCount = end.difference(start).inDays;
  return _PowerStats(
    dayCount: dayCount <= 0 ? 1 : dayCount,
    activeDays: activeDays.length,
    activityCount: activityCount,
    movingTimeSeconds: movingTime,
    totalDistanceMeters: totalDistance,
    fastestPaceSecondsPerKm: fastestPace,
  );
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

class _PowerStats {
  const _PowerStats({
    required this.dayCount,
    required this.activeDays,
    required this.activityCount,
    required this.movingTimeSeconds,
    required this.totalDistanceMeters,
    required this.fastestPaceSecondsPerKm,
  });

  final int dayCount;
  final int activeDays;
  final int activityCount;
  final int movingTimeSeconds;
  final double totalDistanceMeters;
  final double? fastestPaceSecondsPerKm;

  double get activeRatio => activeDays / dayCount;
}
