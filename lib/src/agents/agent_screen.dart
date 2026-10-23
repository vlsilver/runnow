import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_images_screen.dart';
import 'package:myrun/src/agents/agent_km.dart';
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
    // Chạy xong (Strava đồng bộ) rồi quay lại: km, số tin và lượt ảnh đã đổi.
    // Màn chat riêng mở đè lên tab này nên cũng theo kịp.
    ref.invalidate(agentMeProvider);
    if (telegram == null || (telegram.running && !telegram.canJoinPsc)) return;
    // Bấm Start bên Telegram rồi quay lại.
    if (!telegram.linked) _telegramLink.onResume();
    // Vừa tạo bot hay vừa thêm bot vào PSC bên Telegram: đọc thêm một lần sau
    // ít giây vì backend ghi chậm hơn. Không poll tiếp; lần quay lại sau lại
    // đọc.
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
    ref.invalidate(agentImagesPreviewProvider);
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
          : const _LoadingSkeleton();
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
              today: data.today,
              learning: !data.noLearn,
              inPsc: data.telegram?.inPsc ?? false,
              onChat: () => _open('/agent/dm'),
              onRoom: () => _open('/agent/room'),
            ),
            if (data.today case final today?
                when today.dmByKm != null || today.images != null) ...[
              const SizedBox(height: 12),
              _KmTodayCard(today: today),
            ],
            if (data.telegram case final telegram?) ...[
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: _telegramLink,
                builder: (context, _) => _TelegramCard(
                  telegram: telegram,
                  accountLinked: _telegramLink.status?.linked,
                  waitingStart: _telegramLink.waiting,
                  busy: _telegramBusy || _telegramLink.busy,
                  onOpen: (username) => _openExternal('https://t.me/$username'),
                  onCreate: () => _openExternal(telegram.createUrl),
                  onPut: () => _putOnTelegram(telegram),
                  onJoinPsc: _openExternal,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _RoomPreviewCard(onOpen: () => _open('/agent/room')),
            _ImagesPreview(onOpen: () => _open('/agent/images')),
            const SizedBox(height: 22),
            _SectionLabel(
              'Bot biết gì về bạn',
              icon: Icons.psychology_outlined,
              count: '${data.memories.length}/${data.memoryLimit}',
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
              icon: Icons.auto_awesome_outlined,
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
              child: _LinkRow(
                icon: Icons.block_rounded,
                text: 'Người đã chặn',
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

/// Thẻ tối đầu tab, cùng cách tô màu với thẻ điểm sức mạnh ở Hành Trình. Gom
/// trạng thái của bot (nghỉ, ở PSC, tự học) thành chip để tab bớt chữ.
class _BotHeroCard extends StatelessWidget {
  const _BotHeroCard({
    required this.agent,
    required this.today,
    required this.learning,
    required this.inPsc,
    required this.onChat,
    required this.onRoom,
  });

  final AgentProfile agent;
  final AgentToday? today;
  final bool learning;
  final bool inPsc;
  final VoidCallback onChat;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final dark = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    final today = this.today;
    final images = today?.images;
    // Chạm trần chi phí thì mọi bot cùng nghỉ: nói ngay ở tên bot. Hết tin
    // chat riêng thì bot vẫn nói trong phòng, nên chỉ là một chip.
    final budget = today?.resting == AgentResting.budget;
    final chips = [
      if (budget)
        (Icons.bedtime_rounded, 'Quay lại lúc 0h')
      else if (today?.resting == AgentResting.dmLimit)
        (Icons.schedule_rounded, 'Hết tin · mở lại 0h'),
      if (inPsc) (Icons.groups_rounded, 'Ở group PSC'),
      if (learning) (Icons.auto_awesome_rounded, 'Đang tự học'),
    ];
    final subtitle = budget
        ? 'MyBot chạm trần chi phí hôm nay.'
        : agent.persona;
    final buttonText = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w800);
    return _HeroShell(
      palette: dark,
      children: [
        Row(
          children: [
            _BotOrb(palette: dark, size: 76, name: agent.name, resting: budget),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    budget ? '${agent.name} đang nghỉ' : agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dark.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icon, text) in chips)
                _HeroChip(palette: dark, icon: icon, text: text),
            ],
          ),
        ],
        if (today != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: dark.ink.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: dark.ink.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    palette: dark,
                    icon: Icons.chat_bubble_outline_rounded,
                    value: '${today.dmUsed}',
                    suffix: '/${today.dmMax}',
                    label: 'tin hôm nay',
                    used: today.dmUsed,
                    max: today.dmMax,
                  ),
                ),
                if (images != null) ...[
                  const SizedBox(width: 18),
                  Expanded(
                    child: _HeroStat(
                      palette: dark,
                      icon: Icons.palette_outlined,
                      value: '${images.used}',
                      suffix: '/${images.limit}',
                      label: 'ảnh hôm nay',
                      used: images.used,
                      max: images.limit,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onChat,
                style: FilledButton.styleFrom(
                  backgroundColor: dark.accent,
                  foregroundColor: RunNowThemeTokens.lightInk,
                  minimumSize: const Size.fromHeight(52),
                  textStyle: buttonText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_rounded, size: 19),
                label: const Text('Chat riêng'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onRoom,
                style: FilledButton.styleFrom(
                  backgroundColor: dark.ink.withValues(alpha: 0.1),
                  foregroundColor: dark.ink,
                  minimumSize: const Size.fromHeight(52),
                  textStyle: buttonText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.forum_outlined, size: 19),
                label: const Text('Phòng bot'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.palette,
    required this.icon,
    required this.text,
  });

  final RunNowPalette palette;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.accent),
          const SizedBox(width: 5),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: palette.ink,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

/// Km chạy và đi bộ hôm nay mở được bao nhiêu tin chat và ảnh, chạy thêm bao nhiêu thì
/// mở tiếp. Số và mốc đều lấy từ backend (dmByKm, images), app không giữ bảng
/// mốc, để đổi mốc chỉ cần sửa backend.
class _KmTodayCard extends StatelessWidget {
  const _KmTodayCard({required this.today});

  final AgentToday today;

  /// Thước vẽ tới 10 km; chạy xa hơn thì thước đầy.
  static const _rulerKm = 10;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final images = today.images;
    // perKm 0 là admin tắt thưởng theo km: số tin không đổi theo km nên bỏ ô.
    final dm = switch (today.dmByKm) {
      final byKm? when byKm.perKm > 0 => byKm,
      _ => null,
    };
    final runKm = today.dmByKm?.runKm ?? images?.runKm ?? 0;
    // Làm tròn xuống, để 4,96 km không hiện thành 5 km khi chưa mở mốc 5.
    final shownKm = (runKm * 10 + 1e-9).floor() / 10;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.directions_run_rounded,
                  size: 15,
                  color: palette.accentDeep,
                ),
                const SizedBox(width: 6),
                const Expanded(child: _Caps('Km hôm nay')),
                Text(
                  'Đếm lại lúc 0h',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatAgentKm(shownKm),
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'km',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _KmRuler(
              palette: palette,
              runKm: runKm,
              maxKm: _rulerKm,
              nextKm: dm?.nextKm ?? images?.nextKm,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dm != null)
                  Expanded(
                    child: _KmTile(
                      palette: palette,
                      icon: Icons.chat_bubble_outline_rounded,
                      value: '${today.dmMax} tin chat',
                      detail: _dmDetail(dm),
                    ),
                  ),
                if (dm != null && images != null) const SizedBox(width: 10),
                if (images != null)
                  Expanded(
                    child: _KmTile(
                      palette: palette,
                      icon: Icons.palette_outlined,
                      value: '${images.limit} ảnh vẽ',
                      detail: _imageDetail(images),
                    ),
                  ),
              ],
            ),
            for (final hint in _hints(dm, images)) ...[
              const SizedBox(height: 10),
              hint,
            ],
          ],
        ),
      ),
    );
  }

  String _dmDetail(AgentDMByKm dm) {
    final fullKm = (dm.runKm + 1e-9).floor();
    if (dm.nextKm == null) return 'Đã đủ tối đa ${today.dmMax} tin';
    if (fullKm == 0) return '${dm.base} sẵn mỗi ngày';
    return '${dm.base} sẵn + ${today.dmMax - dm.base} từ $fullKm km';
  }

  String _imageDetail(AgentImagesToday images) => switch (images) {
    AgentImagesToday(limit: 0, :final nextKm?) =>
      'Chạy hay đi bộ đủ ${formatAgentKm(nextKm)} km để mở',
    AgentImagesToday(nextKm: null) => 'Mốc cao nhất',
    _ => 'đã vẽ ${images.used}',
  };

  /// Mốc tin và mốc ảnh cùng km thì gộp một dòng; hết cả hai thì một dòng báo
  /// đã mở hết.
  List<Widget> _hints(AgentDMByKm? dm, AgentImagesToday? images) {
    final dmNext = dm?.nextKm;
    final moreDm = (dm?.nextMax ?? 0) - today.dmMax;
    final imageNext = images?.nextKm;
    final moreImages = (images?.nextLimit ?? 0) - (images?.limit ?? 0);
    if (dmNext != null && dmNext == imageNext) {
      return [
        _KmHint(
          runKm: dm!.runKm,
          nextKm: dmNext,
          rest: ' để có thêm $moreDm tin và $moreImages ảnh.',
        ),
      ];
    }
    final hints = [
      if (dmNext != null)
        _KmHint(
          runKm: dm!.runKm,
          nextKm: dmNext,
          rest: ' để có thêm $moreDm tin.',
        ),
      if (imageNext != null)
        _KmHint(
          runKm: images!.runKm,
          nextKm: imageNext,
          rest: ' để vẽ thêm $moreImages ảnh.',
        ),
    ];
    if (hints.isNotEmpty) return hints;
    return [
      _KmHint.done(
        dm != null && images != null
            ? 'Đã mở hết tin và ảnh hôm nay.'
            : dm != null
            ? 'Đã mở hết tin hôm nay.'
            : 'Đã mở hết ảnh hôm nay.',
      ),
    ];
  }
}

