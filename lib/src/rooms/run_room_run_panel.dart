import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_screen.dart'
    show RunRoomCheerBar, RunRoomRequestTile;
import 'package:myrun/src/widgets/glass.dart';

/// Thanh phòng nổi trên màn chạy: tên phòng, bao nhiêu người đang chạy, ai
/// đang xin vào (với chủ phòng), emoji cổ vũ một chạm. Cổ vũ mới của người
/// khác hiện thành snackbar. Chạm vào tên để mở map cả phòng.
class RunRoomRunPanel extends ConsumerWidget {
  const RunRoomRunPanel({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final room = ref.watch(runRoomProvider(roomId)).value;
    final me = ref.watch(myRunRoomMemberProvider(roomId)).value;
    final joined = me?.state == RunRoomMemberState.joined;
    if (room == null || uid == null) return const SizedBox.shrink();
    if (joined) {
      ref.listen(
        runRoomMessagesProvider(roomId),
        (previous, next) => _toastNewCheers(context, ref, uid, previous, next),
      );
    }
    final members = joined
        ? ref.watch(runRoomMembersProvider(roomId)).value ?? const []
        : const <RunRoomMember>[];
    final joinedUids = {
      for (final m in members)
        if (m.state == RunRoomMemberState.joined) m.uid,
    };
    final running = joined
        ? (ref.watch(runRoomLiveProvider(roomId)).value ?? const [])
              .where((s) => joinedUids.contains(s.ownerUid))
              .length
        : 0;
    final isHost = room.hostUid == uid;
    final requested = isHost
        ? [
            for (final m in members)
              if (m.state == RunRoomMemberState.requested) m,
          ]
        : const <RunRoomMember>[];
    final requests = requested.length;
    final open = room.isOpen(DateTime.now());
    final solo = room.kind == RunRoomKind.solo;
    final title = !solo
        ? room.title
        : isHost
        ? 'Đang nhận người chạy cùng'
        : 'Chạy cùng ${room.hostName}';
    final status = !open
        ? 'Phòng đã đóng'
        : !joined
        ? 'Bạn không còn trong phòng'
        : requests > 0
        ? '$running đang chạy · $requests người xin vào'
        : '$running đang chạy';
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/rooms/$roomId'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.map_rounded, size: 20),
              ],
            ),
          ),
          // Duyệt từng người một ngay trên màn chạy, người xin trước lên trước.
          if (open && requested.isNotEmpty)
            RunRoomRequestTile(roomId: roomId, member: requested.first),
          if (open && joined)
            RunRoomCheerBar(roomId: roomId, uid: uid, emojiOnly: true),
        ],
      ),
    );
  }

  /// Báo cổ vũ mới của người khác; lần tải đầu (previous null) chỉ là lịch sử
  /// nên bỏ qua.
  void _toastNewCheers(
    BuildContext context,
    WidgetRef ref,
    String uid,
    AsyncValue<List<RunRoomMessage>>? previous,
    AsyncValue<List<RunRoomMessage>> next,
  ) {
    final before = previous?.value;
    final after = next.value;
    if (before == null || after == null) return;
    final seen = {for (final m in before) m.id};
    final fresh = [
      for (final m in after)
        if (!seen.contains(m.id) && m.uid != uid) m,
    ];
    if (fresh.isEmpty) return;
    final names = {
      for (final m
          in ref.read(runRoomMembersProvider(roomId)).value ??
              const <RunRoomMember>[])
        m.uid: m.name,
    };
    final latest = fresh.first;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text('${names[latest.uid] ?? 'Thành viên'}: ${latest.text}'),
        ),
      );
  }
}
