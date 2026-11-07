import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/split_pace_chart.dart';

void main() {
  testWidgets('hiện pace từng km và km nhanh nhất', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SplitPaceChart(
            splits: [
              {'split': 1, 'distanceMeters': 1000, 'movingTimeSeconds': 360},
              {'split': 2, 'distanceMeters': 1000, 'movingTimeSeconds': 300},
            ],
          ),
        ),
      ),
    );

    expect(find.text('Từng km'), findsOneWidget);
    expect(find.text('nhanh nhất km 2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('6:00'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
  });
}
