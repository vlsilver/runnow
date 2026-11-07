import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_action_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_detail_controller.dart';
import 'package:myrun/src/games/game_ended.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_journal.dart';
import 'package:myrun/src/games/game_my_card.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/games/game_skill_cards.dart';
import 'package:myrun/src/games/game_village.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/games/telegram_link_section.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
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
  final _theme = gameMoonlitTheme();
  bool _registering = false;
  bool _starting = false;
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

  @override
  void initState() {
    super.initState();
    ref.listenManual(firebaseUserProvider.select((user) => user.value?.uid), (
      _,
      uid,
    ) {
      if (uid != null) unawaited(_loadReveal(uid));
    }, fireImmediately: true);
    _controller = GameDetailController(
      api: ref.read(runNowApiClientProvider),
      gameId: widget.gameId,
      clock: widget.clock,
    );
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

  /// Chạy dryRun trước để admin thấy ai sẽ bị loại, đồng ý rồi mới Start.
  Future<void> _start() async {
    final api = ref.read(runNowApiClientProvider);
    setState(() => _starting = true);
    try {
      final preview = await api.previewGameStart(widget.gameId);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _StartPreviewDialog(preview: preview),
      );
      if (confirmed != true) return;
      await api.startGame(widget.gameId);
      await _controller.refresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _starting = false);
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
    return Theme(
      data: _theme,
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
                title: Text(detail?.title ?? 'Ma Sói'),
                actions: [
                  if (detail != null && detail.setup.isNotEmpty)
                    IconButton(
                      tooltip: 'Thiết lập ván',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () =>
                          showGameSetupSheet(context, detail.setup),
                    ),
                ],
              ),
              body: detail == null
                  ? _controller.error == null
                        ? const RunNowLoading(label: 'Đang tải ván')
                        : _LoadError(
                            error: _controller.error!,
                            onRetry: _controller.refresh,
                          )
                  : RefreshIndicator(
                      onRefresh: _controller.refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                        children: [
                          // Giữ chỗ cố định để banner bật tắt không làm các mục
                          // phía dưới đổi vị trí và mất state.
                          _controller.error != null
                              ? const _StaleBanner()
                              : const SizedBox.shrink(),
                          GameHero(
                            detail: detail,
                            rounds: me?.cardRounds ?? 0,
                            closing: _controller.phaseClosing,
                            serverNow: _controller.serverNow,
                          ),
                          if (me != null && me.role != null) ...[
                            const SizedBox(height: 16),
                            GameMyCard(
                              me: me,
                              faceUp: _faceUp,
                              kmTable: kmTable,
                              running: detail.status == 'running',
                              serverNow: _controller.serverNow,
                              card: _cardFor(detail, me, myPlayer),
                              onOpenCard: () => _openCard(detail, me, myPlayer),
                              cardRevealed: _cardRevealed,
                              justRevealed: _justRevealed,
                              onRevealCard: _revealCard,
                              onFlip: () => setState(() {
                                _faceUp = !_faceUp;
                                _justRevealed = false;
                              }),
                              onOpenUrl: _openLink,
                              onOpenChat: (key) {
                                _turnFaceDown();
                                context.push(
                                  '/games/${Uri.encodeComponent(widget.gameId)}'
                                  '/chat/${Uri.encodeComponent(key)}',
                                );
                              },
                            ),
                          ],
                          if (_faceUp &&
                              me != null &&
                              me.actions.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const _SectionTitle('Việc của bạn'),
                            for (final action in me.actions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GameActionCard(
                                  key: ValueKey(action.kind),
                                  action: action,
                                  serverNow: _controller.serverNow,
                                  onSubmit:
                                      ({
                                        targets = const [],
                                        choice,
                                        clear = false,
                                      }) => _submit(
                                        action.kind,
                                        targets: targets,
                                        choice: choice,
                                        clear: clear,
                                      ),
                                ),
                              ),
                          ],
                          if (detail.status == 'registering') ...[
                            const SizedBox(height: 12),
                            TelegramLinkSection(
                              controller: _telegram,
                              onError: _showError,
                            ),
                          ],
                          if (detail.status == 'registering') ...[
                            const SizedBox(height: 12),
                            _Registration(
                              detail: detail,
                              busy: _registering,
                              onToggle: () =>
                                  _toggleRegistration(detail.isRegistered),
                              onOpenUrl: _openLink,
                            ),
                          ],
                          if (detail.isAdmin &&
                              detail.status == 'registering') ...[
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _starting ? null : _start,
                              child: Text(
                                _starting ? 'Đang kiểm tra…' : 'Bắt đầu ván',
                              ),
                            ),
                          ],
                          // Lúc mở đăng ký thì luật nằm ngay dưới nút đăng ký;
                          // ván chạy rồi thì xuống cuối, nhường chỗ cho ván.
                          if (detail.status == 'registering' &&
                              detail.rulesText.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _Rules(text: detail.rulesText),
                          ],
                          if (detail.status == 'registering') ...[
                            if (detail.players.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              _SectionTitle(
                                'ĐÃ VÀO SẢNH',
                                trailing: '${detail.players.length} người',
                              ),
                              GameVillage(
                                players: detail.players,
                                reveals: reveals,
                                table: null,
                                myUid: myUid,
                              ),
                            ],
                          ] else ...[
                            const SizedBox(height: 16),
                            _Tabs(
                              current: _tab,
                              tabs: summary != null
                                  ? [
                                      ('TỔNG KẾT', null),
                                      (
                                        'LẬT BÀI',
                                        '${summary.teams.fold(0, (n, t) => n + t.players.length)}',
                                      ),
                                      ('DIỄN LẠI', null),
                                    ]
                                  : [
                                      (
                                        'LÀNG',
                                        '${detail.players.where((p) => p.alive).length}'
                                            '/${detail.players.length}',
                                      ),
                                      ('NHẬT KÝ', null),
                                    ],
                              onChanged: (tab) => setState(() => _tab = tab),
                            ),
                            const SizedBox(height: 12),
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
                                  const SizedBox(height: 16),
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
                              if (kmTable != null && kmTable.note.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    kmTable.note,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      color: RunNowMoonlitTokens.muted,
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
                              detail.rulesText.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _Rules(text: detail.rulesText),
                          ],
                          if (detail.status != 'registering' &&
                              detail.isRegistered) ...[
                            const SizedBox(height: 12),
                            TelegramLinkSection(
                              controller: _telegram,
                              onError: _showError,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

final _clockFormat = DateFormat('HH:mm');
final _dayFormat = DateFormat('dd/MM');
const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Sảnh đăng ký: số chỗ đã có, giờ đóng, điều kiện vào ván và nút đăng ký.
class _Registration extends StatelessWidget {
  const _Registration({
    required this.detail,
    required this.busy,
    required this.onToggle,
    required this.onOpenUrl,
  });

  final GameDetail detail;
  final bool busy;
  final VoidCallback onToggle;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final deadline = detail.registrationDeadline?.toLocal();
    final requirements = detail.requirements;
    final met = requirements.where((r) => r.ok).length;
    final ready = met == requirements.length;
    final count = detail.playerCount;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _M.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$count',
                            style: const TextStyle(
                              fontSize: 40,
                              color: _M.amberLight,
                            ),
                          ),
                          TextSpan(
                            text: ' / ${detail.maxPlayers} chỗ',
                            style: const TextStyle(
                              fontSize: 18,
                              color: _M.inkSoft,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontFamily: gameTitleFont,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count >= detail.minPlayers
                          ? 'Đủ người để mở ván'
                          : 'Cần ít nhất ${detail.minPlayers} để mở ván',
                      style: const TextStyle(fontSize: 12, color: _M.muted),
                    ),
                  ],
                ),
              ),
              if (deadline != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _clockFormat.format(deadline),
                      style: const TextStyle(
                        fontFamily: gameTitleFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        height: 1,
                        color: _M.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'đóng đăng ký · ${_weekdays[deadline.weekday - 1]} '
                      '${_dayFormat.format(deadline)}',
                      style: const TextStyle(fontSize: 12, color: _M.muted),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Slots(count: count, min: detail.minPlayers, max: detail.maxPlayers),
          if (!detail.isRegistered && requirements.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'ĐỦ ĐIỀU KIỆN $met/${requirements.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: _M.inkSoft,
              ),
            ),
            for (final requirement in requirements)
              _RequirementRow(requirement: requirement, onOpenUrl: onOpenUrl),
          ],
          const SizedBox(height: 16),
          detail.isRegistered
              ? OutlinedButton(
                  onPressed: busy ? null : onToggle,
                  child: const Text('Huỷ đăng ký'),
                )
              : FilledButton(
                  onPressed: busy || !ready ? null : onToggle,
                  child: const Text('Đăng ký'),
                ),
        ],
      ),
    );
  }
}

