// E2E thẻ thành tích trên máy thật: ảnh do Gemini vẽ từ thông số kèo, mở
// viewer 3D, nghiêng, lật, xuất ảnh khoe, đo khung hình lúc hiệu ứng chạy.
//
// Chạy (profile để số đo khung hình có nghĩa; --no-dds để watchPerformance
// nối được VM Service; --keep-app-running vì flutter drive mặc định gỡ app
// khi xong, mất luôn ảnh trong Documents và app cùng bundle id trên máy):
//   flutter drive --profile --no-dds --keep-app-running \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/achievement_card_e2e_test.dart -d <iphone>
// report.json nằm ở build/e2e/achievement/. Ảnh chụp và ảnh xuất ghi vào
// Documents/e2e của app trên máy, kéo về bằng:
//   xcrun devicectl device copy from --device <iphone> \
//     --domain-type appDataContainer --domain-identifier com.threei.run \
//     --source Documents/e2e --destination build/e2e/achievement
// Gửi ảnh qua VM Service thì gói dữ liệu cả trăm MB làm đứt kết nối.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:path_provider/path_provider.dart';

import 'fixtures/achievement_e2e_cards.dart';

/// Khoá bậc của fixture: `super` là siêu hiếm, khác khoá `epic` của backend.
GameCardTier _tierFromKey(String key) => switch (key) {
  'rare' => GameCardTier.rare,
  'super' => GameCardTier.superRare,
  'legendary' => GameCardTier.legendary,
  'mythic' => GameCardTier.mythic,
  _ => GameCardTier.common,
};

/// Thẻ chữ dài nhất có thể, để bắt tràn chữ trên font thật của máy.
const _longText = E2ECard(
  key: 'long',
  tier: 'legendary',
  styleName: 'Chữ dài',
  kind: 'CỘT MỐC HÀNH TRÌNH XUYÊN VIỆT',
  hero: '1.234,5',
  title: 'Hội Chạy Bộ Phường Phúc Xá Quyết Không Bỏ Cuộc Giữa Chừng',
  desc:
      'Một câu mô tả rất dài để xem chữ có tràn không khi người viết kèo '
      'nhập quá nhiều chữ vào phần mô tả của thẻ.',
  owner: 'NGUYỄN THỊ PHƯƠNG THẢO HOÀNG',
  serial: 'Nº 128/128',
  meta: 'KÈO 1.000 KM · 120 NGÀY · 128 NGƯỜI · CHẠY BỀN',
  date: '31.12.2026',
  art: '',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Engine tự vẽ khung hình như app thật, để đo được animation.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('thẻ thành tích: render, nghiêng, lật, xuất ảnh, khung hình', (
    tester,
  ) async {
    final exported = ValueNotifier<Uint8List?>(null);
    final arts = {
      for (final c in e2eCards) c.key: MemoryImage(base64Decode(c.art)),
    };
    final cards = [
      ...e2eCards,
      _longText.withArt(e2eCards.last.art),
    ];
    arts['long'] = arts[e2eCards.last.key]!;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildRunNowDarkTheme(),
        home: _Lab(cards: cards, arts: arts, exported: exported),
      ),
    );
    await _wait(tester, 300);

    final report = <String, Object?>{};
    final out = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/e2e',
    );
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    Future<void> snap(String name) async {
      final png = await binding.takeScreenshot(name);
      await File('${out.path}/$name.png').writeAsBytes(png);
    }

    // Giải mã ảnh trước, như app sẽ tải và giải mã trước khi lật thẻ ra.
    final labContext = tester.element(find.byType(_Lab));
    final decode = <String, int>{};
    for (final c in e2eCards) {
      final watch = Stopwatch()..start();
      await precacheImage(arts[c.key]!, labContext);
      decode[c.key] = watch.elapsedMilliseconds;
    }
    report['decode_ms'] = decode;

    final perf = <String, Object?>{};
    final shareSizes = <String, Object?>{};
    for (final c in cards) {
      await tester.tap(find.byKey(ValueKey('open-${c.key}')));
      await _wait(tester, 900);
      expect(find.byType(AchievementCard), findsOneWidget);
      await snap('${c.key}-1-front');

      // Giữ tay kéo chéo lên phải: thẻ nghiêng, holo và vệt sáng chạy theo.
      final center = tester.getCenter(find.byType(AchievementCard));
      final hold = await tester.startGesture(center);
      for (var i = 0; i < 12; i++) {
        await hold.moveBy(const Offset(10, -7));
        await tester.pump();
      }
      await _wait(tester, 250);
      await snap('${c.key}-2-tilt');
      await hold.up();
      await _wait(tester, 700);

      await tester.tap(find.byType(AchievementCard));
      await _wait(tester, 900);
      expect(find.text('THẺ THÀNH TÍCH'), findsOneWidget);
      await snap('${c.key}-3-back');
      await tester.tap(find.byType(AchievementCard));
      await _wait(tester, 900);

      if (c.key != 'long') {
        perf[c.key] = await _measure(binding, tester, c.key);
      }

      exported.value = null;
      await tester.tap(find.text('Khoe thẻ'));
      final png = await _until(exported);
      final size = await _pngSize(png);
      final cardBox = tester.getSize(find.byType(GameCardScaled));
      shareSizes[c.key] = {
        'width': size.width,
        'height': size.height,
        'bytes': png.length,
        'card_logical_width': cardBox.width,
      };
      // Ảnh khoe chụp ở 3x bề ngang thẻ và giữ tỉ lệ 5:7.
      expect(size.width, closeTo(cardBox.width * 3, 2));
      expect(size.height / size.width, closeTo(420 / 300, 0.01));
      await File('${out.path}/export-${c.key}.png').writeAsBytes(png);

      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 500);
    }

    report['share_png'] = shareSizes;
    report['perf'] = perf;
    report['cards'] = {
      for (final c in e2eCards)
        c.key: {
          'tier': c.tier,
          'style': c.styleName,
          'title': c.title,
          'desc_chars': c.desc.length,
          'title_chars': c.title.length,
        },
    };
    // Ngưỡng khung hình do test_driver chấm: test fail thì integrationDriver
    // không gửi reportData về máy, sẽ mất cả số đo. Ảnh đã nằm trên đĩa nên
    // bỏ khỏi gói gửi về.
    binding.reportData = {...?binding.reportData, ...report}
      ..remove('screenshots');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// Đứng yên 3 giây (đung đưa, viền xoay, sao nhấp nháy) rồi kéo qua lại 2
