import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_chat_seen.dart';
import 'package:myrun/src/games/game_detail_controller.dart';
import 'package:myrun/src/games/game_dialog.dart';
import 'package:myrun/src/games/game_ended.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_journal.dart';
import 'package:myrun/src/games/game_lobby.dart';
import 'package:myrun/src/games/game_my_card.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/games/game_invite_share.dart';
import 'package:myrun/src/games/game_rules_page.dart';
import 'package:myrun/src/games/game_village.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/games/telegram_link_section.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:url_launcher/url_launcher.dart';

/// Màn chi tiết một ván Ma Sói. Mọi chữ (trạng thái, phase, luật, feed) lấy
/// từ API, nên đổi nội dung ở backend thì app đổi theo, không cần ra bản mới.
class GameDetailScreen extends ConsumerStatefulWidget {
  const GameDetailScreen({
    super.key,
    required this.gameId,
    this.clock,
    this.openUrl,
  });

  final String gameId;

  /// Đồng hồ của máy; test thay để chạy thời gian giả.
  final DateTime Function()? clock;

  /// Mở deep link Telegram; test thay để không mở trình duyệt.
  final UrlOpener? openUrl;

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen>
    with WidgetsBindingObserver {
  late final GameDetailController _controller;
  late final TelegramLinkController _telegram;
  bool _registering = false;
  bool _starting = false;
  bool _cancelling = false;
  bool _faking = false;
  bool? _linked;

  /// Lá bài úp thì ẩn cả việc của vai. Rời màn (nền, app switcher, mở chat)
  /// thì úp lại, để quay lại không thấy vai đang ngửa.
  bool _faceUp = false;

  /// Thẻ của ván này đã lật trên máy này chưa; null là đang đọc.
  bool? _cardRevealed;

  /// Vừa lật lúc lá đang ngửa thì chạy hiệu ứng lật một lần.
  bool _justRevealed = false;

  /// Tab dưới lá bài: 0 là Làng, 1 là Nhật ký.
  int _tab = 0;

  /// Tin phòng chung máy này đã đọc; null là chưa biết thì không báo tin mới.
  int? _roomSeen;
  bool _roomSeenRequested = false;
  bool _pushAsked = false;

  final _scroll = ScrollController();
  final _heroKey = GlobalKey();
  final _tabsKey = GlobalKey();

  /// Vị trí trong nội dung cuộn, giữ lại vì ListView bỏ widget ở xa màn.
  double? _heroEnd;
  double? _tabsAt;
  bool _collapsed = false;
  bool _tabsStuck = false;

  /// Khoảng từ đỉnh màn tới hàng tab khi tab đang dính.
  static const _stickyOffset = 4.0 + GameHeroBar.height + 8.0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(firebaseUserProvider.select((user) => user.value?.uid), (
      _,
      uid,
    ) {
      if (uid != null) unawaited(_loadReveal(uid));
    }, fireImmediately: true);
    _controller =
        GameDetailController(
            api: ref.read(runNowApiClientProvider),
            gameId: widget.gameId,
            clock: widget.clock,
          )
          ..addListener(_requestRoomSeen)
          ..addListener(_askForPushIfJoined);
    _scroll.addListener(_syncSticky);
    _telegram = TelegramLinkController(
      api: ref.read(runNowApiClientProvider),
      openUrl: widget.openUrl,
    )..addListener(_onTelegramChanged);
    WidgetsBinding.instance.addObserver(this);
    _controller.setActive(true);
    _telegram.load();
  }