/// Dải chỗ ngồi: mỗi chỗ một vạch, chỗ đã có người sáng lên, vạch số người
/// tối thiểu nhạt hơn khi chưa đủ.
class _Slots extends StatelessWidget {
  const _Slots({required this.count, required this.min, required this.max});

  final int count;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (max <= 0) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < max; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < count
                    ? null
                    : i < min
                    ? _M.amberLine
                    : _M.track,
                gradient: i < count
                    ? const LinearGradient(
                        colors: [_M.amberDeep, _M.amberBright],
                      )
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      border: Border.all(color: context.runNowPalette.border),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text('Luật chơi'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [SelectableText(text)],
        ),
      ),
    );
  }
}

/// Tab dưới lá bài: Làng và Nhật ký khi ván chạy; Tổng kết, Lật bài, Diễn
/// lại khi ván đã xong và có tổng kết.
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: on ? _M.amberLine : Colors.transparent,
                ),
                gradient: on
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_M.heroTop, _M.heroMid],
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
                      color: on ? _M.amberCream : _M.muted,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? _M.amberStrong : _M.track,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: on ? _M.onAmber : _M.inkSoft,
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
        color: _M.tabBar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _M.border),
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

typedef _M = RunNowMoonlitTokens;

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
class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.requirement, required this.onOpenUrl});

  final GameRequirement requirement;
  final ValueChanged<String> onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final action = requirement.action;
    final url = action?.url;
    final Widget? trailing = switch (action?.type) {
      'open_url' when url != null => TextButton(
        onPressed: () => onOpenUrl(url),
        child: const Text('Mở'),
      ),
      'update_app' when url != null => TextButton(
        onPressed: () => onOpenUrl(url),
        child: const Text('Cập nhật'),
      ),
      _ => null,
    };
    final hint = action?.type == 'update_app' && url == null
        ? _updateHint()
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            requirement.ok
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: requirement.ok ? palette.accent : palette.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(requirement.label, style: TextStyle(color: palette.ink)),
                if (hint != null)
                  Text(
                    hint,
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static String _updateHint() {
    if (kIsWeb) return 'Tải lại trang để lấy bản mới.';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'Cập nhật app trên App Store.',
      TargetPlatform.android => 'Cập nhật app trên Google Play.',
      _ => 'Cập nhật app lên bản mới.',
    };
  }
}

class _StartPreviewDialog extends StatelessWidget {
  const _StartPreviewDialog({required this.preview});

  final GameStartPreview preview;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(preview.canStart ? 'Bắt đầu ván?' : 'Chưa bắt đầu được'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${preview.count} người sẽ chơi, cần '
              '${preview.minPlayers}–${preview.maxPlayers}.',
            ),
            if (preview.willExclude.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Sẽ bị loại:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final excluded in preview.willExclude)
                Text('${excluded.name}: ${excluded.reasonLabel}'),
            ],
          ],
        ),
      ),
      actions: preview.canStart
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Thôi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Bắt đầu'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Đóng'),
              ),
            ],
    );
  }
}
