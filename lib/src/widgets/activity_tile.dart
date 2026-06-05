import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

class ActivityTile extends StatelessWidget {
  const ActivityTile({
    required this.activity,
    this.sequence,
    this.ownerUid,
    this.memberName,
    this.memberAvatarUrl,
    super.key,
  });

  final ActivitySummary activity;
  final int? sequence;
  final String? ownerUid;
  final String? memberName;
  final String? memberAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final visual = _ActivityVisual.fromKind(activity.kind);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final faint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.42);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimelineRail(activity: activity),
            const SizedBox(width: 10),
            Expanded(
              child: GlassPanel(
                borderRadius: 22,
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => context.push(
                    ownerUid == null
                        ? '/activity/${activity.id}'
                        : '/club/$ownerUid/activity/${activity.id}',
                  ),
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: LinearGradient(
                              colors: isLight
                                  ? [
                                      Colors.white.withValues(alpha: 0.72),
                                      visual.color.withValues(alpha: 0.08),
                                    ]
                                  : [
                                      const Color(0x2600d9ff),
                                      visual.color.withValues(alpha: 0.12),
                                      Colors.transparent,
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (memberName != null) ...[
                              _MemberStamp(
                                name: memberName!,
                                avatarUrl: memberAvatarUrl,
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _KindTag(visual: visual),
                                          const SizedBox(width: 7),
                                          Expanded(
                                            child: Text(
                                              activity.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatDistance(activity.distanceMeters),
                                      style: const TextStyle(
                                        color: AppColors.blueGlow,
                                        fontSize: 21,
                                        fontWeight: FontWeight.w900,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      sequence == null
                                          ? 'LOG'
                                          : '#${sequence!.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        color: faint,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 13),
                            Row(
                              children: [
                                Expanded(
                                  child: _TileMetric(
                                    label: 'PACE',
                                    value: formatPace(
                                      activity.paceSecondsPerKm,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _TileMetric(
                                    label: 'TIME',
                                    value: formatDuration(
                                      activity.movingTimeSeconds,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _TileMetric(
                                    label: activity.averageHeartRate == null
                                        ? 'ELEV'
                                        : 'HR',
                                    value: activity.averageHeartRate == null
                                        ? _elevationLabel(activity)
                                        : '${activity.averageHeartRate!.round()} bpm',
                                    valueColor:
                                        activity.averageHeartRate == null
                                        ? AppColors.blueGlow
                                        : AppColors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberStamp extends StatelessWidget {
  const _MemberStamp({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.blueGlow.withValues(alpha: 0.16),
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl!),
          child: avatarUrl == null
              ? Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.blueGlow,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.activity});

  final ActivitySummary activity;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: 38,
      child: Column(
        children: [
          Text(
            DateFormat('dd').format(activity.startedAt),
            style: TextStyle(
              color: onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            DateFormat('MMM').format(activity.startedAt).toUpperCase(),
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.48),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.45),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindTag extends StatelessWidget {
  const _KindTag({required this.visual});

  final _ActivityVisual visual;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          visual.code,
          style: TextStyle(
            color: visual.color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }
}

class _TileMetric extends StatelessWidget {
  const _TileMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final resolvedValueColor =
        valueColor ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xffeef3f8) : const Color(0x3d020812),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.56),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: resolvedValueColor.withValues(alpha: 0.94),
              fontSize: 14,
              fontWeight: FontWeight.w900,
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
        code: 'WALK',
      ),
      ActivityKind.hike => const _ActivityVisual(
        icon: Icons.terrain,
        color: AppColors.blueGlow,
        code: 'HIKE',
      ),
      ActivityKind.trailRun => const _ActivityVisual(
        icon: Icons.terrain,
        color: AppColors.blueGlow,
        code: 'TRAIL',
      ),
      ActivityKind.virtualRun => const _ActivityVisual(
        icon: Icons.bolt,
        color: AppColors.blueGlow,
        code: 'VIRTUAL',
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

String _elevationLabel(ActivitySummary activity) {
  final elevation = activity.elevationGainMeters;
  if (elevation == null) return '--';
  return '${elevation.round()} m';
}
