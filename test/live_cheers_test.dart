import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/live_cheers.dart';

LiveCheer _cheer(String uid, String emoji, int second, Map<String, int> n) =>
    LiveCheer(
      uid: uid,
      emoji: emoji,
      at: DateTime.utc(2026, 11, 1, 6, 0, second),
      counts: n,
    );

void main() {
  test('liveCheerTotals cộng mọi người xem, nhiều nhất đứng đầu', () {
    final totals = liveCheerTotals([
      _cheer('a', '🔥', 1, {'🔥': 3, '👏': 1}),
      _cheer('b', '👏', 2, {'👏': 1, '💪': 2}),
      _cheer('c', '🔥', 3, {'🔥': 2}),
    ]);
    // 🔥 3+2=5, 👏 1+1=2, 💪 2: bằng nhau thì theo thứ tự của hàng emoji.
    expect(totals, [('🔥', 5), ('👏', 2), ('💪', 2)]);
    expect(liveCheerTotals(const []), isEmpty);
  });

  test('liveCheerFrom bỏ field sai kiểu thay vì hỏng cả document', () {
    final ok = liveCheerFrom('a', {
      'emoji': '🔥',
      'n': {'🔥': 2, '👏': 'x'},
      'at': 'không phải Timestamp',
    });
    expect(ok.emoji, '🔥');
    expect(ok.counts, {'🔥': 2});
    expect(ok.at, isNull);
    final broken = liveCheerFrom('b', {'emoji': 7, 'n': 'nhiều'});
    expect(broken.emoji, '');
    expect(broken.counts, isEmpty);
  });

  group('newLiveCheers', () {
    test('báo lần bấm mới hoặc bấm lại của người khác, không báo mình', () {
      final before = [
        _cheer('a', '🔥', 1, {'🔥': 1}),
        _cheer('b', '👏', 2, {'👏': 1}),
        _cheer('me', '💪', 3, {'💪': 1}),
      ];
      final after = [
        _cheer('a', '🔥', 1, {'🔥': 1}),
        _cheer('b', '🏁', 9, {'👏': 1, '🏁': 1}),
        _cheer('c', '🐢', 8, {'🐢': 1}),
        _cheer('me', '💪', 10, {'💪': 2}),
      ];
      expect(
        [for (final c in newLiveCheers(before, after, myUid: 'me')) c.uid],
        ['b', 'c'],
      );
    });

    test('lần nhận đầu không báo, để mở màn không báo lại cổ vũ cũ', () {
      final first = [
        _cheer('a', '🔥', 1, {'🔥': 1}),
      ];
      expect(newLiveCheers(null, first, myUid: 'me'), isEmpty);
    });
  });
}
