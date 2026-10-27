import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';

const _light = RunNowAppearance.light;
const _dark = RunNowAppearance.dark;

AchievementCardData _blank(Widget art) => AchievementCardData(
  tier: GameCardTier.common,
  art: art,
  kind: '',
  hero: '',
  title: '',
  owner: '',
  serial: '',
  desc: '',
  meta: '',
  date: '25.10.2026',
);

void main() {
  group('controller', () {
    test('saves the choice and reads it back after a restart', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const storage = FlutterSecureStorage();
      final controller = RunCardSkinController(
        storage: storage,
        loadFromStorage: false,
      );

      await controller.setChoice((_dark, RunNowElement.fire));
      expect(await storage.read(key: 'runnow_card_skin'), 'dark.fire');

      final restarted = RunCardSkinController(storage: storage);
      await pumpEventQueue();
      expect(restarted.choice, (_dark, RunNowElement.fire));
    });

    test('going back to the app theme forgets the saved choice', () async {
      FlutterSecureStorage.setMockInitialValues({
        'runnow_card_skin': 'light.wood',
      });
      const storage = FlutterSecureStorage();
      final controller = RunCardSkinController(storage: storage);
      await pumpEventQueue();
      expect(controller.choice, (_light, RunNowElement.wood));

      await controller.setChoice(null);
      expect(controller.choice, isNull);
      expect(await storage.read(key: 'runnow_card_skin'), isNull);
    });

    test('a pick made before the saved value loads is kept', () async {
      FlutterSecureStorage.setMockInitialValues({
        'runnow_card_skin': 'light.wood',
      });
      final controller = RunCardSkinController();
      // Chọn ngay, trước khi đọc máy xong.
      await controller.setChoice((_dark, RunNowElement.metal));
      await pumpEventQueue();
      expect(controller.choice, (_dark, RunNowElement.metal));
    });

    test('a broken saved value falls back to the app theme', () {
      expect(parseRunCardSkinChoice(null), isNull);
      expect(parseRunCardSkinChoice('dark'), isNull);
      expect(parseRunCardSkinChoice('dim.fire'), isNull);
      expect(parseRunCardSkinChoice('dark.aether'), isNull);
      expect(parseRunCardSkinChoice('light.earth'), (
        _light,
        RunNowElement.earth,
      ));
    });
  });

  test('cards follow the app theme until a choice is saved', () {
    final follow = resolveRunCardSkin(
      appAppearance: _light,
      appElement: RunNowElement.water,
      choice: null,
    );
    expect(follow.id, 'light.water');
    final chosen = resolveRunCardSkin(
      appAppearance: _light,
      appElement: RunNowElement.water,
      choice: (_dark, RunNowElement.fire),
    );
    expect(chosen.id, 'dark.fire');
    // Cùng lựa chọn thì cùng object, thẻ không vẽ lại thừa.
    expect(
      identical(follow, RunCardSkin.forTheme(_light, RunNowElement.water)),
      isTrue,
    );
  });

  testWidgets('the light skin keeps text zones light on a black photo', (
    tester,
  ) async {
    late MemoryImage black;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF000000), BlendMode.src);
      final image = await recorder.endRecording().toImage(30, 42);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      black = MemoryImage(png!.buffer.asUint8List());
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RunCardSkinScope(
            skin: RunCardSkin.forTheme(_light, RunNowElement.water),
            child: RepaintBoundary(
              key: boundary,
              child: AchievementCard(
                animate: false,
                data: _blank(Image(image: black, fit: BoxFit.cover)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(black, tester.element(find.byKey(boundary)));
    });
    await tester.pump();

    late ByteData pixels;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      pixels = (await (await render.toImage()).toByteData())!;
    });
    final width = achievementCardSize.width.toInt();
    int luma(double fx, double fy) {
      final x = (achievementCardSize.width * fx).toInt();
      final y = (achievementCardSize.height * fy).toInt();
      final i = (y * width + x) * 4;
      return (pixels.getUint8(i) +
              pixels.getUint8(i + 1) +
              pixels.getUint8(i + 2)) ~/
          3;
    }

    // Chữ mực cần nền sáng: khối chữ trên nét chân thẻ (giấy E9F0F2 phủ ~92%,
    // 238·0,92 ≈ 219) và chân thẻ phải sáng, phần trên và giữa thẻ vẫn là ảnh.
    expect(luma(0.5, 0.8), greaterThan(170), reason: 'khối chữ');
    expect(luma(0.15, 0.94), greaterThan(200), reason: 'chân thẻ');
    expect(luma(0.5, 0.25), lessThan(40), reason: 'trên tranh');
    expect(luma(0.5, 0.42), lessThan(40), reason: 'giữa ảnh');
  });

  testWidgets('the sheet saves a picked skin and can go back to the app', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final skins = RunCardSkinController(loadFromStorage: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themeControllerProvider.overrideWith(
            (ref) => ThemeController(loadFromStorage: false),
          ),
          runCardSkinControllerProvider.overrideWith((ref) => skins),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRunCardSkinSheet(context),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> open() async {
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
    }

    Future<void> tapVisible(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await open();
    expect(find.text('Đang là Thủy · Sáng'), findsOneWidget);
    // Đang theo app thì chưa chọn hành được.
    await tapVisible(find.text('Hỏa'));
    await tapVisible(find.text('Áp dụng'));
    expect(skins.choice, isNull);

    await open();
    await tapVisible(find.text('Theo theme app'));
    await tapVisible(find.text('Tối'));
    await tapVisible(find.text('Hỏa'));
    await tapVisible(find.text('Áp dụng'));
    expect(skins.choice, (_dark, RunNowElement.fire));

    await open();
    await tapVisible(find.text('Theo theme app'));
    await tapVisible(find.text('Áp dụng'));
    expect(skins.choice, isNull);
  });
}
