import 'package:flutter/material.dart';
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
  });

  final GameMe me;
  final bool faceUp;
  final VoidCallback onFlip;
  final ValueChanged<String> onOpenUrl;

  /// Nhận `key` của chat trong `me.chats`.
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onFlip,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: faceUp
                ? _Face(
                    key: const ValueKey('face'),
                    me: me,
                    onOpenUrl: onOpenUrl,
                    onOpenChat: onOpenChat,
                  )
                : Row(
                    key: const ValueKey('back'),
                    children: [
                      _CardImage(url: me.cardBackUrl, label: '?'),
                      const SizedBox(width: 16),
                      Expanded(
                        // Ai có vai cũng thấy đúng câu này, nên câu chữ không
                        // lộ ai có việc ban đêm hay có chat phe.
                        child: Text(
                          'Lá bài của bạn đang úp. Chạm để xem vai, việc cần '
                          'làm và chat phe.',
                          style: TextStyle(color: palette.textMuted),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    super.key,
    required this.me,
    required this.onOpenUrl,
    required this.onOpenChat,
  });

  final GameMe me;
  final ValueChanged<String> onOpenUrl;
  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final potions = me.potions;
    final muted = TextStyle(color: palette.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardImage(url: me.cardUrl, label: me.roleLabel ?? '?'),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me.roleLabel ?? '',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  if (me.roleRules != null) ...[
                    const SizedBox(height: 4),
                    Text(me.roleRules!, style: muted),
                  ],
                  if (potions != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Bình cứu: ${potions.save ? 'còn' : 'đã dùng'} · '
                      'Bình độc: ${potions.poison ? 'còn' : 'đã dùng'}',
                      style: TextStyle(color: palette.ink),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        for (final note in me.notes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Vòng ${note.round}: ${note.text}'),
          ),
        for (final invite in me.inviteLinks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: () => onOpenUrl(invite.url),
              child: Text(invite.label),
            ),
          ),
        for (final chat in me.chats)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => onOpenChat(chat.key),
              icon: const Icon(Icons.forum_outlined),
              label: Text('Chat ${chat.label}'),
            ),
          ),
        const SizedBox(height: 8),
        Text('Chạm để úp lại.', style: muted),
      ],
    );
  }
}

/// Ảnh lá bài; chưa có ảnh hay tải lỗi thì vẽ khung có chữ.
class _CardImage extends StatelessWidget {
  const _CardImage({required this.url, required this.label});

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final placeholder = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.tint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w800, color: palette.ink),
      ),
    );
    final url = this.url;
    return SizedBox(
      width: 72,
      height: 100,
      child: url == null
          ? placeholder
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}
