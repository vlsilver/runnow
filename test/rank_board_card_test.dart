import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rank/rank_board_card.dart';
import 'package:myrun/src/rank/rank_reward.dart';

LeaderboardStats _stats() => const LeaderboardStats(
  distanceMeters: 0,
  movingTimeSeconds: 0,
  activityCount: 0,
  activeDays: 0,
  longestDistanceMeters: 0,
  fastestPaceSecondsPerKm: null,
  steps: 0,
);

List<ClubRankedMember> _board(int n) => [
  for (var i = 1; i <= n; i++)
    ClubRankedMember(
      rank: i,
      score: (40 - i) * 1000.0,
      entry: LeaderboardEntry(
        uid: 'u$i',
        displayName: 'Người $i',
        visibility: ProfileVisibility.public,
        rollingSevenDays: _stats(),
        currentWeek: _stats(),
        currentMonth: _stats(),
      ),
    ),
];

RankRewardItem _draw(String name) => RankRewardItem(
  id: name,
  kind: rankRewardDrawKind,
  minScore: 15000,
  slots: 1,
  name: name,
  icon: 'shirt',
);

RankBoardCard _card({
  int members = 14,
  String? me,
  List<RankRewardItem>? items,
}) => RankBoardCard(
  boardId: 'week_2026-11-23_run',
  ranked: _board(members),
  sport: ClubRankingSport.run,
  period: currentRankingPeriod(
    DateTime.utc(2026, 11, 25, 5),
    ClubRankingRange.currentWeek,
  ),
  rewards: RankRewards(
    giverName: 'NVL',
    items: items ?? [_draw('Áo Kiprun')],
    periodEnd: DateTime(2026, 11, 30),
  ),
  currentUid: me,
);

Future<void> _pumpBack(WidgetTester tester, RankBoardCard card) =>
    tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: achievementCardSize,
            child: AchievementCard(data: card.data, back: true),
          ),
        ),
      ),
    );

void main() {
  test('mặt trước in top 10; mình ngoài top thì thay dòng 10', () {
    expect(_card(me: 'u3').shown, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(_card(me: 'u13').shown, [0, 1, 2, 3, 4, 5, 6, 7, 8, 12]);
    expect(_card(members: 4, me: 'u2').shown, [0, 1, 2, 3]);
  });

  test('khoe riêng theo bảng, đổi quà thì ra file mới', () {
    final a = _card().subject;
    final b = _card(items: [_draw('Tất')]).subject;
    expect(a.id, 'bxh-week_2026-11-23_run');
    expect(a.printed, isNot(b.printed));
    expect(a.text, contains('1 quà'));
  });

  testWidgets('mặt sau một món: tên, điều kiện, số suất, ngày công bố', (
    tester,
  ) async {
    await _pumpBack(tester, _card());
    expect(find.text('QUÀ TUẦN · 23–29/11'), findsOneWidget);
    expect(find.text('Áo Kiprun'), findsOneWidget);
    expect(find.text('≥15 km'), findsOneWidget);
    expect(find.text('đủ để bốc thăm'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('suất'), findsOneWidget);
    expect(find.text('T2 30/11'), findsOneWidget);
    expect(find.text('12:00 công bố'), findsOneWidget);
  });

  testWidgets('mặt sau nhiều món: luật từng món và tổng quà, số suất', (
    tester,
  ) async {
    await _pumpBack(
      tester,
      _card(
        items: [
          const RankRewardItem(
            id: 'g',
            fromRank: 1,
            toRank: 1,
            name: 'Giày',
            icon: 'shoes',
          ),
          const RankRewardItem(
            id: 'b',
            fromRank: 2,
            toRank: 3,
            name: 'Bình',
            icon: 'bottle',
          ),
          _draw('Áo').copyWith(slots: 2),
        ],
      ),
    );
    expect(find.text('QUÀ TUẦN'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2–3'), findsOneWidget);
    expect(find.text('Bốc 2 · ≥15 km'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('quà'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Mỗi người nhận tối đa 1 quà · 3I RUN'), findsOneWidget);
  });

  testWidgets('mặt trước: bục top 3, dải quà nói cách nhận', (tester) async {
    Future<void> pump(RankBoardCard card) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(
            size: achievementCardSize,
            child: AchievementCard(data: card.data),
          ),
        ),
      ),
    );
    await pump(_card(me: 'u13'));
    expect(find.text('BXH TUẦN'), findsOneWidget);
    expect(find.text('23–29/11'), findsOneWidget);
    expect(find.text('Người 1'), findsOneWidget);
    expect(find.text('Người 13'), findsOneWidget);
    expect(find.text('Người 10'), findsNothing);
    expect(find.text('Bốc thăm 1 người đạt ≥15 km'), findsOneWidget);
    await pump(_card(items: [_draw('Áo'), _draw('Tất')]));
    expect(find.text('2 quà · 2 suất'), findsOneWidget);
    expect(find.text('≥15 km đủ để bốc thăm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kỳ không quà: chỉ mặt BXH, chân thẻ thay dải quà', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final board = _card(me: 'u13').board;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(child: RankBoardPoster(board: board)),
      ),
    );
    expect(find.text('BXH TUẦN'), findsOneWidget);
    expect(find.text('Người 13'), findsOneWidget);
    expect(find.text('3I RUN'), findsOneWidget);
    expect(find.textContaining('LẬT THẺ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thẻ không theo cỡ chữ hệ thống, cỡ lớn vẫn vừa', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final n in [1, 2, 4, 5]) {
      final card = _card(
        items: [
          for (var i = 0; i < n; i++) _draw('Áo chạy Kiprun Run 100 số $i'),
        ],
      );
      for (final back in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: achievementCardSize,
                child: AchievementCard(data: card.data, back: back),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$n món, back=$back');
      }
    }
  });

  testWidgets('mặt sau nhiều món vẫn vừa thẻ', (tester) async {
    for (final n in [2, 3, 4, 5, 10]) {
      await _pumpBack(
        tester,
        _card(items: [for (var i = 0; i < n; i++) _draw('Quà $i')]),
      );
      for (var i = 0; i < n; i++) {
        expect(find.text('Quà $i'), findsOneWidget, reason: '$n món');
      }
      expect(tester.takeException(), isNull, reason: '$n món tràn thẻ');
    }
  });
}
