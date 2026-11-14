import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_look_sync.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/theme.dart';

RunCard _card(
  String id, {
  String? owner,
  Map<String, String>? look,
  String? variant,
}) => RunCard.fromJson({
  'id': id,
  'tier': 'rare',
  'km': 6.1,
  'rolledAt': '2026-11-10T08:00:00Z',
  'ownerUid': ?owner,
  'look': ?look,
  'variant': ?variant,
  'snapshot': const <String, dynamic>{},
});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  const city = RunCardStyle(RunCardSet.city, RunCardTextLayout.top);
  const medal = RunCardStyle(RunCardSet.medal);
  const bib = RunCardStyle.withMap(RunCardSet.bib);

  group('kiểu của thẻ', () {
    test(
      'thẻ người khác khoe mặc kiểu chủ thẻ đã lưu, không theo máy mình',
      () {
        final styles = RunCardStyleController(loadFromStorage: false);
        // Máy mình đặt mặc định Huy chương từ trước khi thẻ này lật.
        styles.apply(medal, now: DateTime.utc(2026, 11, 1));

        expect(
          styles.styleFor(
            _card('a1', owner: 'u2', look: {'style': 'city.top'}),
          ),
          city,
        );
        expect(styles.styleFor(_card('a2', owner: 'u2')), RunCardStyle.current);
        // Bộ của bản app mới hơn mà app này chưa biết thì về kiểu gốc.
        expect(
          styles.styleFor(
            _card('a3', owner: 'u2', look: {'style': 'neon.top'}),
          ),
          RunCardStyle.current,
        );
      },
    );

    test('thẻ của mình: vừa đặt trong phiên, rồi backend, rồi máy này', () {
      final sent = <(String, String)>[];
      final styles = RunCardStyleController(
        loadFromStorage: false,
        onCardStyle: (id, style) => sent.add((id, style.id)),
      );
      styles.decode('{"d":[[0,"medal.full"]],"c":{"a1":"medal.full"}}');

      // Máy này còn giữ Huy chương, nhưng máy khác đã đặt Thành phố.
      expect(styles.styleFor(_card('a1', look: {'style': 'city.top'})), city);
      // Backend chưa có gì thì theo máy này.
      expect(styles.styleFor(_card('a1')), medal);

      styles.apply(bib, cardId: 'a1');
      expect(sent, [('a1', 'bib.full.map')]);
      // Doc trên backend chưa kịp đổi, thẻ vẫn mặc kiểu vừa chọn.
      expect(styles.styleFor(_card('a1', look: {'style': 'city.top'})), bib);
    });
  });

  test('bộ màu chủ thẻ chọn chỉ áp cho thẻ người khác khoe', () {
    final shared = runCardData(
      _card('a1', owner: 'u2', look: {'skin': 'light.water'}),
      owner: 'An',
    );
    expect(
      shared.skin,
      RunCardSkin.forTheme(RunNowAppearance.light, RunNowElement.water),
    );
    expect(runCardData(_card('a1', owner: 'u2'), owner: 'An').skin, isNull);
    expect(
      runCardData(
        _card('a1', owner: 'u2', look: {'skin': 'neon.plasma'}),
        owner: 'An',
      ).skin,
      isNull,
    );
    // Thẻ trong bộ thẻ của mình theo bộ màu máy này đang chọn.
    expect(
      runCardData(_card('a1', look: {'skin': 'light.water'}), owner: 'An').skin,
      isNull,
    );
  });

  test(
    'đổi bộ màu thì báo lựa chọn mới để gửi lên, kể cả khi bỏ chọn',
    () async {
      final sent = <RunCardSkinChoice?>[];
      final skins = RunCardSkinController(
        loadFromStorage: false,
        onChoice: sent.add,
      );
      await skins.setChoice((RunNowAppearance.dark, RunNowElement.fire));
      await skins.setChoice((RunNowAppearance.dark, RunNowElement.fire));
      await skins.setChoice(null);
      expect(sent, [(RunNowAppearance.dark, RunNowElement.fire), null]);
    },
  );

  test('điền bù chỉ lấy phần backend còn thiếu mà máy này đã chọn', () {
    final looks = missingRunCardLooks(
      [
        _card('chua-co-gi'),
        _card('da-co-kieu', look: {'style': 'city.top'}),
        _card('du-ca-hai', look: {'style': 'city.top', 'skin': 'dark.wood'}),
        _card('may-chua-chon'),
        _card('the-an', variant: 'secret.fire'),
      ],
      localStyleId: (card) => card.id == 'may-chua-chon' ? null : 'medal.full',
      skinId: 'dark.fire',
    );
    expect(looks, [
      {'activityId': 'chua-co-gi', 'style': 'medal.full', 'skin': 'dark.fire'},
      {'activityId': 'da-co-kieu', 'skin': 'dark.fire'},
      {'activityId': 'may-chua-chon', 'skin': 'dark.fire'},
    ]);
    expect(
      missingRunCardLooks(
        [_card('a1')],
        localStyleId: (_) => null,
        skinId: null,
      ),
      isEmpty,
    );
  });

  group('RunCardLookSync', () {
    late List<(List<Map<String, String>>, bool)> calls;
    late RunCardLookSync sync;
    setUp(() {
      calls = [];
      sync = RunCardLookSync((looks, {fill = false}) async {
        calls.add((looks, fill));
      });
    });

    test('đổi bộ màu gửi mọi thẻ, 100 thẻ một lượt, đè giá trị cũ', () async {
      await sync.skin([for (var i = 0; i < 230; i++) 'a$i'], '');
      expect([for (final call in calls) call.$1.length], [100, 100, 30]);
      expect(calls.every((call) => !call.$2), isTrue);
      expect(calls.last.$1.last, {'activityId': 'a229', 'skin': ''});
    });

    test('điền bù gửi mỗi nội dung một lần trong phiên', () async {
      final look = {'activityId': 'a1', 'style': 'medal.full'};
      await sync.fill([look]);
      await sync.fill([
        look,
        {'activityId': 'a2', 'skin': 'dark.fire'},
      ]);
      expect(
        [for (final call in calls) call.$1],
        [
          [look],
          [
            {'activityId': 'a2', 'skin': 'dark.fire'},
          ],
        ],
      );
      expect(calls.every((call) => call.$2), isTrue);
      await sync.fill([look]);
      expect(calls, hasLength(2));
    });

    test('backend lỗi thì không ném ra giao diện', () async {
      final failing = RunCardLookSync(
        (looks, {fill = false}) async => throw Exception('503'),
      );
      await failing.cardStyle('a1', 'city.top');
    });
  });
}
