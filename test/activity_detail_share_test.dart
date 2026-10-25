import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
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

final _card = RunCard.fromJson({
  'id': 'a1',
  'tier': 'rare',
  'km': 5.0,
  'rolledAt': DateTime.utc(2026, 10, 24),
  'snapshot': {
    'name': 'Buổi sáng',
    'sportType': 'Run',
    'distanceMeters': 5000,
    'movingTimeSeconds': 1800,
  },
});

Future<void> _pump(
  WidgetTester tester,
  ActivityDetail detail, {
  String? ownerUid,
  RunCard? card,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityDetailProvider.overrideWith((ref, id) async => detail),
        memberActivityDetailProvider.overrideWith((ref, req) async => detail),
        runCardProvider.overrideWith((ref, id) => Stream.value(card)),
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

  testWidgets('a run not flipped yet shows the card face down; a tap opens '
      'the sheet to flip it', (tester) async {
    await _pump(tester, _detail(ActivityKind.run));
    expect(find.byType(RunCardFaceDown), findsOneWidget);
    expect(find.byType(TiltFlipCard), findsNothing);
    expect(find.byTooltip('Khoe thẻ'), findsNothing);

    await tester.tap(find.byType(RunCardFaceDown));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('SHARE // ACTIVITY'), findsOneWidget);
  });

  testWidgets('a flipped card shows on the page and taps flip its faces', (
    tester,
  ) async {
    await _pump(tester, _detail(ActivityKind.run), card: _card);
    expect(find.byType(TiltFlipCard), findsOneWidget);
    expect(find.text('Hiếm · 5,0 km'), findsOneWidget);
    bool showsBack() =>
        tester.widget<AchievementCard>(find.byType(AchievementCard)).back;
    expect(showsBack(), isFalse);

    await tester.tap(find.byType(TiltFlipCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(showsBack(), isTrue);

    await tester.tap(find.byType(TiltFlipCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(showsBack(), isFalse);
  });

  testWidgets('the share icon on the card opens the card sheet', (
    tester,
  ) async {
    await _pump(tester, _detail(ActivityKind.run), card: _card);
    expect(find.text('Khoe thẻ'), findsNothing);
    await tester.tap(find.byTooltip('Khoe thẻ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('SHARE // ACTIVITY'), findsOneWidget);
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
