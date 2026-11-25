import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_map_overlay.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/route_map.dart';

void main() {
  // Tâm ba ô cạnh nhau ở chợ Bến Thành, tính tay theo công thức slippy z18.
  const mineCell = TileXY(208766, 123181);
  const binhCell = TileXY(208767, 123181);
  const offRouteCell = TileXY(208760, 123181);
  const mineCenter = LatLng(10.771928557, 106.697158813);
  const binhCenter = LatLng(10.771928557, 106.698532104);

  group('ô tuyến đi qua', () {
    test('mỗi ô một lần, bỏ điểm toạ độ hỏng', () {
      expect(
        territoryRouteCells(const [
          mineCenter,
          mineCenter,
          LatLng(120, 106.69),
          binhCenter,
        ]),
        {mineCell, binhCell},
      );
      expect(territoryRouteCells(const []), isEmpty);
    });

    test('tuyến thưa: đi dọc từng đoạn, không sót ô giữa hai điểm', () {
      // Tâm ô 208766 và 208770 cùng hàng, cách 4 ô (mỗi ô 360/2^18 =
      // 0,001373291° kinh độ, khoảng 150 m): phải ra đủ 5 ô.
      expect(
        territoryRouteCells(const [
          mineCenter,
          LatLng(10.771928557, 106.702651978),
        ]),
        {for (var x = 208766; x <= 208770; x++) TileXY(x, 123181)},
      );
    });

    test('đoạn nhảy xa hơn 2 km (mất tín hiệu) chỉ lấy hai đầu', () {
      // 0,03° kinh độ ở vĩ độ 10,77 khoảng 3,3 km.
      final far = territoryRouteCells(const [
        mineCenter,
        LatLng(10.771928557, 106.727158813),
      ]);
      expect(far, hasLength(2));
    });
  });

  group('lớp ô dưới đường chạy', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      firestore = FakeFirebaseFirestore();
      await firestore.collection('territoryChunks').doc('6523_3849').set({
        'cells': {
          mineCell.id: {'u': 'an', 'm': 1200, 'm2': 0},
          binhCell.id: {'u': 'binh', 'm': 420, 'm2': 0},
          offRouteCell.id: {'u': 'chi', 'm': 900, 'm2': 0},
        },
      });
    });

    Future<TerritoryMapPrefs> pump(
      WidgetTester tester, {
      bool enabled = true,
      TerritoryMapPlace place = TerritoryMapPlace.detail,
    }) async {
      final prefs = TerritoryMapPrefs(loadFromStorage: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            territoryRepositoryProvider.overrideWithValue(
              TerritoryRepository(firestore),
            ),
            territoryEnabledProvider.overrideWith(
              (ref) => Stream.value(enabled),
            ),
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(MockUser(uid: 'an')),
            ),
            territoryMapPrefsProvider.overrideWith((ref) => prefs),
          ],
          child: MaterialApp(
            theme: buildRunNowTheme(RunNowElement.water),
            home: Scaffold(
              body: FlutterMap(
                options: const MapOptions(
                  initialCenter: mineCenter,
                  initialZoom: 17,
                ),
                children: [
                  TerritoryRouteLayer(
                    points: const [mineCenter, binhCenter],
                    place: place,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      return prefs;
    }

    testWidgets('tô các ô tuyến đi qua theo chủ ô, bỏ ô ngoài tuyến', (
      tester,
    ) async {
      await pump(tester);
      final drawn = tester
          .widget<PolygonLayer>(find.byType(PolygonLayer))
          .polygons;
      expect(drawn, hasLength(2));
      final context = tester.element(find.byType(TerritoryRouteLayer));
      final accent = context.runNowPalette.accent;
      final mine = drawn.singleWhere((p) => p.borderColor == accent);
      // Góc tây bắc ô 208766_123181, như màn Lãnh địa.
      expect(mine.points.first.latitude, closeTo(10.772603102, 1e-9));
      expect(mine.points.first.longitude, closeTo(106.696472168, 1e-9));
      final other = drawn.singleWhere((p) => p != mine);
      expect(other.borderColor, territoryOthersColor(accent));
    });

    testWidgets('tắt công tắc của chỗ đó thì không vẽ, bật lại thì vẽ', (
      tester,
    ) async {
      final prefs = await pump(tester);
      await prefs.setShows(TerritoryMapPlace.detail, false);
      await tester.pump();
      expect(find.byType(PolygonLayer), findsNothing);

      // Tắt chỗ khác không ảnh hưởng chỗ đang xem.
      await prefs.setShows(TerritoryMapPlace.detail, true);
      await prefs.setShows(TerritoryMapPlace.live, false);
      // Lúc tắt không ai nghe chunk nên phải đọc lại.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.byType(PolygonLayer), findsOneWidget);
    });

    testWidgets('lãnh địa chưa mở thì không vẽ', (tester) async {
      await pump(tester, enabled: false);
      expect(find.byType(PolygonLayer), findsNothing);
    });
  });

  group('công tắc lưu trên máy', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('mặc định bật, đọc lại giá trị đã lưu', () async {
      FlutterSecureStorage.setMockInitialValues({
        'runnow_territory_map_live': '0',
      });
      final prefs = TerritoryMapPrefs();
      expect(prefs.shows(TerritoryMapPlace.live), isTrue);
      await pumpEventQueue();
      expect(prefs.shows(TerritoryMapPlace.live), isFalse);
      expect(prefs.shows(TerritoryMapPlace.detail), isTrue);
      expect(prefs.shows(TerritoryMapPlace.share), isTrue);
    });

    test('bấm rồi thì lưu, mở app sau đọc lại đúng', () async {
      final prefs = TerritoryMapPrefs();
      await pumpEventQueue();
      await prefs.setShows(TerritoryMapPlace.share, false);
      final again = TerritoryMapPrefs();
      await pumpEventQueue();
      expect(again.shows(TerritoryMapPlace.share), isFalse);
    });

    test('đọc máy lỗi thì giữ mặc định bật, không ném lỗi', () async {
      final prefs = TerritoryMapPrefs(storage: _BrokenStorage());
      await pumpEventQueue();
      expect(prefs.shows(TerritoryMapPlace.detail), isTrue);
      await prefs.setShows(TerritoryMapPlace.detail, false);
      expect(prefs.shows(TerritoryMapPlace.detail), isFalse);
    });
  });

  testWidgets('bảng Cài đặt bật tắt từng chỗ', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = TerritoryMapPrefs(loadFromStorage: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [territoryMapPrefsProvider.overrideWith((ref) => prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTerritoryMapPrefsSheet(context),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ảnh khoe'));
    await tester.pumpAndSettle();
    expect(prefs.shows(TerritoryMapPlace.share), isFalse);
    expect(prefs.shows(TerritoryMapPlace.live), isTrue);
  });

  test('ảnh khoe có ô lãnh địa dùng khoá cache riêng, tắt thì giữ khoá cũ', () {
    const subject = CardShareSubject(id: 'c1', printed: 'p', text: 't');
    final plain = cardShareKey(subject, skin: RunCardSkin.classic);
    expect(
      cardShareKey(subject, skin: RunCardSkin.classic, territory: false),
      plain,
    );
    expect(
      cardShareKey(subject, skin: RunCardSkin.classic, territory: true),
      isNot(plain),
    );
  });

  RunCard shareCard() => RunCard.fromJson({
    'id': 'r1',
    'activityId': 'r1',
    'tier': 'epic',
    'km': 1.0,
    'rollPpm': 1,
    'rolledAt': '2026-11-10T08:00:00Z',
    'startedAt': '2026-11-10T13:52:00Z',
    'odds': const [],
    'snapshot': {
      'name': 'Sáng',
      'sportType': 'Run',
      'startedAt': '2026-11-10T20:52:00',
      'distanceMeters': 1000,
      'movingTimeSeconds': 360,
      'elapsedTimeSeconds': 360,
      'route': [
        {'lat': mineCenter.latitude, 'lng': mineCenter.longitude},
        {'lat': binhCenter.latitude, 'lng': binhCenter.longitude},
      ],
      'splits': const [],
    },
  });

  /// Mở màn khoe với store đã có file cho mọi khoá; trả store để xem khoá.
  Future<_RecordingStore> pumpShare(
    WidgetTester tester,
    TerritoryMapPrefs prefs,
  ) async {
    // PNG 1×1 thật, để ô chọn ảnh giải mã được.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    final store = _RecordingStore(
      CardShareFiles(
        front: png,
        back: png,
        motion: Uint8List(0),
        motionType: 'video/mp4',
      ),
    );
    final card = shareCard();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryEnabledProvider.overrideWith((ref) => Stream.value(true)),
          territoryMapPrefsProvider.overrideWith((ref) => prefs),
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(MockUser(uid: 'an')),
          ),
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(FakeFirebaseFirestore()),
          ),
          cardShareStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: CardShareScreen(
            subject: runCardShareSubject(card, 'An'),
            data: runCardData(card, owner: 'An'),
            skin: RunCardSkin.classic,
            runCard: card,
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return store;
  }

  RouteUnderlayBuilder? shareUnderlay(WidgetTester tester) => tester
      .widget<RouteUnderlayScope>(find.byType(RouteUnderlayScope))
      .builder;

  testWidgets('màn khoe: bật thì khoá cache có ô và thẻ có lớp ô, tắt thì bỏ', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = TerritoryMapPrefs(loadFromStorage: false);
    final store = await pumpShare(tester, prefs);
    expect(store.keys.last, endsWith('.territory'));
    expect(shareUnderlay(tester), isNotNull);

    await tester.tap(find.byTooltip('Ô lãnh địa'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(prefs.shows(TerritoryMapPlace.share), isFalse);
    expect(store.keys.last, isNot(contains('territory')));
    expect(shareUnderlay(tester), isNull);
    // Ô chọn ảnh giải mã PNG ngoài fake async nên báo lỗi ảnh; không liên
    // quan tới lớp ô.
    while (tester.takeException() != null) {}
  });

  testWidgets('màn khoe chờ công tắc đọc chậm trên máy rồi mới chốt khoá', (
    tester,
  ) async {
    final prefs = TerritoryMapPrefs(storage: _SlowStorage({'share': '0'}));
    final store = await pumpShare(tester, prefs);
    expect(prefs.shows(TerritoryMapPlace.share), isFalse);
    expect(store.keys, isNotEmpty);
    expect(store.keys.every((k) => !k.contains('territory')), isTrue);
    expect(shareUnderlay(tester), isNull);
    while (tester.takeException() != null) {}
  });

  testWidgets('bản đồ tuyến đứng yên vẽ lớp dưới tuyến khi có scope', (
    tester,
  ) async {
    Widget layer(List<LatLng> points) =>
        SizedBox(key: ValueKey('underlay ${points.length}'));
    const still = StillRouteMap(
      points: [mineCenter, binhCenter],
      dark: false,
      background: Colors.white,
      route: Colors.red,
    );
    await tester.pumpWidget(const MaterialApp(home: still));
    expect(find.byKey(const ValueKey('underlay 2')), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: RouteUnderlayScope(builder: layer, child: still),
      ),
    );
    expect(find.byKey(const ValueKey('underlay 2')), findsOneWidget);
  });
}

/// Store đã có file cho mọi khoá, ghi lại các khoá được hỏi.
class _RecordingStore extends CardShareStore {
  _RecordingStore(this.files);

  final CardShareFiles files;
  final keys = <String>[];

  @override
  Future<CardShareFiles?> load(String cardId, String key) async {
    keys.add(key);
    return files;
  }
}

/// Secure storage trả giá trị sau 15 ms, như máy thật lúc mở app.
class _SlowStorage extends Fake implements FlutterSecureStorage {
  _SlowStorage(this.byPlace);

  final Map<String, String> byPlace;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 15));
    return byPlace[key.replaceFirst('runnow_territory_map_', '')];
  }
}

class _BrokenStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'keychain');

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw PlatformException(code: 'keychain');
}
