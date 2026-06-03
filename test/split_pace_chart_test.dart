import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/split_pace_chart.dart';

void main() {
  testWidgets('renders split pace bars and average pace', (tester) async {
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

    expect(find.text('PACE THEO KM'), findsOneWidget);
    expect(find.text('TB 5:30 /km'), findsOneWidget);
    expect(find.text('K1'), findsOneWidget);
    expect(find.text('K2'), findsOneWidget);
    expect(find.text('6:00'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('Nhanh nhất'), findsOneWidget);
  });
}
