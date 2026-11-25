import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_screen.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  // Hai ô cạnh nhau trong chunk 6523_3849 (chợ Bến Thành). Cột 208768 đã
  // sang chunk 6524 (208768 / 32 = 6524).
  const mineCell = TileXY(208766, 123181);
  const binhCell = TileXY(208767, 123181);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.collection('territoryChunks').doc('6523_3849').set({
      'cells': {
        mineCell.id: {'u': 'an', 'm': 1200, 'm2': 0},
        binhCell.id: {'u': 'binh', 'm': 420, 'm2': 300},
      },
    });
    await firestore.collection('territoryOwners').doc('an').set({
      'byChunk': {'6523_3849': 1, '6524_3849': 2},
    });
    // Bình nhiều ô nhất nhưng uid đứng sau; aa bằng ô với An, uid đứng trước;
    // doc rỗng (backend xoá hết chunk nhưng giữ doc) không được lên danh sách.
    await firestore.collection('territoryOwners').doc('binh').set({
      'byChunk': {'6523_3849': 5},
    });
    await firestore.collection('territoryOwners').doc('aa').set({
      'byChunk': {'6600_3849': 3},
    });
    await firestore.collection('territoryOwners').doc('empty').set({
      'byChunk': <String, int>{},
    });
    await firestore.collection('leaderboardEntries').doc('binh').set({
      'displayName': 'Bình',
    });
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool enabled = true,
    Stream<bool>? flag,
    UserProfile? profile,
    String uid = 'an',
    TerritoryRepository? repository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRepositoryProvider.overrideWithValue(
            repository ?? TerritoryRepository(firestore),
          ),
          territoryEnabledProvider.overrideWith(
            (ref) => flag ?? Stream.value(enabled),
          ),
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(MockUser(uid: uid)),
          ),
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          leaderboardDocsProvider.overrideWith(
            (ref) async =>
                (await firestore.collection('leaderboardEntries').get()).docs,
          ),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: child,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  List<Polygon> polygons(WidgetTester tester) =>
      tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons;

  LatLng cellCenter(TileXY cell) =>
      tileCorner(cell.x + 0.5, cell.y + 0.5, territoryCellZoom);

  testWidgets('vẽ ô trong chunk, ô của mình màu chính, nhãn số ô', (
    tester,
  ) async {
    await pump(tester, const TerritoryScreen(chunk: '6523_3849'));

    final drawn = polygons(tester);
    expect(drawn, hasLength(2));
    final context = tester.element(find.byType(TerritoryMap));
    final accent = context.runNowPalette.accent;
    final mine = drawn.singleWhere((p) => p.borderColor == accent);
    expect(mine.points.first.latitude, closeTo(10.772603102, 1e-9));
    expect(mine.points.first.longitude, closeTo(106.696472168, 1e-9));
    final other = drawn.singleWhere((p) => p != mine);
    expect(RunNowTerritoryTokens.otherOwners, contains(other.borderColor));
    // 1 + 2 ô theo byChunk.
    expect(find.text('Của tôi · 3 ô'), findsOneWidget);
  });

  testWidgets('chạm ô thì hiện tên chủ ô và km', (tester) async {
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(binhCell), zoom: 17)),
    );
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    // Map chờ hết thời gian chạm đúp rồi mới báo chạm một lần.
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('0,4 km'), findsOneWidget);
  });

  testWidgets('zoom quá xa thì không tải ô', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: TerritoryMap(center: territoryDefaultCenter, zoom: 9),
      ),
    );
    expect(polygons(tester), isEmpty);
    expect(find.text('Phóng to để xem ô'), findsOneWidget);
  });

  testWidgets('không có chunk thì mở ở chunk mình giữ nhiều ô nhất', (
    tester,
  ) async {
    await pump(tester, const TerritoryScreen());
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter, chunkCenter(const TileXY(6524, 3849)));
  });

  testWidgets('chưa có ô nào thì mở ở trung tâm TP.HCM', (tester) async {
    await pump(tester, const TerritoryScreen(), uid: 'moi');
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter, territoryDefaultCenter);
    expect(find.text('Của tôi · 0 ô'), findsOneWidget);
  });

  testWidgets('cờ tắt thì không có bản đồ và không có dòng ở Trang chủ', (
    tester,
  ) async {
    await pump(tester, const TerritoryScreen(), enabled: false);
    expect(find.byType(FlutterMap), findsNothing);

    await pump(
      tester,
      const Scaffold(body: TerritoryHomeRow()),
      enabled: false,
    );
    expect(find.textContaining('Lãnh địa'), findsNothing);
  });

  testWidgets('hồ sơ private thì nhắc chỉ hồ sơ công khai mới có ô', (
    tester,
  ) async {
    await pump(
      tester,
      const TerritoryScreen(chunk: '6523_3849'),
      profile: const UserProfile(
        athleteId: '1',
        displayName: 'An',
        visibility: ProfileVisibility.private,
      ),
    );
    expect(find.text('Hồ sơ công khai mới có ô'), findsOneWidget);
  });

  testWidgets('hồ sơ công khai thì nhãn là số ô', (tester) async {
    await pump(
      tester,
      const TerritoryScreen(chunk: '6523_3849'),
      profile: const UserProfile(
        athleteId: '1',
        displayName: 'An',
        visibility: ProfileVisibility.public,
      ),
    );
    expect(find.text('Hồ sơ công khai mới có ô'), findsNothing);
    expect(find.text('Của tôi · 3 ô'), findsOneWidget);
  });

  testWidgets('cờ chưa về thì đang tải, không báo chưa mở', (tester) async {
    final flag = StreamController<bool>();
    addTearDown(flag.close);
    await pump(tester, const TerritoryScreen(), flag: flag.stream);
    expect(find.byType(RunNowLoading), findsOneWidget);
    expect(find.text('Lãnh địa chưa mở'), findsNothing);
  });

  testWidgets('đọc cờ lỗi thì báo ngắn, không in lỗi gốc', (tester) async {
    await pump(
      tester,
      const TerritoryScreen(),
      flag: Stream.error(StateError('permission-denied chi tiết nội bộ')),
    );
    expect(find.text('Chưa tải được'), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsNothing);
  });

  testWidgets('cờ bật thì Trang chủ có dòng Lãnh địa · N ô', (tester) async {
    await pump(tester, const Scaffold(body: TerritoryHomeRow()));
    expect(find.text('Lãnh địa · 3 ô'), findsOneWidget);
  });

  test('độ đậm theo km: bốn mức, ngưỡng 300, 750, 1500 m', () {
    expect(territoryCellAlpha(0), 0.2);
    expect(territoryCellAlpha(299), 0.2);
    expect(territoryCellAlpha(300), 0.38);
    expect(territoryCellAlpha(749), 0.38);
    expect(territoryCellAlpha(750), 0.56);
    expect(territoryCellAlpha(1500), 0.74);
    expect(territoryCellAlpha(40000), 0.74);
  });

  testWidgets('ô chạy nhiều km đậm hơn ô ít km', (tester) async {
    await pump(tester, const TerritoryScreen(chunk: '6523_3849'));
    final context = tester.element(find.byType(TerritoryMap));
    final accent = context.runNowPalette.accent;
    final drawn = polygons(tester);
    // An 1200 m (mức 3), Bình 420 m (mức 2).
    final mine = drawn.singleWhere((p) => p.borderColor == accent);
    final other = drawn.singleWhere((p) => p != mine);
    expect(mine.color!.a, closeTo(0.56, 0.01));
    expect(other.color!.a, closeTo(0.38, 0.01));
  });

  testWidgets('Của tôi chỉ hiện ô của mình, Tất cả hiện lại hết', (
    tester,
  ) async {
    // Mở ngay trên ô của An để màn hình đang thấy ô, bản đồ không dời.
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(mineCell), zoom: 17)),
    );
    final accent = tester
        .element(find.byType(TerritoryMap))
        .runNowPalette
        .accent;

    await tester.tap(find.text('Của tôi · 3 ô'));
    await tester.pump();
    expect(polygons(tester).map((p) => p.borderColor), [accent]);

    await tester.tap(find.text('Tất cả'));
    await tester.pump();
    expect(polygons(tester), hasLength(2));
  });

  testWidgets(
    'Mọi người: nhiều ô trước, chọn một người thì chỉ hiện ô người đó',
    (tester) async {
      await pump(tester, const TerritoryScreen(chunk: '6523_3849'));
      final accent = tester
          .element(find.byType(TerritoryMap))
          .runNowPalette
          .accent;

      await tester.tap(find.text('Mọi người'));
      await tester.pumpAndSettle();
      // Bình 5 ô, rồi aa và An cùng 3 ô thì uid nhỏ trước; doc rỗng không lên.
      final rows = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map(
            (tile) => ((tile.title as Text).data, (tile.trailing as Text).data),
          )
          .toList();
      expect(rows, [
        ('Bình', '5 ô'),
        ('3i member', '3 ô'),
        ('3i member (bạn)', '3 ô'),
      ]);

      await tester.tap(find.text('Bình'));
      await tester.pumpAndSettle();
      final drawn = polygons(tester);
      expect(drawn, hasLength(1));
      expect(drawn.single.borderColor, isNot(accent));
      // Chip tên người đang lọc, bấm x thì về tất cả.
      expect(find.widgetWithText(InputChip, 'Bình'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(polygons(tester), hasLength(2));
    },
  );

  testWidgets('chọn người không có ô trong khung nhìn thì bản đồ tới chỗ họ', (
    tester,
  ) async {
    // Mở ở Hà Nội, xa chunk Bến Thành.
    await pump(
      tester,
      const Scaffold(
        body: TerritoryMap(center: LatLng(21.0285, 105.8542), zoom: 15),
      ),
    );
    expect(polygons(tester), isEmpty);

    await tester.tap(find.text('Mọi người'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình'));
    await tester.pumpAndSettle();
    expect(polygons(tester), hasLength(1));
  });

  testWidgets(
    'người được chọn có ô trong chunk nhưng ngoài màn hình thì dời tới ô của họ',
    (tester) async {
      // Zoom 19: một ô rộng 512 px, ô Bình nằm ngoài màn 800 px tính từ tâm ô An.
      await pump(
        tester,
        Scaffold(body: TerritoryMap(center: cellCenter(mineCell), zoom: 19)),
      );
      MapCamera camera() =>
          MapCamera.of(tester.element(find.byType(PolygonLayer)));
      expect(camera().zoom, 19);

      await tester.tap(find.text('Mọi người'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bình'));
      await tester.pumpAndSettle();
      // Một ô thì fit tới mức zoom trần 17, và ô Bình nằm trong màn hình.
      expect(camera().zoom, 17);
      expect(camera().visibleBounds.contains(cellCenter(binhCell)), isTrue);
    },
  );

  testWidgets('đang thấy ô của người được chọn thì giữ nguyên chỗ xem', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(binhCell), zoom: 18)),
    );
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(PolygonLayer)));

    await tester.tap(find.text('Mọi người'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình'));
    await tester.pumpAndSettle();
    expect(camera().zoom, 18);
    expect(camera().center, cellCenter(binhCell));
  });

  testWidgets('đang lọc một người thì chạm ô người khác không mở gì', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(mineCell), zoom: 17)),
    );
    await tester.tap(find.text('Mọi người'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình'));
    await tester.pumpAndSettle();

    // Tâm bản đồ là ô của An, đang ẩn vì lọc Bình.
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.text('1,2 km'), findsNothing);
  });

  testWidgets('đổi lọc trong lúc đang đọc ô thì bản đồ không bị kéo đi', (
    tester,
  ) async {
    final repo = _SlowRepository(firestore);
    await pump(
      tester,
      const Scaffold(
        body: TerritoryMap(center: LatLng(21.0285, 105.8542), zoom: 15),
      ),
      repository: repo,
    );
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(PolygonLayer)));
    final before = camera().center;

    await tester.tap(find.text('Mọi người'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tất cả'));
    await tester.pump();
    repo.owned.complete([binhCell]);
    await tester.pumpAndSettle();
    expect(camera().center, before);
  });

  testWidgets('tự kéo bản đồ trong lúc đang đọc ô thì bản đồ không bị kéo đi', (
    tester,
  ) async {
    final repo = _SlowRepository(firestore);
    await pump(
      tester,
      const Scaffold(
        body: TerritoryMap(center: LatLng(21.0285, 105.8542), zoom: 15),
      ),
      repository: repo,
    );
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(PolygonLayer)));

    await tester.tap(find.text('Mọi người'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(FlutterMap), const Offset(100, 0));
    await tester.pumpAndSettle();
    final dragged = camera().center;
    repo.owned.complete([binhCell]);
    await tester.pumpAndSettle();
    expect(camera().center, dragged);
  });

  testWidgets('mở lại Mọi người không đọc lại danh sách', (tester) async {
    final repo = _SlowRepository(firestore);
    await pump(
      tester,
      const TerritoryScreen(chunk: '6523_3849'),
      repository: repo,
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Mọi người'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // đóng sheet
      await tester.pumpAndSettle();
    }
    expect(repo.holderReads, 1);
  });
}

/// Đọc ô chờ test cho xong, và đếm số lần đọc danh sách người giữ ô.
class _SlowRepository extends TerritoryRepository {
  _SlowRepository(super.firestore);

  final owned = Completer<List<TileXY>>();
  var holderReads = 0;

  @override
  Future<List<TileXY>> fetchOwnedCells(String uid, Iterable<TileXY> chunks) =>
      owned.future;

  @override
  Future<List<TerritoryHolder>> fetchHolders() {
    holderReads++;
    return super.fetchHolders();
  }
}
