import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/rank_mountain.dart';

LeaderboardEntry _entry(String name, double km) {
  final stats = LeaderboardStats(
    distanceMeters: km * 1000,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
  );
  return LeaderboardEntry(
    uid: name,
    displayName: name,
    visibility: ProfileVisibility.public,
    rollingSevenDays: stats,
    currentWeek: stats,
    currentMonth: stats,
  );
}

ClubRankedMember _member(int rank, String name, double km) =>
    ClubRankedMember(rank: rank, score: km * 1000, entry: _entry(name, km));

Future<void> _pump(
  WidgetTester tester,
  List<ClubRankedMember> ranked, {
  String? myUid,
  LeaderboardEntry? myEntry,
  bool meByName = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 358,
          child: RankMountain(
            ranked: ranked,
            myUid: myUid,
            myEntry: myEntry,
            meByName: meByName,
          ),
        ),
      ),
    ),
  ),
);

double _rowY(WidgetTester tester, String name) =>
    tester.getCenter(find.text(name)).dy -
    tester.getTopLeft(find.byType(RankMountain)).dy;

void main() {
  testWidgets('top 5 xếp từ đỉnh xuống, người thứ sáu không lên núi', (
    tester,
  ) async {
    // Km sát nhau tới 0.1 vẫn mỗi người một dòng.
    await _pump(tester, [
      _member(1, 'An', 20.3),
      _member(2, 'Bình', 20.2),
      _member(3, 'Chi', 20.1),
      _member(4, 'Dũng', 20.0),
      _member(5, 'Em', 19.9),
      _member(6, 'Phúc', 19.8),
    ]);
    expect(find.text('Phúc'), findsNothing);
    final ys = [
      for (final name in ['An', 'Bình', 'Chi', 'Dũng', 'Em'])
        _rowY(tester, name),
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i] - ys[i - 1], greaterThan(30));
    }
  });

  testWidgets('ít người thì đứng sát đỉnh', (tester) async {
    await _pump(tester, [_member(1, 'An', 12.0), _member(2, 'Bình', 8.0)]);
    // Tên hạng 1 nằm trên vạch đồng mức thứ nhất, cao 64 trên khung 296.
    expect(_rowY(tester, 'An'), lessThan(296 * 0.3));
    expect(_rowY(tester, 'Bình'), lessThan(296 * 0.45));
  });

  testWidgets('mình ngoài top 5 thì đứng ở trại chân núi với hạng thật', (
    tester,
  ) async {
    final ranked = [
      for (var i = 1; i <= 7; i++) _member(i, 'Người $i', 30.0 - i),
    ];
    await _pump(tester, ranked, myUid: 'Người 7');
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(_rowY(tester, 'Bạn'), greaterThan(296 * 0.8));
  });

  testWidgets('ảnh khoe ghi tên thật của mình thay cho "Bạn"', (tester) async {
    final ranked = [
      for (var i = 1; i <= 7; i++) _member(i, 'Người $i', 30.0 - i),
    ];
    await _pump(tester, ranked, myUid: 'Người 7', meByName: true);
    expect(find.text('Bạn'), findsNothing);
    expect(find.text('Người 7'), findsOneWidget);
    expect(_rowY(tester, 'Người 7'), greaterThan(296 * 0.8));
  });

  testWidgets('mình trong top 5 thì không đứng thêm ở trại', (tester) async {
    await _pump(tester, [
      _member(1, 'An', 12.0),
      _member(2, 'Bình', 8.0),
    ], myUid: 'Bình');
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('Bình'), findsNothing);
    expect(_rowY(tester, 'Bạn'), lessThan(296 * 0.45));
  });

  testWidgets('mình chưa có km thì ở trại, ghi chưa xuất phát', (tester) async {
    await _pump(
      tester,
      [_member(1, 'An', 12.0)],
      myUid: 'Giang',
      myEntry: _entry('Giang', 0),
    );
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('chưa xuất phát'), findsOneWidget);
  });

  test('màu núi theo hành và sáng tối của theme', () {
    final waterLight = RunNowPalette.forSelection(
      RunNowElement.water,
      appearance: RunNowAppearance.light,
    );
    final fireLight = RunNowPalette.forSelection(
      RunNowElement.fire,
      appearance: RunNowAppearance.light,
    );
    final waterDark = RunNowPalette.forSelection(RunNowElement.water);
    final water = MountainColors.of(waterLight);
    expect(water.sky, waterLight.tint);
    expect(MountainColors.of(waterDark).sky, waterDark.tint);
    expect(MountainColors.of(fireLight).face, isNot(water.face));
    expect(MountainColors.of(waterDark).face, isNot(water.face));
  });
}
