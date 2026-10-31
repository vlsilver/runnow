import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
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

/// Cung giả đi thẳng từ [from] tới [to] (vĩ độ, kinh độ), hai mốc ở hai đầu.
JourneyRoute _line((double, double) from, (double, double) to) {
  Map<String, dynamic> at(double t) => {
    'lat': from.$1 + (to.$1 - from.$1) * t,
    'lon': from.$2 + (to.$2 - from.$2) * t,
  };
  return JourneyRoute.fromMap({
    'id': 'hcm_trail',
    'name': 'Cung giả',
    'tagline': '',
    'totalLengthMeters': 1,
    'points': [for (var i = 0; i <= 10; i++) at(i / 10)],
    'milestones': [
      for (final (name, t) in [('A', 0.0), ('B', 1.0)])
        {...at(t), 'name': name, 'cumulativeMeters': t},
    ],
  });
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Kho file khoe đã có sẵn file của mọi thẻ, đếm số lần màn khoe mở ra đọc.
class _FilledShareStore extends CardShareStore {
  int loads = 0;

  @override
  Future<CardShareFiles?> load(String cardId, String key) async {
    loads++;
    return CardShareFiles(
      front: _png,
      back: _png,
      motion: Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
      motionType: 'video/mp4',
    );
  }

  @override
  Future<void> save(String cardId, String key, CardShareFiles files) async {}

  @override
  Future<void> clear(String cardId) async {}
}

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
      expect(data.art, isA<JourneyMedalArt>());
      expect(data.backFace, isA<JourneyRouteMap>());
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

  testWidgets('medal and map paint every campaign, unknown ones included', (
    tester,
  ) async {
    for (final (campaign, routeId) in [
      ('marathon', 'athens_marathon'),
      ('mont_blanc', 'tour_du_mont_blanc'),
      ('xuyen_viet', 'hcm_trail'),
      ('dong_nam_a', 'dong_nam_a'),
      // Chặng và cung app chưa biết: vẽ huy chương và nền, không có đường.
      ('chau_au', 'paris_berlin'),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            journeyRouteDetailProvider.overrideWith(
              (ref, id) async => _line((0, 0), (-1, 1)),
            ),
          ],
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 420,
                child: Row(
                  children: [
                    Expanded(
                      child: JourneyMedalArt(
                        campaign: campaign,
                        routeId: routeId,
                        tier: GameCardTier.rare,
                        rim: 'CHẶNG · 42 KM',
                      ),
                    ),
                    Expanded(
                      child: JourneyRouteMap(
                        campaign: campaign,
                        routeId: routeId,
                        title: 'CHẶNG',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: campaign);
    }
  });

  testWidgets('the back map follows the real route geometry', (tester) async {
    // Bản đồ khổ 300 điểm ngang, vùng vẽ đường là hộp (36, 54) cỡ 228x244.
    // Cung vuông cạnh 1 độ nên phóng thành ô 228x228 ở giữa hộp: góc trên
    // trái (36, 62), góc dưới phải (264, 290). Hai điểm 1/4 và 3/4 đường
    // chéo xuôi là (93, 119) và (207, 233); của đường chéo ngược là (207,
    // 119) và (93, 233).
    Future<int Function(int, int)> paint(JourneyRoute route) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        // Khoá mới thì container mới, không giữ route của lần vẽ trước.
        ProviderScope(
          key: ObjectKey(route),
          overrides: [
            journeyRouteDetailProvider.overrideWith((ref, id) async => route),
          ],
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: const SizedBox(
                width: 300,
                height: 420,
                child: JourneyRouteMap(
                  campaign: 'xuyen_viet',
                  routeId: 'hcm_trail',
                  title: 'XUYÊN VIỆT',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late ByteData pixels;
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        pixels = (await (await render.toImage()).toByteData())!;
      });
      return (x, y) {
        final i = (y * 300 + x) * 4;
        return (pixels.getUint8(i) +
                pixels.getUint8(i + 1) +
                pixels.getUint8(i + 2)) ~/
            3;
      };
    }

    // Nét đường màu vàng sáng (độ sáng cỡ 186), nền xanh tối (cỡ 60-90).
    final down = await paint(_line((0, 0), (-1, 1)));
    for (final (x, y) in [(93, 119), (207, 233)]) {
      expect(down(x, y), greaterThan(150), reason: 'trên đường ($x, $y)');
    }
    for (final (x, y) in [(207, 119), (93, 233)]) {
      expect(down(x, y), lessThan(120), reason: 'ngoài đường ($x, $y)');
    }
    final up = await paint(_line((0, 1), (-1, 0)));
    for (final (x, y) in [(207, 119), (93, 233)]) {
      expect(up(x, y), greaterThan(150), reason: 'trên đường ($x, $y)');
    }
    for (final (x, y) in [(93, 119), (207, 233)]) {
      expect(up(x, y), lessThan(120), reason: 'ngoài đường ($x, $y)');
    }
  });

  testWidgets('sharing waits for the route so the saved files show it', (
    tester,
  ) async {
    final route = Completer<JourneyRoute>();
    final store = _FilledShareStore();
    final card = _card();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journeyRouteDetailProvider.overrideWith((ref, id) => route.future),
          cardShareStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showJourneyCardViewer(
                context,
                card,
                journeyCardData(card, owner: 'An'),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Khoe thẻ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CardShareScreen), findsNothing);
    expect(store.loads, 0, reason: 'chưa có đường thì chưa mở kho file');

    route.complete(_line((0, 0), (-1, 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CardShareScreen), findsOneWidget);
    expect(store.loads, 1);
  });

  group('JourneyTimeline', () {
    // Mọi cung dài 42 km, tổng 50 km: chỉ chặng marathon đã về đích.
    Future<void> pump(
      WidgetTester tester, {
      List<JourneyCard> cards = const [],
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
              body: SingleChildScrollView(child: const JourneyTimeline()),
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
    testWidgets('the journey list keeps the stamp even with a card', (
      tester,
    ) async {
      await pump(tester, cards: [marathon]);
      expect(find.text('HOÀN THÀNH'), findsOneWidget);
      expect(find.byType(AchievementCard), findsNothing);
    });
  });

  testWidgets('the face-down card opens face down and flips to the front', (
    tester,
  ) async {
    final card = JourneyCard.fromJson('marathon', {
      'routeId': 'athens_marathon',
      'level': 1,
      'tier': 'rare',
      'distanceMeters': 42000,
      'runCount': 9,
      'finishedAt': DateTime(2026, 9, 21, 6),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journeyRouteDetailProvider.overrideWith(
            (ref, id) async => _line((0, 0), (-1, 1)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: JourneyCardFaceDown(card: card, owner: 'An', width: 84),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(JourneyRouteMap), findsOneWidget);
    expect(find.byType(JourneyMedalArt), findsNothing);

    // Màn lật mở lá còn úp: thêm một mặt bản đồ, chưa thấy huy chương.
    await tester.tap(find.byType(JourneyCardFaceDown));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hành trình · Level 1'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
    expect(find.byType(JourneyRouteMap), findsNWidgets(2));
    expect(find.byType(JourneyMedalArt), findsNothing);

    // Chạm lá thì lật sang mặt thành tích.
    await tester.tap(find.byType(TiltFlipCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(JourneyMedalArt), findsOneWidget);
    expect(find.byType(JourneyRouteMap), findsOneWidget);
  });
}
