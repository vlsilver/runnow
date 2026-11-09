import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/games/game_action_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/games/game_turn.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _M = RunNowMoonlitTokens;

const _cardWidth = 88.0;

/// Kết quả soi của Tiên tri: backend gửi `Đêm 1: An là Dân.`
final _peekNote = RegExp(r'^Đêm \d+: (.+) là (Dân|Sói)\.?$');

/// Lá bài của người xem, lấy từ `/me`. Úp hay ngửa là do màn chi tiết giữ.
/// Nút hành động, ghi chú, bình thuốc, link nhóm và lối vào chat phe đều lộ
/// vai nên chỉ hiện khi lật.
class GameMyCard extends StatelessWidget {
  const GameMyCard({
    super.key,
    required this.me,
    required this.faceUp,
    required this.onFlip,
    required this.onOpenUrl,
    required this.onOpenChat,
    required this.card,
    required this.onOpenCard,
    required this.cardRevealed,
    required this.justRevealed,
    required this.onRevealCard,
    required this.running,
    required this.serverNow,
    required this.onAction,
    this.kmTable,
  });

  final GameMe me;
  final bool faceUp;
  final GameActionRunner onAction;

  /// Ván đang chạy thì mặt lá có dải "tới giờ của bạn chưa".
  final bool running;
  final DateTime Function() serverNow;

  /// Lá vẽ trong mặt ngửa; chạm vào lá thì mở xem to ([onOpenCard]).
  final AchievementCardData card;
  final VoidCallback onOpenCard;

  /// Bậc thẻ backend bốc sẵn lúc chia bài, nhưng người chơi chỉ thấy khi tự
  /// lật: false thì lá nằm úp chờ lật ([onRevealCard]), null là chưa đọc xong
  /// máy này đã lật chưa.
  final bool? cardRevealed;

  /// Vừa lật trong phiên này thì chạy hiệu ứng lật.
  final bool justRevealed;
  final VoidCallback onRevealCard;

  /// Đầu cột cho bảng km phe trong mặt lá (`me.teamKm`).
  final GameKmTable? kmTable;
  final VoidCallback onFlip;
  final ValueChanged<String> onOpenUrl;

