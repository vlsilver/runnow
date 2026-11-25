import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show SetOptions;
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
import 'package:myrun/src/territory/territory_home_section.dart';
import 'package:myrun/src/territory/territory_mini_map.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_screen.dart';
import 'package:myrun/src/territory/territory_sheets.dart';
import 'package:myrun/src/territory/territory_stats_screen.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/nav_filter.dart';
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

  Widget homeSection() => Scaffold(
    body: SingleChildScrollView(
      child: TerritoryHomeSection(header: (onMore) => const Text('Lãnh địa')),
    ),
  );

  List<Polygon> polygons(WidgetTester tester) =>
      tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons;

  /// Mọi người → chạm [name] → màn số liệu → "Xem trên bản đồ".
  Future<void> pickOnMap(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Người giữ ô'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem bản đồ'));
    await tester.pumpAndSettle();
  }

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
    // Theme Nước có màu chính gần xanh nên ô người khác màu tím.
    expect(other.borderColor, RunNowTerritoryTokens.othersAlt);
    // 1 + 2 ô theo byChunk.
    expect(find.text('Của bạn'), findsOneWidget);
  });

  testWidgets('mở theo ô thì canh giữa ô đó, ô sai lưới thì về chunk', (
    tester,
  ) async {
    await pump(tester, const TerritoryScreen(cell: '208149_115402'));
    var map = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
    // Tâm ô tính tay: lon = 208149,5/2^18·360−180, lat = atan(sinh(π(1−2y/2^18))).
    expect(map.center.longitude, closeTo(105.849838257, 1e-6));
    expect(map.center.latitude, closeTo(21.030032720, 1e-6));
    expect(map.zoom, 16);

    await pump(
      tester,
      const TerritoryScreen(chunk: '6523_3849', cell: '262144_1'),
    );
    map = tester.widget<TerritoryMap>(find.byType(TerritoryMap));
    expect(map.zoom, 15);
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
    expect(find.text('Giữ ô này trong 30 ngày qua'), findsOneWidget);
    // Bình 420 m, người bám sau 300 m (m2).
    expect(find.text('Hạng nhì'), findsOneWidget);
    expect(find.text('0,3 km'), findsOneWidget);
    expect(find.text('Chạy hơn 0,4 km trong ô này để chiếm'), findsOneWidget);

    // Thẻ chỉ để xem, không có nút.
    expect(find.byType(OutlinedButton), findsNothing);
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
    expect(find.text('Của bạn'), findsOneWidget);
  });

  testWidgets('cờ tắt thì không có bản đồ và không có dòng ở Trang chủ', (
    tester,
  ) async {
    await pump(tester, const TerritoryScreen(), enabled: false);
    expect(find.byType(FlutterMap), findsNothing);

    await pump(tester, homeSection(), enabled: false);
    expect(find.textContaining('Lãnh địa'), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
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
    expect(find.text('Bạn cần công khai hồ sơ để được tính ô.'), findsOneWidget);
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
    expect(find.text('Bạn cần công khai hồ sơ để được tính ô.'), findsNothing);
    expect(find.text('Của bạn'), findsOneWidget);
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

  testWidgets('Trang chủ có mục Lãnh địa: bản đồ nhỏ và top 3 có mình', (
    tester,
  ) async {
    await pump(tester, homeSection());
    expect(find.text('Lãnh địa'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    // Bình 5 ô, aa 3 ô, An 3 ô (bằng ô thì theo uid): An đứng hạng 3.
    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('3i member (bạn)'), findsOneWidget);
    // Hạng 3 nằm trong dòng của mình (cạnh chữ cái đầu "3" của avatar).
    final myRow = find
        .ancestor(of: find.text('3i member (bạn)'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: myRow, matching: find.text('3')),
      findsNWidgets(2),
    );
  });

  testWidgets('Trang chủ: số ô của mình đổi thì BXH đọc lại', (tester) async {
    await pump(tester, homeSection());
    // An đang hạng 3 (3 ô, sau Bình 5 ô và aa).
    Finder myRow() => find
        .ancestor(of: find.text('3i member (bạn)'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: myRow(), matching: find.text('1')),
      findsNothing,
    );
    // Backend ghi ô của buổi vừa chạy: doc owner của mình đổi.
    await firestore.collection('territoryOwners').doc('an').set({
      'byChunk': {'6523_3849': 20},
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    // 20 ô, nhiều nhất: An lên hạng 1.
    expect(
      find.descendant(of: myRow(), matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets('Trang chủ: mình ngoài top 3 thì thêm dòng của mình', (
    tester,
  ) async {
    for (final uid in ['c1', 'c2']) {
      await firestore.collection('territoryOwners').doc(uid).set({
        'byChunk': {'6523_3849': 10},
      });
    }
    await pump(tester, homeSection());
    // c1, c2 (10 ô), Bình (5), rồi An hạng 5 (aa đứng trước An).
    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('3i member (bạn)'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('4'), findsNothing);
  });

  testWidgets('Trang chủ: chưa giữ ô vẫn có mục, kèm lời mời chạy', (
    tester,
  ) async {
    await pump(tester, homeSection(), uid: 'moi');
    expect(find.text('Lãnh địa'), findsOneWidget);
    expect(
      find.text('Bạn chưa giữ ô nào, chạy qua ô để có ô.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'avatar lãnh địa theo theme: vuông ở kiểu Thép, tròn ở kiểu gốc',
    (tester) async {
      Future<void> show(RunNowStyle style) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(MockUser(uid: 'an')),
            ),
            leaderboardDocsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: buildRunNowTheme(RunNowElement.water, style: style),
            home: const Scaffold(
              body: TerritoryAvatar(uid: 'binh', name: 'Bình'),
            ),
          ),
        ),
      );
      await show(RunNowStyle.iron);
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.text('B'), findsOneWidget);
      await show(RunNowStyle.elemental);
      // MaterialApp đổi theme dần qua AnimatedTheme.
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsOneWidget);
    },
  );

  testWidgets('bản đồ nhỏ: ô về sau thì dời camera, không dựng lại bản đồ', (
    tester,
  ) async {
    Widget mini(List<TileXY> fit) => MaterialApp(
      theme: buildRunNowTheme(RunNowElement.water),
      home: Scaffold(
        body: SizedBox(
          height: 200,
          child: TerritoryMiniMap(
            center: const LatLng(10.70, 106.60),
            fit: fit,
            polygons: const [],
          ),
        ),
      ),
    );
    await tester.pumpWidget(mini(const []));
    await tester.pump();
    final before = tester.state(find.byType(FlutterMap));
    await tester.pumpWidget(mini(const [binhCell]));
    await tester.pump();
    // Cùng một bản đồ (lớp tile không bị dựng lại), camera đã tới ô.
    expect(tester.state(find.byType(FlutterMap)), same(before));
    final camera = MapCamera.of(tester.element(find.byType(PolygonLayer)));
    expect(
      camera.center.latitude,
      closeTo(cellCenter(binhCell).latitude, 1e-3),
    );
    expect(
      camera.center.longitude,
      closeTo(cellCenter(binhCell).longitude, 1e-3),
    );
  });

  testWidgets('bản đồ nhỏ: cùng số ô nhưng ô khác thì vẫn dời camera', (
    tester,
  ) async {
    const far = TileXY(208830, 123245); // cách hai chunk
    Widget mini(List<TileXY> fit) => MaterialApp(
      theme: buildRunNowTheme(RunNowElement.water),
      home: Scaffold(
        body: SizedBox(
          height: 200,
          child: TerritoryMiniMap(
            center: const LatLng(10.70, 106.60),
            fit: fit,
            polygons: const [],
          ),
        ),
      ),
    );
    await tester.pumpWidget(mini(const [binhCell]));
    await tester.pump();
    await tester.pumpWidget(mini(const [far]));
    await tester.pump();
    final camera = MapCamera.of(tester.element(find.byType(PolygonLayer)));
    expect(camera.center.latitude, closeTo(cellCenter(far).latitude, 1e-3));
    expect(camera.center.longitude, closeTo(cellCenter(far).longitude, 1e-3));
  });

  testWidgets('màn số liệu: chạm ô trên bản đồ mở thông tin ô', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, const TerritoryStatsScreen(uid: 'binh'));
    await tester.pumpAndSettle();
    final camera = MapCamera.of(tester.element(find.byType(PolygonLayer)));
    expect(
      camera.center.latitude,
      closeTo(cellCenter(binhCell).latitude, 1e-3),
    );
    // Bản đồ fit vào ô duy nhất của Bình nên giữa bản đồ là ô đó.
    await tester.tapAt(tester.getCenter(find.byType(TerritoryMiniMap)));
    // Bản đồ có phóng bằng chạm đúp nên chạm đơn chờ hết hạn chạm đúp.
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.byType(TerritoryCellSheet), findsOneWidget);
    expect(find.text('Giữ ô này trong 30 ngày qua'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TerritoryCellSheet),
        matching: find.byType(OutlinedButton),
      ),
      findsNothing,
    );
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

    await tester.tap(find.text('Của bạn'));
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

      await tester.tap(find.byTooltip('Người giữ ô'));
      await tester.pumpAndSettle();
      // Bình 5 ô, rồi aa và An cùng 3 ô thì uid nhỏ trước; doc rỗng không lên.
      // Diện tích: ô ở chunk 3849 (vĩ độ ~10,77°) rộng ~22 555 m², tính tay.
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Bình'), lessThan(y('3i member')));
      expect(y('3i member'), lessThan(y('3i member (bạn)')));
      expect(find.text('11 ha'), findsOneWidget);
      expect(find.text('6,8 ha'), findsNWidgets(2));
      expect(find.text('3 người giữ 25 ha'), findsOneWidget);
      expect(find.text('0 ô'), findsNothing);

      await tester.tap(find.text('Bình'));
      await tester.pumpAndSettle();
      expect(find.text('Lãnh địa của Bình'), findsOneWidget);
      expect(find.text('Hạng 1 trong 3 người giữ ô'), findsOneWidget);
      await tester.tap(find.text('Xem bản đồ'));
      await tester.pumpAndSettle();
      final drawn = polygons(tester);
      expect(drawn, hasLength(1));
      expect(drawn.single.borderColor, isNot(accent));
      // Ô tên người đang lọc nằm trong nút chọn; bấm Tất cả thì về tất cả.
      expect(
        find.descendant(
          of: find.byType(NavPillToggle<String?>),
          matching: find.text('Bình'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tất cả'));
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

    await pickOnMap(tester, 'Bình');
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

      await pickOnMap(tester, 'Bình');
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

    await pickOnMap(tester, 'Bình');
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
    await pickOnMap(tester, 'Bình');

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

    await pickOnMap(tester, 'Bình');
    await tester.tap(find.text('Tất cả'));
    await tester.pump();
    repo.owned.complete(const [
      TerritoryCell(tile: binhCell, ownerUid: 'binh', meters: 420),
    ]);
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

    await pickOnMap(tester, 'Bình');
    await tester.drag(find.byType(FlutterMap), const Offset(100, 0));
    await tester.pumpAndSettle();
    final dragged = camera().center;
    repo.owned.complete(const [
      TerritoryCell(tile: binhCell, ownerUid: 'binh', meters: 420),
    ]);
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
      await tester.tap(find.byTooltip('Người giữ ô'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // đóng sheet
      await tester.pumpAndSettle();
    }
    expect(repo.holderReads, 1);
  });

  testWidgets('chạm ô của mình: không có câu để chiếm, không có bám sau', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(mineCell), zoom: 17)),
    );
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(find.text('1,2 km'), findsOneWidget);
    expect(find.textContaining('để chiếm'), findsNothing);
    expect(find.text('Hạng nhì'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('Luật chơi mở luật lãnh địa', (tester) async {
    await pump(tester, const TerritoryScreen(chunk: '6523_3849'));
    await tester.tap(find.text('Luật chơi'));
    await tester.pumpAndSettle();
    expect(find.text('Luật lãnh địa'), findsOneWidget);
    expect(find.text('Ai chạy nhiều km nhất thì giữ ô'), findsOneWidget);
  });

  testWidgets(
    'Thông số đọc ô ở mọi chunk và tính tổng km, ô chắc nhất, bám sát',
    (tester) async {
      await firestore.collection('territoryOwners').doc('chi').set({
        'byChunk': {'6523_3849': 1, '6524_3849': 1},
      });
      await firestore.collection('territoryChunks').doc('6523_3849').set({
        'cells': {
          '208760_123181': {'u': 'chi', 'm': 1000, 'm2': 900},
        },
      }, SetOptions(merge: true));
      await firestore.collection('territoryChunks').doc('6524_3849').set({
        'cells': {
          '208770_123181': {'u': 'chi', 'm': 2500},
        },
      });
      await pump(tester, const TerritoryStatsScreen(uid: 'chi'));
      await tester.pumpAndSettle();

      // Hai ô ở hai chunk: 1000 + 2500 m; ô chắc nhất 2500 m; 900/1000 ≥ 80%.
      expect(find.text('3,5 km'), findsOneWidget);
      expect(find.text('2,5 km'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Bị bám sát'),
                matching: find.byType(Column),
              )
              .first,
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('chữ trên avatar của mình đọc được trên màu chính', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(body: TerritoryMap(center: cellCenter(mineCell), zoom: 17)),
    );
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(TerritoryAvatar));
    final initial = tester.widget<Text>(
      find.descendant(
        of: find.byType(TerritoryAvatar),
        matching: find.byType(Text),
      ),
    );
    expect(initial.style?.color, context.runNowPalette.onAccent);
  });

  testWidgets(
    'mở từ push bị chiếm: thẻ người chiếm, viền ô vừa mất, đóng được',
    (tester) async {
      // Push: Bình chiếm 2 ô của An. binhCell nay của Bình; mineCell An đã
      // giành lại nên không viền.
      await pump(
        tester,
        const TerritoryScreen(
          chunk: '6523_3849',
          taken: (uid: 'binh', count: 2, cells: [binhCell, mineCell], to: 'an'),
        ),
      );
      await tester.pumpAndSettle();
      // Số ô lấy từ push, không đếm lại.
      expect(find.text('Bình chiếm 2 ô của bạn'), findsOneWidget);
      final dashed = polygons(
        tester,
      ).where((p) => p.pattern != const StrokePattern.solid()).toList();
      expect(dashed, hasLength(1));
      expect(
        dashed.single.points.first.latitude,
        closeTo(cellCorners(binhCell).first.latitude, 1e-12),
      );
      // Bản đồ fit vào hai ô (zoom trần 17), ô vừa mất nằm trong màn hình.
      final camera = MapCamera.of(tester.element(find.byType(PolygonLayer)));
      expect(camera.zoom, 17);
      expect(camera.visibleBounds.contains(cellCenter(binhCell)), isTrue);

      await tester.tap(find.byTooltip('Đóng'));
      await tester.pump();
      expect(find.text('Bình chiếm 2 ô của bạn'), findsNothing);
      expect(polygons(tester), hasLength(2));
    },
  );

  testWidgets('push gửi cho tài khoản khác thì không có thẻ bị chiếm', (
    tester,
  ) async {
    await pump(
      tester,
      const TerritoryScreen(
        chunk: '6523_3849',
        taken: (uid: 'binh', count: 2, cells: [binhCell], to: 'chi'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('chiếm'), findsNothing);
  });

  testWidgets('mở thường thì không có thẻ bị chiếm', (tester) async {
    await pump(tester, const TerritoryScreen(chunk: '6523_3849'));
    expect(find.textContaining('chiếm'), findsNothing);
  });
}

/// Đọc ô chờ test cho xong, và đếm số lần đọc danh sách người giữ ô.
class _SlowRepository extends TerritoryRepository {
  _SlowRepository(super.firestore);

  final owned = Completer<List<TerritoryCell>>();
  var holderReads = 0;

  @override
  Future<List<TerritoryCell>> fetchOwnedCells(
    String uid,
    Iterable<TileXY> chunks,
  ) => owned.future;

  @override
  Future<List<TerritoryHolder>> fetchHolders() {
    holderReads++;
    return super.fetchHolders();
  }
}
