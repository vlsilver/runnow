import 'package:myrun/src/models.dart';

class TrainingSummary {
  const TrainingSummary({
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.activityCount,
  });

  final double distanceMeters;
  final int movingTimeSeconds;
  final int activityCount;

  double? get paceSecondsPerKm =>
      distanceMeters <= 0 ? null : movingTimeSeconds / (distanceMeters / 1000);
}

class TrainingComparison {
  const TrainingComparison({required this.current, required this.previous});

  final TrainingSummary current;
  final TrainingSummary previous;

  double? get distanceChangeRatio {
    if (previous.distanceMeters <= 0) return null;
    return (current.distanceMeters - previous.distanceMeters) /
        previous.distanceMeters;
  }
}

class ActivityKindDistance {
  const ActivityKindDistance({
    required this.kind,
    required this.distanceMeters,
  });

  final ActivityKind kind;
  final double distanceMeters;
}

class DailyDistance {
  const DailyDistance({required this.date, required this.distanceMeters});

  final DateTime date;
  final double distanceMeters;
}

class DisciplineDay {
  const DisciplineDay({required this.date, required this.distanceMeters});

  final DateTime date;
  final double distanceMeters;

  bool get active => distanceMeters > 0;
}

class DisciplineStats {
  const DisciplineStats({
    required this.days,
    required this.activeDays,
    required this.currentDayStreak,
    required this.weeklyStreak,
    required this.averageActivitiesPerWeek,
    required this.totalDistanceMeters,
    required this.longestDistanceMeters,
    required this.fastestPaceSecondsPerKm,
  });

  final List<DisciplineDay> days;
  final int activeDays;
  final int currentDayStreak;
  final int weeklyStreak;
  final double averageActivitiesPerWeek;
  final double totalDistanceMeters;
  final double longestDistanceMeters;
  final double? fastestPaceSecondsPerKm;

  double get activeRatio => days.isEmpty ? 0 : activeDays / days.length;
}

TrainingComparison rollingSevenDayComparison(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final tomorrow = _day(now).add(const Duration(days: 1));
  final currentStart = tomorrow.subtract(const Duration(days: 7));
  final previousStart = currentStart.subtract(const Duration(days: 7));
  return TrainingComparison(
    current: trainingSummary(activities, start: currentStart, end: tomorrow),
    previous: trainingSummary(
      activities,
      start: previousStart,
      end: currentStart,
    ),
  );
}

TrainingComparison currentWeekComparison(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final currentStart = startOfCurrentWeek(now);
  final currentEnd = currentStart.add(const Duration(days: 7));
  final previousStart = currentStart.subtract(const Duration(days: 7));
  return TrainingComparison(
    current: trainingSummary(activities, start: currentStart, end: currentEnd),
    previous: trainingSummary(
      activities,
      start: previousStart,
      end: currentStart,
    ),
  );
}

List<DailyDistance> rollingSevenDayDistances(
  List<ActivitySummary> activities,
  DateTime now,
) {
  return _dailyDistances(activities, startOfRollingSevenDays(now));
}

List<DailyDistance> currentWeekDistances(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final start = startOfCurrentWeek(now);
  return _dailyDistances(activities, start);
}

TrainingSummary trainingSummary(
  List<ActivitySummary> activities, {
  required DateTime start,
  required DateTime end,
}) {
  final selected = activities.where(
    (activity) =>
        !activity.startedAt.isBefore(start) && activity.startedAt.isBefore(end),
  );
  return TrainingSummary(
    distanceMeters: selected.fold(
      0,
      (sum, activity) => sum + activity.distanceMeters,
    ),
    movingTimeSeconds: selected.fold(
      0,
      (sum, activity) => sum + activity.movingTimeSeconds,
    ),
    activityCount: selected.length,
  );
}

TrainingSummary currentMonthSummary(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  return trainingSummary(activities, start: start, end: end);
}

