import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/rooms/run_room_map.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_route_sketch.dart';
import 'package:myrun/src/theme.dart';

/// Emoji cổ vũ nhanh, bấm một chạm khi đang chạy.
const runRoomCheers = ['👏', '🔥', '💪', '🐢', '🏁'];

/// Một phòng chạy: ai đang ở đâu, chạy được bao nhiêu, cổ vũ nhau. Người
/// chưa vào phòng chỉ thấy tên phòng, chủ phòng và số người.
class RunRoomScreen extends ConsumerWidget {
  const RunRoomScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(runRoomProvider(roomId));
    final me = ref.watch(myRunRoomMemberProvider(roomId)).value;
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final data = room.value;
    final joined = me?.state == RunRoomMemberState.joined;
    final host = data != null && data.hostUid == uid;
    final open = data != null && data.isOpen(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(data?.title ?? 'Phòng chạy'),
        actions: [
          if (data != null && open)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Mời bạn',
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => shareRunRoom(context, data),
              ),
            ),
          if (data != null && (host && !data.ended || !host && joined))
            PopupMenuButton<String>(
              onSelected: (value) =>
                  value == 'end' ? _end(context, ref) : _leave(context, ref),
              itemBuilder: (_) => [
                if (host)
                  const PopupMenuItem(
                    value: 'end',
                    child: Text('Kết thúc phòng'),
                  )
                else
                  const PopupMenuItem(value: 'leave', child: Text('Rời phòng')),
              ],
            ),
        ],
      ),
      body: room.when(
        data: (data) {
          if (data == null) {
            return const _Center('Không tìm thấy phòng này.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _RoomHeader(room: data),
              const SizedBox(height: 14),
              if (joined)
                _JoinedBody(room: data, myUid: uid, host: host)
              else ...[
                // Người ngoài phòng không đọc được buổi live của phòng, nên
                // chỉ thấy hình tuyến chứ không có map người chạy.
                if (data.route case final route?) ...[
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: context.runNowPalette.tint,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: RunRoomRouteSketch(
                      route: route,
                      color: context.runNowPalette.accent,
                      dashed: true,
                      padding: const EdgeInsets.all(24),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _JoinPanel(room: data, me: me),
              ],
            ],
          );
        },
        error: (error, _) {
          debugPrint('run room $roomId: $error');
          return const _Center('Không tải được phòng. Kéo xuống để thử lại.');
        },
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final ok = await runRoomAction(
      context,
      () => ref.read(runNowApiClientProvider).leaveRunRoom(roomId),
    );
    if (ok && context.mounted) context.pop();
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kết thúc phòng?'),
        content: const Text(
          'Mọi người sẽ không vào thêm và không gửi cổ vũ được nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runRoomAction(
      context,
      () => ref.read(runNowApiClientProvider).endRunRoom(roomId),
    );
  }
}

class _Center extends StatelessWidget {
  const _Center(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// "Hẹn 05:30, 02/11" khi phòng hẹn trước, "Đang mở" khi chạy ngay, "Đã
/// đóng" khi kết thúc hay quá giờ.
String runRoomWhen(RunRoom room, DateTime now) {
  if (!room.isOpen(now)) return 'Đã đóng';
  final starts = room.startsAt;
  if (starts != null && starts.isAfter(now)) {
    return 'Hẹn ${DateFormat('HH:mm, dd/MM').format(starts.toLocal())}';
  }
  return 'Đang mở';
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});

  final RunRoom room;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            room.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'Chủ phòng ${room.hostName}',
            style: TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(
                icon: Icons.groups_rounded,
                label: '${room.runnerCount}/${room.maxRunners} người',
              ),
              _Chip(
                icon: switch (room.privacy) {
                  RunRoomPrivacy.public => Icons.public_rounded,
                  RunRoomPrivacy.private => Icons.how_to_reg_rounded,
                  RunRoomPrivacy.password => Icons.lock_rounded,
                },
                label: room.privacy.label,
              ),
              _Chip(
                icon: Icons.schedule_rounded,
                label: runRoomWhen(room, DateTime.now()),
              ),
              if (room.route case final route?)
                _Chip(
                  icon: Icons.route_rounded,
                  label: 'Tuyến ${runRoomRouteKm(route)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: onSurface.withValues(alpha: 0.7)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _JoinPanel extends ConsumerStatefulWidget {
  const _JoinPanel({required this.room, required this.me});

  final RunRoom room;
  final RunRoomMember? me;

  @override
  ConsumerState<_JoinPanel> createState() => _JoinPanelState();
}

class _JoinPanelState extends ConsumerState<_JoinPanel> {
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
    final room = widget.room;
    final state = widget.me?.state;
    if (!room.isOpen(DateTime.now())) {
      return const _Note('Phòng đã đóng.');
    }
    switch (state) {
      case RunRoomMemberState.requested:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Note('Đã xin vào, đang chờ chủ phòng duyệt.'),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => runRoomAction(
                        context,
                        () => ref
                            .read(runNowApiClientProvider)
                            .leaveRunRoom(room.id),
                      ),
                    ),
              child: const Text('Huỷ xin vào'),
            ),
          ],
        );
      case RunRoomMemberState.kicked:
        return const _Note('Chủ phòng đã mời bạn ra khỏi phòng này.');
      case RunRoomMemberState.denied:
        return const _Note('Chủ phòng đã từ chối cho bạn vào phòng này.');
      case RunRoomMemberState.joined:
      case RunRoomMemberState.left:
      case null:
        break;
    }
    if (room.full) return const _Note('Phòng đã đủ người.');
    final label = switch (room.privacy) {
      RunRoomPrivacy.public => 'Vào phòng',
      RunRoomPrivacy.private => 'Xin vào phòng',
      RunRoomPrivacy.password => 'Nhập mật khẩu để vào',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Note(
          'Vào phòng để thấy mọi người trên map, xem số liệu và cổ vũ nhau. '
          'Khi chạy cùng phòng, người trong phòng thấy vị trí của bạn.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() => joinRunRoom(context, ref, room)),
          icon: const Icon(Icons.login_rounded),
          label: Text(label),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      fontWeight: FontWeight.w600,
    ),
  );
}

