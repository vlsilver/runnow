import 'package:myrun/src/models.dart';

const minimumOfficialRunNowDistanceMeters = 500.0;
const stravaDuplicateOverlapThreshold = 0.30;

/// Buổi chạy từ nguồn PHỤ (3i native hoặc Apple Health) đủ điều kiện tính vào
/// stats/kèo/journal: là Run + đủ cự ly tối thiểu. Strava xét riêng (luôn tính).
/// (Tên cũ `isRunNowActivityDistanceEligible` — nay gồm cả apple_health.)
bool isCountedNonStravaRun(ActivitySummary activity) =>
    (activity.source == ActivitySource.runnow ||
        activity.source == ActivitySource.appleHealth) &&
    activity.kind == ActivityKind.run &&
    activity.distanceMeters >= minimumOfficialRunNowDistanceMeters;

/// Ưu tiên giữ khi hai buổi nguồn-phụ TRÙNG nhau: 3i native (có GPS/route) hơn
/// Apple Health (chỉ cự ly + thời gian).
int _nonStravaSourcePriority(ActivitySource source) =>
    source == ActivitySource.runnow ? 2 : 1;

bool isPotentialStravaRecording(ActivitySummary activity) =>
    activity.source == ActivitySource.strava &&
    (activity.kind == ActivityKind.run ||
        activity.kind == ActivityKind.trailRun ||
        activity.kind == ActivityKind.virtualRun);

/// Fraction of [candidate]'s elapsed recording interval covered by [other].
///
/// The candidate is the 3i session being evaluated. Using its duration as
/// the denominator correctly treats a short 3i recording fully contained
/// in a longer Strava activity as a duplicate.
double activityOverlapRatio(ActivitySummary candidate, ActivitySummary other) {
  final candidateDuration = _recordingDuration(candidate);
  final otherDuration = _recordingDuration(other);
  final candidateEnd = candidate.startedAt.add(candidateDuration);
  final otherEnd = other.startedAt.add(otherDuration);
  final overlapStart = candidate.startedAt.isAfter(other.startedAt)
      ? candidate.startedAt
      : other.startedAt;
  final overlapEnd = candidateEnd.isBefore(otherEnd) ? candidateEnd : otherEnd;
  if (!overlapEnd.isAfter(overlapStart)) return 0;
  return overlapEnd.difference(overlapStart).inMilliseconds /
      candidateDuration.inMilliseconds;
}

ActivitySummary? preferredStravaDuplicate(
  ActivitySummary runNowActivity,
  Iterable<ActivitySummary> activities,
) {
  if (runNowActivity.source != ActivitySource.runnow) return null;
  return _StravaIntervalIndex(activities).preferredDuplicate(runNowActivity);
}

/// Resolves all RunNow/Strava overlaps in one indexed pass.
///
/// Building the index once avoids scanning every activity for every RunNow
/// session when a Firestore snapshot is parsed. If several Strava activities
/// overlap, the first one in [activities] wins to preserve the previous API's
/// deterministic behavior.
Map<String, ActivitySummary> preferredStravaDuplicates(
  Iterable<ActivitySummary> activities,
) {
  final all = activities.toList();
  final index = _StravaIntervalIndex(all);
  final duplicates = <String, ActivitySummary>{};
  for (final activity in all) {
    if (activity.source != ActivitySource.runnow) continue;
    final duplicate = index.preferredDuplicate(activity);
    if (duplicate != null) duplicates[activity.id] = duplicate;
  }
  return duplicates;
}

