import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/stream_sampling.dart';

void main() {
  test('averages stream values into the selected distance range', () {
    final samples = standardizeDistanceSeries(
      distances: [0, 100, 249, 250, 499, 500],
      values: [10, 20, 30, 40, 60, 80],
      intervalMeters: 250,
    );

    expect(samples.map((sample) => sample.distanceMeters), [250, 500]);
    expect(samples.map((sample) => sample.value), [20, 60]);
  });

  test('does not duplicate a sample exactly on the finish line', () {
    final samples = standardizeDistanceSeries(
      distances: [0, 250, 500, 750, 1000],
      values: [1, 2, 3, 4, 5],
      intervalMeters: 250,
    );

    expect(samples.map((sample) => sample.distanceMeters), [
      250,
      500,
      750,
      1000,
    ]);
  });

  test('integrates power stream into cumulative mechanical energy', () {
    final energy = cumulativeEnergyKilojoules(
      watts: [100, 200, 300],
      times: [0, 10, 20],
    );

    expect(energy, [0, 1.5, 4.0]);
  });
}
