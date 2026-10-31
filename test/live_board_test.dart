import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/live_board.dart';
import 'package:myrun/src/rooms/run_room_models.dart';

void main() {
  final now = DateTime(2026, 10, 31, 18);

  LiveTrackingSession live(String id, String owner, {String? roomId}) =>
      LiveTrackingSession(
        id: id,
        ownerUid: owner,
        ownerName: owner,
        visibility: LiveTrackingVisibility.club,
        status: LiveTrackingStatus.running,
        startedAt: now.subtract(const Duration(minutes: 20)),
        updatedAt: now,
        distanceMeters: 3000,
        movingTimeSeconds: 1200,
        roomId: roomId,
      );

  RunRoom room(
    String id, {
    RunRoomKind kind = RunRoomKind.group,
    RunRoomPrivacy privacy = RunRoomPrivacy.public,
    DateTime? startsAt,
    int runners = 1,
  }) => RunRoom(
    id: id,
    hostUid: 'host-$id',
    hostName: 'Chủ $id',
    title: 'Phòng $id',
    privacy: privacy,
    maxRunners: 8,
    runnerCount: runners,
    ended: false,
    startsAt: startsAt,
    closesAt: now.add(const Duration(hours: 6)),
    kind: kind,
  );

  test('live trong phòng group tính vào phòng, live phòng solo thành dòng '
      'chạy riêng', () {
    final board = buildLiveBoard(
      rooms: {
        'g1': room('g1'),
        's1': room(
          's1',
          kind: RunRoomKind.solo,
          privacy: RunRoomPrivacy.private,
        ),
      },
      myStates: const {},
      sessions: [
        live('a', 'An', roomId: 'g1'),
        live('b', 'Bảo', roomId: 's1'),
        live('c', 'Chi'),
      ],
      uid: 'me',
      now: now,
    );

    expect(board.liveRooms.map((r) => r.id), ['g1']);
    expect(board.solos.map((s) => s.session.id), ['b', 'c']);
    expect(board.solos.map((s) => s.policyLabel(now)), [
      'Nhận chạy cùng · cần duyệt',
      'Chỉ xem',
    ]);
  });

  test('phòng hẹn giờ vào sắp diễn ra, phòng mình ở đầu, live của mình '
      'không thành dòng', () {
    final board = buildLiveBoard(
      rooms: {
        'busy': room('busy', runners: 6),
        'mine': room('mine', runners: 2),
        'late': room('late', startsAt: now.add(const Duration(hours: 12))),
        'soon': room('soon', startsAt: now.add(const Duration(hours: 1))),
      },
      myStates: const {'mine': RunRoomMemberState.joined},
      sessions: [live('m', 'me')],
      uid: 'me',
      now: now,
    );

    expect(board.liveRooms.map((r) => r.id), ['mine', 'busy']);
    expect(board.upcomingRooms.map((r) => r.id), ['soon', 'late']);
    expect(board.solos, isEmpty);
    expect(board.meLive, isTrue);
  });
}
