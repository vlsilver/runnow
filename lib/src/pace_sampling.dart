import 'dart:math' as math;

class PaceSample {
  const PaceSample({
    required this.distanceMeters,
    required this.paceSecondsPerKm,
  });

  final double distanceMeters;
  final double paceSecondsPerKm;
}

List<PaceSample> standardizePaceSamples({
  required double activityDistanceMeters,
  required List<double>? distances,
  required List<double>? speeds,
}) {
  if (distances == null || speeds == null) return const [];
  final sampleCount = distances.length < speeds.length
      ? distances.length
      : speeds.length;
  if (sampleCount == 0 || activityDistanceMeters <= 0) return const [];

  final intervalMeters = activityDistanceMeters > 1000 ? 250.0 : 100.0;
  final lastBucket = math.max(
    (activityDistanceMeters / intervalMeters).ceil() - 1,
    0,
  );
  final buckets = <int, List<double>>{};
  for (var index = 0; index < sampleCount; index++) {
    final distance = distances[index];
    final speed = speeds[index];
    if (distance < 0 || speed < 0.8) continue;
    final bucket = math.min((distance / intervalMeters).floor(), lastBucket);
    buckets.putIfAbsent(bucket, () => []).add(speed);
  }

  final sortedBuckets = buckets.keys.toList()..sort();
  return [
    for (final bucket in sortedBuckets)
      PaceSample(
        distanceMeters: math.min(
          (bucket + 1) * intervalMeters,
          activityDistanceMeters,
        ),
        paceSecondsPerKm:
            1000 /
            (buckets[bucket]!.reduce((left, right) => left + right) /
                buckets[bucket]!.length),
      ),
  ];
}
