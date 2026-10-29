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
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/games/game_my_card.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/games/telegram_link_section.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
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
  final _nightTheme = gameNightTheme();
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
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _telegram]),
      builder: (context, _) {
        final palette = context.runNowPalette;
        final detail = _controller.detail;
        final me = _controller.me;
        // Vai của cả ván chỉ có trong /me sau khi ván kết thúc.
        final reveals = <String, GameRoleReveal>{
          for (final r in me?.allRoles ?? const []) r.uid: r,
        };
        final kmTable = detail?.kmTable;
        final myPlayer = detail?.players
            .where((p) => p.uid == myUid)
            .firstOrNull;
        return Scaffold(
          appBar: AppBar(title: Text(detail?.title ?? 'Ma Sói')),
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
                      // Cảnh đêm/ngày của ván là tranh như lá bài, nên
                      // giữ tông đêm; phần còn lại theo theme của app.
                      Theme(
                        data: _nightTheme,
                        child: _Header(
                          detail: detail,
                          closing: _controller.phaseClosing,
                          serverNow: _controller.serverNow,
                        ),
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
                      if (_faceUp && me != null && me.actions.isNotEmpty) ...[
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
                      if (kmTable != null && myPlayer != null) ...[
                        const SizedBox(height: 16),
                        GameMyKmCard(table: kmTable, player: myPlayer),
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
                      if (detail.isAdmin && detail.status == 'registering') ...[
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
                      if (detail.players.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionTitle(
                          'Người chơi',
                          trailing: detail.status == 'registering'
                              ? '${detail.players.length} người'
                              : '${detail.players.where((p) => p.alive).length}'
                                    ' còn sống / ${detail.players.length}',
                        ),
                        _Players(
                          players: detail.players,
                          reveals: reveals,
                          kmTable: kmTable,
                          myUid: myUid,
                        ),
                        if (kmTable != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                            child: Text(
                              'Số nhạt là chưa tới mốc '
                              '${gameKmUnitText(kmTable.unitKm)} km.',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 20),
                      const _SectionTitle('Diễn biến'),
                      _Feed(
                        items: _controller.feedItems,
                        hasOlder: _controller.hasOlderFeed,
                        loadingOlder: _controller.loadingOlder,
                        onLoadOlder: _loadOlder,
                      ),
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
        );
      },
    );
  }
}

final _timeFormat = DateFormat('HH:mm dd/MM');

/// Các bước trong một ngày của ván, theo phase của backend
/// (`werewolf/state.go`): đêm 22h, rạng sáng 0h, đề cử 10h, biểu quyết 20h.
const _phaseSteps = [
  ('night', 'Đêm'),
  ('dawn', 'Rạng sáng'),
  ('day', 'Đề cử'),
  ('trial', 'Biểu quyết'),
];

/// Tên phase trong key `r3/day` hay `r3/night/hunter`.
String _phaseName(String key) {
  final parts = key.split('/');
  return parts.length > 1 ? parts[1] : key;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.detail,
    required this.closing,
    required this.serverNow,
  });

  final GameDetail detail;
  final bool closing;
  final DateTime Function() serverNow;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final phase = detail.phase;
    final deadline = phase?.deadline;
    final startError = detail.startError;
    final step = phase == null
        ? -1
        : _phaseSteps.indexWhere((s) => s.$1 == _phaseName(phase.key));
    // Đề cử và biểu quyết diễn ra ban ngày; còn lại (kể cả chưa chạy) là đêm.
    final day = step >= 2;
    return GlassPanel(
      gradient: LinearGradient(
        begin: const Alignment(-0.4, -1),
        end: const Alignment(0.4, 1),
        colors: day
            ? const [
                RunNowGameTokens.dayTop,
                RunNowGameTokens.dayMid,
                RunNowGameTokens.dayBottom,
              ]
            : const [
                RunNowGameTokens.heroTop,
                RunNowGameTokens.heroMid,
                RunNowGameTokens.heroBottom,
              ],
        stops: day ? const [0, 0.55, 1] : const [0, 0.6, 1],
      ),
      border: Border.all(
        color: day ? RunNowGameTokens.dayBorder : RunNowGameTokens.heroBorder,
      ),
      child: Stack(
        children: [
          Positioned(
            right: 18,
            top: 16,
            child: day
                ? const GameSun(size: 44, glow: 40)
                : const GameMoon(size: 40, glow: 36),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 56),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _FoilChip(label: detail.statusLabel),
                      if (detail.testMode)
                        _Chip(label: 'Ván thử', color: palette.textMuted),
                    ],
                  ),
                ),
                if (phase != null) ...[
                  const SizedBox(height: 12),
                  // Qua hạn thì không hiện phase cũ như còn mở.
                  Padding(
                    padding: const EdgeInsets.only(right: 56),
                    child: Text(
                      closing ? 'Đang chốt…' : phase.label,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  if (!closing && deadline != null)
                    _Deadline(deadline: deadline, serverNow: serverNow),
                  if (step >= 0) ...[
                    const SizedBox(height: 16),
                    _PhaseSteps(current: step),
                  ],
                ],
                if (detail.winnerLabel != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    detail.winnerLabel!,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.accent,
                    ),
                  ),
                ],
                if (startError != null && detail.status == 'registering') ...[
                  const SizedBox(height: 12),
                  Text(
                    startError.message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hạn của phase kèm thời gian còn lại, đếm theo giờ server.
class _Deadline extends StatefulWidget {
  const _Deadline({required this.deadline, required this.serverNow});

  final DateTime deadline;
  final DateTime Function() serverNow;

  @override
  State<_Deadline> createState() => _DeadlineState();
}

class _DeadlineState extends State<_Deadline> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.serverNow();
    final local = widget.deadline.toLocal();
    final sameDay = DateUtils.isSameDay(local, now.toLocal());
    final at = DateFormat(sameDay ? 'HH:mm' : 'HH:mm dd/MM').format(local);
    final left = widget.deadline.difference(now);
    final String remaining;
    if (left.inMinutes >= 60) {
      final minutes = left.inMinutes % 60;
      remaining =
          'còn ${left.inHours} giờ${minutes == 0 ? '' : ' $minutes phút'}';
    } else if (left.inMinutes >= 1) {
      remaining = 'còn ${left.inMinutes} phút';
    } else {
      remaining = 'sắp hết giờ';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'Hạn $at · $remaining',
        style: const TextStyle(fontSize: 14, color: RunNowGameTokens.heroSub),
      ),
    );
  }
}

/// Thanh bước của một ngày: bước đã qua sáng nhạt, bước hiện tại vàng.
class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        for (var i = 0; i < _phaseSteps.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i == current
                        ? null
                        : Theme.of(context).colorScheme.onSurface.withValues(
                            alpha: i < current ? 0.35 : 0.12,
                          ),
                    gradient: i == current
                        ? const LinearGradient(
                            colors: [
                              RunNowGameTokens.goldDeep,
                              RunNowGameTokens.goldPale,
                            ],
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _phaseSteps[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == current
                        ? FontWeight.w800
                        : FontWeight.w400,
                    color: i == current ? palette.accent : palette.textMuted,
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

/// Chip trạng thái ván, nền vàng foil như viền lá bài.
class _FoilChip extends StatelessWidget {
  const _FoilChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: gameNightFoil,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: RunNowGameTokens.onGold,
        ),
      ),
    );
  }
}

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
    final palette = context.runNowPalette;
    final deadline = detail.registrationDeadline;
    final ready = detail.requirements.every((r) => r.ok);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      border: Border.all(color: palette.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${detail.playerCount} người đã đăng ký · cần '
            '${detail.minPlayers}–${detail.maxPlayers}',
            style: TextStyle(fontWeight: FontWeight.w700, color: palette.ink),
          ),
          if (deadline != null)
            Text(
              'Đóng đăng ký ${_timeFormat.format(deadline.toLocal())}',
              style: TextStyle(color: palette.textMuted),
            ),
          if (!detail.isRegistered)
            for (final requirement in detail.requirements)
              _RequirementRow(requirement: requirement, onOpenUrl: onOpenUrl),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: detail.isRegistered
                ? OutlinedButton(
                    onPressed: busy ? null : onToggle,
                    child: const Text('Huỷ đăng ký'),
                  )
                : FilledButton(
                    onPressed: busy || !ready ? null : onToggle,
                    child: const Text('Đăng ký'),
                  ),
          ),
        ],
      ),
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

