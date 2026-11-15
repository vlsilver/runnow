import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/share.dart';

void main() {
  testWidgets('captures a widget as PNG bytes', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const ColoredBox(color: Colors.teal),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final png = (await tester.runAsync(() => captureRecapPng(boundary)))!;
    expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('a card that is not laid out yet fails instead of sharing nothing', () {
    expect(captureRecapPng(null), throwsStateError);
  });

  group('shareFrameLayout', () {
    test('thẻ vuông trên Story: rộng hết vùng an toàn, dấu 3I RUN nằm dưới', () {
      // Vùng an toàn 952×1420 từ (64, 250). Thẻ co về 952×952, thừa 468 px
      // cao; trừ dải dấu 150 còn 318, chia đôi: thẻ bắt đầu ở 250 + 159 = 409.
      final layout = shareFrameLayout(
        const Size(1080, 1080),
        ShareFormat.story,
      );
      expect(layout.content, const Rect.fromLTWH(64, 409, 952, 952));
      expect(layout.stamp, const Rect.fromLTWH(64, 1361, 952, 150));
    });

    test('thẻ 3:4 trên Feed: cao hết vùng an toàn, không còn chỗ cho dấu', () {
      // Vùng an toàn 952×1222. 1222 / 1200 = 1,01833; rộng 900 × 1,01833 =
      // 916,5; lề trái (1080 - 916,5) / 2 = 81,75.
      final layout = shareFrameLayout(const Size(900, 1200), ShareFormat.feed);
      expect(layout.content.left, closeTo(81.75, 0.001));
      expect(layout.content.top, closeTo(64, 0.001));
      expect(layout.content.width, closeTo(916.5, 0.001));
      expect(layout.content.height, closeTo(1222, 0.001));
      expect(layout.stamp, isNull);
    });

    test('thẻ 9:16 trên Story: co cho lọt vùng an toàn, nằm giữa ngang', () {
      // 1420 / 1920 = 0,739583; rộng 1080 × 0,739583 = 798,75; lề trái
      // (1080 - 798,75) / 2 = 140,625.
      final layout = shareFrameLayout(
        const Size(1080, 1920),
        ShareFormat.story,
      );
      expect(layout.content.left, closeTo(140.625, 0.001));
      expect(layout.content.top, closeTo(250, 0.001));
      expect(layout.content.width, closeTo(798.75, 0.001));
      expect(layout.content.height, closeTo(1420, 0.001));
      expect(layout.stamp, isNull);
    });
  });

  testWidgets('frameShareImage ra file đúng cỡ của khổ, nền phủ kín', (
    tester,
  ) async {
    Future<ui.Image> framed(ShareFormat format) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 40, 40),
        Paint()..color = const Color(0xFFFF0000),
      );
      final card = await recorder.endRecording().toImage(40, 40);
      final png = await frameShareImage(
        card,
        format,
        background: const Color(0xFF102030),
      );
      final codec = await ui.instantiateImageCodec(png);
      return (await codec.getNextFrame()).image;
    }

    await tester.runAsync(() async {
      final story = await framed(ShareFormat.story);
      expect((story.width, story.height), (1080, 1920));
      final feed = await framed(ShareFormat.feed);
      expect((feed.width, feed.height), (1080, 1350));
      final rgba = (await feed.toByteData())!;
      // Góc trên trái là nền, tâm ảnh là thẻ đỏ.
      expect(rgba.buffer.asUint8List(0, 4), [0x10, 0x20, 0x30, 0xFF]);
      final centre = (675 * 1080 + 540) * 4;
      expect(rgba.buffer.asUint8List(centre, 4), [0xFF, 0x00, 0x00, 0xFF]);
    });
  });

  group('khổ chia sẻ', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('chưa cài đặt gì thì là Story', () {
      expect(
        ShareFormatController(loadFromStorage: false).format,
        ShareFormat.story,
      );
    });

    test('chọn Feed thì mở lại app vẫn là Feed', () async {
      await ShareFormatController(
        loadFromStorage: false,
      ).setFormat(ShareFormat.feed);
      final reopened = ShareFormatController();
      await Future<void>.delayed(Duration.zero);
      expect(reopened.format, ShareFormat.feed);
    });

    testWidgets('bảng trong Cài đặt: bấm ô Feed thì khổ chia sẻ thành Feed', (
      tester,
    ) async {
      final controller = ShareFormatController(loadFromStorage: false);
      late BuildContext page;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            shareFormatControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                page = context;
                return TextButton(
                  onPressed: () => showShareFormatSheet(context),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      expect(shareFormatOf(page), ShareFormat.story);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-format-feed')));
      await tester.pumpAndSettle();
      expect(shareFormatOf(page), ShareFormat.feed);
      expect(find.byKey(const ValueKey('share-format-feed')), findsNothing);
    });
  });
}
