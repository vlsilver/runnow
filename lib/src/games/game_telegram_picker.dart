import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _M = RunNowMoonlitTokens;

/// Bot ván và chỗ đã xác nhận. Lỗi thì [GameTelegramPicker] lùi về ô topic
/// PSC như trước; 404 là backend chưa có bot ván.
final gameTelegramProvider = FutureProvider.autoDispose<GameTelegram>(
  retry: (_, _) => null,
  (ref) => ref.watch(runNowApiClientProvider).gameTelegram(),
);

/// Chọn chỗ ván đăng trong tab Giao tiếp: group PSC (3i đăng, như trước) hay
/// một topic mà bot ván của chủ phòng đã xác nhận. Chỉ topic đã xác nhận mới
/// chọn được, nên chỗ gửi lên luôn là chỗ bot đang ở; backend kiểm lại lúc tạo.
class GameTelegramPicker extends ConsumerStatefulWidget {
  const GameTelegramPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.pscFields,
    required this.enabled,
    this.openUrl,
  });

  /// null là group PSC.
  final GameTelegramTarget? selected;
  final ValueChanged<GameTelegramTarget?> onSelected;

  /// Ô topic PSC, hiện khi chọn PSC hay khi backend chưa có bot ván.
  final List<Widget> pscFields;
  final bool enabled;

  /// Thay launchUrl trong test.
  final Future<bool> Function(Uri uri)? openUrl;

  @override
  ConsumerState<GameTelegramPicker> createState() => _GameTelegramPickerState();
}

class _GameTelegramPickerState extends ConsumerState<GameTelegramPicker>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Tạo bot, mời bot, gõ /van đều làm ở Telegram: quay lại app thì đọc lại.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(gameTelegramProvider);
    }
  }

  Future<void> _open(Future<String> Function() url) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = Uri.tryParse(await url());
      final open =
          widget.openUrl ??
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
      if (uri == null || !await open(uri)) _error = 'Không mở được Telegram.';
    } catch (error) {
      _error = error is RunNowApiException
          ? error.message
          : 'Không kết nối được, thử lại sau.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(gameTelegramProvider);
    final tg = status.value;
    if (tg == null) {
      final failed = status.hasError && !_notFound(status.error);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.pscFields,
          if (failed)
            Align(
              alignment: Alignment.centerLeft,
              child: GameCreateLink(
                'Tải lại bot ván',
                onTap: () => ref.invalidate(gameTelegramProvider),
              ),
            ),
        ],
      );
    }
    final enabled = widget.enabled && !_busy;
    final bot = tg.bot;
    final topics = tg.chats.expand((c) => c.topics).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const GameCreateLabel('Đăng vào'),
        const SizedBox(height: 8),
        _Option(
          label: 'Group PSC',
          selected: widget.selected == null,
          onTap: enabled ? () => widget.onSelected(null) : null,
        ),
        if (widget.selected == null) ...widget.pscFields,
        for (final chat in tg.chats) ...[
          const SizedBox(height: 6),
          _ChatHeader(chat: chat),
          const SizedBox(height: 6),
          for (final topic in chat.topics)
            _Option(
              label: _topicLabel(chat, topic),
              selected:
                  widget.selected ==
                  GameTelegramTarget(
                    chatId: chat.chatId,
                    threadId: topic.threadId,
                  ),
              onTap: enabled && chat.admin
                  ? () => widget.onSelected(
                      GameTelegramTarget(
                        chatId: chat.chatId,
                        threadId: topic.threadId,
                      ),
                    )
                  : null,
            ),
        ],
        const SizedBox(height: 4),
        if (!tg.telegramLinked)
          const GameCreateNote(
            icon: Icons.link_rounded,
            text: 'Liên kết Telegram trong app trước để tạo bot ván.',
          )
        else if (bot == null)
          Align(
            alignment: Alignment.centerLeft,
            child: GameCreateLink(
              'Tạo bot ván',
              onTap: () =>
                  _open(() => ref.read(runNowApiClientProvider).startGameBot()),
            ),
          )
        else ...[
          if (!topics)
            const GameCreateNote(
              icon: Icons.smart_toy_outlined,
              text: 'Mời bot vào group làm admin, rồi gõ /van trong topic.',
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: GameCreateLink(
              'Mời @${bot.username} vào group',
              onTap: () => _open(() async => bot.addUrl),
            ),
          ),
          if (bot.setupError != null)
            const _ErrorText('Bot ván chưa sẵn sàng, thử lại sau.'),
        ],
        if (_error case final e?) _ErrorText(e),
      ],
    );
  }
}

bool _notFound(Object? error) =>
    error is RunNowApiException && error.statusCode == 404;

String _topicLabel(GameTelegramChat chat, GameTelegramTopic topic) {
  if (topic.name case final n?) return n;
  if (topic.threadId == 0) return chat.forum ? 'General' : 'Cả group';
  return 'Topic ${topic.threadId}';
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.chat});

  final GameTelegramChat chat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            chat.title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _M.muted,
            ),
          ),
        ),
        Text(
          chat.admin ? 'Admin' : 'Chưa là admin',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: chat.admin ? _M.amberBright : _M.danger,
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? _M.amberTint : _M.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? _M.amber : _M.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: onTap == null && !selected ? _M.faint : _M.ink,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: _M.amber,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
