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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _FilterBar(
            selected: _filter,
            labels: {
              _LiveFilter.all: 'Tất cả · ${roomCount + board.solos.length}',
              _LiveFilter.rooms: 'Phòng · $roomCount',
              _LiveFilter.solo: 'Chạy riêng · ${board.solos.length}',
            },
            onSelected: (filter) => setState(() => _filter = filter),
          ),
          if (running.isEmpty && upcoming.isEmpty) const _EmptyLive(),
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
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
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

/// Ba ô lọc liền nhau, ô đang chọn tô nền accent.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.labels,
    required this.onSelected,
  });

  final _LiveFilter selected;
  final Map<_LiveFilter, String> labels;
  final ValueChanged<_LiveFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final MapEntry(key: filter, value: label) in labels.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: filter == selected,
                child: Material(
                  color: filter == selected
                      ? palette.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(filter),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: filter == selected
                                ? palette.onAccent
                                : palette.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyLive extends StatelessWidget {
  const _EmptyLive();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 0),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: palette.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.sensors_rounded, size: 34, color: palette.accent),
          ),
          const SizedBox(height: 16),
          const Text(
            'Chưa ai đang live',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Mở phòng rủ cả nhóm, hoặc bật live ở tab Chạy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

/// Nhãn nhỏ bo tròn ở góc thẻ: quyền vào phòng hay trạng thái của mình.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.background, required this.foreground});

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Một phòng group. Đang chạy thì là thẻ nền đêm có hình tuyến; hẹn giờ thì
/// là thẻ sáng mở đầu bằng giờ và ngày hẹn.
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
    const onNight = Colors.white;
    final title = Text(
      room.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: upcoming ? null : onNight,
        fontSize: upcoming ? 15 : 18,
        fontWeight: FontWeight.w900,
      ),
    );
    final detailText = Text(
      detail,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: upcoming ? palette.textMuted : onNight.withValues(alpha: 0.72),
        fontSize: 13,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: upcoming ? palette.glassStart : palette.accentNight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: upcoming ? BorderSide(color: palette.border) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/rooms/${room.id}'),
          child: upcoming
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 58,
                        decoration: BoxDecoration(
                          color: palette.tint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            children: [
                              Text(
                                DateFormat('HH:mm').format(starts),
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.1,
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
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 2),
                            detailText,
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Pill(
                        badge,
                        background: palette.accent.withValues(alpha: 0.16),
                        foreground: palette.ink,
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                LiveDot(color: palette.warmMark, size: 7),
                                const SizedBox(width: 6),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: palette.warmMark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.3,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _Pill(
                                  badge,
                                  background: onNight.withValues(alpha: 0.14),
                                  foreground: onNight,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            title,
                            const SizedBox(height: 3),
                            detailText,
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: route != null
                            ? RunRoomRouteSketch(
                                route: route,
                                color: palette.warmMark,
                                padding: const EdgeInsets.all(4),
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: onNight.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.groups_rounded,
                                  color: onNight,
                                  size: 30,
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

/// Một người đang chạy riêng: quãng đã chạy nổi bên phải, dòng dưới nói có
/// nhận người chạy cùng không.
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
    final pace = session.averagePaceSecondsPerKm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.glassStart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/live/${session.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: palette.accent,
                      backgroundImage: hasAvatar
                          ? cachedAvatarImage(context, avatar, 46)
                          : null,
                      child: hasAvatar
                          ? null
                          : Text(
                              session.ownerName.isEmpty
                                  ? '?'
                                  : session.ownerName[0].toUpperCase(),
                              style: TextStyle(
                                color: palette.onAccent,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: palette.glassStart,
                          shape: BoxShape.circle,
                        ),
                        child: const LiveDot(
                          color: RunNowSemanticColors.danger,
                          size: 8,
                        ),
                      ),
                    ),
                  ],
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
                            formatDuration(liveElapsedSeconds(session, now)),
                            if (pace != null && pace.isFinite) formatPace(pace),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(width: 8),
                Text(
                  formatDistance(session.distanceMeters),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
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
