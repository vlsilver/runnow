import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

void main() {
  testWidgets('renders weekly training distance by day', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingVolumeChart(
            now: DateTime(2026, 6, 2),
            period: TrainingVolumePeriod.week,
            activities: [
              _activity(DateTime(2026, 6, 1), 5000),
              _activity(DateTime(2026, 6, 2), 3200),
            ],
          ),
        ),
      ),
    );

    expect(find.text('THEO NGÀY'), findsOneWidget);
    expect(find.text('8.2 km'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);
    expect(find.text('CN'), findsOneWidget);
  });

  testWidgets('renders monthly training distance by month labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingVolumeChart(
            now: DateTime(2026, 6, 15),
            period: TrainingVolumePeriod.month,
            activities: [
              _activity(DateTime(2026, 6, 2), 5000),
              _activity(DateTime(2026, 6, 14), 7000),
            ],
          ),
        ),
      ),
    );

    expect(find.text('THEO TUẦN'), findsOneWidget);
    expect(find.text('12.0 km'), findsWidgets);
    expect(find.text('07/2025'), findsOneWidget);
    expect(find.text('06/2026'), findsOneWidget);
  });

  testWidgets('renders eight week training distance trend', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingVolumeChart(
            now: DateTime(2026, 6, 3),
            period: TrainingVolumePeriod.eightWeeks,
            activities: [
              _activity(DateTime(2026, 4, 14), 5000),
              _activity(DateTime(2026, 6, 2), 7000),
            ],
          ),
        ),
      ),
    );

    expect(find.text('THEO TUẦN'), findsOneWidget);
    expect(find.text('12.0 km'), findsOneWidget);
    expect(find.text('T-7'), findsOneWidget);
    expect(find.text('NAY'), findsOneWidget);
  });

  testWidgets('switches between bar and line chart across time ranges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrainingVolumeChart(
            now: DateTime(2026, 6, 3),
            period: TrainingVolumePeriod.month,
            showControls: true,
            activities: [
              _activity(DateTime(2025, 8, 10), 6000),
              _activity(DateTime(2026, 6, 2), 7000),
            ],
          ),
        ),
      ),
    );

    expect(find.text('KIỂU'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    await tester.tap(find.text('KIỂU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line').last);
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(find.text('RANGE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quý').last);
    await tester.pumpAndSettle();
    expect(find.text('Q2/2026'), findsOneWidget);

    await tester.tap(find.text('RANGE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Năm').last);
    await tester.pumpAndSettle();
    expect(find.text('THEO THÁNG'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });
}

ActivitySummary _activity(DateTime startedAt, double distanceMeters) {
  return ActivitySummary(
    id: startedAt.toIso8601String(),
    name: 'Run',
    kind: ActivityKind.run,
    startedAt: startedAt,
    distanceMeters: distanceMeters,
    movingTimeSeconds: 1800,
    elapsedTimeSeconds: 1900,
  );
}
