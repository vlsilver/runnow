import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/agents/agent_chat_controller.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Quá chừng này mà bot chưa trả lời thì thôi hiện "đang trả lời": task trả
/// lời đã hết lượt chạy lại, chủ nhắn tin mới thì bot trả lời gộp.
const agentReplyTimeout = Duration(minutes: 2);

/// Tên người gửi một tin trong phòng bot, dùng ở phòng và ở tab MyBot.
String agentRoomSenderLabel(AgentRoomMessage m, String? myUid) {
  if (!m.fromAgent) return m.name;
  return m.uid == myUid
      ? '${m.name} · bot của bạn'
      : '${m.name} · bot của ${m.owner ?? 'thành viên'}';
}

/// Chat riêng giữa chủ và bot của mình.
class AgentDMScreen extends ConsumerStatefulWidget {
  const AgentDMScreen({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  @override
  ConsumerState<AgentDMScreen> createState() => _AgentDMScreenState();
}

class _AgentDMScreenState extends _AgentChatState<AgentDMScreen, AgentMessage> {
  @override
  AgentChatController<AgentMessage> createController(RunNowApiClient api) =>
      AgentChatController(
        load: api.getAgentDM,
        post: api.postAgentDM,
        label: 'chat riêng',
      );

  String get _botName => ref.watch(agentMeProvider).value?.agent?.name ?? 'Bot';

  @override
  String get title => _botName;

  @override
  String get hint => 'Kể cho bot nghe…';

  @override
  Widget empty(BuildContext context) => const _EmptyHint(
    text:
        'Kể cho bot nghe về bạn: bạn chạy thế nào, thích gì, nói chuyện ra '
        'sao, kiến thức bạn muốn bot biết. Bot tự ghi điều đáng nhớ vào bộ '
        'nhớ, bạn xem và sửa ở màn Bot của tôi.',
  );

  @override
  _Bubble bubble(AgentMessage m, String? myUid) => _Bubble(
    mine: !m.fromAgent,
    label: m.fromAgent ? _botName : null,
    bot: m.fromAgent,
    text: m.text,
    at: m.at,
  );

  @override
  bool typing(List<AgentMessage> messages) {
    if (!controller.waiting) return false;
    final lastMine = messages.where((m) => !m.fromAgent).firstOrNull?.at;
    return lastMine != null &&
        widget.now().difference(lastMine) < agentReplyTimeout;
  }
}

/// Phòng chung: người và bot của các thành viên cùng chat.
class AgentRoomScreen extends ConsumerStatefulWidget {
  const AgentRoomScreen({super.key});

  @override
  ConsumerState<AgentRoomScreen> createState() => _AgentRoomScreenState();
}

class _AgentRoomScreenState
    extends _AgentChatState<AgentRoomScreen, AgentRoomMessage> {
  @override
  AgentChatController<AgentRoomMessage> createController(RunNowApiClient api) =>
      AgentChatController(
        load: api.getAgentRoom,
        post: api.postAgentRoom,
        label: 'phòng bot',
      );

  @override
  String get title => 'Phòng bot';

  @override
  String get hint => 'Nhắn vào phòng…';

  @override
  List<Widget> actions(BuildContext context) => [
    IconButton(
      tooltip: 'Thành viên',
      icon: const Icon(Icons.groups_outlined),
      onPressed: () => _showMembers(context),
    ),
  ];

  @override
  Widget empty(BuildContext context) => const _EmptyHint(
    text:
        'Chưa ai nói gì. Nhắn một câu, bot của các thành viên sẽ vào nói '
        'chuyện. Mỗi lần bạn nhắn, các bot nói tối đa 6 tin rồi chờ người.',
  );

  @override
  _Bubble bubble(AgentRoomMessage m, String? myUid) {
    final mine = !m.fromAgent && m.uid == myUid;
    return _Bubble(
      mine: mine,
      label: mine ? null : agentRoomSenderLabel(m, myUid),
      bot: m.fromAgent,
      text: m.text,
      at: m.at,
    );
  }

  void _showMembers(BuildContext context) {
    final members = controller.members;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Bot nói dựa trên tính cách và bộ nhớ chủ dạy. Mọi thành viên '
                'đều đọc được tin trong phòng.',
              ),
            ),
            for (final m in members)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(m.name),
                subtitle: Text(
                  m.botName == null ? 'Chưa tạo bot' : 'Bot: ${m.botName}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Phần chung của hai màn chat: vòng đời poll, ô nhập, danh sách tin.
abstract class _AgentChatState<
  W extends ConsumerStatefulWidget,
  M extends AgentSeqMessage
>
    extends ConsumerState<W>
    with WidgetsBindingObserver {
  late final AgentChatController<M> controller;
  final _input = TextEditingController();
  bool _sending = false;

  AgentChatController<M> createController(RunNowApiClient api);
  String get title;
  String get hint;
  List<Widget> actions(BuildContext context) => const [];
  Widget empty(BuildContext context);
  _Bubble bubble(M message, String? myUid);
  bool typing(List<M> messages) => false;

  @override
  void initState() {
    super.initState();
    controller = createController(ref.read(runNowApiClientProvider));
    WidgetsBinding.instance.addObserver(this);
    controller.setActive(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        controller.setActive(true);
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        controller.setActive(false);
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await controller.send(text);
      if (mounted && _input.text.trim() == text) _input.clear();
    } catch (error) {
      _showError(error, 'Không gửi được, thử lại sau.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadOlder() async {
    try {
      await controller.loadOlder();
    } catch (error) {
      _showError(error, 'Không tải được tin cũ, thử lại sau.');
    }
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    final message = error is RunNowApiException ? error.message : fallback;
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
      listenable: controller,
      builder: (context, _) {
        final messages = controller.messages;
        final showTyping = typing(messages);
        final extra = (controller.hasOlder ? 1 : 0) + (showTyping ? 1 : 0);
        final Widget body;
        if (!controller.loaded) {
          body = controller.error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: TextButton(
                    onPressed: controller.refresh,
                    child: Text(_errorText(controller.error!)),
                  ),
                );
        } else if (messages.isEmpty) {
          body = empty(context);
        } else {
          body = ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: messages.length + extra,
            itemBuilder: (context, i) {
              if (showTyping) {
                if (i == 0) return const _Typing();
                i--;
              }
              if (i == messages.length) {
                return Center(
                  child: TextButton(
                    onPressed: controller.loadingOlder ? null : _loadOlder,
                    child: const Text('Tải tin cũ hơn'),
                  ),
                );
              }
              return bubble(messages[i], myUid);
            },
          );
        }
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(title),
            backgroundColor: palette.background,
            elevation: 0,
            actions: actions(context),
          ),
          body: Column(
            children: [
              if (controller.loaded && controller.error != null)
                const _Banner(text: 'Chưa tải được tin mới, đang thử lại.'),
              Expanded(child: body),
              if (controller.loaded)
                _Composer(
                  controller: _input,
                  hint: hint,
                  sending: _sending,
                  onSend: _send,
                ),
            ],
          ),
        );
      },
    );
  }

  String _errorText(Object error) => error is RunNowApiException
      ? '${error.message} Chạm để thử lại.'
      : 'Không tải được chat. Chạm để thử lại.';
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mine,
    required this.label,
    required this.bot,
    required this.text,
    required this.at,
  });

  final bool mine;

  /// Tên hiện trên tin; null thì không hiện (tin của mình).
  final String? label;
  final bool bot;
  final String text;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final time = at == null ? '' : DateFormat('HH:mm').format(at!.toLocal());
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
            color: mine ? palette.accent.withValues(alpha: 0.38) : palette.tint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bot) ...[
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 14,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        label!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              SelectableText(text),
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

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        'Bot đang trả lời…',
        style: TextStyle(
          color: context.runNowPalette.textMuted,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.runNowPalette.textMuted),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
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
                decoration: InputDecoration(hintText: hint, counterText: ''),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: palette.tint,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: palette.textMuted),
      ),
    );
  }
}
