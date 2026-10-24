import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_role_card.dart';

// PNG 1x1 trong suốt, đủ để Image có ảnh mà không cần mạng hay asset.
final _pixel = MemoryImage(
  Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]),
);

AchievementCardData _data(
  GameCardTier tier, {
  String title = 'Bình Minh Long Biên',
  String owner = 'AN NGUYỄN',
  String desc = 'Cả hội dắt nhau về đích 50 km.',
  String meta = 'KÈO 50 KM · 14 NGÀY · 5 NGƯỜI',
}) => AchievementCardData(
  tier: tier,
  art: _pixel,
  kind: 'KÈO HOÀN THÀNH',
  hero: '52,3',
  title: title,
  owner: owner,
  serial: 'Nº 03/05',
  desc: desc,
  meta: meta,
  date: '24.10.2026',
);

Future<void> _pump(WidgetTester tester, Widget card) {
  return tester.pumpWidget(
    MaterialApp(home: Center(child: card)),
  );
}

void main() {
  testWidgets('each tier shows its own label on the card', (tester) async {
    for (final (tier, label) in const [
      (GameCardTier.common, 'THƯỜNG'),
      (GameCardTier.rare, 'HIẾM'),
      (GameCardTier.superRare, 'SIÊU HIẾM'),
      (GameCardTier.legendary, 'HUYỀN THOẠI'),
    ]) {
      await _pump(tester, AchievementCard(data: _data(tier), animate: false));
      expect(find.text(label), findsOneWidget, reason: '$tier');
      expect(find.text('52,3'), findsOneWidget);
    }
  });

  testWidgets('long user text stays inside the card', (tester) async {
    await _pump(
      tester,
      AchievementCard(
        animate: false,
        data: _data(
          GameCardTier.legendary,
          title: 'Hội Chạy Bộ Phường Phúc Xá Quyết Không Bỏ Cuộc Giữa Chừng '
              'Dù Trời Mưa Hay Nắng',
          owner: 'NGUYỄN THỊ PHƯƠNG THẢO HOÀNG LÊ',
          desc: 'Một câu mô tả rất dài ' * 12,
          meta: 'KÈO 1.000 KM · 120 NGÀY · 128 NGƯỜI · CHẠY BỀN MỖI NGÀY',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AchievementCard)), achievementCardSize);
    // Chữ dài không được dâng lên che ảnh: tên tối đa 2 dòng (21 x 1,12),
    // mô tả tối đa 2 dòng (10,5 x 1,38).
    final title = find.textContaining('Hội Chạy Bộ').last;
    expect(tester.getSize(title).height, lessThanOrEqualTo(2 * 21 * 1.12 + 1));
    final desc = find.textContaining('Một câu mô tả');
    expect(tester.getSize(desc).height, lessThanOrEqualTo(2 * 10.5 * 1.38 + 1));
  });

  testWidgets('text zones stay dark on a pure white photo', (tester) async {
    late MemoryImage white;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
      final image = await recorder.endRecording().toImage(30, 42);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      white = MemoryImage(png!.buffer.asUint8List());
    });
    final data = _data(GameCardTier.common);
    final boundary = GlobalKey();
    await _pump(
      tester,
      RepaintBoundary(
        key: boundary,
        child: AchievementCard(
          animate: false,
          data: AchievementCardData(
            tier: data.tier,
            art: white,
            kind: '',
            hero: '',
            title: '',
            owner: '',
            serial: '',
            desc: '',
            meta: '',
            date: data.date,
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(white, tester.element(find.byKey(boundary)));
    });
    await tester.pump();

    late ByteData pixels;
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      pixels = (await image.toByteData())!;
    });
    final width = achievementCardSize.width.toInt();
    int luma(double fx, double fy) {
      final x = (achievementCardSize.width * fx).toInt();
      final y = (achievementCardSize.height * fy).toInt();
      final i = (y * width + x) * 4;
      return (pixels.getUint8(i) + pixels.getUint8(i + 1) + pixels.getUint8(i + 2)) ~/ 3;
    }

    // Góc nhãn bậc và chân thẻ phải tối, giữa thẻ vẫn là ảnh.
    expect(luma(0.85, 0.06), lessThan(128), reason: 'nhãn bậc');
    expect(luma(0.15, 0.94), lessThan(40), reason: 'chân thẻ');
    expect(luma(0.5, 0.42), greaterThan(200), reason: 'giữa ảnh');
  });

  testWidgets('only a legendary card keeps animating', (tester) async {
    await _pump(tester, AchievementCard(data: _data(GameCardTier.superRare)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _pump(tester, AchievementCard(data: _data(GameCardTier.legendary)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await _pump(
      tester,
      AchievementCard(data: _data(GameCardTier.legendary), animate: false),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the back shows the date and tier, not the front text', (
    tester,
  ) async {
    await _pump(
      tester,
      AchievementCard(
        data: _data(GameCardTier.superRare),
        back: true,
        animate: false,
      ),
    );
    expect(find.text('THẺ THÀNH TÍCH'), findsOneWidget);
    expect(find.text('24.10.2026'), findsOneWidget);
    expect(find.text('SIÊU HIẾM'), findsOneWidget);
    expect(find.text('Bình Minh Long Biên'), findsNothing);
  });
}
