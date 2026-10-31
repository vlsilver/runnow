import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Kết nối thoại của một phòng chạy. Bản thật đi qua LiveKit tự host; test thay
/// bằng bản giả vì WebRTC không chạy trong flutter test.
abstract interface class VoiceLink {
  /// Vào phòng thoại và bật micro; trả số người khác đang ở trong phòng.
  /// [onPeers] báo khi có người vào hay ra, [onDropped] khi mất kết nối hẳn.
  Future<int> join(
    String url,
    String token, {
    required void Function(int peers) onPeers,
    required void Function() onDropped,
  });

  Future<void> leave();
}

class LiveKitVoiceLink implements VoiceLink {
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;

  @override
  Future<int> join(
    String url,
    String token, {
    required void Function(int peers) onPeers,
    required void Function() onDropped,
  }) async {
    final room = lk.Room();
    _room = room;
    _events = room.createListener()
      ..on<lk.ParticipantConnectedEvent>(
        (_) => onPeers(room.remoteParticipants.length),
      )
      ..on<lk.ParticipantDisconnectedEvent>(
        (_) => onPeers(room.remoteParticipants.length),
      )
      ..on<lk.RoomDisconnectedEvent>((_) => onDropped());
    await room.connect(url, token);
    final local = room.localParticipant;
    if (local == null) throw StateError('LiveKit chưa có localParticipant');
    await local.setMicrophoneEnabled(true);
    return room.remoteParticipants.length;
  }

  @override
  Future<void> leave() async {
    final room = _room;
    final events = _events;
    _room = null;
    _events = null;
    // Gỡ listener trước để disconnect của chính mình không báo thành rớt mạng.
    await events?.dispose();
    await room?.disconnect();
    await room?.dispose();
  }
}

final voiceLinkFactoryProvider = Provider<VoiceLink Function()>(
  (ref) => LiveKitVoiceLink.new,
);

enum RunRoomVoiceStatus { off, connecting, on }

@immutable
class RunRoomVoiceState {
  const RunRoomVoiceState(this.status, {this.peers = 0, this.error});

  final RunRoomVoiceStatus status;

  /// Số người khác đang ở trong phòng thoại.
  final int peers;

  /// Câu báo cho người dùng khi vào thoại hỏng hay rớt giữa chừng.
  final String? error;
}

final runRoomVoiceProvider = NotifierProvider.autoDispose
    .family<RunRoomVoice, RunRoomVoiceState, String>(RunRoomVoice.new);

/// Thoại của mình trong một phòng chạy. Chỉ [RunRoomVoiceButton] nghe provider
/// này, và thanh phòng chỉ hiện nút khi phòng còn mở và mình còn trong phòng,
/// nên phòng đóng, rời, bị mời ra hay xong buổi chạy đều làm provider dispose
/// và thoát thoại.
class RunRoomVoice extends Notifier<RunRoomVoiceState> {
  RunRoomVoice(this.roomId);

  final String roomId;
  VoiceLink? _link;

  /// Tăng mỗi lần vào hay thoát, để kết quả của lần vào cũ (đã bấm tắt khi
  /// đang kết nối) không ghi đè trạng thái mới.
  int _attempt = 0;

  @override
  RunRoomVoiceState build() {
    ref.onDispose(() {
      _attempt++;
      final link = _link;
      _link = null;
      if (link != null) unawaited(link.leave());
    });
    return const RunRoomVoiceState(RunRoomVoiceStatus.off);
  }

  Future<void> join() async {
    if (state.status != RunRoomVoiceStatus.off) return;
    final attempt = ++_attempt;
    state = const RunRoomVoiceState(RunRoomVoiceStatus.connecting);
    final link = ref.read(voiceLinkFactoryProvider)();
    _link = link;
    try {
      final ticket = await ref
          .read(runNowApiClientProvider)
          .runRoomVoice(roomId);
      if (attempt != _attempt) return;
      final peers = await link.join(
        ticket.url,
        ticket.token,
        onPeers: (peers) {
          if (attempt == _attempt) {
            state = RunRoomVoiceState(RunRoomVoiceStatus.on, peers: peers);
          }
        },
        onDropped: () {
          if (attempt != _attempt) return;
          _attempt++;
          _link = null;
          unawaited(link.leave());
          state = const RunRoomVoiceState(
            RunRoomVoiceStatus.off,
            error: 'Mất kết nối thoại.',
          );
        },
      );
      if (attempt != _attempt) {
        await link.leave();
        return;
      }
      state = RunRoomVoiceState(RunRoomVoiceStatus.on, peers: peers);
    } catch (error) {
      debugPrint('Vào thoại phòng $roomId lỗi: $error');
      await link.leave();
      if (attempt != _attempt) return;
      _link = null;
      state = RunRoomVoiceState(
        RunRoomVoiceStatus.off,
        error: error is RunNowApiException
            ? runRoomErrorText(error)
            : 'Chưa vào được thoại. Kiểm tra mạng và quyền micro rồi thử lại.',
      );
    }
  }

  Future<void> leave() async {
    if (state.status == RunRoomVoiceStatus.off) return;
    _attempt++;
    final link = _link;
    _link = null;
    state = const RunRoomVoiceState(RunRoomVoiceStatus.off);
    await link?.leave();
  }
}

/// Nút vào hay thoát thoại trên thanh phòng. Mặc định tắt: chỉ bật micro khi
/// người dùng tự bấm.
class RunRoomVoiceButton extends ConsumerWidget {
  const RunRoomVoiceButton({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = runRoomVoiceProvider(roomId);
    ref.listen(provider.select((s) => s.error), (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(error)),
        );
    });
    final voice = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return switch (voice.status) {
      RunRoomVoiceStatus.off => TextButton.icon(
        onPressed: controller.join,
        icon: const Icon(Icons.mic_none_rounded, size: 18),
        label: const Text('Nói chuyện'),
      ),
      RunRoomVoiceStatus.connecting => TextButton.icon(
        onPressed: controller.leave,
        icon: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('Đang vào thoại…'),
      ),
      RunRoomVoiceStatus.on => FilledButton.tonalIcon(
        onPressed: controller.leave,
        icon: const Icon(Icons.mic_rounded, size: 18),
        label: Text(
          voice.peers == 0
              ? 'Đang nói · chưa ai nghe'
              : 'Đang nói · ${voice.peers} người nghe',
        ),
      ),
    };
  }
}
