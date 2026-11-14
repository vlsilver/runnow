import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_links.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:share_plus/share_plus.dart';

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

/// Câu gửi kèm thẻ ván đang chơi. Chỉ dùng tin ai cũng thấy: pha và số người
/// còn sống, không nói vai.
String gameLiveCaption(GameDetail game) {
  final alive = game.players.where((p) => p.alive).length;
  return '${game.phase?.label ?? 'Ma Sói đang chơi'}. '
      'Còn $alive/${game.players.length} người sống, ai là sói?\n'
      '${gameInviteLink(game.id)}';
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
  await _showShareSheet(
    context,
    card: GameInviteCard(game: game),
    caption: gameInviteCaption(game),
    button: 'Gửi lời mời',
  );
}

/// Như [showGameInvite], cho ván đang chơi.
Future<void> showGameLive(BuildContext context, GameDetail game) async {
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: gameLiveCaption(game)));
    return;
  }
  await _showShareSheet(
    context,
    card: GameLiveCard(game: game),
    caption: gameLiveCaption(game),
    button: 'Chia sẻ',
  );
}

Future<void> _showShareSheet(
  BuildContext context, {
  required Widget card,
  required String caption,
  required String button,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.moonlit.panel,
    builder: (_) => Theme(
      data: theme,
      child: _GameShareSheet(card: card, caption: caption, button: button),
    ),
  );
}

class _GameShareSheet extends StatefulWidget {
  const _GameShareSheet({
    required this.card,
    required this.caption,
    required this.button,
  });

  final Widget card;
  final String caption;
  final String button;

  @override
  State<_GameShareSheet> createState() => _GameShareSheetState();
}

class _GameShareSheetState extends State<_GameShareSheet> {
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
        text: widget.caption,
      );
      navigator.pop();
    } catch (e, stack) {
      debugPrint('Gửi thẻ ván lỗi: $e\n$stack');
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Chưa gửi được ảnh, thử lại nhé.')),
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
                  borderRadius: context.runNowPalette.radius(14),
                  child: RepaintBoundary(key: _cardKey, child: widget.card),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (buttonContext) => FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.moonlit.amber,
                  foregroundColor: context.moonlit.onAmber,
                ),
                onPressed: _sending ? null : () => _send(buttonContext),
                child: Text(widget.button),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MA SÓI',
                        style: TextStyle(
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                          color: context.moonlit.amberBright,
                        ),
                      ),
                      Text(
                        '3i',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: context.moonlit.faint,
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
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: context.moonlit.ink,
                    ),
                  ),
                  if (hasKm) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Chạy thật, sống sót thật',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.moonlit.muted,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (faces.isNotEmpty) ...[
                    _Faces(players: faces, more: more),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: context.moonlit.raised,
                      borderRadius: context.runNowPalette.radius(10),
                      border: Border.all(color: context.moonlit.border),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          _Stat(
                            value: '${game.playerCount}/${game.maxPlayers}',
                            label: 'người đã vào',
                          ),
                          if (deadline != null) ...[
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: context.moonlit.border,
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

/// Tên ván khi không đặt riêng: thẻ đã có chữ MA SÓI ở đầu nên không in lại.
const _defaultTitle = 'Ma Sói';

/// Thẻ khoe ván đang chơi để rủ người khác. Chỉ có tin công khai: pha, ai còn
/// sống và tổng km cả làng, không có vai hay km từng người. Cỡ cố định như
/// thiệp mời.
class GameLiveCard extends StatelessWidget {
  const GameLiveCard({super.key, required this.game});

  final GameDetail game;

  // Nhãn BE trả cho người đã lộ: lá bài, hoặc chỉ phe nếu bị treo. Người chưa
  // lộ không được đếm, để thẻ không nói hơn những gì cả làng đã biết.
  static const _wolfLabels = {'Sói', 'Phe Sói'};

  static const _maxFaces = 24;
  static const _faceSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final village = [
      ...game.players.where((p) => p.alive),
      ...game.players.where((p) => !p.alive),
    ].take(_maxFaces);
    final alive = game.players.where((p) => p.alive).length;
    final km = game.kmTable == null
        ? 0.0
        : game.players.fold<double>(0, (sum, p) => sum + (p.todayKm ?? 0));
    final deadline = game.phase?.deadline?.toLocal();
    final dead = game.players.length - alive;
    final deadWolves = game.players
        .where((p) => !p.alive && _wolfLabels.contains(p.revealedRoleLabel))
        .length;
    final stats = [
      _Stat(value: '$alive/${game.players.length}', label: 'còn sống'),
      _Stat(value: '$dead', label: 'đã ngủm'),
      _Stat(value: '$deadWolves', label: 'sói đã ngủm'),
      if (km > 0)
        _Stat(value: '${km.round()}', label: 'km cả làng')
      else if (deadline != null)
        _Stat(value: _hour.format(deadline), label: 'chốt lượt này'),
    ];
    // Nhãn pha từ BE có dạng "Đêm 2, sói đang chọn": số đêm làm chữ lớn.
    final label = game.phase?.label ?? game.statusLabel;
    final comma = label.indexOf(', ');
    final headline = comma < 0 ? label : label.substring(0, comma);
    final detail = comma < 0 ? null : label.substring(comma + 2);
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'MA SÓI',
                          style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                            color: context.moonlit.amberBright,
                          ),
                          children: [
                            TextSpan(
                              text: '  3i',
                              style: TextStyle(
                                letterSpacing: 0,
                                color: context.moonlit.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.moonlit.amber,
                          borderRadius: context.runNowPalette.radius(999),
                        ),
                        child: Text(
                          'ĐANG CHƠI',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w900,
                            color: context.moonlit.onAmber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const GameMoonEmblem(size: 64),
                  const SizedBox(height: 8),
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: context.moonlit.ink,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.moonlit.amberBright,
                      ),
                    ),
                  if (game.title != _defaultTitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      game.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.moonlit.muted,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in village)
                        Opacity(
                          opacity: p.alive ? 1 : 0.28,
                          child: _face(
                            context,
                            player: p,
                            size: _faceSize,
                            text: _initial(p),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: context.moonlit.raised,
                      borderRadius: context.runNowPalette.radius(10),
                      border: Border.all(color: context.moonlit.border),
                    ),
                    child: SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          for (final (i, stat) in stats.indexed) ...[
                            if (i > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: context.moonlit.border,
                              ),
                            stat,
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
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: context.moonlit.amberBright,
                ),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.moonlit.faint),
              ),
            ],
          ),
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

  Widget _circle(BuildContext context, GamePlayer? player) => _face(
    context,
    player: player,
    size: _size,
    text: player == null ? '+$more' : _initial(player),
  );
}

String _initial(GamePlayer player) =>
    player.name.isEmpty ? '?' : player.name[0].toUpperCase();

/// Avatar tròn của một người; không có ảnh thì là [text]. [player] null là ô
/// đếm số người còn lại.
Widget _face(
  BuildContext context, {
  required GamePlayer? player,
  required double size,
  required String text,
}) {
  final avatar = player?.avatarUrl;
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: context.runNowPalette.round,
      color: context.moonlit.lifted,
      border: Border.all(color: context.moonlit.page, width: 2),
      image: avatar == null
          ? null
          : DecorationImage(
              image: cachedAvatarImage(context, avatar, size),
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
              color: player == null
                  ? context.moonlit.amberBright
                  : context.moonlit.ink,
            ),
          ),
  );
}
