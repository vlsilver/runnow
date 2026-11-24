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
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(firestore),
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
    expect(find.text('3 ô'), findsOneWidget);
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
    expect(find.text('0 ô'), findsOneWidget);
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
    expect(find.text('3 ô'), findsNothing);
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
    expect(find.text('3 ô'), findsOneWidget);
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
}
