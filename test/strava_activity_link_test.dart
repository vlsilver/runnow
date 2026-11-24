import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/strava_activity_link.dart';

Widget _link(String activityId, {required bool stravaOn}) => ProviderScope(
  overrides: [
    stravaEnabledProvider.overrideWith((ref) => Stream.value(stravaOn)),
  ],
  child: MaterialApp(home: StravaActivityLink(activityId: activityId)),
);

void main() {
  testWidgets('renders the required Strava link text for real activities', (
    tester,
  ) async {
    await tester.pumpWidget(_link('42', stravaOn: true));
    await tester.pump();
    expect(find.text('View on Strava'), findsOneWidget);
  });

  testWidgets('hides the Strava link for demo activities', (tester) async {
    await tester.pumpWidget(_link('demo-run', stravaOn: true));
    await tester.pump();
    expect(find.text('View on Strava'), findsNothing);
  });

  testWidgets('hides the Strava link while Strava is off', (tester) async {
    await tester.pumpWidget(_link('42', stravaOn: false));
    await tester.pump();
    expect(find.text('View on Strava'), findsNothing);
  });
}
