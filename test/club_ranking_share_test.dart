import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
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

void main() {
  testWidgets('Nút khoe ở XẾP HẠNG mở ảnh 10 dòng đầu kèm dòng của mình', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Khoe bảng xếp hạng'), findsOne);
    expect(find.text('Chạy/Đi bộ · tuần này'), findsOneWidget);
    // Ảnh có hạng 1 đến 10 và hạng 12 của mình, không có hạng 11.
    expect(find.text('Người 10'), findsNWidgets(2));
    expect(find.text('Người 11'), findsOneWidget);
    expect(find.text('Người 12'), findsNWidgets(2));
  });
}
