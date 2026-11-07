import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/home_digest.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';

void main() {
  group('HomeDigest.freshAt theo ngày giờ VN', () {
    const post = HomeDigest(day: '2026-10-31', title: 't', body: 'b');

    test('17:00 UTC ngày 30 đã là 0h VN ngày 31: bài hôm nay', () {
      expect(post.freshAt(DateTime.utc(2026, 10, 30, 17)), isTrue);
    });

    test('16:59 UTC ngày 30 vẫn là ngày 30 VN: bài ngày mai chưa tới', () {
      expect(post.freshAt(DateTime.utc(2026, 10, 30, 16, 59)), isFalse);
    });

    test('cả ngày 1/11 VN vẫn hiện bài hôm qua', () {
      expect(post.freshAt(DateTime.utc(2026, 11, 1, 16, 59)), isTrue);
    });

    test('sang ngày 2/11 VN thì bài 31/10 đã cũ', () {
      expect(post.freshAt(DateTime.utc(2026, 11, 1, 17)), isFalse);
    });
  });

  group('HomeDigestCard', () {
    late FakeFirebaseFirestore firestore;

    String vnDay(int daysAgo) {
      final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
      final d = vn.subtract(Duration(days: daysAgo));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeDigestFirestoreProvider.overrideWithValue(firestore),
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(MockUser(uid: 'u1')),
            ),
          ],
          child: MaterialApp(
            theme: buildRunNowTheme(RunNowElement.water),
            home: const Scaffold(body: HomeDigestCard()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    setUp(() => firestore = FakeFirebaseFirestore());

    testWidgets('hiện bài mới nhất', (tester) async {
      for (final (ago, title) in [(1, 'Bài hôm qua'), (0, 'Bài hôm nay')]) {
        await firestore.collection('homeDigests').doc(vnDay(ago)).set({
          'day': vnDay(ago),
          'title': title,
          'body': 'An chạy 8 km',
        });
      }
      await pump(tester);
      expect(find.text('Bài hôm nay'), findsOneWidget);
      expect(find.text('Bài hôm qua'), findsNothing);
      expect(find.text('An chạy 8 km'), findsOneWidget);
    });

    testWidgets('bài cũ hơn hôm qua thì ẩn', (tester) async {
      await firestore.collection('homeDigests').doc(vnDay(2)).set({
        'day': vnDay(2),
        'title': 'Bài cũ',
        'body': 'x',
      });
      await pump(tester);
      expect(find.text('Bài cũ'), findsNothing);
      expect(find.text('3I ĐIỂM TIN'), findsNothing);
    });
  });
}
