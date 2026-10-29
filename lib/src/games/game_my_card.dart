import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/games/game_turn.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Lá bài của người xem, lấy từ `/me`. Úp hay ngửa là do màn chi tiết giữ,
/// vì việc của vai nằm ngoài lá cũng phải ẩn theo. Ghi chú, bình thuốc, link
/// nhóm và lối vào chat phe là thông tin riêng của lá nên chỉ hiện khi lật.
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
    this.kmTable,
  });

  final GameMe me;
  final bool faceUp;

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
    final palette = context.runNowPalette;
    return GlassPanel(
      padding: EdgeInsets.zero,
      // Ngửa thì viền vàng như artboard lật thẻ; úp thì viền kính thường.
      border: Border.all(
        color: faceUp ? palette.accent.withValues(alpha: 0.3) : palette.border,
      ),
      child: InkWell(
        onTap: onFlip,
        child: Padding(
          padding: EdgeInsets.all(faceUp ? 16 : 12),
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
        const GameCardScaled(width: 90, child: GameCardBack()),
        const SizedBox(width: 14),
        Expanded(
          // Ai có vai cũng thấy đúng câu này, nên câu chữ không lộ ai có việc
          // ban đêm hay có chat phe.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lá bài của bạn',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Đang úp. Chạm để xem vai, việc cần làm và chat phe.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Chạm để lật',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
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
  final VoidCallback onOpenCard;
  final bool? cardRevealed;
  final bool justRevealed;
  final VoidCallback onRevealCard;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String> onOpenChat;

  /// Chỗ thẻ trong mặt lá: úp trung tính (lá úp không có khung theo bậc) cho
  /// tới khi người chơi lật, rồi mới là thẻ thật.
  Widget _cardSlot(RunNowPalette palette) {
    const width = 140.0;
    const back = GameCardScaled(width: width, child: GameCardBack());
    final shown = GameCardScaled(
      width: width,
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
    final accent = gameRoleAccent(me.role ?? '');
    const body = TextStyle(
      fontSize: 13,
      height: 1.45,
      color: RunNowGameTokens.heroSub,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardSlot(palette),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me.roleLabel ?? '',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                  if (me.roleRules != null) ...[
                    const SizedBox(height: 6),
                    Text(me.roleRules!, style: body),
                  ],
                  if (potions != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Bình cứu: ${potions.save ? 'còn' : 'đã dùng'} · '
                      'Bình độc: ${potions.poison ? 'còn' : 'đã dùng'}',
                      style: body.copyWith(color: palette.ink),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Chạm thẻ để xem to, xoay 3D',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.accent,
                    ),
                  ),
                  // Thẻ Ẩn luôn mặc màu hành của nó.
                  if (card.secret == null)
                    TextButton.icon(
                      onPressed: () =>
                          showRunCardSkinSheet(context, sample: card),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: const Text('Bộ màu thẻ'),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (running) ...[
          const SizedBox(height: 14),
          GameTurnBanner(
            actions: me.actions,
            alive: me.alive,
            serverNow: serverNow,
          ),
        ],
        for (final note in me.notes)
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
        const SizedBox(height: 10),
        Text(
          'Chạm ra ngoài lá bài để úp lại.',
          style: TextStyle(fontSize: 12, color: palette.textMuted),
        ),
      ],
    );
  }
}

/// Km cả phe (phe Sói cắn theo tổng km phe), chỉ nằm trong mặt lá đã lật để
/// người nhìn qua vai không đoán ra vai.
class _TeamKm extends StatelessWidget {
  const _TeamKm({required this.team, required this.table});

  final GameTeamKm team;
  final GameKmTable? table;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final today = team.today;
    final missing = today == null ? null : gameKmMissing(today, team.need);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
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
            Text(
              team.needLabel,
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GameKmColumns(
          lastLabel: table?.lastLabel ?? 'Chốt 22h',
          todayLabel: table?.todayLabel ?? 'Tới giờ',
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
            'Phe cần thêm $missing km trước 22h thì đêm nay mới cắn được.',
            style: TextStyle(fontSize: 13, color: palette.ink),
          ),
        ],
      ],
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