List<ActivityKindDistance> distanceByActivityKind(
  List<ActivitySummary> activities, {
  required DateTime start,
  required DateTime end,
}) {
  final totals = <ActivityKind, double>{};
  for (final activity in activities) {
    if (activity.startedAt.isBefore(start) ||
        !activity.startedAt.isBefore(end)) {
      continue;
    }
    totals.update(
      activity.kind,
      (distance) => distance + activity.distanceMeters,
      ifAbsent: () => activity.distanceMeters,
    );
  }
  final result = [
    for (final entry in totals.entries)
      ActivityKindDistance(kind: entry.key, distanceMeters: entry.value),
  ];
  result.sort(
    (left, right) => right.distanceMeters.compareTo(left.distanceMeters),
  );
  return result;
}

DisciplineStats personalDisciplineStats(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final today = _day(now);
  final start = today.subtract(const Duration(days: 29));
  final tomorrow = today.add(const Duration(days: 1));
  final dailyDistance = <DateTime, double>{
    for (var index = 0; index < 30; index++)
      start.add(Duration(days: index)): 0,
  };
  var totalDistance = 0.0;
  var longestDistance = 0.0;
  double? fastestPace;
  var recentActivityCount = 0;
  final fourWeeksAgo = tomorrow.subtract(const Duration(days: 28));
  for (final activity in activities) {
    if (!activity.startedAt.isBefore(start) &&
        activity.startedAt.isBefore(tomorrow)) {
      final day = _day(activity.startedAt);
      dailyDistance[day] = (dailyDistance[day] ?? 0) + activity.distanceMeters;
      totalDistance += activity.distanceMeters;
      if (activity.distanceMeters > longestDistance) {
        longestDistance = activity.distanceMeters;
      }
      final pace = activity.paceSecondsPerKm;
      if (pace != null &&
          pace > 0 &&
          (fastestPace == null || pace < fastestPace)) {
        fastestPace = pace;
      }
    }
    if (!activity.startedAt.isBefore(fourWeeksAgo) &&
        activity.startedAt.isBefore(tomorrow)) {
      recentActivityCount++;
    }
  }
  final days = [
    for (final entry in dailyDistance.entries)
      DisciplineDay(date: entry.key, distanceMeters: entry.value),
  ];
  final activeDaySet = {
    for (final day in days)
      if (day.active) day.date,
  };
  return DisciplineStats(
    days: days,
    activeDays: activeDaySet.length,
    currentDayStreak: _currentDayStreak(activeDaySet, today),
    weeklyStreak: _weeklyActivityStreak(activities, today),
    averageActivitiesPerWeek: recentActivityCount / 4,
    totalDistanceMeters: totalDistance,
    longestDistanceMeters: longestDistance,
    fastestPaceSecondsPerKm: fastestPace,
  );
}

DateTime startOfRollingSevenDays(DateTime now) =>
    _day(now).subtract(const Duration(days: 6));

DateTime endOfToday(DateTime now) => _day(now).add(const Duration(days: 1));

DateTime startOfCurrentWeek(DateTime now) =>
    _day(now).subtract(Duration(days: now.weekday - 1));

List<DailyDistance> _dailyDistances(
  List<ActivitySummary> activities,
  DateTime start,
) {
  final buckets = <DateTime, double>{
    for (var index = 0; index < 7; index++) start.add(Duration(days: index)): 0,
  };
  for (final activity in activities) {
    final day = _day(activity.startedAt);
    if (!buckets.containsKey(day)) continue;
    buckets[day] = buckets[day]! + activity.distanceMeters;
  }
  return [
    for (final entry in buckets.entries)
      DailyDistance(date: entry.key, distanceMeters: entry.value),
  ];
}

int _currentDayStreak(Set<DateTime> activeDays, DateTime today) {
  var cursor = activeDays.contains(today)
      ? today
      : today.subtract(const Duration(days: 1));
  var streak = 0;
  while (activeDays.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

int _weeklyActivityStreak(List<ActivitySummary> activities, DateTime today) {
  final activeWeeks = <DateTime>{};
  for (final activity in activities) {
    activeWeeks.add(startOfCurrentWeek(activity.startedAt));
  }
  var cursor = startOfCurrentWeek(today);
  if (!activeWeeks.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 7));
  }
  var streak = 0;
  while (activeWeeks.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return streak;
}

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
