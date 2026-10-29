import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

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
  art: Image(image: _pixel, fit: BoxFit.cover),
  kind: 'KÈO HOÀN THÀNH',
  hero: '52,3',
  title: title,
  owner: owner,
  serial: 'Nº 03/05',
  desc: desc,
  meta: meta,
  date: '24.10.2026',
);

AchievementCardData _secret(AchievementCardData d, RunNowElement element) =>
    AchievementCardData(
      tier: d.tier,
      art: d.art,
      kind: d.kind,
      hero: d.hero,
      heroUnit: d.heroUnit,
      title: d.title,
      owner: d.owner,
      serial: d.serial,
      desc: d.desc,
      meta: d.meta,
      date: d.date,
      secret: element,
    );

Future<void> _pump(WidgetTester tester, Widget card) {
  return tester.pumpWidget(MaterialApp(home: Center(child: card)));
}

void main() {
  testWidgets('each tier shows its own label on the card', (tester) async {
    for (final (tier, label) in const [
      (GameCardTier.common, 'THƯỜNG'),
      (GameCardTier.rare, 'HIẾM'),
      (GameCardTier.superRare, 'SIÊU HIẾM'),
      (GameCardTier.legendary, 'HUYỀN THOẠI'),
      (GameCardTier.mythic, 'THẦN THOẠI'),
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
          title:
              'Hội Chạy Bộ Phường Phúc Xá Quyết Không Bỏ Cuộc Giữa Chừng '
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
            art: Image(image: white, fit: BoxFit.cover),
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
      return (pixels.getUint8(i) +
              pixels.getUint8(i + 1) +
              pixels.getUint8(i + 2)) ~/
          3;
    }

    // Ô đá góc trái trên: nền mực 62% trên ảnh trắng, 255·0,38 + 10·0,62 ≈ 103.
    expect(luma(0.07, 0.06), lessThan(128), reason: 'ô đá');
    // Chân thẻ: mực 94%, 255·0,06 + 9·0,94 ≈ 24.
    expect(luma(0.5, 0.875), lessThan(40), reason: 'chân thẻ, trên dòng chữ');
    expect(luma(0.15, 0.94), lessThan(40), reason: 'chân thẻ');
    // Không còn lớp phủ trên; lớp phủ dưới chỉ nằm sau khối chữ, nên phần
    // trên và giữa tranh vẫn là ảnh.
    expect(luma(0.5, 0.25), greaterThan(200), reason: 'trên tranh');
    expect(luma(0.5, 0.42), greaterThan(200), reason: 'giữa ảnh');
  });

  testWidgets('stats sit on a solid panel under the art instead of the desc', (
    tester,
  ) async {
    late MemoryImage white;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
      final image = await recorder.endRecording().toImage(30, 42);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      white = MemoryImage(png!.buffer.asUint8List());
    });
    final boundary = GlobalKey();
    await _pump(
      tester,
      RepaintBoundary(
        key: boundary,
        child: AchievementCard(
          animate: false,
          data: AchievementCardData(
            tier: GameCardTier.legendary,
            art: Image(image: white, fit: BoxFit.cover),
            kind: 'MA SÓI · PHE SÓI',
            hero: 'SÓI',
            heroUnit: '',
            title: 'Bầy sói thắng · 14 người',
            owner: 'AN',
            serial: '',
            desc: 'Câu mô tả không hiện khi có số liệu.',
            meta: '28.10.2026',
            date: '28.10.2026',
            stats: const [
              (value: 'Thắng', label: 'KẾT QUẢ'),
              (value: '5', label: 'SỐ VÒNG'),
              (value: 'Sống sót', label: 'BẢN THÂN'),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(white, tester.element(find.byKey(boundary)));
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final text in ['Thắng', 'KẾT QUẢ', '5', 'SỐ VÒNG', 'Sống sót']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('Câu mô tả'), findsNothing);
    // Không có serial thì dòng chủ thẻ chỉ còn tên, không treo dấu chấm.
    expect(find.text('AN · '), findsNothing);

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

    // Tranh chiếm 58% trên; dưới đó là nền chân thẻ 08090E (độ sáng ≈ 9).
    expect(luma(0.5, 0.3), greaterThan(200), reason: 'tranh');
    expect(luma(0.9, 0.62), lessThan(40), reason: 'panel ngay dưới tranh');
    expect(luma(0.9, 0.8), lessThan(40), reason: 'panel quanh số liệu');
  });

  testWidgets('a secret card names its element instead of the tier', (
    tester,
  ) async {
    final plain = _data(GameCardTier.legendary);
    await _pump(tester, AchievementCard(data: plain, animate: false));
    expect(find.text('HUYỀN THOẠI'), findsOneWidget);
    expect(find.text('火'), findsNothing);

    await _pump(
      tester,
      AchievementCard(data: _secret(plain, RunNowElement.fire), animate: false),
    );
    expect(find.text('ẨN · HỎA'), findsOneWidget);
    expect(find.text('HUYỀN THOẠI'), findsNothing);
    expect(find.text('火'), findsOneWidget);

    // Mặt sau vẫn ghi bậc.
    await _pump(
      tester,
      AchievementCard(
        data: _secret(plain, RunNowElement.fire),
        back: true,
        animate: false,
      ),
    );
    expect(find.text('HUYỀN THOẠI'), findsOneWidget);
  });

  testWidgets('a secret card turns the art into its element colour', (
    tester,
  ) async {
    late MemoryImage green;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF00FF00), BlendMode.src);
      final image = await recorder.endRecording().toImage(30, 42);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      green = MemoryImage(png!.buffer.asUint8List());
    });
    final base = AchievementCardData(
      tier: GameCardTier.common,
      art: Image(image: green, fit: BoxFit.cover),
      kind: '',
      hero: '',
      title: '',
      owner: '',
      serial: '',
      desc: '',
      meta: '',
      date: '',
    );
    Future<(int, int, int)> rgbAt(AchievementCardData data) async {
      final boundary = GlobalKey();
      await _pump(
        tester,
        RepaintBoundary(
          key: boundary,
          child: AchievementCard(animate: false, data: data),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(green, tester.element(find.byKey(boundary)));
      });
      await tester.pump();
      late ByteData pixels;
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        pixels = (await (await render.toImage()).toByteData())!;
      });
      final x = (achievementCardSize.width * 0.5).toInt();
      final y = (achievementCardSize.height * 0.3).toInt();
      final i = (y * achievementCardSize.width.toInt() + x) * 4;
      return (
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
    }

    final (pr, pg, _) = await rgbAt(base);
    expect(pg - pr, greaterThan(100), reason: 'thẻ thường giữ màu tranh');

    // Tranh xanh lá có độ sáng 0,7152. Hỏa: tối 9C2418·0,28 = (44, 10, 7),
    // sáng giữa FFB3A3 và trắng = (255, 217, 209), nên điểm ảnh ≈ (195, 158,
    // 151): đỏ hơn xanh lá chừng 37.
    final (fr, fg, _) = await rgbAt(_secret(base, RunNowElement.fire));
    expect(fr - fg, greaterThan(20), reason: 'Hỏa');
    // Thủy: tối 0A5663·0,28 = (3, 24, 28), sáng giữa 7FC9D4 và trắng =
    // (191, 228, 234), nên ≈ (137, 170, 175): lam hơn đỏ chừng 38.
    final (wr, _, wb) = await rgbAt(_secret(base, RunNowElement.water));
    expect(wb - wr, greaterThan(20), reason: 'Thủy');
  });

  testWidgets('only mythic cards keep animating', (tester) async {
    await _pump(tester, AchievementCard(data: _data(GameCardTier.legendary)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await _pump(tester, AchievementCard(data: _data(GameCardTier.mythic)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await _pump(
      tester,
      AchievementCard(data: _data(GameCardTier.mythic), animate: false),
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

  testWidgets('a custom back face replaces the 3I emblem', (tester) async {
    final data = _data(GameCardTier.rare);
    await _pump(
      tester,
      AchievementCard(
        back: true,
        animate: false,
        data: AchievementCardData(
          tier: data.tier,
          art: data.art,
          kind: data.kind,
          hero: data.hero,
          title: data.title,
          owner: data.owner,
          serial: data.serial,
          desc: data.desc,
          meta: data.meta,
          date: data.date,
          backFace: const Text('SỐ LIỆU'),
        ),
      ),
    );
    expect(find.text('SỐ LIỆU'), findsOneWidget);
    expect(find.text('THẺ THÀNH TÍCH'), findsNothing);
  });

  testWidgets('a stamp sits on the front only when given', (tester) async {
    const stamp = Key('stamp');
    final data = _data(GameCardTier.rare);
    await _pump(tester, AchievementCard(data: data, animate: false));
    expect(find.byKey(stamp), findsNothing);

    await _pump(
      tester,
      AchievementCard(
        animate: false,
        data: AchievementCardData(
          tier: data.tier,
          art: data.art,
          kind: data.kind,
          hero: data.hero,
          title: data.title,
          owner: data.owner,
          serial: data.serial,
          desc: data.desc,
          meta: data.meta,
          date: data.date,
          stamp: const SizedBox(key: stamp),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(stamp)), const Size(64, 64));
  });
}
