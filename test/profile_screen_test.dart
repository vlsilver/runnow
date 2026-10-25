import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/screens/profile_screen.dart';
import 'package:myrun/src/theme_controller.dart';

/// Trả nhật ký mới trước, như Firestore; còn lại không dùng tới.
class _JournalRepository implements ActivityRepository {
  _JournalRepository(this.activities);

  final List<ActivitySummary> activities;
  int pageReads = 0;

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    pageReads++;
    return JournalActivityPage(
      entries: [
        for (final a in activities.take(limit))
          JournalActivityEntry(activity: a),
      ],
      hasMore: activities.length > limit,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ActivitySummary _run(int n) => ActivitySummary(
  id: 'run-$n',
  name: 'Buổi $n',
  kind: ActivityKind.run,
  startedAt: DateTime(2026, 10, 24).subtract(Duration(days: n)),
  distanceMeters: 5000,
  movingTimeSeconds: 1800,
  elapsedTimeSeconds: 1900,
  hydrated: true,
);

const _month = LeaderboardStats(
  distanceMeters: 35000,
  movingTimeSeconds: 12600,
  activityCount: 7,
  activeDays: 7,
  longestDistanceMeters: 5000,
  fastestPaceSecondsPerKm: 360,
);

/// Thẻ thứ [n] trong bộ, mới lật trước như runCardsProvider trả.
RunCard _card(int n, {String tier = 'rare'}) => RunCard.fromJson({
  'id': 'card-$n',
  'tier': tier,
  'km': 10.0,
  'rolledAt': DateTime.utc(2026, 10, 24).subtract(Duration(days: n)),
  'snapshot': {
    'name': 'Thẻ $n',
    'sportType': 'Run',
    'distanceMeters': 10000,
    'movingTimeSeconds': 3000,
  },
});

void main() {
  Future<_JournalRepository> pumpProfile(
    WidgetTester tester, {
    List<RunCard> cards = const [],
    List<GamePlayerCard> games = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _JournalRepository([
      for (var n = 1; n <= 7; n++) _run(n),
    ]);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/journal',
          builder: (_, _) => const Scaffold(body: Text('Trang nhật ký')),
        ),
        GoRoute(
          path: '/me/cards',
          builder: (_, _) => const Scaffold(body: Text('Trang bộ thẻ')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(repository),
          runCardsProvider.overrideWith((ref) => Stream.value(cards)),
          gameCardsProvider.overrideWith((ref) => Stream.value(games)),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(UserProfile.demo),
          ),
          themeControllerProvider.overrideWith(
            (ref) => ThemeController(loadFromStorage: false),
          ),
          journeyLifetimeDistanceProvider.overrideWith((ref) async => 35000),
          journeyRouteSummaryProvider.overrideWith(
            (ref, id) async => JourneyRouteSummary(
              id: id.name,
              name: id.name,
              tagline: '',
              totalLengthMeters: 42195,
            ),
          ),
          profileStatsProvider.overrideWith(
            (ref) async => ProfileStatsData(
              today: DateTime(2026, 10, 24),
              days: const {},
              weeks: const {},
              months: const {'2026-10': _month},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // Chặng đang chạy nhấp nháy mãi, nên không chờ settle được.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return repository;
  }

  testWidgets('shows the five newest runs, the icon opens the journal', (
    tester,
  ) async {
    final repository = await pumpProfile(tester);
    expect(repository.pageReads, 1);
    for (var n = 1; n <= 5; n++) {
      expect(find.text('Buổi $n'), findsOneWidget);
    }
    expect(find.text('Buổi 6'), findsNothing);
    // Cài đặt chỉ mở từ nút bánh răng, cuối trang không còn dòng riêng.
    expect(find.text('Cài đặt'), findsNothing);
    expect(find.byTooltip('Cài đặt'), findsOneWidget);

    await tester.tap(find.byTooltip('Tất cả buổi chạy'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trang nhật ký'), findsOneWidget);
  });

  testWidgets('no cards yet says how to get one', (tester) async {
    await pumpProfile(tester);
    expect(find.text('BỘ THẺ'), findsOneWidget);
    expect(find.text(collectedCardsEmpty), findsOneWidget);
  });

  testWidgets('the shelf leads the profile with the newest card in 3D', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      cards: [
        _card(1),
        _card(2, tier: 'mythic'),
        _card(3),
      ],
    );
    expect(find.byType(TiltFlipCard), findsOneWidget);
    expect(find.text('MỚI NHẤT'), findsOneWidget);
    expect(find.text('Hiếm · 10,0 km'), findsOneWidget);
    // Hai thẻ Hiếm, một thẻ Thần thoại.
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
    // Bộ thẻ nằm trên các ô số liệu.
    expect(
      tester.getTopLeft(find.text('BỘ THẺ')).dy,
      lessThan(tester.getTopLeft(find.text('TỔNG KM')).dy),
    );
  });

  testWidgets('a newer Ma Sói card leads the shelf', (tester) async {
    await pumpProfile(
      tester,
      cards: [_card(2)],
      games: [
        GamePlayerCard.fromJson('g1', {
          'tier': 'epic',
          'role': 'seer',
          'team': 'village',
          'winner': 'village',
          'alive': true,
          'rounds': 3,
          'playerCount': 10,
          'endedAt': DateTime.utc(2026, 10, 23, 12),
        }),
      ],
    );
    expect(find.text('2 thẻ'), findsOneWidget);
    expect(find.text('Ma Sói · Tiên tri'), findsOneWidget);
    expect(find.text('Siêu hiếm · Phe Dân thắng'), findsOneWidget);
  });

  testWidgets('the shelf shows the ten newest cards and opens the rest', (
    tester,
  ) async {
    await pumpProfile(tester, cards: [for (var n = 1; n <= 12; n++) _card(n)]);
    expect(find.text('12 thẻ'), findsOneWidget);
    List<String> shown() => [
      for (final t in tester.widgetList<CollectedCardThumb>(
        find.byType(CollectedCardThumb),
      ))
        t.card.id,
    ];
    // Thẻ 1 đứng riêng to ở trên, hàng ngang bắt đầu từ thẻ 2.
    expect(shown().first, 'card-2');

    await tester.drag(
      find.byType(CollectedCardThumb).first,
      const Offset(-3000, 0),
    );
    await tester.pump();
    expect(shown(), contains('card-10'));
    expect(shown(), isNot(contains('card-11')));

    await tester.tap(find.text('Xem tất cả'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trang bộ thẻ'), findsOneWidget);
  });
}