/// Thước km hôm nay, mỗi vạch là một km.
class _KmRuler extends StatelessWidget {
  const _KmRuler({
    required this.palette,
    required this.runKm,
    required this.maxKm,
    this.nextKm,
  });

  final RunNowPalette palette;
  final double runKm;
  final int maxKm;

  /// Mốc mở thêm kế tiếp (backend trả); có thì vạch đó sáng lên.
  final double? nextKm;

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(
      color: palette.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, box) => ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: palette.ink.withValues(alpha: 0.08),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: box.maxWidth * (runKm / maxKm).clamp(0, 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [palette.tertiary, palette.accent],
                        ),
                      ),
                    ),
                  ),
                  for (var km = 1; km < maxKm; km++)
                    Positioned(
                      left: box.maxWidth * km / maxKm - 1,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: ColoredBox(
                        color: km == nextKm
                            ? palette.accentDeep
                            : palette.glassStart,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('0', style: label),
            const Spacer(),
            Text('${maxKm ~/ 2}', style: label),
            const Spacer(),
            Text('$maxKm km', style: label),
          ],
        ),
      ],
    );
  }
}

class _KmTile extends StatelessWidget {
  const _KmTile({
    required this.palette,
    required this.icon,
    required this.value,
    required this.detail,
  });

  final RunNowPalette palette;
  final IconData icon;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.accentDeep),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Chạy hay đi bộ thêm X km để …", hoặc một dòng có dấu tích khi đã mở hết.
