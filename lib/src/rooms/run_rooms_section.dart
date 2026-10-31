import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/rooms/run_room_create_sheet.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_screen.dart' show runRoomWhen;
import 'package:myrun/src/screens/keo_hub_screen.dart' show HubSectionHeader;
import 'package:myrun/src/theme.dart';

/// Số phòng tối đa ở Trang chủ, phòng của mình xếp trước.
const _homeRoomLimit = 5;

/// Mục "Phòng chạy" ở Trang chủ: phòng mình đang ở hay đang xin vào, rồi tới
/// phòng công khai còn mở. Không có phòng nào thì mời mở phòng.
class RunRoomsSection extends ConsumerWidget {
  const RunRoomsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myRunRoomsProvider).value ?? const [];
    final public = ref.watch(publicRunRoomsProvider);
    final now = DateTime.now();
    final mineIds = {for (final m in mine) m.roomId};
    final others = [
      for (final room in public.value ?? const <RunRoom>[])
        if (!mineIds.contains(room.id) && room.isOpen(now)) room,
    ];
    final rows = <Widget>[
      for (final m in mine)
        _MyRoomRow(roomId: m.roomId, requested: m.state.isRequested),
      for (final room in others) _RoomRow(room: room),
    ].take(_homeRoomLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionHeader(
          title: 'Phòng chạy',
          action: IconButton(
            tooltip: 'Mở phòng',
            onPressed: () => showCreateRunRoomSheet(context),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ),
        if (public.hasError && mine.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => ref.invalidate(publicRunRoomsProvider),
                child: const Text(
                  'Không tải được phòng chạy. Chạm để thử lại.',
                ),
              ),
            ),
          )
        else if (rows.isEmpty && !public.isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EmptyRow(onTap: () => showCreateRunRoomSheet(context)),
          )
        else
          ...rows,
      ],
    );
  }
}

extension on RunRoomMemberState {
  bool get isRequested => this == RunRoomMemberState.requested;
}

/// Phòng mình đang ở: đọc doc phòng theo id. Phòng đã đóng thì ẩn, dòng
/// member vẫn còn `joined` sau khi phòng kết thúc.
class _MyRoomRow extends ConsumerWidget {
  const _MyRoomRow({required this.roomId, required this.requested});

  final String roomId;
  final bool requested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(runRoomProvider(roomId)).value;
    if (room == null || !room.isOpen(DateTime.now())) {
      return const SizedBox.shrink();
    }
    return _RoomRow(room: room, badge: requested ? 'Chờ duyệt' : 'Đã vào');
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, this.badge});

  final RunRoom room;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/rooms/${room.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Icon(switch (room.privacy) {
                  RunRoomPrivacy.public => Icons.groups_rounded,
                  RunRoomPrivacy.private => Icons.how_to_reg_rounded,
                  RunRoomPrivacy.password => Icons.lock_rounded,
                }, color: palette.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${room.hostName} · ${room.runnerCount}/${room.maxRunners} · '
                        '${runRoomWhen(room, DateTime.now())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (badge case final badge?)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return Material(
      color: palette.glassStart,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rủ bạn chạy cùng',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mở phòng, gửi link: cả nhóm thấy nhau trên map và cổ vũ.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 19,
                backgroundColor: palette.accent,
                child: Icon(
                  Icons.add_rounded,
                  color:
                      ThemeData.estimateBrightnessForColor(palette.accent) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
