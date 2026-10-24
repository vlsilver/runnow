import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

void main() {
  Future<_JournalRepository> pumpProfile(WidgetTester tester) async {
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
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(repository),
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

    await tester.tap(find.byTooltip('Tất cả buổi chạy'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trang nhật ký'), findsOneWidget);
  });
}
