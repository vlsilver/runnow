import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/rank/rank_gift_card.dart';

/// Thẻ hạng như backend ghi, kèm quà; Timestamp đã đổi sang DateTime.
RankCard _card({int rank = 14, Map<String, dynamic>? reward}) =>
    RankCard.fromJson('an', 'week_2026-11-23_run', {
      'range': 'week',
      'sport': 'run',
      'periodStart': '2026-11-23',
      'periodEnd': '2026-11-30',
      'rank': rank,
      'participants': 31,
      'tier': 'common',
      'score': 16400,
      'displayName': 'An',
      'stats': {'runMeters': 15200, 'walkMeters': 1200},
      'quote': 'Đều chân.',
      'awardedAt': DateTime(2026, 11, 30, 12),
      'reward':
          reward ??
          {
            'name': 'Áo Kiprun',
            'icon': 'shirt',
            'photos': <String>[],
            'giverName': 'Bình',
            'kind': 'draw',
            'pool': 23,
          },
    })!;

void main() {
  test('thẻ quà bốc thăm: tên quà, số km, lượt bốc và người trao', () {
    final data = rankGiftCardData(_card());

    expect(data.kind, 'QUÀ BXH TUẦN · CHẠY · ĐI BỘ');
    expect(data.title, 'Áo Kiprun');
    expect((data.hero, data.heroUnit), ('16,4', 'KM'));
    expect(data.quote, 'Trúng bốc thăm trong 23 người · Bình trao');
    expect(data.serial, 'BỐC THĂM');
    expect(data.owner, 'AN');
    expect(data.stats, [
      (value: '#14', label: 'TRÊN 31'),
      (value: '15,2', label: 'CHẠY · KM'),
      (value: '1,2', label: 'ĐI BỘ · KM'),
    ]);
  });

  test('thẻ quà theo hạng ghi hạng, không ghi bốc thăm', () {
    final data = rankGiftCardData(
      _card(
        rank: 1,
        reward: {'name': 'Giày', 'icon': 'shoes', 'giverName': ''},
      ),
    );

    expect(data.quote, 'Quà Quán quân tuần');
    expect(data.serial, 'HẠNG 1');
  });

  test('thẻ quà khoe riêng với thẻ hạng', () {
    final card = _card();
    expect(rankGiftCardShareSubject(card).id, 'gift-week_2026-11-23_run');
    expect(rankCardShareSubject(card).id, isNot('gift-week_2026-11-23_run'));
  });

  testWidgets('mở thẻ quà có nút khoe và nút nhận quà', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRankGiftCardViewer(context, _card()),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    // Thẻ huyền thoại có vệt sáng chạy mãi, nên pump đủ lâu cho màn mở xong.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nhận quà'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('hộp quà còn gói thì chưa có nút nhận quà', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showRankGiftCardViewer(context, _card(), faceDown: true),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nhận quà'), findsNothing);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });
}
