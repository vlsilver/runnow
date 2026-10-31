import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/live_board.dart';
import 'package:myrun/src/rooms/live_screen.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/theme.dart';

void main() {
  final now = DateTime.now();

  RunRoom room(
    String id, {
    RunRoomKind kind = RunRoomKind.group,
    DateTime? startsAt,
  }) => RunRoom(
    id: id,
    hostUid: 'host-$id',
    hostName: 'Hà My',
    title: 'Phòng $id',
    privacy: RunRoomPrivacy.public,
    maxRunners: 10,
    runnerCount: 4,
    ended: false,
    startsAt: startsAt,
    closesAt: now.add(const Duration(hours: 6)),
    kind: kind,
  );

  final solo = SoloLive(
    session: LiveTrackingSession(
      id: 'live-1',
      ownerUid: 'u1',
      ownerName: 'Minh Anh',
      visibility: LiveTrackingVisibility.club,
      status: LiveTrackingStatus.running,
      startedAt: now.subtract(const Duration(minutes: 30)),
      updatedAt: now,
      distanceMeters: 6420,
      movingTimeSeconds: 1800,
      roomId: 's1',
    ),
    room: room('s1', kind: RunRoomKind.solo),
  );

  testWidgets('lọc chạy riêng thì ẩn phòng, dòng chạy riêng nói nhận người', (
    tester,
  ) async {
    final board = LiveBoard(
      liveRooms: [room('dem')],
      upcomingRooms: [
        room('sang', startsAt: now.add(const Duration(hours: 3))),
      ],
      solos: [solo],
      myStates: const {},
      meLive: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveBoardProvider.overrideWithValue(AsyncValue.data(board)),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: const LiveScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tất cả · 3'), findsOneWidget);
    expect(find.text('Phòng dem'), findsOneWidget);
    expect(find.text('SẮP DIỄN RA'), findsOneWidget);
    expect(find.text('Nhận chạy cùng · tự vào'), findsOneWidget);

    await tester.tap(find.text('Chạy riêng · 1'));
    await tester.pump();

    expect(find.text('Phòng dem'), findsNothing);
    expect(find.text('SẮP DIỄN RA'), findsNothing);
    expect(find.text('Minh Anh'), findsOneWidget);
  });
}
