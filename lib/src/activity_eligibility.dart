import 'package:myrun/src/models.dart';

const minimumOfficialRunNowDistanceMeters = 500.0;
const stravaDuplicateOverlapThreshold = 0.30;

bool isRunNowActivityDistanceEligible(ActivitySummary activity) =>
    activity.source == ActivitySource.runnow &&
    activity.kind == ActivityKind.run &&
    activity.distanceMeters >= minimumOfficialRunNowDistanceMeters;

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
  final duplicates = preferredStravaDuplicates(all);
  final selected = <ActivitySummary>[
    for (final activity in all)
      if (activity.source == ActivitySource.strava ||
          (isRunNowActivityDistanceEligible(activity) &&
              !duplicates.containsKey(activity.id)))
        activity,
  ];
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
