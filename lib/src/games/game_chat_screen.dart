import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_chat_controller.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Chat kín của một phe trong ván Ma Sói. Ai vào được, ai gửi được là do
/// backend quyết; màn này chỉ vẽ theo `canSend`.
class GameChatScreen extends ConsumerStatefulWidget {
  const GameChatScreen({
    super.key,
    required this.gameId,
    required this.chatKey,
  });

  final String gameId;
  final String chatKey;

  @override
  ConsumerState<GameChatScreen> createState() => _GameChatScreenState();
}

class _GameChatScreenState extends ConsumerState<GameChatScreen>
    with WidgetsBindingObserver {
  late final GameChatController _controller;
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = GameChatController(
      api: ref.read(runNowApiClientProvider),
      gameId: widget.gameId,
      chatKey: widget.chatKey,
    );
    WidgetsBinding.instance.addObserver(this);
    _controller.setActive(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.setActive(true);
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _controller.setActive(false);
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _controller.send(text);
      _input.clear();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadOlder() async {
    try {
      await _controller.loadOlder();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is RunNowApiException
        ? error.message
        : 'Không gửi được, thử lại sau.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final myUid = ref.watch(
      firebaseUserProvider.select((user) => user.value?.uid),
    );
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final messages = _controller.messages;
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(_controller.label ?? 'Chat'),
            backgroundColor: palette.background,
            elevation: 0,
          ),
          body: Column(
            children: [
              if (_controller.error != null)
                _Banner(
                  text: _controller.loaded
                      ? 'Chưa tải được tin mới, đang thử lại.'
                      : _errorText(_controller.error!),
                ),
              Expanded(
                child: !_controller.loaded && _controller.error == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        // Tin mới nằm dưới cùng, cạnh ô nhập.
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount:
                            messages.length + (_controller.hasOlder ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == messages.length) {
                            return Center(
                              child: TextButton(
                                onPressed: _controller.loadingOlder
                                    ? null
                                    : _loadOlder,
                                child: const Text('Tải tin cũ hơn'),
                              ),
                            );
                          }
                          final m = messages[i];
                          return _MessageRow(
                            message: m,
                            mine: !m.system && m.uid == myUid,
                          );
                        },
                      ),
              ),
              if (_controller.loaded)
                _controller.canSend
                    ? _Composer(
                        controller: _input,
                        sending: _sending,
                        onSend: _send,
                      )
                    : const _Banner(text: 'Bạn chỉ xem được chat này.'),
            ],
          ),
        );
      },
    );
  }

  String _errorText(Object error) => error is RunNowApiException
      ? error.message
      : 'Không tải được chat. Kéo lại hoặc mở lại sau.';
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.mine});

  final GameChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final at = message.at;
    final time = at == null ? '' : DateFormat('HH:mm').format(at.toLocal());
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            time.isEmpty ? message.text : '${message.text} · $time',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // 0.18 thì ở theme tối gần trùng màu tint, không nhận ra tin của mình.
            color: mine ? palette.accent.withValues(alpha: 0.38) : palette.tint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  message.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
              SelectableText(message.text),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Nhắn cho phe…',
                  counterText: '',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Gửi',
              onPressed: sending ? null : onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: palette.tint,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted),
        ),
      ),
    );
  }
}
