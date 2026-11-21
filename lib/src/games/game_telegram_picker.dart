import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myrun/src/theme.dart';

/// Bot ván và chỗ đã xác nhận. Lỗi thì [GameTelegramPicker] chỉ còn group
/// PSC; 404 là backend chưa có bot ván.
final gameTelegramProvider = FutureProvider.autoDispose<GameTelegram>(
  retry: (_, _) => null,
  (ref) => ref.watch(runNowApiClientProvider).gameTelegram(),
);

/// Quản trò lên Telegram ở đâu: group PSC (3i đăng vào topic Ma Sói, như
/// trước) hay một topic mà bot ván của chủ phòng đã xác nhận, làm theo ba
/// bước. Chỉ topic đã xác nhận mới chọn được, nên chỗ gửi lên luôn là chỗ bot
/// đang ở; backend kiểm lại lúc tạo.
class GameTelegramPicker extends ConsumerStatefulWidget {
  const GameTelegramPicker({
    super.key,
    required this.own,
    this.canUsePsc = true,
    required this.onOwn,
    required this.selected,
    required this.onSelected,
    required this.enabled,
    this.openUrl,
  });

  /// Đang chọn "Group của bạn".
  final bool own;

  /// Chọn được group PSC. Không thì chỉ có group của bạn, không có nút chọn.
  final bool canUsePsc;
  final ValueChanged<bool> onOwn;

