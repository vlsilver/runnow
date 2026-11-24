import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/activity_detail_screen.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';

void main() {
  const names = {
    'binh': (name: 'Bình', avatarUrl: null),
    'chi': (name: 'Chi', avatarUrl: null),
  };

  group('chữ trên chip', () {
    test('ô mới và ô chiếm cộng lại thành +N ô', () {
      final text = territoryResultText(
        const TerritoryResult(gained: 3, taken: {'binh': 2}),
        names,
      );
      expect(text.gain, '+5 ô');
      expect(text.takenFrom, 'chiếm của Bình');
    });

    test('chỉ có ô mới thì không ghi chiếm của ai', () {
      final text = territoryResultText(const TerritoryResult(gained: 4), names);
      expect(text.gain, '+4 ô');
      expect(text.takenFrom, isNull);
    });

    test('nhiều người bị chiếm: ghi người mất nhiều nhất, kèm +k', () {
      final text = territoryResultText(
        const TerritoryResult(gained: 0, taken: {'binh': 1, 'chi': 2, 'x': 1}),
        names,
      );
      expect(text.gain, '+4 ô');
      expect(text.takenFrom, 'chiếm của Chi +2');
    });

    test('chưa biết tên thì dùng tên mặc định', () {
      final text = territoryResultText(
        const TerritoryResult(gained: 0, taken: {'la': 1}),
        names,
      );
      expect(text.takenFrom, 'chiếm của 3i member');
    });
  });

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('leaderboardEntries').doc('binh').set({
      'displayName': 'Bình',
    });
  });

  DocumentRef result(String uid, String activityId) =>
      firestore.collection('territoryResults').doc('${uid}_$activityId');

  Map<String, dynamic> doc(
    String uid,
    int gained, {
    Map<String, int> taken = const {},
    String? chunk,
  }) => {
    'uid': uid,
    'activityId': 'a1',
    'gained': gained,
    'taken': taken,
    'chunk': ?chunk,
  };

  test('nghe doc nhỏ territoryResults, không đọc doc buổi', () async {
    // Doc buổi có result khác hẳn để test đỏ nếu còn đọc nhầm doc buổi.
    await firestore
        .collection('users')
        .doc('an')
        .collection('activities')
        .doc('a1')
        .set({
          'territory': {
            'result': {'gained': 9, 'taken': {}},
          },
        });
    final seen = <int?>[];
    final sub = TerritoryRepository(
      firestore,
    ).watchActivityResult('an', 'a1').listen((r) => seen.add(r?.total));
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await result('an', 'a1').set(doc('an', 2, chunk: '6523_3849'));
    await pumpEventQueue();
    // Backend ghi lại khi buổi đổi sang được tính: vẫn nghe tiếp.
    await result('an', 'a1').set(doc('an', 3, taken: {'binh': 1}));
    await pumpEventQueue();
    expect(seen, [null, 2, 4]);
  });

  Future<List<String>> pumpChip(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    final opened = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: TerritoryResultChip(uid: 'an', activityId: 'a1'),
          ),
        ),
        GoRoute(
          path: '/lanh-dia',
          builder: (context, state) {
            opened.add(state.uri.toString());
            return const Scaffold();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(firestore),
          ),
          territoryEnabledProvider.overrideWith((ref) => Stream.value(enabled)),
          leaderboardDocsProvider.overrideWith(
            (ref) async =>
                (await firestore.collection('leaderboardEntries').get()).docs,
          ),
        ],
        child: MaterialApp.router(
          theme: buildRunNowTheme(RunNowElement.water),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    return opened;
  }

  testWidgets('chưa có kết quả thì không hiện gì, có thì hiện +N ô', (
    tester,
  ) async {
    await pumpChip(tester);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await result('an', 'a1').set(doc('an', 3, taken: {'binh': 2}));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.text('+5 ô · chiếm của Bình'), findsOneWidget);
  });

  testWidgets('chạm chip mở màn Lãnh địa ở chunk của buổi', (tester) async {
    await result('an', 'a1').set(doc('an', 3, chunk: '6523_3849'));
    final opened = await pumpChip(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(opened, ['/lanh-dia?chunk=6523_3849']);
  });

  testWidgets('buổi không thêm ô nào thì không có chip', (tester) async {
    await result('an', 'a1').set(doc('an', 0));
    await pumpChip(tester);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('cờ tắt thì không có chip dù đã có kết quả', (tester) async {
    await result('an', 'a1').set(doc('an', 3));
    await pumpChip(tester, enabled: false);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('màn chi tiết buổi của người khác hiện chip của buổi đó', (
    tester,
  ) async {
    await result('binh', 'a1').set(doc('binh', 7));
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final detail = ActivityDetail(
      summary: ActivitySummary(
        id: 'a1',
        name: 'Buổi sáng',
        kind: ActivityKind.run,
        startedAt: DateTime(2026, 11, 24),
        distanceMeters: 5000,
        movingTimeSeconds: 1800,
        elapsedTimeSeconds: 1900,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(firestore),
          ),
          territoryEnabledProvider.overrideWith((ref) => Stream.value(true)),
          leaderboardDocsProvider.overrideWith((ref) async => const []),
          memberActivityDetailProvider.overrideWith((ref, req) async => detail),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
          runCardProvider.overrideWith((ref, id) => Stream.value(null)),
          runCardViewProvider.overrideWith(
            (ref, id) async => const RunCardView(chance: 20),
          ),
          myActiveContractsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(
          home: ActivityDetailScreen(activityId: 'a1', ownerUid: 'binh'),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.text('+7 ô'), findsOneWidget);
  });
}

typedef DocumentRef = DocumentReference<Map<String, dynamic>>;
