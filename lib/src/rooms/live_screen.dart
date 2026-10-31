import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/live_board.dart';
import 'package:myrun/src/rooms/run_room_create_sheet.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_route_sketch.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/live_bits.dart';

enum _LiveFilter { all, rooms, solo }

/// Trang Live: phòng đang chạy, người đang chạy riêng, rồi phòng hẹn giờ.
/// Vào từ mục Live ở Trang chủ; chạm một dòng mới vào chi tiết.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  _LiveFilter _filter = _LiveFilter.all;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final board = ref.watch(liveBoardProvider);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(color: palette.accent),
            const SizedBox(width: 8),
            const Text('Live'),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () => showCreateRunRoomSheet(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Mở phòng chạy'),
        ),
      ),
      body: switch (board) {
        AsyncData(:final value) => _body(context, value),
        AsyncError(:final error) => Center(
          child: TextButton(
            onPressed: () {
              debugPrint('live board: $error');
              ref.invalidate(clubLiveSessionsProvider);
              ref.invalidate(publicRunRoomsProvider);
              ref.invalidate(myRunRoomsProvider);
            },
            child: const Text('Không tải được ai đang live. Chạm để thử lại.'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, LiveBoard board) {
    final now = DateTime.now();
    final roomCount = board.liveRooms.length + board.upcomingRooms.length;
    final showRooms = _filter != _LiveFilter.solo;
    final showSolo = _filter != _LiveFilter.rooms;
    final running = [
      if (showRooms)
        for (final room in board.liveRooms)
          LiveRoomTile(room: room, myState: board.myStates[room.id]),
      if (showSolo)
        for (final solo in board.solos) SoloLiveTile(solo: solo, now: now),
    ];
    final upcoming = [
      if (showRooms)
        for (final room in board.upcomingRooms)
          LiveRoomTile(room: room, myState: board.myStates[room.id]),
    ];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(clubLiveSessionsProvider);
        ref.invalidate(publicRunRoomsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final (filter, label) in [
                (_LiveFilter.all, 'Tất cả · ${roomCount + board.solos.length}'),
                (_LiveFilter.rooms, 'Phòng · $roomCount'),
                (_LiveFilter.solo, 'Chạy riêng · ${board.solos.length}'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _filter == filter,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          if (running.isEmpty && upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Text(
                'Chưa ai đang live. Mở phòng rủ cả nhóm, hoặc bắt đầu chạy '
                'ở tab Chạy để bạn bè xin chạy cùng.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.runNowPalette.textMuted),
              ),
            ),
          if (running.isNotEmpty) ...[
            const _SectionLabel('ĐANG CHẠY'),
            ...running,
          ],
          if (upcoming.isNotEmpty) ...[
            const _SectionLabel('SẮP DIỄN RA'),
            ...upcoming,
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        color: context.runNowPalette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}

/// Một phòng group: đang chạy thì ô trái là hình tuyến, hẹn giờ thì ô trái
/// là giờ và ngày hẹn.
class LiveRoomTile extends StatelessWidget {
  const LiveRoomTile({required this.room, this.myState, super.key});

  final RunRoom room;
  final RunRoomMemberState? myState;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final now = DateTime.now();
    final starts = room.startsAt?.toLocal();
    final upcoming = starts != null && starts.isAfter(now);
    final route = room.route;
    final detail = [
      room.hostName,
      '${room.runnerCount}/${room.maxRunners} '
          '${upcoming ? 'đăng ký' : 'người'}',
      if (route != null) 'tuyến ${runRoomRouteKm(route)}',
    ].join(' · ');
    final badge = switch (myState) {
      RunRoomMemberState.joined => upcoming ? 'Đã đăng ký' : 'Đã vào',
      RunRoomMemberState.requested => 'Chờ duyệt',
      _ => runRoomAccessLabel(room.privacy),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/rooms/${room.id}'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: palette.tint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: upcoming
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            children: [
                              Text(
                                DateFormat('HH:mm').format(starts),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                runRoomDayLabel(starts, now),
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        )
                      : route != null
                      ? RunRoomRouteSketch(route: route, color: palette.accent)
                      : Icon(Icons.groups_rounded, color: palette.accent),
                ),
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
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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

/// Một người đang chạy riêng; dòng dưới nói có nhận người chạy cùng không.
class SoloLiveTile extends StatelessWidget {
  const SoloLiveTile({required this.solo, required this.now, super.key});

  final SoloLive solo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final session = solo.session;
    final accepts = solo.acceptsRunners(now);
    final avatar = session.ownerAvatarUrl;
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/live/${session.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: palette.accent,
                  backgroundImage: hasAvatar
                      ? cachedAvatarImage(context, avatar, 44)
                      : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          session.ownerName.isEmpty
                              ? '?'
                              : session.ownerName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      EverySecond(
                        builder: (context, now) => Text(
                          [
                            formatDistance(session.distanceMeters),
                            formatDuration(liveElapsedSeconds(session, now)),
                            formatPace(session.averagePaceSecondsPerKm),
                          ].join(' · '),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        solo.policyLabel(now),
                        style: TextStyle(
                          color: accepts
                              ? palette.accentDeep
                              : palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