  /// Topic đã chọn ở group của bạn.
  final GameTelegramTarget? selected;
  final ValueChanged<GameTelegramTarget?> onSelected;

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
    _check();
  }

  /// Bot có thể đã bị kick, group hay topic đã bị xoá mà không báo về: nhờ
  /// backend hỏi lại Telegram, xong thì đọc lại danh sách.
  Future<void> _check() async {
    try {
      if (!await ref.read(runNowApiClientProvider).checkGameTelegram()) return;
    } catch (_) {
      // Kiểm lại chỉ là làm mới; danh sách cũ vẫn dùng được, tạo ván vẫn kiểm.
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) ref.invalidate(gameTelegramProvider);
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
          // Backend tự đăng ván PSC vào topic Ma Sói theo config, bỏ qua topic
          // app gửi, nên không có ô ID topic để điền.
          if (widget.canUsePsc)
            ..._psc(choosable: false)
          else if (status.isLoading)
            const _Hint('Đang tải bot quản trò…')
          else
            const _ErrorText('Chưa tải được bot quản trò của bạn.'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canUsePsc) ...[
          GameCreateSegment(
            labels: const ['Group PSC', 'Group của bạn'],
            selected: widget.own ? 1 : 0,
            onSelect: enabled ? (i) => widget.onOwn(i == 1) : null,
          ),
          const SizedBox(height: 12),
        ],
        if (widget.own) ..._ownSteps(tg, enabled) else ..._psc(choosable: true),
        if (_error case final e?) _ErrorText(e),
      ],
    );
  }

  /// [choosable]: có nút chọn giữa PSC và group của bạn, chỉ admin thấy.
  List<Widget> _psc({required bool choosable}) => [
    const _GroupLine(title: 'Group PSC', chip: '3i đăng'),
    const SizedBox(height: 8),
    const _Option(label: 'Ma Sói', selected: true, onTap: null, hash: true),
    _Hint(
      choosable
          ? 'Ván PSC luôn đăng vào topic Ma Sói. Chỉ admin thấy lựa chọn này.'
          : 'Ván PSC luôn đăng vào topic Ma Sói.',
    ),
  ];

  /// Ba bước đưa Quản trò lên group của bạn: tạo bot, mời bot làm admin, gõ
  /// /van trong topic. Bước đang làm có nút, bước sau mờ.
  List<Widget> _ownSteps(GameTelegram tg, bool enabled) {
    if (!tg.telegramLinked) {
      return const [
        _Hint(
          'Bot ván do 3i tạo cho bạn, nên cần liên kết Telegram trong app trước.',
        ),
      ];
    }
    final api = ref.read(runNowApiClientProvider);
    final bot = tg.bot;
    final admins = tg.chats.where((c) => c.admin).toList();
    final topics = [
      for (final chat in admins)
        for (final topic in chat.topics) (chat: chat, topic: topic),
    ];
    final step1 = bot == null
        ? _Step(
            n: 1,
            state: _StepState.now,
            title: 'Tạo bot Quản trò',
            sub: 'Telegram mở trang tạo bot, tên điền sẵn. Bấm Tạo là xong.',
            action: _StepButton(
              'Tạo bot ván',
              onTap: enabled ? () => _open(api.startGameBot) : null,
            ),
          )
        : _Step(
            n: 1,
            state: _StepState.done,
            title: 'Bot ván',
            sub: '@${bot.username}',
            extra: bot.setupError == null
                ? null
                : const _ErrorText('Bot ván chưa sẵn sàng, thử lại sau.'),
          );
    void invite() => _open(() async => bot!.addUrl);
    final step2 = <Widget>[
      if (bot == null)
        const _Step(
          n: 2,
          state: _StepState.later,
          title: 'Mời bot vào group làm admin',
        )
      else if (tg.chats.isEmpty)
        _Step(
          n: 2,
          state: _StepState.now,
          title: 'Mời bot vào group làm admin',
          sub: 'Chọn group của bạn, giữ quyền admin bot xin.',
          action: _StepButton('Mời vào group', onTap: enabled ? invite : null),
        )
      else
        for (final chat in tg.chats)
          chat.admin
              ? _Step(
                  n: 2,
                  state: _StepState.done,
                  title: chat.title,
                  chip: 'Admin',
                )
              : _Step(
                  n: 2,
                  state: _StepState.warn,
                  title: 'Bot chưa là admin',
                  sub: '${chat.title}: bot cần quyền admin để đăng vào topic.',
                  action: _StepButton(
                    'Mời lại với quyền admin',
                    onTap: enabled ? invite : null,
                  ),
                ),
    ];
    final Widget step3;
    if (admins.isEmpty) {
      step3 = const _Step(
        n: 3,
        state: _StepState.later,
        title: 'Gõ /van trong topic muốn đăng',
      );
    } else if (topics.isEmpty) {
      step3 = _Step(
        n: 3,
        state: _StepState.now,
        title: 'Gõ /van trong topic muốn đăng',
        sub:
            'Mở topic trong ${admins.first.title}, gửi /van. Bot trả lời '
            '"Ván Ma Sói sẽ đăng vào đây" là xong.',
      );
    } else {
      step3 = _Step(
        n: 3,
        state: _StepState.done,
        title: 'Chọn topic',
        extra: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            for (final (:chat, :topic) in topics)
              _Option(
                label: admins.length > 1
                    ? '${chat.title} · ${_topicLabel(chat, topic)}'
                    : _topicLabel(chat, topic),
                hash: true,
                tag: chat.busy ? 'Đang có ván' : null,
                selected:
                    widget.selected ==
                    GameTelegramTarget(
                      chatId: chat.chatId,
                      threadId: topic.threadId,
                    ),
                onTap: enabled && !chat.busy
                    ? () => widget.onSelected(
                        GameTelegramTarget(
                          chatId: chat.chatId,
                          threadId: topic.threadId,
                        ),
                      )
                    : null,
              ),
            const _Hint('Thêm topic: gõ /van trong topic đó.'),
          ],
        ),
      );
    }
    return [
      step1,
      ...step2,
      if (bot != null && tg.chats.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: GameCreateLink(
            'Mời vào group khác',
            onTap: enabled ? invite : () {},
          ),
        ),
      step3,
      // Telegram chỉ cho bot nhắn riêng người đã Start nó; người chơi mới
      // Start 3i lúc liên kết, nên DM của ván vẫn đi qua 3i.
      const _Hint('Lá bài và nhắc lượt gửi riêng qua bot 3i.'),
    ];
  }
}

/// Dòng dưới tên Quản trò: Quản trò nói ở đâu.
String gameTelegramSummary({
  required bool telegramOn,
  required bool own,
  required GameTelegram? tg,
  required GameTelegramTarget? selected,
}) {
  if (!telegramOn) return 'Trong app';
  if (!own) return 'Trong app · PSC #Ma Sói';
  for (final chat in tg?.chats ?? const <GameTelegramChat>[]) {
    for (final topic in chat.topics) {
      if (selected ==
          GameTelegramTarget(chatId: chat.chatId, threadId: topic.threadId)) {
        return 'Trong app · ${chat.title} #${_topicLabel(chat, topic)}';
      }
    }
  }
  return 'Trong app · Telegram chưa xong';
}