/// Bảng người chơi trong một khung: cột tên và cột km. Có [kmTable] thì hai
/// cột km (chốt 22h và tới giờ), chưa có thì một cột km chốt như cũ.
class _Players extends StatelessWidget {
  const _Players({
    required this.players,
    required this.reveals,
    required this.kmTable,
    required this.myUid,
  });

  final List<GamePlayer> players;
  final Map<String, GameRoleReveal> reveals;
  final GameKmTable? kmTable;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final table = kmTable;
    // Đầu cột ngắn: chỉ phần trước " · " (Hôm qua, Hôm nay).
    String short(String label) => label.split(' · ').first;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      border: Border.all(color: palette.border),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Tên',
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                ),
                if (table == null)
                  _KmHead('Km chốt', width: _kmColumnWidth + 8)
                else ...[
                  _KmHead(short(table.lastLabel)),
                  _KmHead(short(table.todayLabel), today: true),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 4),
          for (final player in _ranked(players, table != null))
            _PlayerRow(
              player: player,
              reveal: reveals[player.uid],
              kmTable: table,
              isMe: player.uid == myUid,
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Xếp người còn sống theo km từ cao xuống thấp, người chết xuống cuối. Có
/// bảng km thì xếp theo km đang gom hôm nay, vì đó là số sẽ chốt lúc 22h cho
/// biểu quyết và kỹ năng đêm; bằng nhau thì xét km chốt hôm qua. Chưa có bảng
/// thì xếp theo km chốt. Cùng số thì giữ thứ tự backend gửi.
List<GamePlayer> _ranked(List<GamePlayer> players, bool live) {
  double km(double? value) => value ?? -1;
  int byKm(GamePlayer a, GamePlayer b) {
    if (a.alive != b.alive) return a.alive ? -1 : 1;
    if (!a.alive) return 0;
    final first = live
        ? km(b.todayKm).compareTo(km(a.todayKm))
        : km(b.lastKm).compareTo(km(a.lastKm));
    if (first != 0 || !live) return first;
    return km(b.lastKm).compareTo(km(a.lastKm));
  }

  // List.sort không giữ thứ tự cho phần tử bằng nhau, nên so thêm vị trí gốc.
  final indexed = players.indexed.toList()
    ..sort((a, b) {
      final order = byKm(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return [for (final (_, player) in indexed) player];
}

class _KmHead extends StatelessWidget {
  const _KmHead(this.text, {this.today = false, this.width = _kmColumnWidth});

  final String text;
  final bool today;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 12,
          fontWeight: today ? FontWeight.w800 : FontWeight.w400,
          color: today ? palette.accent : palette.textMuted,
        ),
      ),
    );
  }
}

