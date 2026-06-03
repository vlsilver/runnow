import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/formatters.dart';

void main() {
  test('formats metric distance', () {
    expect(formatDistance(8240), '8.24 km');
  });

  test('formats durations with and without hours', () {
    expect(formatDuration(2922), '48:42');
    expect(formatDuration(3723), '1:02:03');
  });

  test('formats pace per kilometer', () {
    expect(formatPace(354.6), '5:55 /km');
    expect(formatPace(null), '--');
  });
}
