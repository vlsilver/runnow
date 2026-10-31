import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/theme.dart';

/// Nút chạy cùng ở màn xem live của người đang chạy riêng có mở phòng solo.
/// Phòng tự vào thì vào thẳng rồi sang màn chạy; phòng cần duyệt thì xin vào
/// và chờ, được duyệt thì nút thành "Chạy cùng".
class RunTogetherButton extends ConsumerStatefulWidget {
  const RunTogetherButton({required this.session, super.key});

  final LiveTrackingSession session;

  @override
  ConsumerState<RunTogetherButton> createState() => _RunTogetherButtonState();
}

class _RunTogetherButtonState extends ConsumerState<RunTogetherButton> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final roomId = session.roomId;
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    if (roomId == null || uid == null || session.ownerUid == uid) {
      return const SizedBox.shrink();
    }
    final room = ref.watch(runRoomProvider(roomId)).value;
    if (room == null ||
        room.kind != RunRoomKind.solo ||
        !session.isActive ||
        !room.isOpen(DateTime.now())) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(myRunRoomMemberProvider(roomId)).value?.state;
    void runWith() => context.push('/tracking/room/$roomId');
    final Widget child = switch (state) {
      RunRoomMemberState.joined => FilledButton.icon(
        onPressed: runWith,
        icon: const Icon(Icons.directions_run_rounded),
        label: const Text('Chạy cùng'),
      ),
      RunRoomMemberState.requested => OutlinedButton(
        onPressed: _busy
            ? null
            : () => _run(
                () => runRoomAction(
                  context,
                  () => ref.read(runNowApiClientProvider).leaveRunRoom(roomId),
                ),
              ),
        child: const Text('Đang chờ duyệt · Huỷ'),
      ),
      RunRoomMemberState.kicked || RunRoomMemberState.denied => _note(
        context,
        'Lần này ${session.ownerName} không nhận thêm người chạy cùng.',
      ),
      _ when room.full => _note(context, 'Đã đủ người chạy cùng.'),
      _ => FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() async {
                final ok = await joinRunRoom(context, ref, room);
                if (ok &&
                    room.privacy == RunRoomPrivacy.public &&
                    context.mounted) {
                  runWith();
                }
              }),
        icon: const Icon(Icons.directions_run_rounded),
        label: Text(
          room.privacy == RunRoomPrivacy.public ? 'Chạy cùng' : 'Xin chạy cùng',
        ),
      ),
    };
    return Padding(padding: const EdgeInsets.only(top: 12), child: child);
  }

  Widget _note(BuildContext context, String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: context.runNowPalette.textMuted,
      fontWeight: FontWeight.w700,
    ),
  );
}