/// giây, như người cầm máy ngắm thẻ.
Future<Map<String, Object?>> _measure(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String key,
) async {
  final reportKey = 'perf_$key';
  await binding.watchPerformance(() async {
    await Future<void>.delayed(const Duration(seconds: 3));
    final center = tester.getCenter(find.byType(AchievementCard));
    final hold = await tester.startGesture(center);
    for (var i = 0; i < 120; i++) {
      final dx = math.cos(i / 10) * 9;
      final dy = math.sin(i / 7) * 6;
      await hold.moveBy(Offset(dx, dy));
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await hold.up();
    await Future<void>.delayed(const Duration(seconds: 1));
  }, reportKey: reportKey);
  return Map<String, Object?>.from(binding.reportData![reportKey]! as Map);
}

Future<void> _wait(WidgetTester tester, int ms) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await tester.pump();
}

Future<Uint8List> _until(ValueNotifier<Uint8List?> value) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (value.value == null) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Không xuất được ảnh khoe sau 10 giây');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return value.value!;
}

Future<Size> _pngSize(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final size = Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  return size;
}

/// Màn thử: mỗi thẻ một nút mở viewer, nút khoe chụp ảnh bằng đúng hàm chụp
/// của app nhưng không mở bảng chia sẻ iOS (test không đóng được nó).
class _Lab extends StatelessWidget {
  const _Lab({
    required this.cards,
    required this.arts,
    required this.exported,
  });

  final List<E2ECard> cards;
  final Map<String, ImageProvider> arts;
  final ValueNotifier<Uint8List?> exported;

  AchievementCardData _data(E2ECard c) => AchievementCardData(
    tier: _tierFromKey(c.tier),
    art: Image(
      image: arts[c.key]!,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    ),
    kind: c.kind,
    hero: c.hero,
    title: c.title,
    owner: c.owner,
    serial: c.serial,
    desc: c.desc,
    meta: c.meta,
    date: c.date,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton(
                  key: ValueKey('open-${c.key}'),
                  onPressed: () {
                    final data = _data(c);
                    showCardViewer(
                      context,
                      cardSize: achievementCardSize,
                      chips: [
                        gameCardTiers[data.tier]!.label,
                        c.styleName,
                      ],
                      front: (pose) => AchievementCard(data: data, pose: pose),
                      back: (pose) => AchievementCard(
                        data: data,
                        pose: Offset(-pose.dx, pose.dy),
                        back: true,
                      ),
                      onShare: (cardKey, _) async {
                        final boundary =
                            cardKey.currentContext?.findRenderObject()
                                as RenderRepaintBoundary?;
                        exported.value = await captureRecapPng(boundary);
                      },
                    );
                  },
                  child: Text('${c.key} · ${c.styleName}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
