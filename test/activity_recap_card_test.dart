import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/widgets/activity_recap_card.dart';

void main() {
  test('builds a cubic path for poster pace telemetry', () {
    final path = smoothPacePath(const [
      Offset(0, 30),
      Offset(40, 10),
      Offset(80, 40),
    ], const Size(80, 50));
    final metrics = path.computeMetrics().toList();

    expect(metrics, hasLength(1));
    expect(metrics.single.length, greaterThan(80));
  });

  testWidgets('renders core training metrics on recap card', (tester) async {
    final activity = ActivitySummary(
      id: '42',
      name: 'Chạy buổi sáng',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 5, 31),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
      averageHeartRate: 150,
      elevationGainMeters: 32,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityRecapCard(
            activity: activity,
            streams: const {
              'distance': [0, 250, 500, 750, 1000],
              'velocity_smooth': [3, 3.2, 3.4, 3.1, 3.5],
            },
          ),
        ),
      ),
    );
    expect(find.text('CHẠY BUỔI SÁNG'), findsOneWidget);
    expect(find.text('RUN // LOGGED'), findsOneWidget);
    expect(find.text('PACE // TELEMETRY'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('5:00 /km'), findsOneWidget);
    expect(find.text('150 bpm'), findsOneWidget);
    expect(find.text('32 m'), findsOneWidget);
  });

  testWidgets('captures recap card as PNG bytes', (tester) async {
    final repaintBoundaryKey = GlobalKey();
    final activity = ActivitySummary(
      id: '42',
      name: 'Chạy buổi sáng',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 5, 31),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityRecapCard(
            activity: activity,
            repaintBoundaryKey: repaintBoundaryKey,
          ),
        ),
      ),
    );
    final boundary =
        repaintBoundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final png = (await tester.runAsync(() => captureRecapPng(boundary)))!;
    expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
  });
}