const _kmColumnWidth = 60.0;

/// Một ô km của dòng người chơi: đậm khi đạt mốc, nhạt khi chưa.
class _PlayerKm extends StatelessWidget {
  const _PlayerKm({
    required this.km,
    required this.unitKm,
    this.today = false,
    this.width = _kmColumnWidth,
  });

  final double? km;
  final double unitKm;
  final bool today;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final km = this.km;
    final reached = km != null && gameKmMissing(km, unitKm) == null;
    return SizedBox(
      width: width,
      child: Text(
        km == null ? '—' : gameKmText(km),
        textAlign: TextAlign.right,
        style: TextStyle(
          fontSize: 14,
          fontWeight: !reached
              ? FontWeight.w400
              : today
              ? FontWeight.w800
              : FontWeight.w700,
          color: !reached
              ? palette.textMuted
              : today
              ? palette.accent
              : palette.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.reveal,
    this.kmTable,
    this.isMe = false,
  });

  final GamePlayer player;
  final GameRoleReveal? reveal;

  /// Có bảng km thì hai cột km; chưa có thì một cột km chốt.
  final GameKmTable? kmTable;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final avatar = player.avatarUrl;
    final roleLabel = player.revealedRoleLabel ?? reveal?.roleLabel;
    final cardUrl = player.revealedCardUrl ?? reveal?.cardUrl;
    final table = kmTable;
    final danger = Theme.of(context).colorScheme.error;
    final details = [
      if (isMe) 'Bạn',
      if (player.onTrial) 'Lên giàn',
      if (!player.alive)
        player.deathRound == null
            ? 'Đã chết'
            : 'Chết vòng ${player.deathRound}',
      ?roleLabel,
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe ? palette.accent.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: player.alive ? 1 : 0.55,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isMe
                            ? palette.accent.withValues(alpha: 0.55)
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.14),
                      ),
                    ),
                    child: CircleAvatar(
                      // Mọi avatar một tông kính; riêng mình nhấn màu hành.
                      backgroundColor: isMe
                          ? palette.accent.withValues(alpha: 0.16)
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.07),
                      foregroundColor: isMe ? palette.accent : palette.ink,
                      backgroundImage: avatar == null
                          ? null
                          : cachedAvatarImage(context, avatar, 34),
                      child: avatar == null
                          ? Text(
                              player.name.isEmpty
                                  ? '?'
                                  : player.name[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                            decoration: player.alive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        if (details.isNotEmpty)
                          Text(
                            details.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: player.onTrial
                                  ? danger
                                  : isMe
                                  ? palette.accent
                                  : palette.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (cardUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.network(
                          cardUrl,
                          width: 28,
                          height: 39,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Người chết không còn tính km, kể cả km đã chốt.
          if (table == null)
            _PlayerKm(
              km: player.alive ? player.lastKm : null,
              unitKm: 1,
              width: _kmColumnWidth + 8,
            )
          else ...[
            _PlayerKm(
              km: player.alive ? player.lastKm : null,
              unitKm: table.unitKm,
            ),
            _PlayerKm(
              km: player.alive ? player.todayKm : null,
              unitKm: table.unitKm,
              today: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({
    required this.items,
    required this.hasOlder,
    required this.loadingOlder,
    required this.onLoadOlder,
  });

  final List<GameFeedItem> items;
  final bool hasOlder;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    if (items.isEmpty) {
      return Text('Chưa có gì.', style: TextStyle(color: palette.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          GlassPanel(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: Border.all(color: palette.border),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                if (item.at != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      _timeFormat.format(item.at!.toLocal()),
                      style: TextStyle(fontSize: 12, color: palette.textMuted),
                    ),
                  ),
                for (final line in item.lines)
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: palette.ink,
                    ),
                  ),
              ],
            ),
          ),
        if (hasOlder)
          Center(
            child: TextButton(
              onPressed: loadingOlder ? null : onLoadOlder,
              child: Text(loadingOlder ? 'Đang tải…' : 'Xem cũ hơn'),
            ),
          ),
      ],
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
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
