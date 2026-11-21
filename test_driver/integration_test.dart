import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Phía Mac của `flutter drive`: ghi số đo vào build/e2e/achievement/report.json
/// và chấm ngưỡng khung hình. Ảnh nằm trên máy test, xem đầu file test.
Future<void> main() async {
  const dir = 'build/e2e/achievement';
  await integrationDriver(
    writeResponseOnFailure: true,
    responseDataCallback: (data) async {
      if (data == null) return;
      final file = File('$dir/report.json');
      await file.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      final slow = _slowFrames(data['perf'] as Map<String, dynamic>? ?? {});
      if (slow.isNotEmpty) {
        stderr.writeln('Khung hình chậm hơn 60 fps (p90 > $_frameBudgetMs ms):');
        slow.forEach(stderr.writeln);
        exit(1);
      }
    },
  );
}

const _frameBudgetMs = 16.7;

/// Thẻ nào có p90 build hoặc raster vượt một khung hình 60 fps.
List<String> _slowFrames(Map<String, dynamic> perf) => [
  for (final MapEntry(:key, :value) in perf.entries)
    for (final metric in const [
      '90th_percentile_frame_build_time_millis',
      '90th_percentile_frame_rasterizer_time_millis',
    ])
      if (((value as Map<String, dynamic>)[metric] as num) > _frameBudgetMs)
        '  $key $metric = ${value[metric]}',
];
