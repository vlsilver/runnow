import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_screen.dart';
import 'package:myrun/src/territory/territory_share.dart';
import 'package:myrun/src/theme.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// Font thật của app, vì font giả của test thấp hơn nên không lộ chỗ tràn.
Future<void> _loadFonts() async {
  const fonts = {
    'Exo 2': ['exo2/Exo2-Variable.ttf'],
    'Barlow Condensed': [
      'barlow_condensed/BarlowCondensed-SemiBold.ttf',
      'barlow_condensed/BarlowCondensed-Bold.ttf',
      'barlow_condensed/BarlowCondensed-ExtraBold.ttf',
    ],
    'VT323': ['vt323/VT323-Regular.ttf'],
  };
  for (final MapEntry(key: family, value: files) in fonts.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

void main() {
  group('vẽ ô lên thẻ', () {
    test('canh giữa, giữ ô vuông theo cạnh hẹp', () {
      // Khối 2 cột × 3 hàng trong khung 100×100 chừa 10: cạnh ô
      // min(80/2, 80/3) = 26,67; khối rộng 53,33 nên lề trái 10 + 13,33.
      final rects = territoryArtRects(
        const [TileXY(10, 10), TileXY(11, 10), TileXY(10, 12)],
        const Size(100, 100),
        padding: 10,
      );
      const side = 80 / 3;
      const left = 10 + (80 - 2 * side) / 2;
      expect(rects[0].left, closeTo(left, 1e-9));
      expect(rects[0].top, closeTo(10, 1e-9));
      expect(rects[0].width, closeTo(side, 1e-9));
      expect(rects[1].left, closeTo(left + side, 1e-9));
      expect(rects[2].top, closeTo(10 + 2 * side, 1e-9));
      expect(rects[2].bottom, closeTo(90, 1e-9));
    });

    test('một ô không phình ra cả thẻ', () {
      final rects = territoryArtRects(
        const [TileXY(5, 5)],
        const Size(100, 100),
        padding: 10,
        maxSide: 40,
      );
      expect(rects.single, const Rect.fromLTWH(30, 30, 40, 40));
    });

    test('không có ô thì không vẽ', () {
      expect(territoryArtRects(const [], const Size(100, 100)), isEmpty);
    });
  });

  test('chỉ vẽ chunk nhiều ô nhất và 8 chunk quanh nó', () {
    final owner = TerritoryOwner.fromMap({
      'byChunk': {
        '6523_3849': 5, // nhiều ô nhất
        '6524_3850': 2, // chéo góc, vẫn là hàng xóm
        '6522_3849': 1,
        '6525_3849': 3, // cách hai cột
        '6600_3700': 4, // thành phố khác
      },
    });
    expect(territoryShareChunks(owner).toSet(), {
      const TileXY(6523, 3849),
      const TileXY(6524, 3850),
      const TileXY(6522, 3849),
    });
    expect(territoryShareChunks(TerritoryOwner.fromMap(null)), isEmpty);
  });

  test('câu kèm ảnh', () {
    expect(
      territoryShareCaption('An', '2,6 km²'),
      'An giữ 2,6 km² lãnh địa trên 3i',
    );
  });

  testWidgets('thẻ lãnh địa không tràn ở mọi kiểu theme', (tester) async {
    await tester.runAsync(_loadFonts);
    for (final style in RunNowStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(style),
          theme: buildRunNowTheme(RunNowElement.fire, style: style),
          home: Material(
            child: Center(
              child: TerritoryPoster(
                name: 'Nguyễn Văn Một Cái Tên Rất Dài Cho Thẻ',
                area: '27,8 km²',
                cellCount: 1234,
                cells: const [TileXY(1, 1), TileXY(40, 9)],
                date: DateTime(2026, 11, 5),
              ),
            ),
          ),
        ),
      );
      expect(find.text('1234 ô'), findsOneWidget);
      expect(find.text('27,8 km²'), findsOneWidget);
      expect(find.text('05.11.2026'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('khoe lãnh địa gửi ảnh PNG chỉ có ô của mình', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    // Màn có bản đồ; cache tile của flutter_map hỏi thư mục cache khi chạy
    // runAsync.
    final cacheDir = Directory.systemTemp.createTempSync('territory_share');
    addTearDown(() => cacheDir.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cacheDir.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );
    final share = _FakeShare();
    SharePlatform.instance = share;
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('territoryChunks').doc('6523_3849').set({
      'cells': {
        '208766_123181': {'u': 'an', 'm': 900},
        '208767_123181': {'u': 'binh', 'm': 420},
      },
    });
    await firestore.collection('territoryChunks').doc('6524_3849').set({
      'cells': {
        '208768_123181': {'u': 'an', 'm': 300},
      },
    });
    // Ô ở thành phố khác (chunk 6600_3700) không lên thẻ, nhưng vẫn tính vào
    // số ô.
    await firestore.collection('territoryChunks').doc('6600_3700').set({
      'cells': {
        '211200_118400': {'u': 'an', 'm': 500},
      },
    });
    await firestore.collection('territoryOwners').doc('an').set({
      'byChunk': {'6523_3849': 1, '6524_3849': 1, '6600_3700': 1},
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(firestore),
          ),
          territoryEnabledProvider.overrideWith((ref) => Stream.value(true)),
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(MockUser(uid: 'an')),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(
              const UserProfile(athleteId: '1', displayName: 'An'),
            ),
          ),
          leaderboardDocsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildRunNowDarkTheme(),
          home: const TerritoryScreen(chunk: '6523_3849'),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Khoe lãnh địa'));
      for (
        var i = 0;
        i < 20 && find.byType(TerritoryPoster).evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    final poster = tester.widget<TerritoryPoster>(find.byType(TerritoryPoster));
    expect(poster.cells.toSet(), {
      const TileXY(208766, 123181),
      const TileXY(208768, 123181),
    });
    expect(poster.cellCount, 3);
    // 2 ô ở chunk y=3849 và 1 ô ở y=3700: 66 454,6 m², tính tay.
    expect(poster.area, '6,6 ha');
    expect(poster.name, 'An');
    // Khổ ảnh theo Cài đặt như mọi thẻ khác, sheet không hỏi lại.
    expect(find.text('Story'), findsNothing);
    expect(find.text('Feed'), findsNothing);
    // Ô vẽ trên nền bản đồ.
    expect(
      find.descendant(
        of: find.byType(TerritoryPoster),
        matching: find.byType(FlutterMap),
      ),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Chia sẻ'));
      for (var i = 0; i < 40 && share.shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    final params = share.shared.single;
    expect(params.text, 'An giữ 6,6 ha lãnh địa trên 3i');
    expect(params.files!.single.mimeType, 'image/png');
  });
}
