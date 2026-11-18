import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';
import 'package:myrun/src/achievements/run_card_look_sync.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_style.dart';

RunCard _card(String id, {Map<String, String>? look}) => RunCard.fromJson({
  'id': id,
  'tier': 'epic',
  'km': 5.0,
  'odds': const [],
  'snapshot': const {},
  'look': ?look,
});

void main() {
  group('RunCardLayout', () {
    test('đọc chuỗi lưu: chỗ, cỡ, ẩn, màu đặc trưng và màu tự chọn', () {
      const raw =
          'km:30,66,3,1;time:,,1,h2;pace:50,80,2,h;route:50,30,4,ff8800';
      final layout = RunCardLayout.parse(raw);

      expect(layout.parts, {
        CardPart.km: const PartPlacement(
          x: 30,
          y: 66,
          size: 3,
          color: PartTone(1),
        ),
        CardPart.time: const PartPlacement(
          size: 1,
          hidden: true,
          color: PartTone(2),
        ),
        CardPart.pace: const PartPlacement(x: 50, y: 80, hidden: true),
        CardPart.route: PartPlacement(
          x: 50,
          y: 30,
          size: 4,
          color: PartCustom(const Color(0xFFFF8800)),
        ),
      });
      expect(layout.code, raw);
    });

    test('chưa chỉnh gì thì chuỗi rỗng, chỉnh phần nào ghi phần đó', () {
      expect(RunCardLayout.initial.code, '');
      final layout = RunCardLayout.initial.place(
        CardPart.time,
        // Màu tự chọn lưu sáu chữ hex thường, bỏ kênh alpha.
        PartPlacement(color: PartCustom(const Color(0x803366CC))),
      );
      expect(layout.code, 'time:,,2,3366cc');
    });

    test('đặt lại phần về y như gốc thì phần đó ra khỏi chuỗi', () {
      final layout = RunCardLayout.parse('km:30,60,2;pace:,,3');

      expect(
        layout.place(CardPart.pace, PartPlacement.initial).code,
        'km:30,60,2',
      );
    });

    test('phần lạ, số sai, cỡ ngoài bậc, màu lạ thì bỏ, phần khác vẫn đọc', () {
      final layout = RunCardLayout.parse(
        'zz:1,2,3;km:101,50,2;km:30,,2;pace:10,20;time:10,20,5;'
        'time:10,20,2,q;time:10,20,2,FF8800;time:10,20,2,ff88;'
        'time:10,20,2,12;route:1,2,3,4,5;pace:40,30,0',
      );

      expect(layout.parts, {
        CardPart.pace: const PartPlacement(x: 40, y: 30, size: 0),
      });
    });

    test('số km không ẩn được, kể cả chuỗi từ máy khác ghi ẩn', () {
      expect(RunCardLayout.parse('km:30,60,2,h').of(CardPart.km).hidden, false);
      expect(
        RunCardLayout.initial
            .place(CardPart.km, const PartPlacement(hidden: true))
            .code,
        '',
      );
    });

    test('bỏ màu thì về màu gốc, không giữ màu cũ', () {
      const tinted = PartPlacement(size: 3, color: PartTone(0));

      expect(tinted.withColor(null), const PartPlacement(size: 3));
      expect(tinted.copyWith(size: 1).color, const PartTone(0));
    });
  });

  group('RunCardStyle mang bố cục', () {
    const moved = 'km:30,60,2';

    test('bộ nào cũng mang bố cục trong look, id như cũ', () {
      for (final raw in ['iron.full.map', 'city.top', 'pixel.full']) {
        final style = RunCardStyle.parse(raw, layout: moved)!;

        expect(style.id, raw);
        expect(style.look, {'style': raw, 'layout': moved}, reason: raw);
      }
    });

    test('chưa chỉnh gửi layout rỗng để xoá bố cục cũ', () {
      expect(const RunCardStyle(RunCardSet.city, RunCardTextLayout.top).look, {
        'style': 'city.top',
        'layout': '',
      });
    });

    test('chỉnh một phần là khoá ảnh khoe khác, chưa chỉnh thì như id', () {
      const plain = RunCardStyle(RunCardSet.blocks);
      final a = plain.withLayout(RunCardLayout.parse(moved));
      final b = plain.withLayout(RunCardLayout.parse('km:30,60,2,1'));

      expect(plain.shareKey, 'blocks.full');
      expect(a.shareKey, isNot(b.shareKey));
      expect(a.shareKey, startsWith('blocks.full.'));
      expect(a, isNot(b));
    });

    test('thẻ khoe đọc bố cục chủ thẻ đã lưu', () {
      final card = _card(
        'a1',
        look: {'style': 'medal.top', 'layout': 'pace:,,3,0'},
      );

      expect(
        savedRunCardStyle(card)!.layout.of(CardPart.pace),
        const PartPlacement(size: 3, color: PartTone(0)),
      );
    });
  });

  group('lưu trong máy', () {
    test('kiểu đã chỉnh lưu cả bố cục, id cũ dạng chuỗi vẫn đọc', () {
      FlutterSecureStorage.setMockInitialValues({});
      final styles = RunCardStyleController(loadFromStorage: false);
      final iron = const RunCardStyle(
        RunCardSet.iron,
      ).withLayout(RunCardLayout.parse('km:30,60,2'));
      styles.apply(iron, cardId: 'a1', now: DateTime.utc(2026, 11, 18));
      final raw = styles.encode();

      final again = RunCardStyleController(loadFromStorage: false)..decode(raw);
      expect(again.localStyleOf('a1', null), iron);
      expect(
        again.localStyleOf('later', DateTime.utc(2026, 11, 19)),
        iron,
        reason: 'mặc định cho thẻ lật sau cũng giữ bố cục',
      );

      final old = RunCardStyleController(loadFromStorage: false)
        ..decode('{"d":[[1,"city.top"]],"c":{"a1":"medal.full"}}');
      expect(old.localStyleOf('a1', null)?.id, 'medal.full');
    });

    test('điền bù gửi cả bố cục cho thẻ backend chưa có kiểu', () {
      final looks = missingRunCardLooks(
        [_card('a1')],
        localStyle: (_) => const RunCardStyle(
          RunCardSet.iron,
        ).withLayout(RunCardLayout.parse('km:30,60,2')).look,
        skinId: null,
      );

      expect(looks, [
        {'activityId': 'a1', 'style': 'iron.full', 'layout': 'km:30,60,2'},
      ]);
    });
  });
}