class _JoinedBody extends ConsumerWidget {
  const _JoinedBody({
    required this.room,
    required this.myUid,
    required this.host,
  });

  final RunRoom room;
  final String? myUid;
  final bool host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(runRoomMembersProvider(room.id)).value ?? [];
    final joined =
        [
          for (final m in members)
            if (m.state == RunRoomMemberState.joined) m,
        ]..sort(
          (a, b) =>
              a.host == b.host ? a.name.compareTo(b.name) : (a.host ? -1 : 1),
        );
    final joinedUids = {for (final m in joined) m.uid};
    // Chỉ vẽ người còn trong phòng: người bị mời ra có thể vẫn chạy với buổi
    // mang roomId cũ.
    final sessions = <LiveTrackingSession>[
      for (final s
          in ref.watch(runRoomLiveProvider(room.id)).value ??
              const <LiveTrackingSession>[])
        if (joinedUids.contains(s.ownerUid)) s,
    ];
    final requests = [
      for (final m in members)
        if (m.state == RunRoomMemberState.requested) m,
    ];
    final open = room.isOpen(DateTime.now());
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 280,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RunRoomMap(
                    sessions: sessions,
                    myUid: myUid,
                    plannedRoute: switch (room.route) {
                      final route? => runRoomRouteLatLngs(route),
                      null => const [],
                    },
                  ),
                ),
                if (sessions.isEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.glassStart,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        room.route == null
                            ? 'Chưa ai bắt đầu chạy trong phòng.'
                            : 'Nét đứt là tuyến chủ phòng vẽ. Chưa ai bắt đầu chạy.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (open && !kIsWeb) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push('/tracking/room/${room.id}'),
            icon: const Icon(Icons.directions_run_rounded),
            label: const Text('Chạy cùng phòng'),
          ),
        ],
        if (host && requests.isNotEmpty) ...[
          const _SectionTitle('Đang xin vào'),
          for (final m in requests)
            RunRoomRequestTile(roomId: room.id, member: m),
        ],
        _SectionTitle('Trong phòng (${joined.length})'),
        for (final m in joined)
          if (sessions.indexWhere((s) => s.ownerUid == m.uid) case final index)
            _RunnerTile(
              room: room,
              member: m,
              // Cùng màu với đường của người đó trên map; chưa chạy thì tile
              // tự vẽ màu xám nên index -1 không dùng tới.
              session: index < 0 ? null : sessions[index],
              color: runRoomRunnerColor(
                context,
                index < 0 ? 0 : index,
                me: m.uid == myUid,
              ),
              canKick: host && open && m.uid != myUid,
            ),
        const _SectionTitle('Cổ vũ'),
        if (open && myUid != null)
          RunRoomCheerBar(roomId: room.id, uid: myUid!),
        _MessageList(roomId: room.id, members: members),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
    ),
  );
}

