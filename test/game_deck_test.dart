import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_models.dart';

// Bảng 1.2 như backend gửi trong createOptions.deck.
final _plan = GameDeckPlan.fromJson({
  'note': 'Theo số người',
  'fixedNote': 'Tự chỉnh',
  'wolvesKey': 'wolves',
  'preview': 12,
  'tiers': [
    {'from': 10, 'to': 10, 'wolves': 2, 'specials': 2},
    {'from': 11, 'to': 11, 'wolves': 3, 'specials': 3},
    {'from': 12, 'to': 12, 'wolves': 3, 'specials': 4},
    {'from': 13, 'to': 16, 'wolves': 3, 'specials': 5},
    {'from': 17, 'to': 20, 'wolves': 4, 'specials': 5},
    {'from': 21, 'to': 24, 'wolves': 5, 'specials': 5},
  ],
});

const _specials = ['seer', 'guard', 'witch', 'hunter', 'cupid'];

void main() {
  test('theo số người: 12 người là 3 sói, 4 vai đầu, 5 Dân', () {
    final c = _plan.counts(n: 12, specials: _specials, on: (_) => true);
    expect(c, {
      'wolf': 3,
      'seer': 1,
      'guard': 1,
      'witch': 1,
      'hunter': 1,
      'cupid': 0,
      'villager': 5,
    });
  });

  test('theo số người: vai tắt thành Dân, vai thêm lấy chỗ Dân', () {
    final c = _plan.counts(
      n: 17,
      specials: _specials,
      on: (r) => r != 'guard',
      extended: const ['elder'],
      extraWolves: 1,
    );
    expect(c, {
      'wolf': 5,
      'seer': 1,
      'guard': 0,
      'witch': 1,
      'hunter': 1,
      'cupid': 1,
      'elder': 1,
      'villager': 7,
    });
  });

  test('tự chỉnh: đúng số sói đã chọn, đủ vai đang bật, sói không quá 1/3', () {
    expect(
      _plan.counts(n: 12, specials: _specials, on: (_) => true, wolves: 4),
      {
        'wolf': 4,
        'seer': 1,
        'guard': 1,
        'witch': 1,
        'hunter': 1,
        'cupid': 1,
        'villager': 3,
      },
    );
    expect(
      _plan.counts(
        n: 10,
        specials: _specials,
        on: (_) => true,
        wolves: 5,
      )['wolf'],
      3,
    );
  });
}
