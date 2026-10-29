import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/agents/agent_bot_card.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_images_screen.dart';
import 'package:myrun/src/agents/agent_km.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/games/game_role_card.dart';
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

  /// Màn lên bậc đang mở hay đang đọc bậc đã khoe, để hai lần đọc hồ sơ liền
  /// nhau không mở hai màn.
  bool _revealing = false;

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
      if (next.value case final me?) unawaited(_maybeReveal(me));
    }, fireImmediately: true);
  }

  /// Thẻ vừa lên bậc (qua mốc ảnh mới hôm nay) thì mở màn lên bậc, mỗi bậc
  /// một lần mỗi ngày trên máy này. Chỉ mở khi tab đang hiện và không có màn
  /// nào đè lên, để không bật ra lúc người dùng ở tab khác.
  Future<void> _maybeReveal(AgentMe me) async {
    final agent = me.agent;
    final today = me.today;
    final images = today?.images;
    if (_revealing ||
        agent == null ||
        !agent.created ||
        today == null ||
        images == null) {
      return;
    }
    final reached = agentTiersReached(images);
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (reached == 0 || uid == null) return;
    final day = agentVnDay(DateTime.now());
    final seen = ref.read(agentTierSeenProvider);
    _revealing = true;
    try {
      if (!await seen.shouldReveal(uid, day, reached)) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !TickerMode.valuesOf(context).enabled ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      await seen.markSeen(uid, day, reached);
      if (!mounted) return;
      final data = AgentBotCardData.fromMe(me, agent);
      final next = images.nextKm;
      await showAgentTierReveal(
        context,
        data: data,
        milestoneKm: images.tiers[reached - 1].km,
        unlocked: [
          '${today.dmMax} tin chat',
          if (images.limit > 0) '${images.limit} ảnh vẽ',
        ],
        next: next == null
            ? 'Bậc cao nhất trong ngày.'
            : 'Thêm ${formatAgentKm(agentKmLeft(next, images.runKm))} km nữa '
                  'là lên ${agentCardTierAt(reached + 1, images.tiers.length).label}.',
        onChat: () => unawaited(_open('/agent/dm')),
      );
    } catch (error) {
      debugPrint('MyBot: mở màn lên bậc lỗi: $error');
    } finally {
      _revealing = false;
    }
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
            _BotCardSection(data: AgentBotCardData.fromMe(data, agent)),
            if (data.today case final today?
                when today.dmByKm != null || today.images != null) ...[
              const SizedBox(height: 16),
              _KmTodayCard(today: today),
            ],
            const SizedBox(height: 16),
            _BotActions(
              onChat: () => _open('/agent/dm'),
              onRoom: () => _open('/agent/room'),
            ),
            const SizedBox(height: 16),
            _RoomPreviewCard(onOpen: () => _open('/agent/room')),
            _ImagesPreview(onOpen: () => _open('/agent/images')),
            const SizedBox(height: 22),
            _MemoryPreviewCard(
              name: agent.name,
              memories: data.memories,
              limit: data.memoryLimit,
              busy: _busy,
              onAdd: () => _editMemory(null),
              onEdit: _editMemory,
              onSeeAll: () => _open('/agent/memories'),
            ),
            if (data.telegram case final telegram?) ...[
              const SizedBox(height: 16),
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
          ] else
            _CreateBotCard(onCreate: () => _open('/agent/setup')),
          // Bot tự học cả khi chưa tạo bot (vd. trí nhớ cũ của 3i), nên có gì
          // thì vẫn hiện để người dùng xem và cho quên. Đã tắt tự học thì vẫn
          // hiện để bật lại được.
          if (agent.created || data.learned.isNotEmpty || data.noLearn) ...[
            const SizedBox(height: 22),
            _LearnedCard(
              learned: data.learned.take(_previewCount).toList(),
              busy: _busy,
              onForget: _forgetLearned,
              learning: !data.noLearn,
              onLearning: (learn) => _setLearning(learn, data.learned.length),
              onSeeAll: data.learned.length > _previewCount
                  ? () => _open('/agent/learned')
                  : null,
              onGroupFacts: () => _open('/agent/group-facts'),
              // Chặn chỉ làm được trong phòng bot, mà phòng chỉ mở được khi
              // đã có bot, nên mục bỏ chặn cũng chỉ hiện lúc đó.
              onBlocks: agent.created ? () => _open('/agent/blocks') : null,
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

/// Đầu tab: thẻ bot của mình trên quầng sáng màu hành.
class _BotCardSection extends StatelessWidget {
  const _BotCardSection({required this.data});

  final AgentBotCardData data;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final width = math.min(box.maxWidth - 40, 320.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                IgnorePointer(
                  child: Container(
                    width: width * 1.3,
                    height: width * 1.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          palette.accent.withValues(alpha: 0.3),
                          palette.accent.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.68],
                      ),
                    ),
                  ),
                ),
                Stack(
                  children: [
                    // Đệm đều bốn phía cho nút đè góc thẻ vẫn nằm trong khung
                    // Stack: phần lòi ra ngoài khung thì Flutter không nhận
                    // chạm. Đệm đều để thẻ vẫn ở giữa.
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: AgentBotCardView(data: data, width: width),
                    ),
                    // Nút nhỏ đè góc thẻ thay cho một hàng nút riêng: bộ màu
                    // bên trái, khoe bên phải.
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        tooltip: 'Bộ màu thẻ',
                        onPressed: () => showRunCardSkinSheet(
                          context,
                          sample: agentCardData(data),
                        ),
                        icon: const Icon(Icons.palette_outlined, size: 20),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        tooltip: 'Khoe thẻ',
                        onPressed: () => showAgentCardShare(context, data),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Hai nút chat riêng và vào phòng, ngay dưới bậc thẻ: chạy xong xem thẻ lên
/// bậc rồi đi nói chuyện luôn.
class _BotActions extends StatelessWidget {
  const _BotActions({required this.onChat, required this.onRoom});

  final VoidCallback onChat;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final buttonText = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w800);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onChat,
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
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
              backgroundColor: palette.glassStart,
              foregroundColor: palette.ink,
              minimumSize: const Size.fromHeight(52),
              textStyle: buttonText,
              side: BorderSide(color: palette.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.forum_outlined, size: 19),
            label: const Text('Phòng bot'),
          ),
        ),
      ],
    );
  }
}

