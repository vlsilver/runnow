import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/journey/journey_card_art.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/journey/journey_timeline.dart';
import 'package:myrun/src/providers.dart';

/// Thẻ như doc journeyCards backend ghi.
JourneyCard _card({
  String campaign = 'xuyen_viet',
  int runCount = 214,
  String tier = 'legendary',
}) => JourneyCard.fromJson(campaign, {
  'campaign': campaign,
  'routeId': 'hcm_trail',
  'level': 3,
  'tier': tier,
  'distanceMeters': 2100000,
  'runCount': runCount,
  'finishedAt': DateTime(2027, 8, 14, 6),
});

void main() {
  group('journeyCardKm', () {
    test('rounds to whole km and groups thousands with a dot', () {
      expect(journeyCardKm(42195), '42');
      expect(journeyCardKm(170000), '170');
      expect(journeyCardKm(999499), '999');
      expect(journeyCardKm(1000000), '1.000');
      expect(journeyCardKm(5967000), '5.967');
    });
  });

  group('JourneyCard.fromJson', () {
    test('reads the card the backend wrote', () {
      final card = _card();
      expect(card.campaign, 'xuyen_viet');
      expect(card.routeId, 'hcm_trail');
      expect(card.level, 3);
      expect(card.tier, GameCardTier.legendary);
      expect(card.distanceMeters, 2100000);
      expect(card.runCount, 214);
      expect(card.finishedAt, DateTime(2027, 8, 14, 6));
      expect(card.name, 'Xuyên Việt');
    });

    test('an unknown campaign keeps its key as the name', () {
      final card = JourneyCard.fromJson('chau_au', {'tier': 'mythic'});
      expect(card.name, 'chau_au');
      expect(card.finishedAt, isNull);
      expect(journeyCardData(card, owner: 'An').kind, 'HÀNH TRÌNH');
    });
  });

  group('journeyCardData', () {
    test('the front shows distance, runs and finish date as stats', () {
      final data = journeyCardData(_card(), owner: 'An');
      expect(data.tier, GameCardTier.legendary);
      expect(data.kind, 'HÀNH TRÌNH · HÀ NỘI – CÀ MAU');
      expect(data.hero, 'XUYÊN VIỆT');
      expect(data.title, 'Đã về đích · Level 3');
      expect(data.stats, const [
        (value: '2.100 km', label: 'CỰ LY'),
        (value: '214', label: 'BUỔI CHẠY'),
        (value: '14.08.27', label: 'VỀ ĐÍCH'),
      ]);
      expect(data.owner, 'AN');
      expect(data.meta, 'LEVEL 3');
      expect(data.date, '14.08.2027');
      expect(data.backFace, isA<JourneyCardEmblem>());
    });
  });

  group('journeyCardShareSubject', () {
    String key(JourneyCard card, {String owner = 'AN'}) => cardShareKey(
      journeyCardShareSubject(card, owner: owner),
      skin: RunCardSkin.classic,
    );

    test('keeps files apart per campaign', () {
      expect(
        journeyCardShareSubject(_card(), owner: 'AN').id,
        'journey-xuyen_viet',
      );
    });

    test('the cache key follows what the card shows', () {
      expect(key(_card()), key(_card()));
      expect(key(_card()), isNot(key(_card(runCount: 215))));
      expect(key(_card()), isNot(key(_card(tier: 'mythic'))));
      expect(key(_card()), isNot(key(_card(), owner: 'BÌNH')));
    });

    test('says which leg was finished', () {
      expect(
        journeyCardShareSubject(_card(), owner: 'AN').text,
        'Về đích Xuyên Việt · 2.100 km\nChia sẻ từ 3i',
      );
    });
  });

  testWidgets('poster and emblem paint every campaign and unknown ones', (
    tester,
  ) async {
    for (final campaign in [
      'marathon',
      'mont_blanc',
      'xuyen_viet',
      'dong_nam_a',
      'chau_au',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 420,
              child: Row(
                children: [
                  Expanded(
                    child: JourneyPosterArt(campaign: campaign, km: '42 KM'),
                  ),
                  Expanded(
                    child: JourneyCardEmblem(
                      campaign: campaign,
                      tier: GameCardTier.rare,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: campaign);
    }
  });

  group('JourneyTimeline', () {
    // Mọi cung dài 42 km, tổng 50 km: chỉ chặng marathon đã về đích.
    Future<void> pump(
      WidgetTester tester, {
      List<JourneyCard> cards = const [],
      String? memberUid,
    }) async {
      tester.view.physicalSize = const Size(420, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            journeyCardsProvider.overrideWith((ref) => Stream.value(cards)),
            userProfileProvider.overrideWith((ref) => Stream.value(null)),
            journeyLifetimeDistanceProvider.overrideWith((ref) async => 50000),
            memberJourneyLifetimeDistanceProvider.overrideWith(
              (ref, uid) async => 50000,
            ),
            journeyRouteSummaryProvider.overrideWith(
              (ref, id) async => JourneyRouteSummary(
                id: id.name,
                name: id.name,
                tagline: '',
                totalLengthMeters: 42000,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: JourneyTimeline(memberUid: memberUid),
              ),
            ),
          ),
        ),
      );
      // Chặng đang chạy nhấp nháy mãi, nên không chờ settle được.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    final marathon = JourneyCard.fromJson('marathon', {
      'routeId': 'athens_marathon',
      'level': 1,
      'tier': 'rare',
      'distanceMeters': 42000,
      'runCount': 9,
      'finishedAt': DateTime(2026, 9, 21, 6),
    });
    Finder faceDown() =>
        find.bySemanticsLabel('Thẻ Hành trình Marathon Athens, chạm để lật');

    testWidgets('a finished leg with a card shows it face down', (
      tester,
    ) async {
      await pump(tester, cards: [marathon]);
      expect(faceDown(), findsOneWidget);
      expect(find.text('HOÀN THÀNH'), findsNothing);

      await tester.tap(faceDown());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Hành trình · Level 1'), findsOneWidget);
      expect(find.text('Khoe thẻ'), findsOneWidget);
    });

    testWidgets('without a card yet the leg keeps the stamp', (tester) async {
      await pump(tester);
      expect(faceDown(), findsNothing);
      expect(find.text('HOÀN THÀNH'), findsOneWidget);
    });

    testWidgets("another member's journey keeps the stamp", (tester) async {
      await pump(tester, cards: [marathon], memberUid: 'u2');
      expect(faceDown(), findsNothing);
      expect(find.text('HOÀN THÀNH'), findsOneWidget);
    });
  });
}
