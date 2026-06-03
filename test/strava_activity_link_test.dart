import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/strava_activity_link.dart';

void main() {
  testWidgets('renders the required Strava link text for real activities', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StravaActivityLink(activityId: '42')),
    );
    expect(find.text('View on Strava'), findsOneWidget);
  });

  testWidgets('hides the Strava link for demo activities', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StravaActivityLink(activityId: 'demo-run')),
    );
    expect(find.text('View on Strava'), findsNothing);
  });
}