  /// Vừa liên kết xong thì requirements của ván đổi: đọc lại ván.
  /// Mở màn lúc đã liên kết sẵn thì không đọc lại.
  void _onTelegramChanged() {
    final linked = _telegram.status?.linked;
    if (linked == null) return;
    if (linked && _linked == false) _controller.refresh();
    _linked = linked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.setActive(true);
        _telegram.onResume();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _controller.setActive(false);
        _turnFaceDown();
      // iOS chụp ảnh màn cho app switcher ngay khi inactive.
      case AppLifecycleState.inactive:
        _turnFaceDown();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Mở chat của ván; bài úp lại để quay về không lộ vai.
  Future<void> _openChat(String key) async {
    _turnFaceDown();
    await context.push(
      '/games/${Uri.encodeComponent(widget.gameId)}'
      '/chat/${Uri.encodeComponent(key)}',
    );
    if (mounted && key == _controller.detail?.room?.key) {
      await _readRoomSeen(key);
    }
  }

  /// Đọc một lần khi đã biết phòng chung và người dùng.
  /// Người vào ván từ bản app chưa biết hỏi quyền thì chưa bao giờ được hỏi.
  void _askForPushIfJoined() {
    final detail = _controller.detail;
    if (detail == null || !detail.isRegistered || detail.status == 'ended') {
      return;
    }
    _askForPush();
  }

  void _askForPush() {
    if (_pushAsked) return;
    _pushAsked = true;
    unawaited(ref.read(pushControllerProvider)?.askAfterJoining());
  }

  void _requestRoomSeen() {
    final key = _controller.detail?.room?.key;
    if (key == null || _roomSeenRequested) return;
    if (ref.read(firebaseUserProvider).value?.uid == null) return;
    _roomSeenRequested = true;
    unawaited(_readRoomSeen(key));
  }

  Future<void> _readRoomSeen(String key) async {
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid == null) return;
    final seen = await ref
        .read(gameChatSeenProvider)
        .seen(uid, widget.gameId, key);
    if (mounted) setState(() => _roomSeen = seen);
  }

  /// Vị trí đầu [box] trong nội dung cuộn, không phụ thuộc đang cuộn tới đâu.
  double _contentY(RenderBox box) =>
      RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;

  void _syncSticky() {
    if (!_scroll.hasClients) return;
    if (_heroKey.currentContext?.findRenderObject() case final RenderBox hero
        when hero.hasSize) {
      _heroEnd = _contentY(hero) + hero.size.height;
    }
    if (_tabsKey.currentContext?.findRenderObject() case final RenderBox tabs
        when tabs.hasSize) {
      _tabsAt = _contentY(tabs);
    }
    final heroEnd = _heroEnd;
    final tabsAt = _tabsAt;
    if (heroEnd == null || tabsAt == null) return;
    final offset = _scroll.offset;
    final stuck = offset >= tabsAt - _stickyOffset;
    final collapsed = stuck || offset >= heroEnd;
    if (stuck != _tabsStuck || collapsed != _collapsed) {
      setState(() {
        _tabsStuck = stuck;
        _collapsed = collapsed;
      });
    }
  }

