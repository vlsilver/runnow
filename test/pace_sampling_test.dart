import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/pace_sampling.dart';

void main() {
  test(
    'standardizes activities longer than one kilometer every 250 meters',
    () {
      final samples = standardizePaceSamples(
        activityDistanceMeters: 1500,
        distances: [0, 100, 249, 250, 499, 500, 749, 750, 1000, 1250, 1500],
        speeds: [3, 3, 3, 4, 4, 5, 5, 6, 6, 6, 6],
      );

      expect(samples.map((sample) => sample.distanceMeters), [
        250,
        500,
        750,
        1000,
        1250,
        1500,
      ]);
      expect(samples.first.paceSecondsPerKm, closeTo(1000 / 3, 0.001));
    },
  );

  test('standardizes activities up to one kilometer every 100 meters', () {
    final samples = standardizePaceSamples(
      activityDistanceMeters: 1000,
      distances: [0, 99, 100, 199, 200, 299],
      speeds: [2, 2, 4, 4, 5, 5],
    );

    expect(samples.map((sample) => sample.distanceMeters), [100, 200, 300]);
  });

  test('ignores pace samples below the running speed floor', () {
    final samples = standardizePaceSamples(
      activityDistanceMeters: 500,
      distances: [0, 100],
      speeds: [0, 2],
    );

    expect(samples, hasLength(1));
    expect(samples.single.distanceMeters, 200);
  });
}
