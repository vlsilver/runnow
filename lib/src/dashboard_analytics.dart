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

List<DailyDistance> rollingSevenDayDistances(
  List<ActivitySummary> activities,
  DateTime now,
) {
  final start = startOfRollingSevenDays(now);
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

DateTime startOfRollingSevenDays(DateTime now) =>
    _day(now).subtract(const Duration(days: 6));

DateTime endOfToday(DateTime now) => _day(now).add(const Duration(days: 1));

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
