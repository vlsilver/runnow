import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/keo_scene.dart';

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
    // Ma Sói luôn là cảnh đêm, nên chữ lấy màu của cảnh chứ không theo theme.
    final night = KeoSceneColors.resolve(
      context.runNowPalette,
      KeoScene.werewolf,
    );
    final accent = night.accent;
    final deadline = game.nextDeadline;

    return KeoSceneCard(
      scene: KeoScene.werewolf,
      seed: game.id,
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Icon(Icons.nightlight_round, size: 20, color: accent),
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
                    color: night.ink,
                  ),
                ),
              ),
              if (game.testMode) ...[
                _Badge(label: 'VÁN THỬ', color: night.muted),
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
              color: night.ink,
            ),
          ),
          if (game.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              game.subtitle,
              style: TextStyle(fontSize: 13, color: night.muted),
            ),
          ],
          const SizedBox(height: 14),
          // Wrap: màn hẹp hay chữ phóng to thì badge xuống dòng chứ không
          // bị cắt.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_rounded, size: 15, color: night.muted),
                  const SizedBox(width: 3),
                  Text(
                    '${game.playerCount}/${game.maxPlayers} người',
                    style: TextStyle(fontSize: 13, color: night.muted),
                  ),
                ],
              ),
              if (deadline != null)
                Text(
                  'Hạn ${_deadlineFormat.format(deadline.toLocal())}',
                  style: TextStyle(fontSize: 13, color: night.muted),
                ),
              if (game.hasTodo) _Badge(label: 'Có việc cho bạn', color: accent),
            ],
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        // Nền đặc: chip có thể nằm đè lên trăng sáng của cảnh đêm.
        color: Color.alphaBlend(
          color.withValues(alpha: 0.22),
          Theme.of(context).colorScheme.surface,
        ),
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
