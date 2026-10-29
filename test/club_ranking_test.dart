import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';

LeaderboardStats _stats({double meters = 0, int steps = 0}) => LeaderboardStats(
  distanceMeters: meters,
  movingTimeSeconds: 0,
  activityCount: 0,
  activeDays: 0,
  longestDistanceMeters: 0,
  fastestPaceSecondsPerKm: null,
  steps: steps,
);

LeaderboardEntry _member(
  String uid, {
  double weekMeters = 0,
  int weekSteps = 0,
  double monthMeters = 0,
  ProfileVisibility visibility = ProfileVisibility.public,
}) => LeaderboardEntry(
  uid: uid,
  displayName: uid,
  visibility: visibility,
  rollingSevenDays: _stats(),
  currentWeek: _stats(meters: weekMeters, steps: weekSteps),
  currentMonth: _stats(meters: monthMeters),
);

void main() {
  test('only public members with something in the period are ranked', () {
    final ranked = rankClubMembers(
      [
        _member('zero'),
        _member(
          'private',
          weekMeters: 9000,
          visibility: ProfileVisibility.private,
        ),
        _member('runner', weekMeters: 5000),
        _member('monthOnly', monthMeters: 20000),
      ],
      ClubRankingSport.run,
      ClubRankingRange.currentWeek,
    );

    expect(ranked.map((m) => m.entry.uid), ['runner']);
    expect(ranked.single.rank, 1);
  });

  test('sorts by steps and gives tied members the same rank', () {
    final ranked = rankClubMembers(
      [
        _member('c', weekSteps: 7000),
        _member('a', weekSteps: 12000),
        _member('d', weekSteps: 3000),
        _member('b', weekSteps: 12000),
      ],
      ClubRankingSport.steps,
      ClubRankingRange.currentWeek,
    );

    expect(ranked.map((m) => m.entry.uid), ['a', 'b', 'c', 'd']);
    expect(ranked.map((m) => m.rank), [1, 1, 3, 4]);
  });

  test('time left counts to the period end on Vietnam time', () {
    // Thứ Sáu 30/10/2026 17:00 giờ VN.
    final friday = DateTime.utc(2026, 10, 30, 10);
    expect(
      clubRankingTimeLeftLabel(friday, ClubRankingRange.currentWeek),
      'Còn 2 ngày 7 giờ',
    );
    expect(
      clubRankingTimeLeftLabel(friday, ClubRankingRange.currentMonth),
      'Còn 1 ngày 7 giờ',
    );
    // Chủ nhật 1/11/2026 23:30 giờ VN, theo UTC mới 16:30.
    expect(
      clubRankingTimeLeftLabel(
        DateTime.utc(2026, 11, 1, 16, 30),
        ClubRankingRange.currentWeek,
      ),
      'Còn 30 phút',
    );
  });

  test('gap label points at the nearest member with more', () {
    final ranked = rankClubMembers(
      [
        _member('lead', weekSteps: 15000),
        _member('tieA', weekSteps: 9000),
        _member('tieB', weekSteps: 9000),
        _member('me', weekSteps: 7750),
      ],
      ClubRankingSport.steps,
      ClubRankingRange.currentWeek,
    );

    expect(
      clubRankingGapLabel(ranked, 3, ClubRankingSport.steps),
      'Còn 1.250 bước nữa lên hạng 2',
    );
    expect(
      clubRankingGapLabel(ranked, 2, ClubRankingSport.steps),
      'Còn 6.000 bước nữa lên hạng 1',
    );
    expect(
      clubRankingGapLabel(ranked, 0, ClubRankingSport.steps),
      'Hơn hạng 2 tới 6.000 bước',
    );
  });

  test('gap label is empty for a lone leader', () {
    final ranked = rankClubMembers(
      [_member('only', weekMeters: 4200)],
      ClubRankingSport.run,
      ClubRankingRange.currentWeek,
    );

    expect(clubRankingGapLabel(ranked, 0, ClubRankingSport.run), isNull);
  });
}
