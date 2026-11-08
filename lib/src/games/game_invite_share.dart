import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:intl/intl.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:share_plus/share_plus.dart';

typedef _M = RunNowMoonlitTokens;

/// Link mở trang ván trên web 3i (hosting rewrite về app web), nên ai có link
/// cũng vào được kể cả chưa cài app.
Uri gameInviteLink(String gameId) =>
    Uri.parse('${AppConfig.webBaseUrl}/games/${Uri.encodeComponent(gameId)}');

/// Câu gửi kèm thiệp, có link vì ảnh thì không bấm được.
String gameInviteCaption(GameDetail game) {
  final free = game.maxPlayers - game.playerCount;
  final deadline = game.registrationDeadline?.toLocal();
  final hook = free <= 0
      ? 'Đã đủ ${game.maxPlayers} người. Vào xem không?'
      : deadline == null
      ? 'Còn $free chỗ. Vào không?'
      : 'Còn $free chỗ, chốt ${_closing(deadline)}. Vào không?';
  return '$hook\n${gameInviteLink(game.id)}';
}

String _closing(DateTime d) => '${_hour.format(d)} ${_shortDay(d)}';

/// `T2 09/11`, `CN 08/11`.
String _shortDay(DateTime d) {
  final day = d.weekday == DateTime.sunday ? 'CN' : 'T${d.weekday + 1}';
  return '$day ${_date.format(d)}';
}

final _hour = DateFormat('HH:mm');
final _date = DateFormat('dd/MM');

/// Mở sheet xem trước thiệp rồi mới gửi: ảnh chụp đúng cái đang thấy, và avatar
/// có thời gian tải xong. Web không gửi được file nên chỉ gửi chữ.
Future<void> showGameInvite(BuildContext context, GameDetail game) async {
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: gameInviteCaption(game)));
    return;
  }
  final theme = Theme.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    builder: (_) => Theme(
      data: theme,
      child: _GameInviteSheet(game: game),
    ),
  );
}

class _GameInviteSheet extends StatefulWidget {
  const _GameInviteSheet({required this.game});

  final GameDetail game;

  @override
  State<_GameInviteSheet> createState() => _GameInviteSheetState();
}

class _GameInviteSheetState extends State<_GameInviteSheet> {
  final _cardKey = GlobalKey();
  var _sending = false;

  Future<void> _send(BuildContext buttonContext) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final png = await captureRecapPng(boundary);
      if (!buttonContext.mounted) return;
      await shareCardFile(
        bytes: png,
        mimeType: 'image/png',
        fileName: '3i-ma-soi.png',
        shareOriginContext: buttonContext,
        text: gameInviteCaption(widget.game),
      );
      navigator.pop();
    } catch (e, stack) {
      debugPrint('Gửi thiệp mời lỗi: $e\n$stack');
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Chưa gửi được thiệp, thử lại nhé.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxCardHeight = MediaQuery.sizeOf(context).height * 0.62;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxCardHeight),
              child: FittedBox(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: GameInviteCard(game: widget.game),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (buttonContext) => FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _M.amber,
                  foregroundColor: _M.onAmber,
                ),
                onPressed: _sending ? null : () => _send(buttonContext),
                child: const Text('Gửi lời mời'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thiệp mời vào ván. Cỡ cố định và bỏ phóng chữ để ảnh giống nhau trên mọi máy.
class GameInviteCard extends StatelessWidget {
  const GameInviteCard({super.key, required this.game});

  final GameDetail game;

  static const _maxFaces = 4;

  @override
  Widget build(BuildContext context) {
    final deadline = game.registrationDeadline?.toLocal();
    final hasKm = game.rulesCard.any(
      (s) => s.items.any((it) => it.key == 'kmWindow'),
    );
    final faces = game.players.take(_maxFaces).toList();
    final more = game.playerCount - faces.length;
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: 320,
        height: 400,
        child: Material(
          type: MaterialType.transparency,
          child: GameMoonlitBackdrop(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MA SÓI',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                          color: _M.amberBright,
                        ),
                      ),
                      Text(
                        '3i',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _M.faint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const GameMoonEmblem(size: 92),
                  const SizedBox(height: 14),
                  Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: _M.ink,
                    ),
                  ),
                  if (hasKm) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Chạy thật, sống sót thật',
                      style: TextStyle(fontSize: 14, color: _M.muted),
                    ),
                  ],
                  const Spacer(),
                  if (faces.isNotEmpty) ...[
                    _Faces(players: faces, more: more),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: _M.raised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _M.border),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          _Stat(
                            value: '${game.playerCount}/${game.maxPlayers}',
                            label: 'người đã vào',
                          ),
                          if (deadline != null) ...[
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: _M.border,
                            ),
                            _Stat(
                              value: _hour.format(deadline),
                              label: 'chốt, ${_shortDay(deadline)}',
                            ),
                          ],
                        ],
                      ),
                    ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: _M.amberBright,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: _M.faint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar xếp chồng, ô cuối là số người còn lại.
class _Faces extends StatelessWidget {
  const _Faces({required this.players, required this.more});

  static const _size = 36.0;
  static const _step = 27.0;

  final List<GamePlayer> players;
  final int more;

  @override
  Widget build(BuildContext context) {
    final circles = [
      for (final p in players) _circle(context, p),
      if (more > 0) _circle(context, null),
    ];
    return SizedBox(
      width: _size + _step * (circles.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (final (i, circle) in circles.indexed)
            Positioned(left: _step * i, child: circle),
        ],
      ),
    );
  }

  Widget _circle(BuildContext context, GamePlayer? player) {
    final avatar = player?.avatarUrl;
    final text = player == null
        ? '+$more'
        : player.name.isEmpty
        ? '?'
        : player.name[0].toUpperCase();
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _M.lifted,
        border: Border.all(color: _M.page, width: 2),
        image: avatar == null
            ? null
            : DecorationImage(
                image: cachedAvatarImage(context, avatar, _size),
                fit: BoxFit.cover,
              ),
      ),
      child: avatar != null
          ? null
          : Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: player == null ? _M.amberBright : _M.ink,
              ),
            ),
    );
  }
}