  /// Nhận `key` của chat trong `me.chats`.
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _M.border),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_M.panelTop, _M.panelBottom],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onFlip,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: faceUp
                  ? _Face(
                      key: const ValueKey('face'),
                      me: me,
                      card: card,
                      kmTable: kmTable,
                      running: running,
                      serverNow: serverNow,
                      onAction: onAction,
                      onFlip: onFlip,
                      onOpenCard: onOpenCard,
                      cardRevealed: cardRevealed,
                      justRevealed: justRevealed,
                      onRevealCard: onRevealCard,
                      onOpenUrl: onOpenUrl,
                      onOpenChat: onOpenChat,
                    )
                  : const _Back(key: ValueKey('back')),
            ),
          ),
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        const GameCardScaled(width: _cardWidth, child: GameCardBack()),
        const SizedBox(width: 12),
        Expanded(
          // Ai có vai cũng thấy đúng hai dòng này, nên câu chữ không lộ vai.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LÁ BÀI CỦA BẠN',
                style: TextStyle(
                  fontFamily: gameTitleFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _M.amberSoft,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chạm để lật',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    super.key,
    required this.me,
    required this.card,
    required this.kmTable,
    required this.running,
    required this.serverNow,
    required this.onAction,
    required this.onFlip,
    required this.onOpenCard,
    required this.cardRevealed,
    required this.justRevealed,
    required this.onRevealCard,
    required this.onOpenUrl,
    required this.onOpenChat,
  });

  final GameMe me;
  final AchievementCardData card;
  final GameKmTable? kmTable;
  final bool running;
  final DateTime Function() serverNow;
  final GameActionRunner onAction;
  final VoidCallback onFlip;
  final VoidCallback onOpenCard;
  final bool? cardRevealed;
  final bool justRevealed;
  final VoidCallback onRevealCard;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String> onOpenChat;

  /// Chỗ thẻ trong mặt lá: úp trung tính (lá úp không có khung theo bậc) cho
  /// tới khi người chơi lật, rồi mới là thẻ thật.
  Widget _cardSlot(RunNowPalette palette) {
    const back = GameCardScaled(width: _cardWidth, child: GameCardBack());
    final shown = GameCardScaled(
      width: _cardWidth,
      size: achievementCardSize,
      child: AchievementCard(data: card),
    );
    return switch (cardRevealed) {
      null => back,
      false => Semantics(
        button: true,
        label: 'Lật thẻ',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onRevealCard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              back,
              const SizedBox(height: 6),
              Text(
                'Lật thẻ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
            ],
          ),
        ),
      ),
      true => GestureDetector(
        onTap: onOpenCard,
        child: justRevealed ? CardFlipReveal(from: back, to: shown) : shown,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final potions = me.potions;
    final sameWindow =
        {for (final a in me.actions) (a.opensAt, a.closesAt)}.length == 1;
    final roleRules = me.roleRules;
    // Màu vai pha cho nền đêm của lá bài; nền sáng thì hạ độ sáng để chữ
    // còn đọc được mà vẫn giữ sắc của vai.
    final roleAccent = gameRoleAccent(me.role ?? '');
    final accent = Theme.of(context).brightness == Brightness.light
        ? HSLColor.fromColor(roleAccent).withLightness(0.36).toColor()
        : roleAccent;
    final body = TextStyle(
      fontSize: 13,
      height: 1.45,
      color: palette.foreground,
    );
    // Có việc thì câu hỏi chiếm chỗ, tên vai đã nằm trên thẻ. Không có việc
    // thì cột phải nói mình là ai và làm gì, để khối không trống.
    final idle = me.actions.isEmpty;
    final showName = idle || cardRevealed != true;
    final roleLine = idle && roleRules != null
        ? gameRuleLines(roleRules).firstOrNull
        : null;
    final peeks = [
      for (final note in me.notes) ?_peekNote.firstMatch(note.text),
    ];
    final notes = me.notes.where((n) => !_peekNote.hasMatch(n.text));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardSlot(palette),
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (running)
                        GameTurnBanner(
                          actions: me.actions,
                          alive: me.alive,
                          serverNow: serverNow,
                        ),
                      if (showName) ...[
                        if (running) const SizedBox(height: 8),
                        Text(
                          (me.roleLabel ?? '').toUpperCase(),
                          style: TextStyle(
                            fontFamily: gameTitleFont,
                            fontSize: 28,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: accent,
                          ),
                        ),
                      ],
                      if (me.cardOwned && cardRevealed == true) ...[
                        const SizedBox(height: 6),
                        Text(
                          me.alive ? 'Thắng · sống tới cuối' : 'Thắng · đã ngã',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _M.amberSoft,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ClaimButton(onPressed: onOpenCard),
                      ],
                      if (roleLine != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          roleLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: _M.inkSoft,
                          ),
                        ),
                      ],
                      if (potions != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Bình cứu: ${potions.save ? 'còn' : 'đã dùng'} · '
                          'Bình độc: ${potions.poison ? 'còn' : 'đã dùng'}',
                          style: body.copyWith(color: palette.ink),
                        ),
                      ],
                      if (peeks.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final peek in peeks)
                              _PeekChip(name: peek[1]!, side: peek[2]!),
                          ],
                        ),
                      ],
                    ],
                  ),
                  Positioned(
                    top: -10,
                    right: -8,
                    child: PopupMenuButton<VoidCallback>(
                      tooltip: 'Thêm',
                      color: _M.raised,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 140),
                      iconSize: 20,
                      iconColor: _M.muted,
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (run) => run(),
                      itemBuilder: (_) => [
                        if (roleRules != null)
                          PopupMenuItem(
                            value: () => _showRoleRules(
                              context,
                              me.roleLabel ?? '',
                              roleRules,
                            ),
                            child: const Text('Là gì?'),
                          ),
                        // Thẻ Ẩn luôn mặc màu hành của nó.
                        if (card.secret == null)
                          PopupMenuItem(
                            value: () =>
                                showRunCardSkinSheet(context, sample: card),
                            child: const Text('Bộ màu'),
                          ),
                        PopupMenuItem(
                          value: onFlip,
                          child: const Text('Úp lá bài'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (me.actions.isNotEmpty)
          // Cả khối lá bài chạm là úp, nên phải chặn ở đây: bấm trượt cạnh nút
          // chọn người mà lá úp xuống thì mất luôn lựa chọn đang dở.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final action in me.actions) ...[
                  const SizedBox(height: 14),
                  if (me.actions.length > 1) ...[
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: 14),
                  ],
                  GameActionCard(
                    key: ValueKey(action.kind),
                    showHeader: me.actions.length > 1,
                    showTime: !sameWindow,
                    action: action,
                    serverNow: serverNow,
                    onSubmit: ({targets = const [], choice, clear = false}) =>
                        onAction(
                          action.kind,
                          targets: targets,
                          choice: choice,
                          clear: clear,
                        ),
                  ),
                ],
              ],
            ),
          ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Vòng ${note.round}: ${note.text}',
              style: body.copyWith(color: palette.ink),
            ),
          ),
        if (me.teamKm case final team?) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 12),
          _TeamKm(team: team, table: kmTable),
        ],
        for (final invite in me.inviteLinks)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: () => onOpenUrl(invite.url),
              child: Text(invite.label),
            ),
          ),
        for (final chat in me.chats)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: () => onOpenChat(chat.key),
              // Nút chat phe tô theo màu vai, như nút Chat Phe Sói ở artboard.
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: accent.withValues(alpha: 0.16),
                foregroundColor: Color.lerp(accent, palette.ink, 0.55),
                side: BorderSide(color: accent.withValues(alpha: 0.45)),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text('Chat ${chat.label}'),
            ),
          ),
      ],
    );
  }
}

