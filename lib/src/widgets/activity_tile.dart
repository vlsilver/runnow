import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/prc_brand_mark.dart';

class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.activity, this.sequence, super.key});

  final ActivitySummary activity;
  final int? sequence;

  @override
  Widget build(BuildContext context) {
    final visual = _ActivityVisual.fromKind(activity.kind);
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      borderRadius: 14,
      child: InkWell(
        onTap: () => context.push('/activity/${activity.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ActivityBadge(visual: visual),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activity.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatDate(activity.startedAt),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatDistance(activity.distanceMeters),
                        style: const TextStyle(
                          color: AppColors.blueGlow,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sequence == null
                            ? 'ACTIVITY'
                            : 'LOG // ${sequence!.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TileMetric(
                      label: 'PACE',
                      value: formatPace(activity.paceSecondsPerKm),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TileMetric(
                      label: 'TIME',
                      value: formatDuration(activity.movingTimeSeconds),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TileMetric(
                      label: activity.averageHeartRate == null
                          ? 'STATUS'
                          : 'HR',
                      value: activity.averageHeartRate == null
                          ? (activity.hydrated ? 'CACHED' : 'SYNCED')
                          : '${activity.averageHeartRate!.round()} bpm',
                      valueColor: activity.averageHeartRate == null
                          ? (activity.hydrated
                                ? AppColors.blueGlow
                                : Colors.white)
                          : AppColors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const PrcBrandMark(compact: true),
                  Row(
                    children: [
                      Text(
                        activity.hydrated ? 'DETAIL READY' : 'OPEN DETAIL',
                        style: TextStyle(
                          color: activity.hydrated
                              ? AppColors.blueGlow
                              : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: activity.hydrated
                            ? AppColors.blueGlow
                            : Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityBadge extends StatelessWidget {
  const _ActivityBadge({required this.visual});

  final _ActivityVisual visual;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.2),
        border: Border.all(color: visual.color),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: visual.color.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      child: Stack(
        children: [
          Center(child: Icon(visual.icon, color: Colors.white, size: 25)),
          Positioned(
            right: 4,
            bottom: 3,
            child: Text(
              visual.code,
              style: TextStyle(
                color: visual.color,
                fontSize: 7,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TileMetric extends StatelessWidget {
  const _TileMetric({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0x3d020812),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor.withValues(alpha: 0.92),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityVisual {
  const _ActivityVisual({
    required this.icon,
    required this.color,
    required this.code,
  });

  factory _ActivityVisual.fromKind(ActivityKind kind) {
    return switch (kind) {
      ActivityKind.walk => const _ActivityVisual(
        icon: Icons.directions_walk,
        color: AppColors.blueGlow,
        code: 'WLK',
      ),
      ActivityKind.hike => const _ActivityVisual(
        icon: Icons.terrain,
        color: AppColors.amber,
        code: 'HKE',
      ),
      ActivityKind.trailRun => const _ActivityVisual(
        icon: Icons.terrain,
        color: AppColors.amber,
        code: 'TRL',
      ),
      ActivityKind.virtualRun => const _ActivityVisual(
        icon: Icons.bolt,
        color: AppColors.blueGlow,
        code: 'VRT',
      ),
      ActivityKind.run => const _ActivityVisual(
        icon: Icons.directions_run,
        color: AppColors.red,
        code: 'RUN',
      ),
    };
  }

  final IconData icon;
  final Color color;
  final String code;
}