/// Canonical activity view consumed by official stats and contracts.
///
/// Strava remains authoritative when both sources record the same run. The
/// underlying 3i document is retained for route inspection and GPS tuning.
List<ActivitySummary> selectOfficialActivities(
  Iterable<ActivitySummary> activities,
) {
  final all = activities.toList();
  // Strava luôn tính; run/trail/virtual của Strava là pool dedup cho nguồn phụ.
  final stravaPool = [for (final a in all) if (isPotentialStravaRecording(a)) a];
  final selected = <ActivitySummary>[
    for (final a in all)
      if (a.source == ActivitySource.strava) a,
  ];
  // Nguồn phụ (3i native + Apple Health): xét theo ưu tiên nguồn (native > health)
  // rồi id → kết quả ỔN ĐỊNH. Loại nếu trùng một buổi Strava HOẶC trùng một buổi
  // nguồn-phụ ĐÃ giữ — chống đếm đôi cùng một lần chạy ở nhiều nguồn (vd Apple
  // Health + 3i native) hoặc bản Health bị sửa (2 doc trùng thời gian).
  final nonStrava = [for (final a in all) if (isCountedNonStravaRun(a)) a]
    ..sort((x, y) {
      final byPrio = _nonStravaSourcePriority(
        y.source,
      ).compareTo(_nonStravaSourcePriority(x.source));
      return byPrio != 0 ? byPrio : x.id.compareTo(y.id);
    });
  final kept = <ActivitySummary>[];
  for (final a in nonStrava) {
    final isDup =
        stravaPool.any(
          (s) => activityOverlapRatio(a, s) > stravaDuplicateOverlapThreshold,
        ) ||
        kept.any(
          (k) => activityOverlapRatio(a, k) > stravaDuplicateOverlapThreshold,
        );
    if (!isDup) {
      kept.add(a);
      selected.add(a);
    }
  }
  selected.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return selected;
}

Duration _recordingDuration(ActivitySummary activity) {
  final seconds = activity.elapsedTimeSeconds > 0
      ? activity.elapsedTimeSeconds
      : activity.movingTimeSeconds > 0
      ? activity.movingTimeSeconds
      : 1;
  return Duration(seconds: seconds);
}

class _StravaIntervalIndex {
  _StravaIntervalIndex(Iterable<ActivitySummary> activities)
    : _intervals = _buildIntervals(activities) {
    var maxEnd = -1;
    for (final interval in _intervals) {
      if (interval.endMilliseconds > maxEnd) {
        maxEnd = interval.endMilliseconds;
      }
      _prefixMaxEndMilliseconds.add(maxEnd);
    }
  }

  final List<_IndexedActivityInterval> _intervals;
  final List<int> _prefixMaxEndMilliseconds = [];

  ActivitySummary? preferredDuplicate(ActivitySummary candidate) {
    if (candidate.source != ActivitySource.runnow || _intervals.isEmpty) {
      return null;
    }
    final candidateStart = candidate.startedAt.millisecondsSinceEpoch;
    final candidateEnd = candidate.startedAt
        .add(_recordingDuration(candidate))
        .millisecondsSinceEpoch;
    var index = _firstStartAtOrAfter(candidateEnd) - 1;
    _IndexedActivityInterval? preferred;
    while (index >= 0 && _prefixMaxEndMilliseconds[index] > candidateStart) {
      final interval = _intervals[index];
      if (interval.endMilliseconds > candidateStart &&
          activityOverlapRatio(candidate, interval.activity) >
              stravaDuplicateOverlapThreshold &&
          (preferred == null ||
              interval.originalIndex < preferred.originalIndex)) {
        preferred = interval;
      }
      index--;
    }
    return preferred?.activity;
  }

  int _firstStartAtOrAfter(int timestamp) {
    var low = 0;
    var high = _intervals.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_intervals[middle].startMilliseconds < timestamp) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static List<_IndexedActivityInterval> _buildIntervals(
    Iterable<ActivitySummary> activities,
  ) {
    final intervals = <_IndexedActivityInterval>[];
    var originalIndex = 0;
    for (final activity in activities) {
      if (isPotentialStravaRecording(activity)) {
        intervals.add(
          _IndexedActivityInterval(
            activity: activity,
            originalIndex: originalIndex,
          ),
        );
      }
      originalIndex++;
    }
    intervals.sort(
      (left, right) =>
          left.startMilliseconds.compareTo(right.startMilliseconds),
    );
    return intervals;
  }
}

class _IndexedActivityInterval {
  _IndexedActivityInterval({
    required this.activity,
    required this.originalIndex,
  }) : startMilliseconds = activity.startedAt.millisecondsSinceEpoch,
       endMilliseconds = activity.startedAt
           .add(_recordingDuration(activity))
           .millisecondsSinceEpoch;

  final ActivitySummary activity;
  final int originalIndex;
  final int startMilliseconds;
  final int endMilliseconds;
}
