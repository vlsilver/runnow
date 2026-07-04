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
  for (final activity in activities) {
    if (!isPotentialStravaRecording(activity)) continue;
    if (activityOverlapRatio(runNowActivity, activity) >
        stravaDuplicateOverlapThreshold) {
      return activity;
    }
  }
  return null;
}

/// Canonical activity view consumed by official stats and contracts.
///
/// Strava remains authoritative when both sources record the same run. The
/// underlying 3i document is retained for route inspection and GPS tuning.
List<ActivitySummary> selectOfficialActivities(
  Iterable<ActivitySummary> activities,
) {
  final all = activities.toList();
  final selected = <ActivitySummary>[
    for (final activity in all)
      if (activity.source == ActivitySource.strava ||
          (isRunNowActivityDistanceEligible(activity) &&
              preferredStravaDuplicate(activity, all) == null))
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
