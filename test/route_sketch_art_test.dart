import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/route_sketch_art.dart';

void main() {
  test('đặt dáng tuyến vào giữa khung, giữ tỉ lệ', () {
    // Dáng rộng 1000 cao 500 vào khung 100x100: co 0.1 lần, dư 50 theo chiều
    // dọc nên lùi xuống 25.
    final points = fitRouteSketch([
      0,
      500,
      1000,
      500,
      1000,
      0,
    ], const Rect.fromLTWH(0, 0, 100, 100));
    expect(points, const [Offset(0, 75), Offset(100, 75), Offset(100, 25)]);
  });
}
