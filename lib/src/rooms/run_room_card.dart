import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_route_sketch.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/keo_scene.dart';

/// Card một phòng chạy chung đã xong trên feed Kèo, cùng khung với GameCard.
class RunRoomDoneCard extends StatelessWidget {
  const RunRoomDoneCard({super.key, required this.room, required this.onTap});

  final RunRoom room;
  final VoidCallback onTap;

  static final _timeFormat = DateFormat('HH:mm dd/MM');

  @override
  Widget build(BuildContext context) {
    final scene = KeoSceneColors.resolve(context.runNowPalette, KeoScene.live);
    final accent = scene.accent;
    final starts = room.startsAt;
    final route = room.route;
    final muted = TextStyle(fontSize: 13, color: scene.muted);

    return KeoSceneCard(
      scene: KeoScene.live,
      seed: room.id,
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
                child: Icon(Icons.groups_rounded, size: 20, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Đã chạy xong',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: scene.ink,
                  ),
                ),
              ),
              _Badge(label: 'CHẠY CHUNG', color: accent),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            room.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: scene.ink,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            [
              'Chủ phòng ${room.hostName}',
              if (route != null) 'tuyến ${runRoomRouteKm(route)}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
          const SizedBox(height: 14),
          // Wrap: màn hẹp hay chữ phóng to thì dòng dưới xuống dòng chứ không
          // bị cắt.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.directions_run_rounded,
                    size: 15,
                    color: scene.muted,
                  ),
                  const SizedBox(width: 3),
                  Text('${room.runnerCount} người chạy', style: muted),
                ],
              ),
              if (starts != null)
                Text(_timeFormat.format(starts.toLocal()), style: muted),
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
        // Nền đặc: chip có thể nằm đè lên phần sáng của cảnh.
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
