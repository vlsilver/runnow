import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:myrun/src/widgets/stream_chart.dart';

void main() {
  testWidgets('renders training statistics for available streams', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StreamChart(
              streams: {
                'distance': [0, 1000, 2000],
                'time': [0, 300, 600],
                'velocity_smooth': [2.5, 3.0, 3.5],
                'heartrate': [130, 145, 160],
                'altitude': [10, 18, 12],
                'cadence': [70, 75, 80],
                'watts': [180, 200, 220],
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Nhịp tim'), findsOneWidget);
    expect(find.text('Cao độ'), findsOneWidget);
    expect(find.text('Cadence'), findsOneWidget);
    expect(find.text('Năng lượng'), findsOneWidget);
    expect(find.text('PHÚT / KM'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('MÉT'), findsOneWidget);
    expect(find.text('RPM'), findsOneWidget);
    expect(find.text('KJ'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);

    await tester.tap(find.text('Pace'));
    await tester.pumpAndSettle();

    expect(find.text('TB'), findsOneWidget);
    expect(find.text('MIN'), findsOneWidget);
    expect(find.text('MAX'), findsOneWidget);
    expect(find.text('Quãng đường đã chạy'), findsOneWidget);
    expect(find.text('2.0 km'), findsWidgets);
    expect(find.text('KIỂU'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);
    final dropdowns = find.byWidgetPredicate(
      (widget) => widget is DropdownButton,
    );
    expect(dropdowns, findsNWidgets(2));
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(dropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cột').last);
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('renders time in heart rate zones when heart stream exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeartRateZoneChart(
            streams: {
              'time': [0, 60, 180, 300, 420],
              'heartrate': [120, 135, 155, 175, 190],
            },
          ),
        ),
      ),
    );

    expect(find.text('TIME IN HEART ZONES'), findsOneWidget);
    expect(find.text('Z1'), findsOneWidget);
    expect(find.text('Z5'), findsOneWidget);
    expect(find.textContaining('2:00'), findsWidgets);
  });

  test('calculates heart rate zone durations from stream samples', () {
    final zones = heartRateZoneDurations(
      times: const [0, 60, 180, 300, 420],
      heartRates: const [120, 135, 155, 175, 190],
    );

    expect(zones.map((zone) => zone.seconds), [60, 120, 120, 120, 120]);
  });

  test('shows only the first, middle and last bar axis labels', () {
    const points = [
      FlSpot(0.1, 1),
      FlSpot(0.2, 2),
      FlSpot(0.3, 3),
      FlSpot(0.4, 4),
      FlSpot(0.5, 5),
    ];

    expect(barAxisDistance(0, points), 0.1);
    expect(barAxisDistance(1, points), isNull);
    expect(barAxisDistance(2, points), 0.3);
    expect(barAxisDistance(3, points), isNull);
    expect(barAxisDistance(4, points), 0.5);
  });
}