  /// Đổi tab lúc đang dính thì nội dung mới bắt đầu ngay dưới hàng tab.
  void _selectTab(int tab) {
    setState(() => _tab = tab);
    final tabsAt = _tabsAt;
    if (!_tabsStuck || tabsAt == null) return;
    _scroll.jumpTo(tabsAt - _stickyOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSticky();
    });
  }

  Widget _tabsFor(GameDetail detail, GameSummary? summary) {
    return _Tabs(
      current: _tab,
      tabs: summary != null
          ? [
              ('TỔNG KẾT', null),
              (
                'LẬT BÀI',
                '${summary.teams.fold(0, (n, t) => n + t.players.length)}',
              ),
              ('DIỄN LẠI', _replayBadge(summary)),
            ]
          : [
              (
                'LÀNG',
                '${detail.players.where((p) => p.alive).length}'
                    '/${detail.players.length}',
              ),
              ('NHẬT KÝ', null),
            ],
      onChanged: _selectTab,
    );
  }

  void _turnFaceDown() {
    if (_faceUp && mounted) {
      setState(() {
        _faceUp = false;
        _justRevealed = false;
      });
    }
  }

  Future<void> _loadReveal(String uid) async {
    final revealed = await ref
        .read(gameCardRevealsProvider)
        .revealed(uid, widget.gameId);
    if (mounted) setState(() => _cardRevealed = revealed);
  }

  Future<void> _revealCard() async {
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (uid == null) return;
    setState(() {
      _cardRevealed = true;
      _justRevealed = true;
    });
    try {
      await ref.read(gameCardRevealsProvider).markRevealed(uid, widget.gameId);
    } catch (error) {
      // Không ghi được thì lần sau mở màn lá lại úp, bậc vẫn như cũ.
      debugPrint('Ma Sói: ghi thẻ đã lật lỗi: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _controller.dispose();
    _telegram.dispose();
    super.dispose();
  }

  Future<void> _toggleRegistration(bool registered) async {
    setState(() => _registering = true);
    try {
      if (registered) {
        await _controller.unregister();
      } else {
        await _controller.register();
        _askForPush();
      }
    } catch (error) {
      _showError(error);
      if (error is RunNowApiException && error.code == 'requirements_unmet') {
        await _controller.refresh();
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _submit(
    String kind, {
    List<String> targets = const [],
    String? choice,
    bool clear = false,
  }) async {
    try {
      await _controller.submitAction(
        kind: kind,
        targets: targets,
        choice: choice,
        clear: clear,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openLink(String url) async {
    final open =
        widget.openUrl ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await open(Uri.parse(url));
    } catch (error) {
      // URL rỗng hay sai thì iOS ném PlatformException thay vì trả false.
      debugPrint('Ma Sói: mở $url lỗi: $error');
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Không mở được link.')));
  }

  /// Chạy dryRun trước để chủ ván thấy ai sẽ bị loại, đồng ý rồi mới Start.
  Future<void> _start() async {
    final api = ref.read(runNowApiClientProvider);
    setState(() => _starting = true);
    try {
      final preview = await api.previewGameStart(widget.gameId);
      if (!mounted) return;
      final confirmed = await showGameConfirm(
        context,
        title: preview.startable ? 'Bắt đầu ván?' : 'Chưa bắt đầu được',
        body: _StartPreviewBody(preview: preview),
        confirmLabel: preview.startable ? 'Bắt đầu' : null,
        cancelLabel: preview.startable ? 'Thôi' : 'Đóng',
      );
      if (!confirmed) return;
      await api.startGame(widget.gameId);
      await _controller.refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showGameConfirm(
      context,
      title: 'Huỷ ván này?',
      body: const Text('Huỷ rồi không lấy lại được.'),
      confirmLabel: 'Huỷ ván',
      cancelLabel: 'Thôi',
    );
    if (!confirmed || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(runNowApiClientProvider).cancelGame(widget.gameId);
      await _controller.refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  /// Ván thử: thêm người giả cho đủ số tối thiểu để Start.
  Future<void> _fillFakes(GameDetail detail) async {
    final real = detail.players.where((p) => !p.fake).length;
    setState(() => _faking = true);
    try {
      await ref
          .read(runNowApiClientProvider)
          .setFakePlayers(
            widget.gameId,
            count: (detail.minPlayers - real).clamp(0, detail.maxPlayers),
          );
      await _controller.refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _faking = false);
    }
  }

  Future<void> _loadOlder() async {
    try {
      await _controller.loadOlderFeed();
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

  /// Thẻ Ma Sói của người xem: bậc bốc lúc chia bài, phe thắng giữ thẻ khi
  /// ván kết thúc.
  AchievementCardData _cardFor(
    GameDetail detail,
    GameMe me,
    GamePlayer? player,
  ) => gameCardData(
    GamePlayerCard.fromMe(detail: detail, me: me, player: player),
    owner: player?.name ?? 'Bạn',
  );

  bool _hasTelegramRow(GameDetail detail) =>
      !detail.isRegistered &&
      detail.requirements.any((r) => r.key == gameTelegramRequirement);

  String? _replayBadge(GameSummary summary) {
    final rounds = gameReplayRounds(summary.replay).length;
    return rounds == 0 ? null : '$rounds';
  }

  Future<void> _linkTelegram() async {
    try {
      await _telegram.link();
    } catch (error) {
      _showError(error);
    }
  }

  void _openCard(GameDetail detail, GameMe me, GamePlayer? player) {
    final card = GamePlayerCard.fromMe(detail: detail, me: me, player: player);
    // Ván còn chạy mà mình còn sống thì vai còn bí mật.
    final secret = detail.status != 'ended' && me.alive;
    showGameCardViewer(
      context,
      card: card,
      data: _cardFor(detail, me, player),
      secret: secret,
      chips: [
        detail.statusLabel,
        gameCardTiers[card.tier]!.label,
        if (secret) 'Chỉ mình bạn thấy',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.watch(
      firebaseUserProvider.select((user) => user.value?.uid),
    );
    // Trang ván luôn tông ánh trăng, không theo sáng/tối của app.
    return GameThemed(
      moonlit: true,
      child: ListenableBuilder(
        listenable: Listenable.merge([_controller, _telegram]),
        builder: (context, _) {
          final detail = _controller.detail;
          final me = _controller.me;
          // Vai của cả ván chỉ có trong /me sau khi ván kết thúc.
          final reveals = <String, GameRoleReveal>{
            for (final r in me?.allRoles ?? const []) r.uid: r,
          };
          final kmTable = detail?.kmTable;
          final summary = me?.summary;
          final myPlayer = detail?.players
              .where((p) => p.uid == myUid)
              .firstOrNull;
          return GameMoonlitBackdrop(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text(
                  detail?.title ?? 'Ma Sói',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                actions: [
                  // Ván của user không hiện ở danh sách chung, nên chủ ván
                  // gửi link cho bạn bè vào đăng ký.
                  if (detail != null && detail.status == 'registering')
                    Builder(
                      builder: (context) => _HeaderButton(
                        tooltip: 'Mời bạn',
                        icon: Icons.ios_share_rounded,
                        onPressed: () => showGameInvite(context, detail),
                      ),
                    ),
                  if (detail != null &&
                      detail.status == 'running' &&
                      summary == null)
                    Builder(
                      builder: (context) => _HeaderButton(
                        tooltip: 'Chia sẻ ván',
                        icon: Icons.ios_share_rounded,
                        onPressed: () => showGameLive(context, detail),
                      ),
                    ),
                  if (detail != null && summary != null)
                    Builder(
                      builder: (context) => _HeaderButton(
                        tooltip: 'Chia sẻ tóm tắt',
                        icon: Icons.ios_share_rounded,
                        onPressed: () =>
                            shareGameSummary(context, detail.title, summary),
                      ),
                    ),
                  if (detail?.room case final room?)
                    _HeaderButton(
                      tooltip: room.label,
                      icon: Icons.chat_bubble_outline_rounded,
                      dot: room.latestSeq > (_roomSeen ?? room.latestSeq),
                      onPressed: () => _openChat(room.key),
                    ),
                  if (detail != null && GameRulesPage.hasContent(detail))
                    Builder(
                      builder: (context) => _HeaderButton(
                        tooltip: 'Luật chơi',
                        icon: Icons.info_outline_rounded,
                        onPressed: () => GameRulesPage.open(context, detail),
                      ),
                    ),
                  if (detail != null &&
                      detail.canManage &&
                      detail.status != 'ended' &&
                      detail.status != 'cancelled')
                    _HeaderButton(
                      tooltip: 'Huỷ ván',
                      icon: Icons.cancel_outlined,
                      onPressed: _cancelling ? null : _cancel,
                    ),
                  const SizedBox(width: 16),
                ],
              ),
              body: detail == null
                  ? _controller.error == null
                        ? const RunNowLoading(label: 'Đang tải ván')
                        : _LoadError(
                            error: _controller.error!,
                            onRetry: _controller.refresh,
                          )
                  : Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: _controller.refresh,
                          child: ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                            children: [
                              // Giữ chỗ cố định để banner bật tắt không làm các mục
                              // phía dưới đổi vị trí và mất state.
                              _controller.error != null
                                  ? const _StaleBanner()
                                  : const SizedBox.shrink(),
                              if (detail.status == 'registering')
                                GameLobbyHero(detail: detail)
                              else
                                GameHero(
                                  key: _heroKey,
                                  detail: detail,
                                  subtitle: summary?.subtitle ?? '',
                                  rounds: me?.cardRounds ?? 0,
                                  closing: _controller.phaseClosing,
                                  serverNow: _controller.serverNow,
                                ),
                              if (me != null && me.role != null) ...[
                                const SizedBox(height: 14),
                                GameMyCard(
                                  me: me,
                                  faceUp: _faceUp,
                                  kmTable: kmTable,
                                  running: detail.status == 'running',
                                  serverNow: _controller.serverNow,
                                  onAction: _submit,
                                  card: _cardFor(detail, me, myPlayer),
                                  onOpenCard: () =>
                                      _openCard(detail, me, myPlayer),
                                  cardRevealed: _cardRevealed,
                                  justRevealed: _justRevealed,
                                  onRevealCard: _revealCard,
                                  onFlip: () => setState(() {
                                    _faceUp = !_faceUp;
                                    _justRevealed = false;
                                  }),
                                  onOpenUrl: _openLink,
                                  onOpenChat: _openChat,
                                ),
                              ],
                              if (detail.status == 'registering') ...[
                                if (detail.lobby?.roles case final roles?
                                    when roles.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  GameLobbyRoles(roles: roles),
                                ],
                                if (!detail.isRegistered &&
                                    detail.requirements.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  GameLobbyRequirements(
                                    requirements: detail.requirements,
                                    onOpenUrl: _openLink,
                                    onLinkTelegram:
                                        detail.needsTelegram && !_telegram.busy
                                        ? _linkTelegram
                                        : null,
                                    waitingTelegram: _telegram.waiting,
                                  ),
                                ],
                                if (detail.needsTelegram &&
                                    !_hasTelegramRow(detail))
                                  TelegramLinkSection(
                                    controller: _telegram,
                                    onError: _showError,
                                  ),
                                if (detail.players.isNotEmpty ||
                                    !detail.isRegistered) ...[
                                  const SizedBox(height: 18),
                                  GameLobbyPlayers(
                                    players: detail.players,
                                    myUid: myUid,
                                    showJoinSlot: !detail.isRegistered,
                                    onJoin:
                                        _registering ||
                                            detail.requirements.any(
                                              (r) => !r.ok,
                                            )
                                        ? null
                                        : () => _toggleRegistration(false),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                GameLobbyJoin(
                                  detail: detail,
                                  busy: _registering,
                                  onToggle: () =>
                                      _toggleRegistration(detail.isRegistered),
                                ),
                              ],
                              if (detail.canStart &&
                                  detail.status == 'registering') ...[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed:
                                      _starting ||
                                          detail.playerCount < detail.minPlayers
                                      ? null
                                      : _start,
                                  child: Text(
                                    _starting
                                        ? 'Đang kiểm tra…'
                                        : detail.playerCount < detail.minPlayers
                                        ? 'Bắt đầu ván (${detail.playerCount}/${detail.minPlayers})'
                                        : 'Bắt đầu ván',
                                  ),
                                ),
                              ],
                              if (detail.isAdmin &&
                                  detail.testMode &&
                                  detail.status == 'registering' &&
                                  detail.playerCount < detail.minPlayers) ...[
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: _faking
                                      ? null
                                      : () => _fillFakes(detail),
                                  child: Text(
                                    _faking
                                        ? 'Đang thêm…'
                                        : 'Thêm người giả cho đủ ${detail.minPlayers}',
                                  ),
                                ),
                              ],
                              if (detail.status != 'registering') ...[
                                const SizedBox(height: 14),
                                KeyedSubtree(
                                  key: _tabsKey,
                                  child: _tabsFor(detail, summary),
                                ),
                                const SizedBox(height: 14),
                                if (summary != null)
                                  switch (_tab) {
                                    0 => GameEndedSummary(summary: summary),
                                    1 => GameEndedReveal(teams: summary.teams),
                                    _ => GameReplay(sections: summary.replay),
                                  }
                                else if (_tab == 0) ...[
                                  if (me != null) ...[
                                    GameKmGoals(
                                      goals: me.kmGoals,
                                      faceUp: _faceUp,
                                      table: kmTable,
                                      myKm: myPlayer?.todayKm,
                                    ),
                                    if (me.kmGoals.isNotEmpty)
                                      const SizedBox(height: 14),
                                  ],
                                  _SectionTitle(
                                    'LÀNG',
                                    trailing: kmTable == null
                                        ? null
                                        : 'xếp theo km hôm nay',
                                  ),
                                  GameVillage(
                                    players: detail.players,
                                    reveals: reveals,
                                    table: kmTable,
                                    myUid: myUid,
                                  ),
                                  if (kmTable != null &&
                                      kmTable.note.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        kmTable.note,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.45,
                                          color: context.moonlit.muted,
                                        ),
                                      ),
                                    ),
                                ] else
                                  GameJournal(
                                    items: _controller.feedItems,
                                    hasOlder: _controller.hasOlderFeed,
                                    loadingOlder: _controller.loadingOlder,
                                    onLoadOlder: _loadOlder,
                                  ),
                              ],
                              if (detail.status != 'registering' &&
                                  detail.status != 'ended' &&
                                  detail.isRegistered) ...[
                                TelegramLinkSection(
                                  controller: _telegram,
                                  onError: _showError,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (detail.status != 'registering')
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.topCenter,
                                children: [...previous, ?current],
                              ),
                              child: _collapsed
                                  ? _StickyHeader(
                                      key: const ValueKey('game-sticky-header'),
                                      bar: GameHeroBar(
                                        detail: detail,
                                        rounds: me?.cardRounds ?? 0,
                                        closing: _controller.phaseClosing,
                                        serverNow: _controller.serverNow,
                                      ),
                                      tabs: _tabsStuck
                                          ? _tabsFor(detail, summary)
                                          : null,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Header thu gọn và hàng tab, đè lên nội dung đang cuộn.
class _StickyHeader extends StatelessWidget {
  const _StickyHeader({super.key, required this.bar, required this.tabs});

  final Widget bar;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.moonlit.page.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar,
            if (tabs case final tabs?) ...[const SizedBox(height: 8), tabs],
          ],
        ),
      ),
    );
  }
}

/// Nút vuông trên header ván, [dot] là chấm báo có tin mới.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.dot = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Stack(
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            iconSize: 20,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(44),
              minimumSize: const Size.square(44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: context.moonlit.ink,
              backgroundColor: context.moonlit.heroMid.withValues(alpha: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: context.runNowPalette.radius(12),
                side: BorderSide(color: context.moonlit.border),
              ),
            ),
            icon: Icon(icon),
          ),
          if (dot)
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                label: 'Có tin mới',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: context.runNowPalette.round,
                    color: context.moonlit.amberStrong,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.current,
    required this.tabs,
    required this.onChanged,
  });

  final int current;

  /// Tên tab và số nhỏ kèm theo (như 9/12 người còn sống), null là không có.
  final List<(String, String?)> tabs;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(int index, String label, String? badge) {
      final on = index == current;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(index),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: context.runNowPalette.radius(10),
                border: Border.all(
                  color: on ? context.moonlit.amberLine : Colors.transparent,
                ),
                gradient: on
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          context.moonlit.heroTop,
                          context.moonlit.heroMid,
                        ],
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: gameTitleFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 1.2,
                      color: on
                          ? context.moonlit.amberCream
                          : context.moonlit.muted,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? context.moonlit.amberStrong
                            : context.moonlit.track,
                        borderRadius: context.runNowPalette.radius(999),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: on
                              ? context.moonlit.onAmber
                              : context.moonlit.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.moonlit.tabBar,
        borderRadius: context.runNowPalette.radius(14),
        border: Border.all(color: context.moonlit.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final (i, (label, badge)) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            tab(i, label, badge),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
        ],
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Chưa cập nhật được, đang thử lại…',
        style: TextStyle(color: context.runNowPalette.textMuted),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error is RunNowApiException
                ? (error as RunNowApiException).message
                : 'Không tải được ván.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

/// Một điều kiện đăng ký. Nút theo `action.type` của backend; link_telegram
/// không có nút ở đây vì phần Telegram ngay trên đã có nút liên kết.
class _StartPreviewBody extends StatelessWidget {
  const _StartPreviewBody({required this.preview});

  final GameStartPreview preview;

  @override
  Widget build(BuildContext context) {
    final closed = preview.startClosed;
    return Column(
      children: [
        if (closed != null) ...[
          Text(
            closed,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: context.moonlit.danger),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          '${preview.count}',
          style: TextStyle(
            fontFamily: gameTitleFont,
            fontSize: 64,
            height: 1,
            fontWeight: FontWeight.w800,
            color: preview.canStart
                ? context.moonlit.amberBright
                : context.moonlit.danger,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          preview.canStart
              ? 'người chơi'
              : 'người · cần ${preview.minPlayers}–${preview.maxPlayers}',
          style: TextStyle(fontSize: 13.5, color: context.moonlit.faint),
        ),
        if (preview.willExclude.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.moonlit.well,
              borderRadius: context.runNowPalette.radius(14),
              border: Border.all(color: context.moonlit.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SẼ BỊ LOẠI',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: context.moonlit.faint,
                  ),
                ),
                for (final excluded in preview.willExclude)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            excluded.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.moonlit.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            excluded.reasonLabel,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: context.moonlit.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