/// Một kết quả soi; soi trúng Sói thì nổi hơn.
class _PeekChip extends StatelessWidget {
  const _PeekChip({required this.name, required this.side});

  final String name;
  final String side;

  @override
  Widget build(BuildContext context) {
    final wolf = side == 'Sói';
    final color = wolf ? _M.amberPale : _M.amberBright;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: wolf ? FontWeight.w700 : FontWeight.w400,
      color: color,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: wolf ? _M.amberTint : _M.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          // Tên dài thì cắt tên, kết quả soi luôn phải đọc được.
          Text(' · ${wolf ? 'SÓI' : side}', style: style),
        ],
      ),
    );
  }
}

/// Cách chơi của vai: backend gửi một đoạn, app hiện mỗi ý một dòng.
Future<void> _showRoleRules(BuildContext context, String role, String rules) {
  final palette = context.runNowPalette;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RunNowMoonlitTokens.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            role.toUpperCase(),
            style: TextStyle(
              fontFamily: gameTitleFont,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 12),
          for (final line in gameRuleLines(rules))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Km cả phe (phe Sói cắn theo tổng km phe), chỉ nằm trong mặt lá đã lật để
/// người nhìn qua vai không đoán ra vai.
class _ClaimButton extends StatelessWidget {
  const _ClaimButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [_M.amber, _M.amberBright]),
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: _M.onAmber,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: gameTitleFont,
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
        child: const Text('NHẬN THẺ'),
      ),
    );
  }
}

class _TeamKm extends StatefulWidget {
  const _TeamKm({required this.team, required this.table});

  final GameTeamKm team;
  final GameKmTable? table;

  @override
  State<_TeamKm> createState() => _TeamKmState();
}

class _TeamKmState extends State<_TeamKm> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final team = widget.team;
    final today = team.today;
    final missing = today == null ? null : gameKmMissing(today, team.need);
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  team.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
              ),
              GameKmNumber(km: today, highlight: true),
              const SizedBox(width: 8),
              GameKmStatusLabel(km: today, unitKm: team.need),
              Icon(
                _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20,
                color: palette.textMuted,
              ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            Text(
              team.needLabel,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
            const SizedBox(height: 6),
            GameKmColumns(
              lastLabel: widget.table?.lastLabel ?? 'Chốt 22h',
              todayLabel: widget.table?.todayLabel ?? 'Tới giờ',
              rows: [
                GameKmRow(
                  label: 'Cả phe',
                  last: GameKmNumber(km: team.last),
                  today: GameKmNumber(km: today, highlight: true),
                ),
                GameKmRow(
                  label: 'Đủ để cắn',
                  last: GameKmStatusLabel(km: team.last, unitKm: team.need),
                  today: GameKmStatusLabel(km: today, unitKm: team.need),
                ),
              ],
            ),
            if (missing != null) ...[
              const SizedBox(height: 8),
              Text(
                'Phe cần thêm $missing km trước lần chốt tới thì đêm sau mới cắn được.',
                style: TextStyle(fontSize: 13, color: palette.ink),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Ván nào người chơi đã lật thẻ trên máy này. Chỉ lưu trong máy: đổi máy thì
/// lật lại, bậc vẫn là bậc backend đã bốc.
class GameCardReveals {
  GameCardReveals({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String uid, String gameId) =>
      'masoi_card_revealed_v1_${uid}_$gameId';

  /// Đọc lỗi thì coi như đã lật, để lỗi máy không giấu thẻ mãi.
  Future<bool> revealed(String uid, String gameId) async {
    try {
      return await _storage.read(key: _key(uid, gameId)) != null;
    } catch (error) {
      debugPrint('Ma Sói: đọc thẻ đã lật lỗi: $error');
      return true;
    }
  }

  Future<void> markRevealed(String uid, String gameId) =>
      _storage.write(key: _key(uid, gameId), value: '1');
}

final gameCardRevealsProvider = Provider<GameCardReveals>(
  (ref) => GameCardReveals(),
);
