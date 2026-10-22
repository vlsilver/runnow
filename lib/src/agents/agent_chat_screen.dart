import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/agents/agent_chat_controller.dart';
import 'package:myrun/src/agents/agent_consent_screen.dart';
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

  /// Seq tin mới nhất của bot đã thấy; null là chưa tải xong lần đầu.
  int? _lastBotSeq;

  @override
  void initState() {
    super.initState();
    controller.addListener(_rereadTodayOnReply);
  }

  @override
  void dispose() {
    controller.removeListener(_rereadTodayOnReply);
    super.dispose();
  }

  /// Backend đếm lượt khi bot trả lời, nên có tin mới của bot thì đọc lại hồ
  /// sơ để "Còn N tin" và trạng thái hết lượt theo kịp. Tin cũ tải thêm không
  /// đổi tin mới nhất nên không đọc lại.
  void _rereadTodayOnReply() {
    if (!controller.loaded) return;
    final seq =
        controller.messages.where((m) => m.fromAgent).firstOrNull?.seq ?? 0;
    final last = _lastBotSeq;
    _lastBotSeq = seq;
    if (last != null && seq > last) ref.invalidate(agentMeProvider);
  }

  String get _botName => ref.watch(agentMeProvider).value?.agent?.name ?? 'Bot';

  AgentToday? get _today => ref.watch(agentMeProvider).value?.today;

  @override
  String get title => _botName;

  @override
  Widget titleWidget(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_botName),
      Text(
        'Chat riêng · chỉ bạn thấy',
        style: TextStyle(
          color: context.runNowPalette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  @override
  List<Widget> actions(BuildContext context) {
    final today = _today;
    if (today == null || today.resting != null) return const [];
    final left = today.dmMax - today.dmUsed;
    return [_QuotaChip(text: 'Còn ${left < 0 ? 0 : left} tin')];
  }

  @override
  Widget? notice(BuildContext context) => switch (_today) {
    AgentToday(resting: AgentResting.dmLimit, :final dmMax) => _RestNotice(
      icon: Icons.schedule_rounded,
      title: 'Hết $dmMax tin hôm nay',
      detail: 'Chat lại được lúc 0h. Bot vẫn nói trong phòng bot.',
    ),
    AgentToday(resting: AgentResting.budget) => _RestNotice(
      icon: Icons.bedtime_outlined,
      title: '$_botName đang nghỉ tới 0h',
      detail: 'MyBot chạm trần chi phí hôm nay.',
    ),
    _ => null,
  };

  /// Đang nghỉ thì bot chỉ trả câu nghỉ, nên khoá ô nhập cho khỏi tốn lượt.
  @override
  bool get canSend => _today?.resting == null;

  @override
  String get hint => 'Kể cho bot nghe…';

  @override
  Widget empty(BuildContext context) => const _EmptyHint(
    text:
        'Kể cho bot nghe về bạn. Bot tự ghi điều đáng nhớ, bạn xem và sửa ở '
        'tab MyBot.',
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
      // Tin của bot mình cũng là của mình (uid là chủ bot): backend không cho
      // báo cáo, nên không mở menu.
      onLongPress: m.uid == myUid ? null : () => _onLongPress(m),
    );
  }

  /// Nhấn giữ tin của người khác: sao chép, báo cáo, hoặc báo cáo và chặn.
  /// Chặn từ tin của bot là chặn chủ bot, nên ẩn cả người lẫn bot của họ.
  Future<void> _onLongPress(AgentRoomMessage m) async {
    final who = m.fromAgent ? (m.owner ?? 'thành viên') : m.name;
    final action = await showModalBottomSheet<_RoomAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Sao chép'),
              onTap: () => Navigator.pop(context, _RoomAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Báo cáo tin này'),
              onTap: () => Navigator.pop(context, _RoomAction.report),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text('Báo cáo và chặn $who'),
              subtitle: Text(
                'Ẩn tin của $who và bot của họ. $who không được báo.',
              ),
              onTap: () => Navigator.pop(context, _RoomAction.block),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == _RoomAction.copy) {
      await Clipboard.setData(ClipboardData(text: m.text));
      return;
    }
    final block = action == _RoomAction.block;
    try {
      await ref
          .read(runNowApiClientProvider)
          .reportAgentRoomMessage(m.seq, block: block);
      if (block) {
        // Chờ lượt poll đang chạy (có thể mang tin đọc trước lúc chặn) rồi mới
        // ẩn, để không còn tin nào của người vừa chặn lọt lại trên màn.
        await controller.refresh();
        controller.update((x) => x.uid == m.uid ? x.asHidden() : x);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(block ? 'Đã báo cáo và chặn' : 'Đã báo cáo')),
      );
    } catch (error) {
      _showError(error, 'Không báo cáo được, thử lại sau.');
    }
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

enum _RoomAction { copy, report, block }

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

  /// Tiêu đề trên thanh trên cùng; mặc định là [title].
  Widget titleWidget(BuildContext context) => Text(title);

  /// Thẻ báo ngay trên ô nhập, vd. bot hết lượt hôm nay.
  Widget? notice(BuildContext context) => null;

  /// false thì khoá ô nhập, vẫn đọc được tin cũ.
  bool get canSend => true;
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
      await withAgentConsent(context, ref, () => controller.send(text));
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
        } else if (messages.isEmpty && !controller.hasOlder) {
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
            title: titleWidget(context),
            backgroundColor: palette.background,
            elevation: 0,
            actions: actions(context),
          ),
          body: Column(
            children: [
              if (controller.loaded && controller.error != null)
                const _Banner(text: 'Chưa tải được tin mới, đang thử lại.'),
              Expanded(child: body),
              if (controller.loaded) ...[
                ?notice(context),
                _Composer(
                  controller: _input,
                  hint: hint,
                  enabled: canSend,
                  sending: _sending,
                  onSend: _send,
                ),
              ],
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
    this.onLongPress,
  });

  final bool mine;

  /// Tên hiện trên tin; null thì không hiện (tin của mình).
  final String? label;
  final bool bot;
  final String text;
  final DateTime? at;

  /// Có thì nhấn giữ để mở menu báo cáo, và chữ không chọn được nữa (sao chép
  /// nằm trong menu).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final time = at == null ? '' : DateFormat('HH:mm').format(at!.toLocal());
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: mine
                  ? palette.accent.withValues(alpha: 0.38)
                  : palette.tint,
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
                if (onLongPress == null) SelectableText(text) else Text(text),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
              ],
            ),
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
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
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
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: enabled ? hint : 'Hết lượt hôm nay',
                  counterText: '',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Gửi',
              onPressed: sending || !enabled ? null : onSend,
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

class _QuotaChip extends StatelessWidget {
  const _QuotaChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: palette.accentDeep,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Thẻ báo bot đang nghỉ, nằm ngay trên ô nhập đã khoá.
class _RestNotice extends StatelessWidget {
  const _RestNotice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: palette.accentDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
