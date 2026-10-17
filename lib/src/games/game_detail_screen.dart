import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_detail_controller.dart';
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
  bool _registering = false;
  bool _starting = false;
  bool? _linked;

  @override
  void initState() {
    super.initState();
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
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
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

  Future<void> _openRequirement(String url) async {
    final open =
        widget.openUrl ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    if (await open(Uri.parse(url)) || !mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return ListenableBuilder(
      listenable: Listenable.merge([_controller, _telegram]),
      builder: (context, _) {
        final detail = _controller.detail;
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            title: Text(detail?.title ?? 'Ma Sói'),
            backgroundColor: palette.background,
            elevation: 0,
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
                      if (_controller.error != null) const _StaleBanner(),
                      _Header(
                        detail: detail,
                        closing: _controller.phaseClosing,
                      ),
                      if (detail.status == 'registering' ||
                          detail.isRegistered) ...[
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
                          onOpenUrl: _openRequirement,
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
                      if (detail.rulesText.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _Rules(text: detail.rulesText),
                      ],
                      if (detail.players.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionTitle('Người chơi (${detail.players.length})'),
                        for (final player in detail.players)
                          _PlayerRow(player: player),
                      ],
                      const SizedBox(height: 20),
                      const _SectionTitle('Diễn biến'),
                      _Feed(
                        items: _controller.feedItems,
                        hasOlder: _controller.hasOlderFeed,
                        loadingOlder: _controller.loadingOlder,
                        onLoadOlder: _loadOlder,
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

final _timeFormat = DateFormat('HH:mm dd/MM');

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.closing});

  final GameDetail detail;
  final bool closing;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final phase = detail.phase;
    final deadline = phase?.deadline;
    final startError = detail.startError;
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Chip(label: detail.statusLabel, color: palette.accent),
              if (detail.testMode)
                _Chip(label: 'Ván thử', color: palette.textMuted),
            ],
          ),
          if (phase != null) ...[
            const SizedBox(height: 12),
            // Qua hạn thì không hiện phase cũ như còn mở.
            Text(
              closing ? 'Đang chốt…' : phase.label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
            if (!closing && deadline != null)
              Text(
                'Hạn ${_timeFormat.format(deadline.toLocal())}',
                style: TextStyle(color: palette.textMuted),
              ),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
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

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final GamePlayer player;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final avatar = player.avatarUrl;
    final details = [
      if (!player.alive)
        player.deathRound == null
            ? 'Đã chết'
            : 'Chết vòng ${player.deathRound}',
      ?player.revealedRoleLabel,
      if (player.lastKm != null) '${player.lastKm!.toStringAsFixed(1)} km',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Opacity(
            opacity: player.alive ? 1 : 0.4,
            child: CircleAvatar(
              radius: 18,
              backgroundImage: avatar == null
                  ? null
                  : cachedAvatarImage(context, avatar, 36),
              child: avatar == null
                  ? Text(
                      player.name.isEmpty ? '?' : player.name[0].toUpperCase(),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: TextStyle(
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
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
              ],
            ),
          ),
          if (player.onTrial)
            _Chip(
              label: 'Lên giàn',
              color: Theme.of(context).colorScheme.error,
            ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                if (item.at != null)
                  Text(
                    _timeFormat.format(item.at!.toLocal()),
                    style: TextStyle(fontSize: 12, color: palette.textMuted),
                  ),
                for (final line in item.lines) Text(line),
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
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
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
