import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/providers.dart';

RunCard _card(String id, String tier, int daysAgo) => RunCard.fromJson({
  'id': id,
  'tier': tier,
  'km': 10.0,
  'rolledAt': DateTime.utc(2026, 10, 24).subtract(Duration(days: daysAgo)),
  'snapshot': {
    'name': 'Buổi $id',
    'sportType': 'Run',
    'distanceMeters': 10000,
    'movingTimeSeconds': 3000,
  },
});

Future<void> _pump(WidgetTester tester, List<RunCard> cards) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runCardsProvider.overrideWith((ref) => Stream.value(cards)),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: const MaterialApp(home: RunCardCollectionScreen()),
    ),
  );
  // Thẻ Thần thoại chạy hiệu ứng mãi, nên không chờ settle.
  await tester.pump();
  await tester.pump();
}

List<String> _shown(WidgetTester tester) => [
  for (final t in tester.widgetList<RunCardThumb>(find.byType(RunCardThumb)))
    t.card.id,
];

void main() {
  testWidgets('cards keep the newest-first order and filter by tier', (
    tester,
  ) async {
    await _pump(tester, [
      _card('a', 'rare', 1),
      _card('b', 'mythic', 2),
      _card('c', 'rare', 3),
    ]);
    expect(_shown(tester), ['a', 'b', 'c']);
    expect(find.text('Tất cả · 3'), findsOneWidget);
    expect(find.text('Thần thoại · 1'), findsOneWidget);
    expect(find.text('Hiếm · 2'), findsOneWidget);

    // Bậc chưa có thẻ vẫn hiện nhưng không chọn được.
    final common = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Thường · 0'),
    );
    expect(common.onSelected, isNull);

    await tester.tap(find.text('Hiếm · 2'));
    await tester.pump();
    expect(_shown(tester), ['a', 'c']);

    await tester.tap(find.text('Tất cả · 3'));
    await tester.pump();
    expect(_shown(tester), ['a', 'b', 'c']);
  });

  testWidgets('an empty collection says how to get a card', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(RunCardThumb), findsNothing);
    expect(
      find.text(
        'Chưa có thẻ nào. Mở một buổi chạy và lật thẻ để bắt đầu bộ sưu tập.',
      ),
      findsOneWidget,
    );
  });
}
