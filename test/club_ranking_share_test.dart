import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/screens/club_screen.dart';
import 'package:myrun/src/theme.dart';

class _FakeUser implements User {
  @override
  String get uid => 'u12';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Thành viên thứ [n] chạy (13 - n) km tuần này: u1 nhiều nhất, u12 ít nhất.
LeaderboardEntry _member(int n) {
  final stats = LeaderboardStats(
    distanceMeters: (13 - n) * 1000,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
  );
  return LeaderboardEntry(
    uid: 'u$n',
    displayName: 'Người $n',
    visibility: ProfileVisibility.public,
    rollingSevenDays: stats,
    currentWeek: stats,
    currentMonth: stats,
  );
}

Future<void> _pump(WidgetTester tester, RankRewards? rewards) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        totalKmLeaderboardProvider.overrideWith(
          (ref) async => [for (var n = 1; n <= 12; n++) _member(n)],
        ),
        rankBoardProvider.overrideWith((ref, id) => Stream.value(null)),
        rankRewardsProvider.overrideWith((ref, id) => Stream.value(rewards)),
      ],
      child: MaterialApp(
        theme: buildRunNowDarkTheme(),
        home: const ClubScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Bảng trên màn có đủ 12 người.
  expect(find.text('Người 11'), findsOneWidget);
  await tester.tap(find.byTooltip('Khoe bảng xếp hạng'));
  // Thẻ hai mặt có hiệu ứng chạy liên tục nên không đợi settle.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('Kỳ không quà: khoe ảnh BXH 9 dòng đầu kèm dòng của mình', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.widgetWithText(FilledButton, 'Khoe bảng xếp hạng'), findsOne);
    expect(find.text('BXH TUẦN'), findsOneWidget);
    expect(find.text('3I RUN'), findsOneWidget);
    // Ảnh có hạng 1 đến 9 và hạng 12 của mình, thay cho dòng 10; không có 11.
    expect(find.text('Người 9'), findsNWidgets(2));
    expect(find.text('Người 10'), findsOneWidget);
    expect(find.text('Người 11'), findsOneWidget);
    expect(find.text('Người 12'), findsNWidgets(2));
  });

  testWidgets('Kỳ có quà: khoe thẻ hai mặt, mặt trước có dải quà', (
    tester,
  ) async {
    await _pump(
      tester,
      const RankRewards(
        giverName: 'A',
        items: [
          RankRewardItem(
            id: 'a',
            kind: rankRewardDrawKind,
            minScore: 5000,
            slots: 1,
            name: 'Áo',
            icon: 'shirt',
          ),
        ],
      ),
    );
    expect(find.text('Khoe bảng xếp hạng'), findsNothing);
    expect(find.text('QUÀ TUẦN NÀY · LẬT THẺ'), findsOneWidget);
    expect(find.text('Bốc thăm 1 người đạt ≥5 km'), findsOneWidget);
  });
}
