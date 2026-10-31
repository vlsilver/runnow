import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/heart_button.dart';

class _FakeHearts implements HeartRepository {
  final calls = <String>[];

  @override
  Stream<Hearts> watch(String target) =>
      Stream.value(const Hearts(uids: ['me'], mine: true));

  @override
  Future<void> like(String target) async => calls.add('like $target');

  @override
  Future<void> unlike(String target) async => calls.add('unlike $target');
}

Future<_FakeHearts> _pumpButton(WidgetTester tester, HeartButton button) async {
  final fake = _FakeHearts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        heartRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: button)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Đã nhận dữ liệu: mình đã thả tim.
  expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  return fake;
}

void main() {
  group('heartsFrom', () {
    test('mới nhất đứng đầu, tim chưa có giờ server coi là mới nhất', () {
      final hearts = heartsFrom([
        (uid: 'a', at: DateTime.utc(2026, 10, 30, 5, 1)),
        (uid: 'me', at: null),
        (uid: 'b', at: DateTime.utc(2026, 10, 30, 5, 9)),
      ], myUid: 'me');
      expect(hearts.uids, ['me', 'b', 'a']);
      expect(hearts.count, 3);
      expect(hearts.mine, isTrue);
    });

    test('chưa đăng nhập hoặc chưa thả thì mine là false', () {
      final entries = [(uid: 'a', at: DateTime.utc(2026))];
      expect(heartsFrom(entries, myUid: null).mine, isFalse);
      expect(heartsFrom(entries, myUid: 'me').mine, isFalse);
    });
  });

  group('newHeartUids', () {
    const before = Hearts(uids: ['a'], mine: false);

    test('chỉ người mới thả, bỏ chính mình', () {
      const after = Hearts(uids: ['me', 'c', 'b', 'a'], mine: true);
      expect(newHeartUids(before, after, myUid: 'me'), ['c', 'b']);
    });

    test('lần đầu nhận dữ liệu thì không báo ai', () {
      const after = Hearts(uids: ['b', 'a'], mine: false);
      expect(newHeartUids(null, after, myUid: 'me'), isEmpty);
    });
  });

  group('HeartButton', () {
    testWidgets('đã thả tim buổi chạy, bấm lại là gỡ', (tester) async {
      final fake = await _pumpButton(
        tester,
        const HeartButton(target: 'run_u1_a1'),
      );
      await tester.tap(find.byType(HeartButton));
      await tester.pumpAndSettle();
      expect(fake.calls, ['unlike run_u1_a1']);
    });

    testWidgets('tim live không gỡ được, bấm lại là cổ vũ thêm', (
      tester,
    ) async {
      final fake = await _pumpButton(
        tester,
        const HeartButton(target: 'live_s1', canUnlike: false),
      );
      await tester.tap(find.byType(HeartButton));
      await tester.pumpAndSettle();
      expect(fake.calls, ['like live_s1']);
    });
  });
}