/// Bậc thẻ hôm nay: km chạy và đi bộ mở được bao nhiêu tin chat và ảnh, chạy
/// thêm bao nhiêu thì thẻ lên bậc. Số và mốc đều lấy từ backend (dmByKm,
/// images), app không giữ bảng mốc, để đổi mốc chỉ cần sửa backend.
class _KmTodayCard extends StatelessWidget {
  const _KmTodayCard({required this.today});

  final AgentToday today;

  /// Thước vẽ tới 10 km; chạy xa hơn thì thước đầy.
  static const _rulerKm = 10;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final images = today.images;
    // perKm 0 là admin tắt thưởng theo km: số tin không đổi theo km nên không
    // nhắc tin.
    final dm = switch (today.dmByKm) {
      final byKm? when byKm.perKm > 0 => byKm,
      _ => null,
    };
    final runKm = today.dmByKm?.runKm ?? images?.runKm ?? 0;
    final tier = agentCardTier(images);
    final tiers = images?.tiers ?? const [];
    // Mốc ảnh kế tiếp là bậc thẻ kế tiếp; backend cũ không có bảng mốc thì
    // không gọi tên bậc.
    final nextTier = images == null || tiers.isEmpty || images.nextKm == null
        ? null
        : agentCardTierAt(agentTiersReached(images) + 1, tiers.length);
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
                const Expanded(child: _Caps('Bậc thẻ hôm nay')),
                Text(
                  tier == AgentCardTier.common
                      ? 'Đếm lại lúc 0h'
                      : 'Về Thường lúc 0h',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            // Số km, số tin và số ảnh đã ở mặt trước thẻ ngay trên; thẻ này
            // chỉ nói bậc và chạy thêm bao nhiêu để lên bậc.
            const SizedBox(height: 14),
            if (images != null && tiers.isNotEmpty)
              _TierTrack(images: images)
            else
              _KmRuler(
                palette: palette,
                runKm: runKm,
                maxKm: _rulerKm,
                nextKm: dm?.nextKm ?? images?.nextKm,
              ),
            for (final hint in _hints(dm, images, nextTier)) ...[
              const SizedBox(height: 10),
              hint,
            ],
          ],
        ),
      ),
    );
  }

  /// Mốc tin và mốc ảnh cùng km thì gộp một dòng; hết cả hai thì một dòng báo
  /// đã mở hết.
  List<Widget> _hints(
    AgentDMByKm? dm,
    AgentImagesToday? images,
    AgentCardTier? nextTier,
  ) {
    final dmNext = dm?.nextKm;
    final moreDm = (dm?.nextMax ?? 0) - today.dmMax;
    final imageNext = images?.nextKm;
    final moreImages = (images?.nextLimit ?? 0) - (images?.limit ?? 0);
    final up = nextTier == null ? '' : ' thẻ lên ${nextTier.label},';
    if (dmNext != null && dmNext == imageNext) {
      return [
        _KmHint(
          runKm: dm!.runKm,
          nextKm: dmNext,
          rest: ' để$up mở thêm $moreDm tin và $moreImages ảnh.',
        ),
      ];
    }
    final hints = [
      if (dmNext != null)
        _KmHint(
          runKm: dm!.runKm,
          nextKm: dmNext,
          rest: ' để mở thêm $moreDm tin.',
        ),
      if (imageNext != null)
        _KmHint(
          runKm: images!.runKm,
          nextKm: imageNext,
          rest: ' để$up vẽ thêm $moreImages ảnh.',
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

/// Đường mốc trong ngày: 0 km rồi từng mốc backend gửi, mỗi nút là một bậc
/// thẻ, cách đều nhau (không theo tỉ lệ km) để tên bậc không chen nhau. Phần
/// đã chạy tô màu, tới giữa hai mốc thì tô theo tỉ lệ km.
class _TierTrack extends StatelessWidget {
  const _TierTrack({required this.images});

  final AgentImagesToday images;

  static const _node = 22.0;

  /// Nút của bậc kế tiếp to hơn và có vòng sáng: đó là đích đang chạy tới.
  static const _nextNode = 28.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final tiers = images.tiers;
    final kms = [0.0, for (final t in tiers) t.km];
    final reached = agentTiersReached(images);
    final next = reached < tiers.length ? reached + 1 : null;
    // Vị trí đã chạy tính theo số nút: qua r mốc, đi thêm một phần đoạn kế.
    final position = next == null
        ? tiers.length.toDouble()
        : reached +
              ((images.runKm - kms[reached]) /
                      (kms[reached + 1] - kms[reached]))
                  .clamp(0.0, 1.0);
    final count = kms.length;
    return LayoutBuilder(
      builder: (context, box) {
        final cell = box.maxWidth / count;
        double x(double at) => cell * (at + 0.5);
        double size(int i) => i == next ? _nextNode : _node;
        return Column(
          children: [
            SizedBox(
              height: _nextNode,
              child: Stack(
                children: [
                  Positioned(
                    left: x(0),
                    width: x(count - 1.0) - x(0),
                    top: _nextNode / 2 - 3,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: x(0),
                    width: x(position) - x(0),
                    top: _nextNode / 2 - 3,
                    height: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          colors: [palette.tertiary, palette.accent],
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < count; i++)
                    Positioned(
                      left: x(i.toDouble()) - size(i) / 2,
                      top: (_nextNode - size(i)) / 2,
                      child: _TrackNode(
                        tier: agentCardTierAt(i, tiers.length),
                        next: i == next,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${formatAgentKm(kms[i])} km',
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            text: agentCardTierAt(i, tiers.length).label,
                            children: [
                              // Mốc đã qua có dấu tích; 0 km không phải mốc.
                              // Vẽ bằng icon vì Exo 2 không có glyph ✓.
                              if (i > 0 && i <= reached)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 2),
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 13,
                                      color: palette.ink,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          style: TextStyle(
                            color: i == next
                                ? _tierInk(
                                    agentCardTierAt(i, tiers.length),
                                    palette,
                                  )
                                : palette.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Màu tên bậc: màu đá của bậc trên nền tối, bản đậm hơn trên nền sáng để
/// còn đọc được.
Color _tierInk(AgentCardTier tier, RunNowPalette palette) {
  final light = palette.appearance == RunNowAppearance.light;
  return switch (tier) {
    AgentCardTier.common => palette.ink,
    AgentCardTier.silver =>
      light ? RunNowGameTokens.silverDeep : RunNowGameTokens.gemSilver,
    AgentCardTier.gold =>
      light ? RunNowGameTokens.goldEdge : RunNowGameTokens.sunMid,
    AgentCardTier.foil =>
      light ? RunNowBotCardTokens.foilInk : RunNowBotCardTokens.foilPink,
  };
}

/// Nút mốc tô bằng chất liệu khung thẻ của bậc đó, để đường mốc đọc như dãy
/// thẻ sẽ mở.
class _TrackNode extends StatelessWidget {
  const _TrackNode({required this.tier, required this.next});

  final AgentCardTier tier;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final t = gameCardTiers[tier.material]!;
    final size = next ? _TierTrack._nextNode : _TierTrack._node;
    final foil = tier == AgentCardTier.foil;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Khung Foil là vàng, ánh cầu vồng nằm ở lớp holo phủ lên thẻ; nút
        // nhỏ không có lớp đó nên vẽ thẳng cầu vồng.
        gradient: foil
            ? const SweepGradient(
                colors: [
                  RunNowGameTokens.gold,
                  RunNowBotCardTokens.foilSky,
                  RunNowBotCardTokens.foilPink,
                  RunNowGameTokens.gold,
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: t.frame,
                stops: t.frameStops,
              ),
        border: Border.all(color: palette.glassStart, width: 2),
        boxShadow: next
            ? [
                BoxShadow(
                  color: (foil ? RunNowBotCardTokens.foilPink : t.gem)
                      .withValues(alpha: 0.35),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
    );
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

/// Quả cầu robot trên thẻ tạo bot và khung chờ tải.
class _BotOrb extends StatelessWidget {
  const _BotOrb({required this.palette, required this.size});

  final RunNowPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ring = size * 0.06;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            palette.accent,
            palette.tertiary.withValues(alpha: 0.2),
            palette.accent,
          ],
        ),
        boxShadow: [
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
          gradient: LinearGradient(
            colors: [palette.tertiary, palette.accentDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: palette.tint, width: ring * 0.8),
        ),
        child: Icon(
          Icons.smart_toy_rounded,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
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
                const Expanded(child: _Caps('Phòng bot đang nói')),
                if (bots.isNotEmpty) ...[
                  _AvatarStack(names: bots),
                  const SizedBox(width: 8),
                  Text(
                    '${bots.length} bot',
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
                  Expanded(child: Text('Vào phòng xem tiếp')),
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
    final palette = context.runNowPalette;
    final image = ref.watch(agentImageBuilderProvider);
    // Dải ảnh dọc như thẻ sưu tập, kéo ngang; ít ảnh nên dựng hết một lần.
    final content = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Container(
              width: 150,
              height: 200,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.tertiary, palette.accentDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: AgentImageTile(
                onTap: onOpen,
                child: image(images[i].path, full: false),
              ),
            ),
          ],
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel(
            'Bộ sưu tập ảnh',
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
/// thì tròn, như trong phòng. Tin bot của mình nằm bên phải, không avatar, tô
/// màu nhấn, như tin mình gửi trong app chat.
class _RoomPreviewLine extends StatelessWidget {
  const _RoomPreviewLine({required this.message, required this.myUid});

  final AgentRoomMessage message;
  final String? myUid;

  /// Avatar 32 cộng khoảng cách 10: bong bóng của mình không vượt quá mép
  /// trái bong bóng người khác.
  static const _indent = 42.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = message.name.trim();
    final mine = message.fromAgent && message.uid == myUid;
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: mine ? palette.tint : palette.ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(mine ? 14 : 4),
          topRight: Radius.circular(mine ? 4 : 14),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
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
    );
    if (mine) {
      return Padding(
        padding: const EdgeInsets.only(left: _indent),
        child: Align(alignment: Alignment.centerRight, child: bubble),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: message.fromAgent ? palette.ink : palette.accentDeep,
            borderRadius: BorderRadius.circular(message.fromAgent ? 10 : 16),
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
        const SizedBox(width: _indent - 32),
        Expanded(child: bubble),
      ],
    );
  }
}

/// Bộ nhớ ở tab: đếm mục so với trần, các mục thành chip, chạm chip để sửa
/// hay xoá. Chỉ hiện vài mục đầu, còn lại ở trang đầy đủ.
class _MemoryPreviewCard extends StatelessWidget {
  const _MemoryPreviewCard({
    required this.name,
    required this.memories,
    required this.limit,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onSeeAll,
  });

  /// Tên bot, cho tiêu đề "Cú Mèo biết về bạn".
  final String name;
  final List<AgentMemory> memories;
  final int limit;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<AgentMemory> onEdit;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final full = memories.length >= limit;
    final chipText = const TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _Caps('$name biết về bạn')),
                const SizedBox(width: 8),
                Text(
                  '${memories.length}/$limit',
                  style: TextStyle(
                    color: palette.accentDeep,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: limit <= 0 ? 0 : (memories.length / limit).clamp(0, 1),
                minHeight: 5,
                color: palette.accent,
                backgroundColor: palette.ink.withValues(alpha: 0.08),
              ),
            ),
            const SizedBox(height: 12),
            if (memories.isEmpty) ...[
              Text(
                'Chưa có gì. Kể cho bot trong Chat riêng.',
                style: TextStyle(color: palette.textMuted),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in memories.take(_previewCount))
                  _Chip(
                    onTap: busy ? null : () => onEdit(m),
                    color: palette.ink.withValues(alpha: 0.06),
                    child: Text(
                      m.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: chipText,
                    ),
                  ),
                if (memories.length > _previewCount)
                  _Chip(
                    onTap: onSeeAll,
                    color: palette.ink.withValues(alpha: 0.06),
                    child: Text(
                      'Xem tất cả',
                      style: chipText.copyWith(
                        color: palette.accentDeep,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                _Chip(
                  onTap: busy || full ? null : onAdd,
                  dashed: palette.accent,
                  child: Text(
                    full ? 'Bộ nhớ đã đầy ($limit mục)' : '+ Dạy thêm',
                    style: chipText.copyWith(
                      color: full ? palette.textMuted : palette.accentDeep,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip bấm được của thẻ bộ nhớ: nền đặc cho mục nhớ, viền nét đứt cho việc
/// thêm mục.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.child,
    required this.onTap,
    this.color,
    this.dashed,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  /// Màu viền nét đứt; null là không viền.
  final Color? dashed;

  @override
  Widget build(BuildContext context) {
    final dashed = this.dashed;
    final radius = BorderRadius.circular(12);
    final chip = Material(
      color: color ?? Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: child,
        ),
      ),
    );
    if (dashed == null) return chip;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(color: dashed, radius: 12),
      child: chip,
    );
  }
}

/// Viền nét đứt bo góc; Flutter không có sẵn kiểu viền này.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in border.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Bộ nhớ ở trang đầy đủ: mọi mục, mỗi mục có nút xoá riêng, chạm vào mục để
/// sửa.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memories,
    required this.limit,
    required this.busy,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AgentMemory> memories;
  final int limit;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<AgentMemory> onEdit;
  final ValueChanged<AgentMemory> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final full = memories.length >= limit;
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
              action: IconButton(
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

/// Điều bot tự học về chủ, kèm nút Quên từng điều. Ở tab, thẻ này gom luôn các
/// cài đặt của bot: công tắc tự học, bot biết gì về nhóm, người đã chặn.
class _LearnedCard extends StatelessWidget {
  const _LearnedCard({
    required this.learned,
    required this.busy,
    required this.onForget,
    this.learning = true,
    this.onLearning,
    this.onSeeAll,
    this.onGroupFacts,
    this.onBlocks,
  });

  final List<AgentLearnedFact> learned;
  final bool busy;
  final ValueChanged<AgentLearnedFact> onForget;
  final bool learning;

  /// Có thì hiện công tắc tự học ở đầu thẻ (chỉ ở tab, không ở trang đầy đủ).
  final ValueChanged<bool>? onLearning;

  /// Có khi tab chỉ hiện vài điều đầu: mở trang đủ điều đã học.
  final VoidCallback? onSeeAll;
  final VoidCallback? onGroupFacts;
  final VoidCallback? onBlocks;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSeeAll = this.onSeeAll;
    final onGroupFacts = this.onGroupFacts;
    final onBlocks = this.onBlocks;
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
          if (onSeeAll != null) ...[
            const _RowDivider(),
            _LinkRow(
              icon: Icons.list_rounded,
              text: 'Xem tất cả điều bot đã học',
              onTap: onSeeAll,
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
          if (onBlocks != null) ...[
            const _RowDivider(),
            _LinkRow(
              icon: Icons.block_rounded,
              text: 'Người đã chặn',
              onTap: onBlocks,
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
  const _SectionLabel(this.text, {this.icon, this.onSeeAll});

  final String text;
  final IconData? icon;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSeeAll = this.onSeeAll;
    final icon = this.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: palette.accentDeep),
            const SizedBox(width: 6),
          ],
          // Nhãn chiếm hết phần còn lại để "Xem tất cả" sát mép phải.
          // Flexible cạnh Spacer thì hai bên chia đôi chỗ trống, phần
          // Flexible không dùng bị bỏ thừa ở cuối hàng.
          Expanded(child: _Caps(text)),
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
