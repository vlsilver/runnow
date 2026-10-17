import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Card một ván Ma Sói trên feed Kèo, cùng kiểu với CoachCard. Chữ trạng thái
/// do backend gửi. Badge việc cần làm không nói là việc gì, vì màn hình người
/// chơi có thể bị người bên cạnh nhìn thấy.
class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, required this.onTap});

  final GameListItem game;
  final VoidCallback onTap;

  static final _deadlineFormat = DateFormat('HH:mm dd/MM');

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = palette.accent;
    final deadline = game.nextDeadline;

    return Material(
      color: dark ? palette.glassStart : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: dark ? 0.14 : 0.08),
                accent.withValues(alpha: 0.0),
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: accent.withValues(alpha: 0.18),
                    child: Icon(
                      Icons.nightlight_round,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      game.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  if (game.testMode) ...[
                    _Badge(label: 'VÁN THỬ', color: palette.textMuted),
                    const SizedBox(width: 6),
                  ],
                  _Badge(label: 'MA SÓI', color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                game.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: palette.ink,
                ),
              ),
              if (game.subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  game.subtitle,
                  style: TextStyle(fontSize: 13, color: palette.textMuted),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${game.playerCount}/${game.maxPlayers} người',
                    style: TextStyle(fontSize: 13, color: palette.textMuted),
                  ),
                  if (deadline != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'Hạn ${_deadlineFormat.format(deadline.toLocal())}',
                      style: TextStyle(fontSize: 13, color: palette.textMuted),
                    ),
                  ],
                  const Spacer(),
                  if (game.hasTodo)
                    _Badge(label: 'Có việc cho bạn', color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
