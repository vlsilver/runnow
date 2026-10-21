import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Trang danh sách đầy đủ, mở từ "Xem tất cả" của tab MyBot.
enum AgentListView { memories, learned }

/// Tab tự học và bộ nhớ chỉ hiện vài mục đầu cho gọn, phần còn lại ở trang
/// danh sách.
const _previewCount = 3;

/// Telegram báo backend tạo bot xong rồi backend mới nối bot với chủ (một task
/// chạy vài giây), nên quay về app có thể còn sớm: đọc lại thêm một lần nữa.
const _telegramRecheckAfter = Duration(seconds: 5);

/// Tab MyBot: thẻ bot của mình, tin mới trong phòng bot, bộ nhớ và những điều
/// bot tự học. Có [list] thì là trang đầy đủ của một mục. Tạo và sửa tên, tính
/// cách nằm ở màn `/agent/setup`.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({this.list, this.openUrl, super.key});

  final AgentListView? list;

  /// Thay cho launchUrl trong test.
  final UrlOpener? openUrl;

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

  /// Liên kết tài khoản 3i với Telegram, dùng lại luồng của Cài đặt. Backend
  /// chỉ nối được bot khi chủ đã liên kết, nên phải biết trước khi mở Telegram.
  late final TelegramLinkController _telegramLink;
  bool _telegramBusy = false;
  Timer? _telegramRecheck;

  @override
  void initState() {
    super.initState();
    _telegramLink = TelegramLinkController(
      api: ref.read(runNowApiClientProvider),
      openUrl: widget.openUrl,
    );
    if (widget.list != null) return;
    WidgetsBinding.instance.addObserver(this);
    // Chỉ hỏi trạng thái liên kết khi mục Telegram cần, để backend cũ và cờ
    // tắt không tốn thêm request nào.
    ref.listenManual(agentMeProvider, (_, next) {
      final telegram = next.value?.telegram;
      if (telegram != null &&
          !telegram.linked &&
          _telegramLink.status == null) {
        unawaited(_telegramLink.load());
      }
    }, fireImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final telegram = ref.read(agentMeProvider).value?.telegram;
    if (telegram == null || telegram.running) return;
    // Bấm Start bên Telegram rồi quay lại.
    if (!telegram.linked) _telegramLink.onResume();
    // Vừa tạo bot bên Telegram: đọc lại ngay, rồi một lần nữa sau ít giây vì
    // backend nối bot chậm hơn. Không poll tiếp; lần quay lại sau lại đọc.
    ref.invalidate(agentMeProvider);
    _telegramRecheck?.cancel();
    _telegramRecheck = Timer(
      _telegramRecheckAfter,
      () => ref.invalidate(agentMeProvider),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telegramRecheck?.cancel();
    _telegramLink.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    final open =
        widget.openUrl ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    if (uri == null || !await open(uri)) _toast('Không mở được Telegram.');
  }

  /// Chưa liên kết Telegram thì chạy luồng liên kết trước; liên kết xong thì
  /// bấm lại để mở màn tạo bot. Đọc lại trạng thái lúc bấm, vì có thể vừa
  /// liên kết ở Cài đặt.
  Future<void> _putOnTelegram(AgentTelegram telegram) async {
    if (_telegramBusy) return;
    setState(() => _telegramBusy = true);
    try {
      if (_telegramLink.status?.linked != true) await _telegramLink.load();
      final status = _telegramLink.status;
      if (status == null) {
        _toast('Chưa đọc được trạng thái Telegram, thử lại sau.');
      } else if (status.linked) {
        await _openExternal(telegram.createUrl);
      } else {
        await _telegramLink.link();
      }
    } catch (error) {
      _toast(
        error is RunNowApiException
            ? error.message
            : error is StateError
            ? error.message
            : 'Không kết nối được, thử lại sau.',
      );
    } finally {
      if (mounted) setState(() => _telegramBusy = false);
    }
  }

  /// Chạy một thao tác ghi, báo lỗi nếu có, rồi đọc lại hồ sơ.
  Future<void> _run(Future<void> Function(RunNowApiClient api) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(runNowApiClientProvider));
      ref.invalidate(agentMeProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is RunNowApiException
                  ? error.message
                  : 'Không lưu được, thử lại sau.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mở màn con; quay về thì đọc lại hồ sơ, vì bot có thể vừa nhớ hay quên
  /// gì, và tin mới trong phòng.
  Future<void> _open(String path) async {
    await context.push(path);
    if (!mounted) return;
    ref.invalidate(agentMeProvider);
    ref.invalidate(agentRoomPreviewProvider);
  }

  Future<void> _editMemory(AgentMemory? memory) async {
    final result = await showDialog<_MemoryEdit>(
      context: context,
      builder: (context) => _MemoryDialog(initial: memory?.text ?? ''),
    );
    if (result == null) return;
    if (result.delete) {
      if (memory != null) {
        await _run((api) => api.deleteAgentMemory(memory.id));
      }
      return;
    }
    final text = result.text.trim();
    if (text.isEmpty) return;
    await _run(
      (api) => memory == null
          ? api.addAgentMemory(text)
          : api.updateAgentMemory(memory.id, text),
    );
  }

  Future<void> _deleteMemory(AgentMemory memory) async {
    final yes = await _confirm(
      title: 'Xoá mục nhớ?',
      content: memory.text,
      action: 'Xoá',
    );
    if (yes) await _run((api) => api.deleteAgentMemory(memory.id));
  }

  Future<void> _forgetLearned(AgentLearnedFact fact) async {
    final yes = await _confirm(
      title: 'Cho bot quên điều này?',
      content: fact.text,
      action: 'Quên',
    );
    if (yes) await _run((api) => api.deleteAgentLearned(fact.id));
  }

  Future<void> _setLearning(bool learn, int learnedCount) async {
    // Tắt tự học thì backend xoá luôn điều đã học, nên hỏi lại trước.
    if (!learn) {
      final yes = await _confirm(
        title: 'Tắt tự học?',
        content: learnedCount > 0
            ? 'Bot xoá $learnedCount điều đã học về bạn và không học thêm.'
            : 'Bot sẽ không học thêm về bạn.',
        action: 'Tắt',
      );
      if (!yes) return;
    }
    await _run((api) => api.setAgentNoLearn(!learn));
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Thôi'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(agentMeProvider);
    final data = me.value;
    final agent = data?.agent;
    final list = widget.list;
    final Widget body;
    if (data == null) {
      body = me.hasError
          ? Center(
              child: TextButton(
                onPressed: () => ref.invalidate(agentMeProvider),
                child: const Text('Không tải được bot. Chạm để thử lại.'),
              ),
            )
          : const Center(child: CircularProgressIndicator());
    } else if (!data.enabled || agent == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Bot cá nhân đang thử nghiệm với vài thành viên.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (list != null) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (list == AgentListView.memories)
            _MemoryCard(
              memories: data.memories,
              limit: data.memoryLimit,
              busy: _busy,
              onAdd: () => _editMemory(null),
              onEdit: _editMemory,
              onDelete: _deleteMemory,
            )
          else
            _LearnedCard(
              learned: data.learned,
              busy: _busy,
              onForget: _forgetLearned,
            ),
        ],
      );
    } else {
      body = ListView(
        // Chừa chỗ cho thanh tab nổi phía dưới.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _Header(onEdit: agent.created ? () => _open('/agent/setup') : null),
          const SizedBox(height: 18),
          if (agent.created) ...[
            _BotHeroCard(
              agent: agent,
              memoryCount: data.memories.length,
              memoryLimit: data.memoryLimit,
              learnedCount: data.learned.length,
              today: data.today,
              onChat: () => _open('/agent/dm'),
              onRoom: () => _open('/agent/room'),
            ),
            if (data.today case final today? when today.resting != null) ...[
              const SizedBox(height: 12),
              _RestingBanner(botName: agent.name, today: today),
            ],
            if (data.telegram case final telegram?) ...[
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _telegramLink,
                builder: (context, _) => _TelegramCard(
                  botName: agent.name,
                  telegram: telegram,
                  accountLinked: _telegramLink.status?.linked,
                  waitingStart: _telegramLink.waiting,
                  busy: _telegramBusy || _telegramLink.busy,
                  onOpen: (username) => _openExternal('https://t.me/$username'),
                  onCreate: () => _openExternal(telegram.createUrl),
                  onPut: () => _putOnTelegram(telegram),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _RoomPreviewCard(onOpen: () => _open('/agent/room')),
            const SizedBox(height: 22),
            _SectionLabel(
              'Bot biết gì về bạn',
              onSeeAll: data.memories.length > _previewCount
                  ? () => _open('/agent/memories')
                  : null,
            ),
            const SizedBox(height: 8),
            _MemoryCard(
              memories: data.memories.take(_previewCount).toList(),
              limit: data.memoryLimit,
              full: data.memories.length >= data.memoryLimit,
              busy: _busy,
              onAdd: () => _editMemory(null),
              onEdit: _editMemory,
            ),
          ] else
            _CreateBotCard(onCreate: () => _open('/agent/setup')),
          // Bot tự học cả khi chưa tạo bot (vd. trí nhớ cũ của 3i), nên có gì
          // thì vẫn hiện để người dùng xem và cho quên. Đã tắt tự học thì vẫn
          // hiện để bật lại được.
          if (agent.created || data.learned.isNotEmpty || data.noLearn) ...[
            const SizedBox(height: 22),
            _SectionLabel(
              'Bot tự học về bạn',
              onSeeAll: data.learned.length > _previewCount
                  ? () => _open('/agent/learned')
                  : null,
            ),
            const SizedBox(height: 8),
            _LearnedCard(
              learned: data.learned.take(_previewCount).toList(),
              busy: _busy,
              onForget: _forgetLearned,
              learning: !data.noLearn,
              onLearning: (learn) => _setLearning(learn, data.learned.length),
              onGroupFacts: () => _open('/agent/group-facts'),
            ),
          ],
          // Chặn chỉ làm được trong phòng bot, mà phòng chỉ mở được khi đã có
          // bot, nên mục bỏ chặn cũng chỉ hiện lúc đó.
          if (agent.created) ...[
            const SizedBox(height: 22),
            _Card(
              child: ListTile(
                title: const Text(
                  'Người đã chặn',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open('/agent/blocks'),
              ),
            ),
          ],
        ],
      );
    }
    if (list != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            list == AgentListView.memories
                ? 'Bot biết gì về bạn'
                : 'Bot tự học về bạn',
          ),
        ),
        body: body,
      );
    }
    return Scaffold(body: SafeArea(bottom: false, child: body));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        const Expanded(
          child: Text(
            'MyBot',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (onEdit != null)
          Tooltip(
            message: 'Sửa bot',
            child: Material(
              color: palette.glassStart,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.edit_outlined),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Thẻ tối đầu tab, cùng cách tô màu với thẻ điểm sức mạnh ở Hành Trình.
class _BotHeroCard extends StatelessWidget {
  const _BotHeroCard({
    required this.agent,
    required this.memoryCount,
    required this.memoryLimit,
    required this.learnedCount,
    required this.today,
    required this.onChat,
    required this.onRoom,
  });

  final AgentProfile agent;
  final int memoryCount;
  final int memoryLimit;
  final int learnedCount;
  final AgentToday? today;
  final VoidCallback onChat;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final dark = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    return _HeroShell(
      palette: dark,
      children: [
        Row(
          children: [
            _BotOrb(palette: dark, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (agent.persona.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      agent.persona,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark.textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Divider(height: 1, color: dark.ink.withValues(alpha: 0.12)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _HeroStat(
                palette: dark,
                value: '$memoryCount',
                suffix: '/$memoryLimit',
                label: 'mục nhớ',
              ),
            ),
            Expanded(
              child: _HeroStat(
                palette: dark,
                value: '$learnedCount',
                label: 'điều tự học',
              ),
            ),
            if (today case final today?)
              Expanded(
                child: _HeroStat(
                  palette: dark,
                  value: '${today.dmUsed}',
                  suffix: '/${today.dmMax}',
                  label: 'tin hôm nay',
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onChat,
                style: FilledButton.styleFrom(
                  backgroundColor: dark.accent,
                  foregroundColor: RunNowThemeTokens.lightInk,
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Chat riêng'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRoom,
                style: OutlinedButton.styleFrom(
                  foregroundColor: dark.ink,
                  side: BorderSide(color: dark.ink.withValues(alpha: 0.28)),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Phòng bot'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Báo bot đang trả câu nghỉ, để chủ biết trước khi nhắn. Nút chat riêng vẫn
/// mở được để đọc lại tin cũ.
class _RestingBanner extends StatelessWidget {
  const _RestingBanner({required this.botName, required this.today});

  final String botName;
  final AgentToday today;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final budget = today.resting == AgentResting.budget;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                budget ? Icons.bedtime_outlined : Icons.schedule_rounded,
                size: 20,
                color: palette.accentDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    budget
                        ? '$botName đang nghỉ tới 0h'
                        : 'Hết ${today.dmMax} tin hôm nay',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    budget
                        ? 'Hôm nay MyBot đã chạm trần chi phí.'
                        : 'Chat riêng lại được lúc 0h.',
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
      ),
    );
  }
}

/// Mục MyBot trên Telegram: bot đang chạy, bot hỏng cần tạo lại, hoặc chưa
/// có bot. Chat trên Telegram là một kênh riêng của cùng một bot.
class _TelegramCard extends StatelessWidget {
  const _TelegramCard({
    required this.botName,
    required this.telegram,
    required this.accountLinked,
    required this.waitingStart,
    required this.busy,
    required this.onOpen,
    required this.onCreate,
    required this.onPut,
  });

  final String botName;
  final AgentTelegram telegram;

  /// Tài khoản 3i đã liên kết Telegram chưa; null là chưa đọc được.
  final bool? accountLinked;

  /// Đang chờ chủ bấm Start bên Telegram để liên kết tài khoản.
  final bool waitingStart;
  final bool busy;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onPut;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final username = telegram.botUsername;
    final String title;
    final String detail;
    final String action;
    final VoidCallback? onPressed;
    if (telegram.running) {
      title = username == null
          ? 'Đã có bot trên Telegram'
          : 'Trên Telegram: @$username';
      detail =
          'Chat trên Telegram tách riêng với chat trong app. Bộ nhớ và lượt '
          'mỗi ngày thì dùng chung.';
      action = 'Mở trên Telegram';
      onPressed = username == null ? null : () => onOpen(username);
    } else if (telegram.linked) {
      title = 'Bot trên Telegram chưa chạy được';
      detail = 'Có thể bot đã bị xoá bên Telegram. Bot mới sẽ thay bot cũ.';
      action = 'Tạo lại bot';
      onPressed = busy ? null : onCreate;
    } else {
      title = 'MyBot trên Telegram';
      detail = waitingStart
          ? 'Bấm Start trong Telegram rồi quay lại đây.'
          : accountLinked == false
          ? 'Liên kết Telegram với 3i trước, xong thì bấm lại để tạo bot '
                'mang tên $botName. Bạn là chủ bot.'
          : 'Telegram sẽ tạo một bot mang tên $botName. Bạn là chủ bot.';
      action = 'Đưa bot lên Telegram';
      onPressed = busy ? null : onPut;
    }
    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    telegram.linked && !telegram.running
                        ? Icons.error_outline_rounded
                        : Icons.send_rounded,
                    size: 20,
                    color: palette.accentDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              icon: const Icon(Icons.send_rounded),
              label: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ đầu tab khi chưa có bot.
class _CreateBotCard extends StatelessWidget {
  const _CreateBotCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final dark = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    return _HeroShell(
      palette: dark,
      children: [
        _BotOrb(palette: dark, size: 56),
        const SizedBox(height: 14),
        Text(
          'Tạo bot của riêng bạn',
          style: TextStyle(
            color: dark.ink,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Bot thay bạn nói chuyện trong phòng bot.',
          style: TextStyle(color: dark.textMuted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            backgroundColor: dark.accent,
            foregroundColor: RunNowThemeTokens.lightInk,
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Tạo bot'),
        ),
      ],
    );
  }
}

class _HeroShell extends StatelessWidget {
  const _HeroShell({required this.palette, required this.children});

  final RunNowPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: palette.tint.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _BotOrb extends StatelessWidget {
  const _BotOrb({required this.palette, required this.size});

  final RunNowPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: LinearGradient(
          colors: [palette.tertiary, palette.accentDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.smart_toy_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.palette,
    required this.value,
    required this.label,
    this.suffix,
  });

  final RunNowPalette palette;
  final String value;
  final String? suffix;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: value,
            children: [
              if (suffix != null)
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          style: TextStyle(
            color: palette.ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Hai tin mới nhất trong phòng bot, đọc một lần mỗi lần mở tab.
class _RoomPreviewCard extends ConsumerWidget {
  const _RoomPreviewCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final preview = ref.watch(agentRoomPreviewProvider);
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final muted = TextStyle(color: palette.textMuted, fontSize: 14);
    final room = preview.value;
    final Widget content;
    if (preview.hasError && room == null) {
      content = InkWell(
        onTap: () => ref.invalidate(agentRoomPreviewProvider),
        child: Text('Không tải được phòng bot. Chạm để thử lại.', style: muted),
      );
    } else if (room == null) {
      content = const LinearProgressIndicator(minHeight: 2);
    } else if (room.messages.isEmpty) {
      content = Text('Phòng chưa có tin nào.', style: muted);
    } else {
      content = Column(
        children: [
          for (final m in room.messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RoomPreviewLine(message: m, myUid: myUid),
            ),
        ],
      );
    }
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _Caps('Phòng bot')),
                if (room != null && room.bots > 0)
                  Text(
                    '${room.bots} bot đang ở phòng',
                    style: TextStyle(
                      color: palette.accentDeep,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            content,
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: palette.accentDeep,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Row(
                children: [
                  Expanded(child: Text('Vào phòng')),
                  Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPreviewLine extends StatelessWidget {
  const _RoomPreviewLine({required this.message, required this.myUid});

  final AgentRoomMessage message;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = message.name.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: message.fromAgent ? palette.ink : palette.accentDeep,
            // Bot thì vuông bo góc, người thì tròn, như trong phòng.
            borderRadius: BorderRadius.circular(message.fromAgent ? 10 : 15),
          ),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              color: palette.background,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agentRoomSenderLabel(message, myUid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                message.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thẻ bộ nhớ. Không có [onDelete] là bản rút gọn ở tab: chạm vào mục để sửa
/// hay xoá. Có [onDelete] là trang đầy đủ, mỗi mục có nút xoá riêng.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memories,
    required this.limit,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    this.onDelete,
    bool? full,
  }) : full = full ?? memories.length >= limit;

  final List<AgentMemory> memories;
  final int limit;
  final bool full;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<AgentMemory> onEdit;
  final ValueChanged<AgentMemory>? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onDelete = this.onDelete;
    return _Card(
      child: Column(
        children: [
          if (memories.isEmpty)
            const _EmptyRow('Chưa có gì. Kể cho bot trong Chat riêng.'),
          for (final m in memories) ...[
            _FactRow(
              text: m.text,
              source: m.fromChat ? 'Bot ghi khi chat' : 'Bạn thêm',
              onTap: busy ? null : () => onEdit(m),
              action: onDelete == null
                  ? null
                  : IconButton(
                      tooltip: 'Xoá',
                      icon: const Icon(Icons.delete_outline),
                      color: palette.textMuted,
                      onPressed: busy ? null : () => onDelete(m),
                    ),
            ),
            const _RowDivider(),
          ],
          ListTile(
            enabled: !busy && !full,
            leading: Icon(Icons.add_rounded, color: palette.accentDeep),
            title: Text(
              full ? 'Bộ nhớ đã đầy ($limit mục)' : 'Thêm điều cần nhớ',
              style: TextStyle(
                color: full ? palette.textMuted : palette.accentDeep,
                fontWeight: FontWeight.w800,
              ),
            ),
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _LearnedCard extends StatelessWidget {
  const _LearnedCard({
    required this.learned,
    required this.busy,
    required this.onForget,
    this.learning = true,
    this.onLearning,
    this.onGroupFacts,
  });

  final List<AgentLearnedFact> learned;
  final bool busy;
  final ValueChanged<AgentLearnedFact> onForget;
  final bool learning;

  /// Có thì hiện công tắc tự học ở đầu thẻ (chỉ ở tab, không ở trang đầy đủ).
  final ValueChanged<bool>? onLearning;
  final VoidCallback? onGroupFacts;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onGroupFacts = this.onGroupFacts;
    final onLearning = this.onLearning;
    return _Card(
      child: Column(
        children: [
          if (onLearning != null) ...[
            SwitchListTile(
              value: learning,
              onChanged: busy ? null : onLearning,
              title: const Text(
                'Cho bot tự học về bạn',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const _RowDivider(),
          ],
          if (learned.isEmpty)
            _EmptyRow(
              learning
                  ? 'Bot chưa học được gì về bạn.'
                  : 'Bot không tự học về bạn.',
            ),
          for (final (i, f) in learned.indexed) ...[
            if (i > 0) const _RowDivider(),
            _FactRow(
              text: f.text,
              source: f.migrated ? 'Từ trí nhớ cũ của 3i' : 'Bot tự học',
              action: TextButton(
                onPressed: busy ? null : () => onForget(f),
                style: TextButton.styleFrom(foregroundColor: palette.textMuted),
                child: const Text('Quên'),
              ),
            ),
          ],
          if (onGroupFacts != null) ...[
            const _RowDivider(),
            ListTile(
              title: const Text(
                'Bot biết gì về nhóm',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onGroupFacts,
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.runNowPalette.glassStart,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Nhãn mục kiểu chữ hoa nhỏ, có "Xem tất cả" khi mục dài hơn phần đang hiện.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.onSeeAll});

  final String text;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final onSeeAll = this.onSeeAll;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(child: _Caps(text)),
          if (onSeeAll != null)
            InkWell(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Xem tất cả',
                  style: TextStyle(
                    color: context.runNowPalette.accentDeep,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Caps extends StatelessWidget {
  const _Caps(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.runNowPalette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.text,
    required this.source,
    this.action,
    this.onTap,
  });

  final String text;
  final String source;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16, right: action == null ? 16 : 4),
      title: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        source,
        style: TextStyle(
          color: context.runNowPalette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      trailing: action,
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: context.runNowPalette.textMuted),
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      color: context.runNowPalette.border.withValues(alpha: 0.6),
    );
  }
}

/// Kết quả hộp thoại mục nhớ: chữ mới, hoặc xoá mục đang sửa.
typedef _MemoryEdit = ({String text, bool delete});

class _MemoryDialog extends StatefulWidget {
  const _MemoryDialog({required this.initial});

  final String initial;

  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial.isNotEmpty;
    return AlertDialog(
      title: Text(editing ? 'Sửa mục nhớ' : 'Thêm điều cần nhớ'),
      content: TextField(
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Vd: Chủ chạy sáng thứ 7 ở hồ Tây.',
          // Bộ nhớ đi cả vào phòng bot: nói ở đúng lúc người dùng đang gõ.
          helperText: 'Mọi thành viên trong phòng bot đều đọc được.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop((text: '', delete: true)),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xoá'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Thôi'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((text: _text.text, delete: false)),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
