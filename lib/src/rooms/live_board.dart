import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';

/// Một buổi chạy riêng đang live. [room] là phòng solo chủ buổi chạy mở để
/// nhận người chạy cùng; null khi chủ chọn "Không cho" hoặc chưa đọc được.
class SoloLive {
  const SoloLive({required this.session, this.room});

  final LiveTrackingSession session;
  final RunRoom? room;

  /// Còn xin chạy cùng được: phòng còn mở và còn chỗ.
  bool acceptsRunners(DateTime now) {
    final room = this.room;
    return room != null && room.isOpen(now) && !room.full;
  }

  String policyLabel(DateTime now) {
    if (!acceptsRunners(now)) return 'Chỉ xem';
    return room!.privacy == RunRoomPrivacy.public
        ? 'Nhận chạy cùng · tự vào'
        : 'Nhận chạy cùng · cần duyệt';
  }
}

/// Mọi thứ đang live hay sắp live mà mình thấy được: phòng group đã tới giờ,
/// phòng hẹn giờ, và buổi chạy riêng của người khác trong club.
class LiveBoard {
  const LiveBoard({
    required this.liveRooms,
    required this.upcomingRooms,
    required this.solos,
    required this.myStates,
    required this.meLive,
  });

  final List<RunRoom> liveRooms;

  /// Sớm nhất trước.
  final List<RunRoom> upcomingRooms;
  final List<SoloLive> solos;

  /// Phòng mình đã vào hay đang xin vào.
  final Map<String, RunRoomMemberState> myStates;

  /// Chính mình đang chạy live.
  final bool meLive;
}

/// Chia phòng và buổi live thành các mục của [LiveBoard]. Buổi live nằm
/// trong phòng group thì tính vào thẻ phòng, không thành dòng chạy riêng.
/// [rooms] là mọi doc phòng đã đọc, theo id.
LiveBoard buildLiveBoard({
  required Map<String, RunRoom> rooms,
  required Map<String, RunRoomMemberState> myStates,
  required List<LiveTrackingSession> sessions,
  required String? uid,
  required DateTime now,
}) {
  final open = [
    for (final room in rooms.values)
      if (room.kind == RunRoomKind.group && room.isOpen(now)) room,
  ];
  bool started(RunRoom room) {
    final starts = room.startsAt;
    return starts == null || !starts.isAfter(now);
  }

  int mineFirst(RunRoom a, RunRoom b) {
    final byMine = (myStates.containsKey(a.id) ? 0 : 1).compareTo(
      myStates.containsKey(b.id) ? 0 : 1,
    );
    if (byMine != 0) return byMine;
    return b.runnerCount.compareTo(a.runnerCount);
  }

  final solos = <SoloLive>[];
  for (final session in sessions) {
    if (session.ownerUid == uid) continue;
    final room = switch (session.roomId) {
      final id? => rooms[id],
      null => null,
    };
    if (room?.kind == RunRoomKind.group) continue;
    solos.add(SoloLive(session: session, room: room));
  }
  return LiveBoard(
    liveRooms: [
      for (final room in open)
        if (started(room)) room,
    ]..sort(mineFirst),
    upcomingRooms: [
      for (final room in open)
        if (!started(room)) room,
    ]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!)),
    solos: solos,
    myStates: myStates,
    meLive: sessions.any((s) => s.ownerUid == uid),
  );
}

/// [LiveBoard] của người đang đăng nhập. Lỗi đọc live hay phòng thì trả lỗi,
/// không thay bằng bảng rỗng.
final liveBoardProvider = Provider.autoDispose<AsyncValue<LiveBoard>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  final sessions = ref.watch(clubLiveSessionsProvider);
  final public = ref.watch(publicRunRoomsProvider);
  final mine = ref.watch(myRunRoomsProvider);
  for (final part in [sessions, public, mine]) {
    if (part case AsyncError(:final error, :final stackTrace)) {
      return AsyncValue.error(error, stackTrace);
    }
  }
  final sessionList = sessions.value;
  final publicRooms = public.value;
  if (sessionList == null || publicRooms == null) {
    return const AsyncValue.loading();
  }
  final rooms = {for (final room in publicRooms) room.id: room};
  final myStates = <String, RunRoomMemberState>{};
  for (final membership in mine.value ?? const <RunRoomMembership>[]) {
    myStates[membership.roomId] = membership.state;
  }
  // Phòng của mình và phòng của từng buổi live chưa có trong list công khai
  // thì đọc doc theo id: phòng chủ duyệt, mật khẩu, phòng solo.
  final ids = {
    ...myStates.keys,
    for (final session in sessionList) ?session.roomId,
  };
  for (final id in ids) {
    if (rooms.containsKey(id)) continue;
    if (ref.watch(runRoomProvider(id)).value case final room?) {
      rooms[id] = room;
    }
  }
  return AsyncValue.data(
    buildLiveBoard(
      rooms: rooms,
      myStates: myStates,
      sessions: sessionList,
      uid: uid,
      now: DateTime.now(),
    ),
  );
});
