import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_edit.dart';
import 'package:myrun/src/achievements/run_faces/run_faces.dart';
import 'package:myrun/src/games/game_role_card.dart';

RunCard _card() => RunCard.fromJson({
  'id': 'r1',
  'activityId': 'r1',
  'tier': 'epic',
  'km': 6.1,
  'rollPpm': 1,
  'rolledAt': '2026-11-10T08:00:00Z',
  'startedAt': '2026-11-10T13:52:00Z',
  'odds': const [],
  'snapshot': {
    'name': 'Morning Run',
    'sportType': 'Run',
    'startedAt': '2026-11-10T20:52:00',
    'distanceMeters': 6100,
    'movingTimeSeconds': 3609,
    'elapsedTimeSeconds': 3609,
    'route': const [
      {'lat': 21.05, 'lng': 105.82},
      {'lat': 21.06, 'lng': 105.83},
      {'lat': 21.07, 'lng': 105.82},
      {'lat': 21.06, 'lng': 105.81},
      {'lat': 21.05, 'lng': 105.82},
    ],
    'splits': [
      for (var i = 0; i < 6; i++)
        {'distanceMeters': 1000, 'movingTimeSeconds': 600},
    ],
  },
});

Future<void> _loadCardFont() async {
  final loader = FontLoader('Barlow Condensed');
  for (final weight in ['SemiBold', 'Bold', 'ExtraBold']) {
    final file = File(
      'assets/fonts/barlow_condensed/BarlowCondensed-$weight.ttf',
    );
    loader.addFont(
      Future.value(ByteData.sublistView(await file.readAsBytes())),
    );
  }
  await loader.load();
}

/// Khoá đo của màn chỉnh, gắn lại mỗi lần vẽ để đo phần trên mặt thẻ.
final _keys = {for (final p in CardPart.values) p: GlobalKey()};
final _faceKey = GlobalKey();
final _artKey = GlobalKey();
final _shot = GlobalKey();

/// [art] là thẻ đã có tranh: đường chạy thành con dấu tròn trên tranh.
Widget _face(RunCardStyle style, {bool edit = true, bool art = true}) {
  Widget card = GameCardScaled(
    width: 300,
    size: achievementCardSize,
    child: AchievementCard(
      data: runCardData(
        _card(),
        owner: 'NGUYEN VAN A',
        previewArt: art ? const ColoredBox(color: Color(0xFF55708A)) : null,
      ),
      animate: false,
    ),
  );
  if (edit) {
    card = CardEditScope(
      keys: _keys,
      face: _faceKey,
      art: _artKey,
      selected: null,
      outline: const Color(0xFFFF0000),
      child: card,
    );
  }
  return MaterialApp(
    home: RunCardSkinScope(
      skin: RunCardSkin.classic,
      child: RunCardStyleScope.fixed(
        style: style,
        child: Center(
          child: RepaintBoundary(key: _shot, child: card),
        ),
      ),
    ),
  );
}

RenderBox _boxOf(GlobalKey key) =>
    key.currentContext!.findRenderObject()! as RenderBox;

/// Điểm [at] của [part] (theo khung của phần) trong toạ độ của [space].
/// Đo qua phép biến đổi nên đúng cả với phần đang nghiêng.
Offset _pointOf(CardPart part, Alignment at, {GlobalKey? space}) {
  final box = _boxOf(_keys[part]!);
  return _boxOf(
    space ?? _faceKey,
  ).globalToLocal(box.localToGlobal(at.alongSize(box.size)));
}

/// Bề ngang đang vẽ của [part], tính cả phần phóng to.
double _width(CardPart part) {
  final box = _boxOf(_keys[part]!);
  return (box.localToGlobal(Offset(box.size.width, 0)) -
          box.localToGlobal(Offset.zero))
      .distance;
}

Set<CardPart> _present() => {
  for (final p in CardPart.values)
    if (_keys[p]!.currentContext != null) p,
};

