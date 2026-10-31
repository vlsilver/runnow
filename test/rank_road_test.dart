import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/widgets/rank_road.dart';

ClubRankedMember _member(int rank, String name, double km) {
  final stats = LeaderboardStats(
    distanceMeters: km * 1000,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
  );
  return ClubRankedMember(
    rank: rank,
    score: km * 1000,
    entry: LeaderboardEntry(
      uid: name,
      displayName: name,
      visibility: ProfileVisibility.public,
      rollingSevenDays: stats,
      currentWeek: stats,
      currentMonth: stats,
    ),
  );
}

Future<void> _pump(WidgetTester tester, List<ClubRankedMember> ranked) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: RankRoad(ranked: ranked, myUid: null),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('chỉ vẽ năm người đầu, hạng 1 sát đích, hạng 5 đầu đường', (
    tester,
  ) async {
    // Km sát nhau tới 0.1 vẫn mỗi người một chỗ.
    await _pump(tester, [
      _member(1, 'An', 20.3),
      _member(2, 'Bình', 20.2),
      _member(3, 'Chi', 20.1),
      _member(4, 'Dũng', 20.0),
      _member(5, 'Em', 19.9),
      _member(6, 'Phúc', 19.8),
      _member(7, 'Giang', 5.0),
    ]);
    for (final name in ['An', 'Bình', 'Chi', 'Dũng', 'Em']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Phúc'), findsNothing);
    expect(find.text('Giang'), findsNothing);
    final xs = [
      for (final name in ['Em', 'Dũng', 'Chi', 'Bình', 'An'])
        tester.getCenter(find.text(name)).dx,
    ];
    // Từ hạng 5 tới hạng 1 đi dần sang phải, mỗi người cách nhau rõ ràng.
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i] - xs[i - 1], greaterThan(40));
    }
  });

  testWidgets('ít hơn năm người thì đứng ở các chỗ gần đích nhất', (
    tester,
  ) async {
    await _pump(tester, [_member(1, 'An', 12.0), _member(2, 'Bình', 8.0)]);
    final left = tester.getTopLeft(find.byType(RankRoad)).dx;
    // Chỗ sát đích ở 84% bề ngang, chỗ kế ở 65%.
    expect(tester.getCenter(find.text('An')).dx - left, closeTo(360 * 0.84, 1));
    expect(
      tester.getCenter(find.text('Bình')).dx - left,
      closeTo(360 * 0.65, 1),
    );
  });
}
