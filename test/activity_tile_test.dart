import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/activity_tile.dart';

void main() {
  testWidgets('renders an open activity timeline row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTile(
            sequence: 3,
            activity: ActivitySummary(
              id: '42',
              name: 'Night Run',
              kind: ActivityKind.run,
              startedAt: DateTime(2026, 6, 1, 21, 15),
              distanceMeters: 5100,
              movingTimeSeconds: 2646,
              elapsedTimeSeconds: 2700,
              hydrated: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Night Run'), findsOneWidget);
    expect(find.text('5.10 km'), findsOneWidget);
    expect(find.text('8:39 /km'), findsOneWidget);
    expect(find.text('44:06'), findsOneWidget);
    expect(find.text('#03'), findsOneWidget);
    expect(find.text('RUN'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('JUN'), findsOneWidget);
  });

  testWidgets('marks a RunNow recording superseded by Strava', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTile(
            preferredStravaActivityId: 'strava-42',
            activity: ActivitySummary(
              id: 'runnow-42',
              name: '3I Run',
              kind: ActivityKind.run,
              source: ActivitySource.runnow,
              startedAt: DateTime(2026, 7, 5, 6),
              distanceMeters: 5000,
              movingTimeSeconds: 1800,
              elapsedTimeSeconds: 1900,
              hydrated: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('3I Run'), findsOneWidget);
    expect(find.text('TRÙNG · ƯU TIÊN STRAVA'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
  });
}