final _styles = [
  for (final set in RunCardSet.values)
    for (final text in RunCardTextLayout.values)
      if (set.ownColors || text == RunCardTextLayout.full)
        RunCardStyle(set, text),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('mọi bộ có số km để chỉnh, bộ có đường chạy thì chỉnh được', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    for (final style in _styles) {
      await tester.pumpWidget(_face(style));
      final present = _present();
      expect(present, contains(CardPart.km), reason: style.id);
      // Mặt trước Pixel là cảnh pixel, không vẽ đường chạy.
      if (style.set != RunCardSet.pixel) {
        expect(present, contains(CardPart.route), reason: style.id);
      }
      // Bộ nào cũng in pace ở kiểu Đầy đủ (có bộ in chung một dòng với giờ).
      if (style.text == RunCardTextLayout.full) {
        expect(present, contains(CardPart.pace), reason: style.id);
      }
    }
  });

  testWidgets('dời phần nào thì điểm neo của phần đó tới đúng chỗ lưu', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    for (final style in _styles) {
      await tester.pumpWidget(_face(style));
      final parts = _present().difference({CardPart.route});
      final anchors = {for (final p in parts) p: editAnchorOf(_keys[p]!)!};
      final widths = {for (final p in parts) p: _width(p)};

      // Mỗi phần một chỗ, cỡ bậc 4 (gấp 1,45).
      const spots = {
        CardPart.km: (20, 30),
        CardPart.time: (60, 55),
        CardPart.pace: (40, 80),
      };
      var layout = RunCardLayout.initial;
      for (final p in parts) {
        final (x, y) = spots[p]!;
        layout = layout.place(p, PartPlacement(x: x, y: y, size: 4));
      }
      await tester.pumpWidget(_face(style.withLayout(layout)));
      for (final p in parts) {
        final (x, y) = spots[p]!;
        // 20% ngang là 60 điểm trên 300, 30% dọc là 126 điểm trên 420.
        final at = _pointOf(p, anchors[p]!);
        final why = '${style.id} ${p.name}';
        expect(at.dx, closeTo(300 * x / 100, 0.01), reason: why);
        expect(at.dy, closeTo(420 * y / 100, 0.01), reason: why);
        expect(_width(p), closeTo(widths[p]! * 1.45, 0.01), reason: why);
      }
    }
  });

  testWidgets('ẩn thì phần giữ chỗ mà không vẽ, km không ẩn được', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    const style = RunCardStyle(RunCardSet.iron);
    await tester.pumpWidget(_face(style));
    final before = _pointOf(CardPart.pace, Alignment.topLeft);

    await tester.pumpWidget(
      _face(style.withLayout(RunCardLayout.parse('km:,,2,h;pace:,,2,h'))),
    );
    bool shown(CardPart p) => find
        .ancestor(of: find.byKey(_keys[p]!), matching: find.byType(Visibility))
        .evaluate()
        .every((e) => (e.widget as Visibility).visible);
    expect(shown(CardPart.km), isTrue);
    expect(shown(CardPart.pace), isFalse);
    expect(
      _pointOf(CardPart.pace, Alignment.topLeft),
      before,
      reason: 'vẫn giữ chỗ',
    );
  });

  testWidgets('tô màu phủ lên phần, màu đặc trưng theo thứ tự của bộ', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    ColorFilter? tint(CardPart p) {
      final f = find.descendant(
        of: find.byKey(_keys[p]!),
        matching: find.byType(ColorFiltered),
      );
      return f.evaluate().isEmpty
          ? null
          : tester.widget<ColorFiltered>(f.first).colorFilter;
    }

    for (final set in RunCardSet.values) {
      final tones = faceTones(set);
      expect(tones.length, inInclusiveRange(1, 3), reason: set.name);
      final last = tones.length - 1;
      await tester.pumpWidget(
        _face(
          RunCardStyle(
            set,
          ).withLayout(RunCardLayout.parse('km:,,2,$last;pace:,,2,3366cc')),
        ),
      );
      expect(
        tint(CardPart.km),
        ColorFilter.mode(tones[last].color, BlendMode.srcIn),
        reason: set.name,
      );
      expect(
        tint(CardPart.pace),
        const ColorFilter.mode(Color(0xFF3366CC), BlendMode.srcIn),
        reason: set.name,
      );
    }
  });

  testWidgets('thẻ chưa có tranh: đường chạy dời theo vùng tranh', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    for (final style in _styles) {
      if (style.set == RunCardSet.pixel) continue;
      await tester.pumpWidget(_face(style, art: false));
      final before = _width(CardPart.route);
      await tester.pumpWidget(
        _face(
          style.withLayout(RunCardLayout.parse('route:30,40,4')),
          art: false,
        ),
      );
      final art = _boxOf(_artKey).size;
      final center = _pointOf(CardPart.route, Alignment.center, space: _artKey);
      final why = style.id;
      expect(center.dx, closeTo(art.width * 0.3, 0.01), reason: why);
      expect(center.dy, closeTo(art.height * 0.4, 0.01), reason: why);
      expect(_width(CardPart.route), closeTo(before * 1.45, 0.01), reason: why);
    }
  });

  testWidgets('thẻ có tranh: con dấu đường chạy dời theo mặt thẻ', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    for (final style in _styles) {
      if (style.set == RunCardSet.pixel) continue;
      await tester.pumpWidget(_face(style));
      final before = _width(CardPart.route);
      await tester.pumpWidget(
        _face(style.withLayout(RunCardLayout.parse('route:30,40,4'))),
      );
      final center = _pointOf(CardPart.route, Alignment.center);
      final why = style.id;
      expect(center.dx, closeTo(300 * 0.3, 0.01), reason: why);
      expect(center.dy, closeTo(420 * 0.4, 0.01), reason: why);
      expect(_width(CardPart.route), closeTo(before * 1.45, 0.01), reason: why);
    }
  });

  testWidgets('màu đường chạy tô vào nét con dấu, không tô cả khối', (
    tester,
  ) async {
    await tester.runAsync(_loadCardFont);
    await tester.pumpWidget(
      _face(
        const RunCardStyle(
          RunCardSet.iron,
        ).withLayout(RunCardLayout.parse('route:,,2,3366cc')),
      ),
    );
    final stamp = find.descendant(
      of: find.byKey(_keys[CardPart.route]!),
      matching: find.byType(RunRouteStamp),
    );
    expect(stamp, findsOneWidget);
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: stamp, matching: find.byType(CustomPaint)).first,
    );
    // ignore: avoid_dynamic_calls
    expect((paint.painter! as dynamic).line, const Color(0xFF3366CC));
    expect(
      find.descendant(
        of: find.byKey(_keys[CardPart.route]!),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
  });

  testWidgets('ảnh khoe chụp cả phần đã dời', (tester) async {
    await tester.runAsync(_loadCardFont);
    Future<Uint8List> shot(String layout) async {
      await tester.pumpWidget(
        _face(
          const RunCardStyle(
            RunCardSet.blocks,
          ).withLayout(RunCardLayout.parse(layout)),
          edit: false,
        ),
      );
      final boundary =
          _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      }))!;
    }

    final plain = await shot('');
    final moved = await shot('time:50,40,2');
    final hidden = await shot('time:,,2,h');
    // Chụp mà thiếu lớp phần đã dời thì ảnh dời giống hệt ảnh ẩn.
    expect(moved, isNot(plain));
    expect(moved, isNot(hidden));
  });
}