/// Một người xin vào, chủ phòng duyệt hay từ chối. Màn chạy dùng lại.
class RunRoomRequestTile extends ConsumerWidget {
  const RunRoomRequestTile({
    required this.roomId,
    required this.member,
    super.key,
  });

  final String roomId;
  final RunRoomMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(runNowApiClientProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(
        member.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => runRoomAction(
              context,
              () => api.moderateRunRoom(roomId, member.uid, 'deny'),
            ),
            child: const Text('Từ chối'),
          ),
          FilledButton(
            onPressed: () => runRoomAction(
              context,
              () => api.moderateRunRoom(roomId, member.uid, 'approve'),
            ),
            child: const Text('Cho vào'),
          ),
        ],
      ),
    );
  }
}

class _RunnerTile extends ConsumerWidget {
  const _RunnerTile({
    required this.room,
    required this.member,
    required this.session,
    required this.color,
    required this.canKick,
  });

  final RunRoom room;
  final RunRoomMember member;
  final LiveTrackingSession? session;
  final Color color;
  final bool canKick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = session;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: live == null ? muted.withValues(alpha: 0.3) : color,
        ),
      ),
      minLeadingWidth: 12,
      title: Text(
        member.host ? '${member.name} · chủ phòng' : member.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        live == null
            ? 'Chưa chạy'
            : '${formatDistance(live.distanceMeters)} · '
                  '${formatPace(live.averagePaceSecondsPerKm)} · '
                  '${formatDuration(live.movingTimeSeconds)}'
                  '${live.status == LiveTrackingStatus.paused ? ' · tạm dừng' : ''}',
      ),
      trailing: canKick
          ? IconButton(
              tooltip: 'Mời ra khỏi phòng',
              icon: const Icon(Icons.person_remove_rounded),
              onPressed: () => runRoomAction(
                context,
                () => ref
                    .read(runNowApiClientProvider)
                    .moderateRunRoom(room.id, member.uid, 'kick'),
              ),
            )
          : null,
    );
  }
}

/// Hàng emoji cổ vũ và ô gõ câu ngắn. Màn chạy dùng lại hàng emoji.
class RunRoomCheerBar extends ConsumerStatefulWidget {
  const RunRoomCheerBar({
    required this.roomId,
    required this.uid,
    this.emojiOnly = false,
    super.key,
  });

  final String roomId;
  final String uid;
  final bool emojiOnly;

  @override
  ConsumerState<RunRoomCheerBar> createState() => _RunRoomCheerBarState();
}

class _RunRoomCheerBarState extends ConsumerState<RunRoomCheerBar> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String text, {required bool emoji}) async {
    final value = text.trim();
    if (value.isEmpty) return;
    try {
      await ref
          .read(runRoomRepositoryProvider)
          .sendMessage(
            widget.roomId,
            uid: widget.uid,
            text: value,
            emoji: emoji,
          );
      if (!emoji) _text.clear();
    } catch (error) {
      debugPrint('run room cheer: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không gửi được cổ vũ, thử lại nhé.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final emojis = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final e in runRoomCheers)
          IconButton.filledTonal(
            onPressed: () => _send(e, emoji: true),
            icon: Text(e, style: const TextStyle(fontSize: 22)),
          ),
      ],
    );
    if (widget.emojiOnly) return emojis;
    return Column(
      children: [
        emojis,
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          maxLength: 120,
          textInputAction: TextInputAction.send,
          onSubmitted: (value) => _send(value, emoji: false),
          decoration: InputDecoration(
            hintText: 'Nhắn một câu cổ vũ',
            counterText: '',
            suffixIcon: IconButton(
              icon: const Icon(Icons.send_rounded),
              onPressed: () => _send(_text.text, emoji: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.roomId, required this.members});

  final String roomId;
  final List<RunRoomMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(runRoomMessagesProvider(roomId)).value ?? [];
    if (messages.isEmpty) return const SizedBox.shrink();
    final names = {for (final m in members) m.uid: m.name};
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    names[m.uid] ?? 'Thành viên',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      m.text,
                      style: TextStyle(fontSize: m.emoji ? 20 : 14),
                    ),
                  ),
                  if (m.at case final at?)
                    Text(
                      DateFormat('HH:mm').format(at.toLocal()),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
