import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/activity_detail_screen.dart';

ActivityDetail _detail(ActivityKind kind) => ActivityDetail(
  summary: ActivitySummary(
    id: 'a1',
    name: 'Buổi sáng',
    kind: kind,
    startedAt: DateTime(2026, 10, 24),
    distanceMeters: 5000,
    movingTimeSeconds: 1800,
    elapsedTimeSeconds: 1900,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  ActivityDetail detail, {
  String? ownerUid,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityDetailProvider.overrideWith((ref, id) async => detail),
        memberActivityDetailProvider.overrideWith((ref, req) async => detail),
        runCardProvider.overrideWith((ref, id) => Stream.value(null)),
        myActiveContractsProvider.overrideWith((ref) => Stream.value(const [])),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        home: ActivityDetailScreen(activityId: 'a1', ownerUid: ownerUid),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('own run opens the card sheet, with no poster option', (
    tester,
  ) async {
    await _pump(tester, _detail(ActivityKind.run));
    await tester.tap(find.byTooltip('Chia sẻ hoạt động'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('SHARE // ACTIVITY'), findsOneWidget);
    expect(find.text('Poster'), findsNothing);
    expect(find.text('Chia sẻ poster'), findsNothing);
  });

  // Ngoài thẻ không còn gì để chia sẻ, nên buổi không có thẻ thì không có nút.
  testWidgets('a ride has nothing to share', (tester) async {
    await _pump(tester, _detail(ActivityKind.ride));
    expect(find.byTooltip('Chia sẻ hoạt động'), findsNothing);
  });

  testWidgets("another member's run has nothing to share", (tester) async {
    await _pump(tester, _detail(ActivityKind.run), ownerUid: 'u2');
    expect(find.byTooltip('Chia sẻ hoạt động'), findsNothing);
  });
}
