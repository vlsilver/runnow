import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/activity_tile.dart';

Widget _app(Widget tile, {bool stravaOn = false}) => ProviderScope(
  overrides: [
    stravaEnabledProvider.overrideWith((ref) => Stream.value(stravaOn)),
  ],
  child: MaterialApp(home: Scaffold(body: tile)),
);

ActivitySummary _stravaRun() => ActivitySummary(
  id: '42',
  name: 'Night Run',
  kind: ActivityKind.run,
  startedAt: DateTime(2026, 6, 1, 21, 15),
  distanceMeters: 5100,
  movingTimeSeconds: 2646,
  elapsedTimeSeconds: 2700,
  hydrated: true,
);

void main() {
  testWidgets('renders an open activity timeline row', (tester) async {
    await tester.pumpWidget(
      _app(
        ActivityTile(
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
    );
    await tester.pump();

    expect(find.text('Night Run'), findsOneWidget);
    expect(find.text('5.10 km'), findsOneWidget);
    expect(find.text('8:39 /km'), findsOneWidget);
    expect(find.text('44:06'), findsOneWidget);
    expect(find.text('RUN'), findsOneWidget);
    // Nguồn mặc định là Strava. Strava đang tắt nên nhãn trung tính.
    expect(find.text('NHẬP'), findsOneWidget);
    expect(find.text('STRAVA'), findsNothing);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('JUN'), findsOneWidget);
  });

  testWidgets('marks a RunNow recording superseded by an imported run', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ActivityTile(
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
    );
    await tester.pump();

    expect(find.text('3I Run'), findsOneWidget);
    expect(find.text('TRÙNG · TÍNH THEO BUỔI KHÁC'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
  });

  testWidgets('labels a Garmin run as GARMIN, not STRAVA', (tester) async {
    await tester.pumpWidget(
      _app(
        ActivityTile(
          activity: ActivitySummary(
            id: 'garmin-21468990741',
            name: 'Chạy sáng',
            kind: ActivityKind.run,
            source: ActivitySource.fromValue('garmin'),
            startedAt: DateTime(2026, 10, 21, 6),
            distanceMeters: 5012.3,
            movingTimeSeconds: 1500,
            elapsedTimeSeconds: 1500,
            hydrated: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('GARMIN'), findsOneWidget);
    expect(find.text('STRAVA'), findsNothing);
  });

  testWidgets('labels a Strava run STRAVA while Strava is on', (tester) async {
    await tester.pumpWidget(
      _app(ActivityTile(activity: _stravaRun()), stravaOn: true),
    );
    await tester.pump();
    expect(find.text('STRAVA'), findsOneWidget);
    expect(find.text('NHẬP'), findsNothing);
  });
}