class _KmHint extends StatelessWidget {
  const _KmHint({
    required double this.runKm,
    required double this.nextKm,
    required this.rest,
  }) : done = null;

  const _KmHint.done(String this.done) : runKm = null, nextKm = null, rest = '';

  final double? runKm;
  final double? nextKm;
  final String rest;
  final String? done;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final (runKm, nextKm, done) = (this.runKm, this.nextKm, this.done);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            done != null
                ? Icons.check_circle_outline_rounded
                : Icons.trending_up_rounded,
            size: 18,
            color: palette.accentDeep,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              done != null
                  ? TextSpan(text: done)
                  : TextSpan(
                      children: [
                        TextSpan(
                          text:
                              'Chạy hay đi bộ thêm ${formatAgentKm(agentKmLeft(nextKm!, runKm!))} km',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        TextSpan(text: rest),
                      ],
                    ),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mục MyBot trên Telegram, một dòng cho mỗi việc: bot đang chạy, bot hỏng
/// cần tạo lại, hoặc chưa có bot; thêm một dòng đưa bot vào PSC khi được. Chat
/// trên Telegram là một kênh riêng của cùng một bot, và ảnh chỉ vẽ ở đó.
class _TelegramCard extends StatelessWidget {
  const _TelegramCard({
    required this.telegram,
    required this.accountLinked,
    required this.waitingStart,
    required this.busy,
    required this.onOpen,
    required this.onCreate,
    required this.onPut,
    required this.onJoinPsc,
  });

  final AgentTelegram telegram;

  /// Tài khoản 3i đã liên kết Telegram chưa; null là chưa đọc được.
  final bool? accountLinked;

  /// Đang chờ chủ bấm Start bên Telegram để liên kết tài khoản.
  final bool waitingStart;
  final bool busy;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;
  final VoidCallback onPut;

  /// Mở link chọn group để thêm bot vào PSC.
  final ValueChanged<String> onJoinPsc;

  @override
  Widget build(BuildContext context) {
    final username = telegram.botUsername;
    final pscJoinUrl = telegram.pscJoinUrl;
    final _TelegramRow main;
    if (telegram.running) {
      main = _TelegramRow(
        icon: Icons.send_rounded,
        title: username == null ? 'Telegram' : '@$username',
        detail: 'Chat và vẽ ảnh trên Telegram',
        action: 'Mở',
        onPressed: username == null ? null : () => onOpen(username),
      );
    } else if (telegram.linked) {
      main = _TelegramRow(
        icon: Icons.error_outline_rounded,
        title: 'Bot Telegram bị lỗi',
        detail: 'Bot mới sẽ thay bot cũ',
        action: 'Tạo lại',
        onPressed: busy ? null : onCreate,
      );
    } else {
      main = _TelegramRow(
        icon: Icons.send_rounded,
        title: 'Đưa bot lên Telegram',
        detail: waitingStart
            ? 'Bấm Start trong Telegram rồi quay lại'
            : accountLinked == false
            ? 'Liên kết Telegram trước, rồi bấm lại'
            : 'Chat và vẽ ảnh trên Telegram',
        action: 'Đưa lên',
        onPressed: busy ? null : onPut,
      );
    }
    return _Card(
      child: Column(
        children: [
          main,
          // Bot API không cho 3i tự thêm bot vào group, nên chủ tự thêm. Bot
          // đã ở PSC thì thẻ bot có chip, không cần dòng này.
          if (telegram.canJoinPsc && pscJoinUrl != null) ...[
            const _RowDivider(),
            _TelegramRow(
              icon: Icons.group_add_rounded,
              title: 'Đưa bot vào group PSC',
              action: 'Thêm',
              onPressed: () => onJoinPsc(pscJoinUrl),
            ),
          ],
        ],
      ),
    );
  }
}

class _TelegramRow extends StatelessWidget {
  const _TelegramRow({
    required this.icon,
    required this.title,
    required this.action,
    required this.onPressed,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final detail = this.detail;
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khung xương lúc đang tải hồ sơ bot, cùng bố cục với tab để không giật.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = RunNowPalette.forSelection(
      palette.element,
      appearance: RunNowAppearance.dark,
    );
    Widget bar(Color color, double width, double height) =>
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: width,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
    final heroBlock = dark.ink.withValues(alpha: 0.12);
    final cardBlock = palette.border.withValues(alpha: 0.5);
    return Semantics(
      label: 'Đang tải bot',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const _Header(onEdit: null),
          const SizedBox(height: 18),
          _HeroShell(
            palette: dark,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: heroBlock,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        bar(heroBlock, 0.6, 18),
                        const SizedBox(height: 8),
                        bar(heroBlock, 0.85, 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              bar(heroBlock, 1, 50),
            ],
          ),
          for (final lines in [2, 3]) ...[
            const SizedBox(height: 16),
            _Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    bar(cardBlock, 0.35, 10),
                    for (var i = 0; i < lines; i++) ...[
                      const SizedBox(height: 12),
                      bar(cardBlock, i.isEven ? 0.9 : 0.7, 14),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
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
          'Bot thay bạn nói chuyện trong phòng bot. Mỗi km bạn chạy mở thêm '
          'tin chat và lượt vẽ ảnh cho bot.',
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(palette.tint, palette.accentDeep, 0.18)!,
            palette.tint,
            Color.lerp(palette.tint, palette.background, 0.5)!,
          ],
          stops: const [0, 0.55, 1],
        ),
        border: Border.all(color: palette.ink.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Quầng sáng góc trên phải, cho thẻ có chiều sâu mà không thêm ảnh.
          Positioned(
            top: -90,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.26),
                      palette.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mặt bot: chữ cái đầu tên bot trong quả cầu màu nhấn, vòng sáng quanh và
/// chấm trạng thái. Chưa có tên (thẻ tạo bot) thì vẽ robot.
class _BotOrb extends StatelessWidget {
  const _BotOrb({
    required this.palette,
    required this.size,
    this.name,
    this.resting = false,
  });

  final RunNowPalette palette;
  final double size;
  final String? name;

  /// Bot đang nghỉ: tắt màu và đổi sang mặt trăng.
  final bool resting;

  @override
  Widget build(BuildContext context) {
    final name = this.name?.trim() ?? '';
    final Widget face = resting
        ? Icon(
            Icons.bedtime_outlined,
            color: palette.textMuted,
            size: size * 0.42,
          )
        : name.isEmpty
        ? Icon(Icons.smart_toy_rounded, color: Colors.white, size: size * 0.5)
        : Text(
            name.characters.first.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.44,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          );
    final ring = size * 0.06;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            padding: EdgeInsets.all(ring),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: resting
                  ? null
                  : SweepGradient(
                      colors: [
                        palette.accent,
                        palette.tertiary.withValues(alpha: 0.2),
                        palette.accent,
                      ],
                    ),
              color: resting ? palette.ink.withValues(alpha: 0.12) : null,
              boxShadow: resting
                  ? null
                  : [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.4),
                        blurRadius: 24,
                      ),
                    ],
            ),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: resting ? palette.tint : null,
                gradient: resting
                    ? null
                    : LinearGradient(
                        colors: [palette.tertiary, palette.accentDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                border: Border.all(color: palette.tint, width: ring * 0.8),
              ),
              child: face,
            ),
          ),
          if (this.name != null)
            Positioned(
              right: size * 0.04,
              bottom: size * 0.04,
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: resting
                      ? RunNowSemanticColors.inactive
                      : RunNowSemanticColors.success,
                  border: Border.all(color: palette.tint, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Một chỉ số trong thẻ bot: số đã dùng trên trần, kèm thanh đầy dần.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.palette,
    required this.icon,
    required this.value,
    required this.label,
    required this.used,
    required this.max,
    this.suffix,
  });

  final RunNowPalette palette;
  final IconData icon;
  final String value;
  final String? suffix;
  final String label;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: palette.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 5,
            child: ColoredBox(
              color: palette.ink.withValues(alpha: 0.1),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [palette.tertiary, palette.accent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
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
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoomPreviewLine(message: m, myUid: myUid),
            ),
        ],
      );
    }
    final bots = room?.bots ?? const <String>[];
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.forum_outlined, size: 15, color: palette.accentDeep),
                const SizedBox(width: 6),
                const Expanded(child: _Caps('Phòng bot')),
                if (bots.isNotEmpty) ...[
                  _AvatarStack(names: bots),
                  const SizedBox(width: 8),
                  Text(
                    '${bots.length} bot đang ở phòng',
                    style: TextStyle(
                      color: palette.accentDeep,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            content,
            const SizedBox(height: 4),
            FilledButton.tonal(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: palette.accent.withValues(alpha: 0.14),
                foregroundColor: palette.accentDeep,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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

/// Tối đa ba avatar bot chồng lên nhau, như nhóm chat.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});

  final List<String> names;

  static const _size = 22.0;
  static const _step = 14.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final shown = names.take(3).toList();
    final tones = [palette.accentDeep, palette.tertiary, palette.secondary];
    return SizedBox(
      width: _size + _step * (shown.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (final (i, name) in shown.indexed)
            Positioned(
              left: _step * i,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tones[i % tones.length],
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.glassStart, width: 2),
                ),
                child: Text(
                  name.trim().isEmpty
                      ? '?'
                      : name.trim().characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
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

/// Vài ảnh mới nhất bot đã vẽ; chạm vào đâu cũng mở trang đủ ảnh. Bot chưa vẽ
/// gì, hay tải lỗi, thì không hiện mục này: ảnh là phần phụ của tab.
class _ImagesPreview extends ConsumerWidget {
  const _ImagesPreview({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(agentImagesPreviewProvider).value;
    if (images == null || images.isEmpty) return const SizedBox.shrink();
    final image = ref.watch(agentImageBuilderProvider);
    Widget tile(int i) => AgentImageTile(
      onTap: onOpen,
      child: image(images[i].path, full: false),
    );
    const gap = 6.0;
    // Đủ ba ảnh thì ảnh mới nhất to gấp đôi, bên phải hai ảnh, hàng dưới ba
    // ảnh còn lại; ít hơn thì một hàng.
    final content = LayoutBuilder(
      builder: (context, box) {
        final cell = (box.maxWidth - gap * 2) / 3;
        if (images.length < 3) {
          return Row(
            children: [
              for (var i = 0; i < images.length; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox(width: cell, height: cell, child: tile(i)),
              ],
            ],
          );
        }
        final big = cell * 2 + gap;
        return Column(
          children: [
            Row(
              children: [
                SizedBox(width: big, height: big, child: tile(0)),
                const SizedBox(width: gap),
                Column(
                  children: [
                    SizedBox(width: cell, height: cell, child: tile(1)),
                    const SizedBox(height: gap),
                    SizedBox(width: cell, height: cell, child: tile(2)),
                  ],
                ),
              ],
            ),
            if (images.length > 3) ...[
              const SizedBox(height: gap),
              Row(
                children: [
                  for (var i = 3; i < images.length && i < 6; i++) ...[
                    if (i > 3) const SizedBox(width: gap),
                    SizedBox(width: cell, height: cell, child: tile(i)),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            'Ảnh bot đã vẽ',
            icon: Icons.palette_outlined,
            onSeeAll: onOpen,
          ),
          const SizedBox(height: 10),
          content,
        ],
      ),
    );
  }
}

/// Một tin trong phòng, dạng bong bóng: bot thì avatar vuông bo góc, người
/// thì tròn, như trong phòng; bot của mình tô màu nhấn.
class _RoomPreviewLine extends StatelessWidget {
  const _RoomPreviewLine({required this.message, required this.myUid});

  final AgentRoomMessage message;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = message.name.trim();
    final mine = message.fromAgent && message.uid == myUid;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: mine
                ? null
                : message.fromAgent
                ? palette.ink
                : palette.accentDeep,
            gradient: mine
                ? LinearGradient(
                    colors: [palette.tertiary, palette.accentDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(message.fromAgent ? 10 : 16),
          ),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: TextStyle(
              color: mine ? Colors.white : palette.background,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: mine
                  ? palette.accent.withValues(alpha: 0.12)
                  : palette.ink.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agentRoomSenderLabel(message, myUid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mine ? palette.accentDeep : palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ],
            ),
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
              icon: m.fromChat
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.push_pin_outlined,
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
          _LinkRow(
            enabled: !busy && !full,
            accent: true,
            icon: Icons.add_rounded,
            text: full ? 'Bộ nhớ đã đầy ($limit mục)' : 'Thêm điều cần nhớ',
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
              contentPadding: const EdgeInsets.only(left: 14, right: 12),
              secondary: const _RowIcon(Icons.auto_awesome_rounded),
              title: const Text(
                'Cho bot tự học về bạn',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                learning ? 'Đang bật' : 'Đang tắt',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
              icon: f.migrated
                  ? Icons.history_rounded
                  : Icons.lightbulb_outline_rounded,
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
            _LinkRow(
              icon: Icons.groups_2_outlined,
              text: 'Bot biết gì về nhóm',
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
    final palette = context.runNowPalette;
    return Material(
      color: palette.glassStart,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.border.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Nhãn mục kiểu chữ hoa nhỏ, có "Xem tất cả" khi mục dài hơn phần đang hiện.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.icon, this.count, this.onSeeAll});

  final String text;
  final IconData? icon;

  /// Số đếm cạnh nhãn, như "3/50" mục nhớ.
  final String? count;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSeeAll = this.onSeeAll;
    final icon = this.icon;
    final count = this.count;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: palette.accentDeep),
            const SizedBox(width: 6),
          ],
          Flexible(child: _Caps(text)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: palette.ink.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (onSeeAll != null) ...[
            const SizedBox(width: 8),
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
    required this.icon,
    required this.text,
    required this.source,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final String source;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 14, right: action == null ? 16 : 4),
      leading: _RowIcon(icon),
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
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

/// Ô icon đầu dòng của các thẻ danh sách, cùng cỡ để chữ thẳng hàng.
class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon, {this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final color = this.color ?? palette.accentDeep;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

/// Dòng bấm được cuối thẻ (thêm mục, mở trang con), chữ cùng cỡ với dòng mục
/// thay vì cỡ mặc định to của ListTile.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.text,
    required this.onTap,
    this.accent = false,
    this.enabled = true,
  });

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  /// Tô màu nhấn cho việc chính của thẻ (thêm mục nhớ).
  final bool accent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final color = !enabled
        ? palette.textMuted
        : accent
        ? palette.accentDeep
        : palette.ink;
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.only(left: 14, right: 12),
      leading: _RowIcon(icon, color: enabled ? null : palette.textMuted),
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
      title: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      trailing: accent
          ? null
          : Icon(Icons.chevron_right_rounded, color: palette.textMuted),
      onTap: onTap,
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
      // Thẳng mép chữ, sau ô icon đầu dòng.
      indent: 60,
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