/// Vì sao chưa mở ván được khi chọn group của bạn; null là mở được.
String? gameTelegramBlocker({
  required bool telegramOn,
  required bool own,
  required GameTelegram? tg,
  required GameTelegramTarget? selected,
  bool canUsePsc = true,
}) {
  if (!telegramOn || !own) return null;
  if (tg == null || !tg.telegramLinked) {
    return canUsePsc
        ? 'Liên kết Telegram, hoặc tắt Telegram'
        : 'Liên kết Telegram';
  }
  final ready = tg.chats.any((c) => c.admin && c.topics.isNotEmpty);
  if (tg.bot == null || !ready) {
    return canUsePsc
        ? 'Làm xong 3 bước, hoặc chọn Group PSC'
        : 'Làm xong 3 bước';
  }
  if (selected == null) return 'Chọn topic để bot đăng';
  final busy = tg.chats.any((c) => c.busy && c.chatId == selected.chatId);
  if (busy) return 'Group này đang có ván, chọn group khác';
  return null;
}

bool _notFound(Object? error) =>
    error is RunNowApiException && error.statusCode == 404;

String _topicLabel(GameTelegramChat chat, GameTelegramTopic topic) {
  if (topic.name case final n?) return n;
  if (topic.threadId == 0) return chat.forum ? 'General' : 'Cả group';
  return 'Topic ${topic.threadId}';
}

enum _StepState { now, done, warn, later }

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.state,
    required this.title,
    this.sub,
    this.chip,
    this.action,
    this.extra,
  });

  final int n;
  final _StepState state;
  final String title;
  final String? sub;
  final String? chip;
  final Widget? action;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final (dotBg, dotFg) = switch (state) {
      _StepState.done => (context.moonlit.amber, context.moonlit.onAmber),
      _StepState.now => (
        context.moonlit.amberTint,
        context.moonlit.amberBright,
      ),
      _StepState.warn => (context.moonlit.danger, context.moonlit.onAmber),
      _StepState.later => (context.moonlit.raised, context.moonlit.faint),
    };
    return Opacity(
      opacity: state == _StepState.later ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dotBg,
                shape: context.runNowPalette.round,
                border: Border.all(
                  color: state == _StepState.later
                      ? context.moonlit.border
                      : dotBg,
                ),
              ),
              child: state == _StepState.done
                  ? Icon(Icons.check_rounded, size: 15, color: dotFg)
                  : Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: dotFg,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: state == _StepState.warn
                                ? context.moonlit.danger
                                : context.moonlit.ink,
                          ),
                        ),
                      ),
                      if (chip case final c?) ...[
                        const SizedBox(width: 8),
                        _Chip(c),
                      ],
                    ],
                  ),
                  if (sub case final s?) ...[
                    const SizedBox(height: 2),
                    Text(
                      s,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.moonlit.muted,
                      ),
                    ),
                  ],
                  if (action case final a?) ...[const SizedBox(height: 8), a],
                  ?extra,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.send_rounded, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: context.moonlit.amber,
          foregroundColor: context.moonlit.onAmber,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _GroupLine extends StatelessWidget {
  const _GroupLine({required this.title, required this.chip});

  final String title;
  final String chip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.moonlit.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Chip(chip, muted: true),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? context.moonlit.raised : context.moonlit.amberTint,
        borderRadius: context.runNowPalette.radius(999),
        border: Border.all(
          color: muted ? context.moonlit.border : context.moonlit.amberLine,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: muted ? context.moonlit.muted : context.moonlit.amberBright,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: context.moonlit.muted,
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hash = false,
    this.tag,
  });

  final String label;

  /// Nhãn ngắn bên phải; có nhãn mà không bấm được thì vẽ mờ.
  final String? tag;
  final bool selected;
  final VoidCallback? onTap;

  /// Vẽ dấu # trước tên như topic Telegram.
  final bool hash;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: tag != null && onTap == null ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected
                ? context.moonlit.amberTint
                : context.moonlit.raised,
            shape: RoundedRectangleBorder(
              borderRadius: context.runNowPalette.radius(14),
              side: BorderSide(
                color: selected
                    ? context.moonlit.amber
                    : context.moonlit.border,
              ),
            ),
            child: InkWell(
              borderRadius: context.runNowPalette.radius(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (hash) ...[
                      Text(
                        '#',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: context.moonlit.faint,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: context.moonlit.ink,
                        ),
                      ),
                    ),
                    if (tag case final t?)
                      Text(
                        t,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: context.moonlit.faint,
                        ),
                      ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: context.moonlit.amber,
                      ),
                  ],
                ),
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
