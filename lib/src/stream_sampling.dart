import 'dart:math' as math;

class DistanceSample {
  const DistanceSample({required this.distanceMeters, required this.value});

  final double distanceMeters;
  final double value;
}

List<double> cumulativeEnergyKilojoules({
  required List<double>? watts,
  required List<double>? times,
}) {
  if (watts == null || times == null) return const [];
  final sampleCount = math.min(watts.length, times.length);
  if (sampleCount == 0) return const [];

  var energyKilojoules = 0.0;
  return [
    for (var index = 0; index < sampleCount; index++)
      if (index == 0)
        0
      else
        energyKilojoules +=
            math.max(times[index] - times[index - 1], 0) *
            math.max((watts[index - 1] + watts[index]) / 2, 0) /
            1000,
  ];
}

List<DistanceSample> standardizeDistanceSeries({
  required List<double>? distances,
  required List<double> values,
  required double intervalMeters,
  bool Function(double value)? accept,
}) {
  if (distances == null || distances.isEmpty || values.isEmpty) return const [];
  final sampleCount = math.min(distances.length, values.length);
  final activityDistanceMeters = distances.take(sampleCount).reduce(math.max);
  if (activityDistanceMeters <= 0 || intervalMeters <= 0) return const [];

  final lastBucket = math.max(
    (activityDistanceMeters / intervalMeters).ceil() - 1,
    0,
  );
  final buckets = <int, List<double>>{};
  for (var index = 0; index < sampleCount; index++) {
    final distance = distances[index];
    final value = values[index];
    if (distance < 0 || !value.isFinite || accept?.call(value) == false) {
      continue;
    }
    final bucket = math.min((distance / intervalMeters).floor(), lastBucket);
    buckets.putIfAbsent(bucket, () => []).add(value);
  }

  final sortedBuckets = buckets.keys.toList()..sort();
  return [
    for (final bucket in sortedBuckets)
      DistanceSample(
        distanceMeters: math.min(
          (bucket + 1) * intervalMeters,
          activityDistanceMeters,
        ),
        value:
            buckets[bucket]!.reduce((left, right) => left + right) /
            buckets[bucket]!.length,
      ),
  ];
}
