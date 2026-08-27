import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

class ActivityTile extends StatelessWidget {
  const ActivityTile({
    required this.activity,
    this.ownerUid,
    this.memberName,
    this.memberAvatarUrl,
    this.preferredStravaActivityId,
    super.key,
  });

  final ActivitySummary activity;
  final String? ownerUid;
  final String? memberName;
  final String? memberAvatarUrl;
  final String? preferredStravaActivityId;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final visual = _ActivityVisual.fromKind(activity.kind, palette);
    final timelineHeight =
        memberName != null || preferredStravaActivityId != null ? 142.0 : 118.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimelineRail(activity: activity, height: timelineHeight),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.push(
                  ownerUid == null
                      ? '/activity/${activity.id}'
                      : '/club/$ownerUid/activity/${activity.id}',
                ),
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [palette.glassStart, palette.glassEnd],
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Tiêu đề chiếm trọn bề ngang; hai nhãn
                                    // (loại vận động + nguồn dữ liệu) xuống
                                    // dòng dưới, gom lại một chỗ.
                                    Text(
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
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        _KindTag(visual: visual),
                                        const SizedBox(width: 5),
                                        _SourceBadge(source: activity.source),
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
                                    style: TextStyle(
                                      color: palette.accent,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 13),
                          if (preferredStravaActivityId != null) ...[
                            _StravaOverlapFlag(
                              activityId: preferredStravaActivityId!,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _TileMetric(
                                  label: 'PACE',
                                  value: formatPace(activity.paceSecondsPerKm),
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
    );
  }
}

class _StravaOverlapFlag extends StatelessWidget {
  const _StravaOverlapFlag({required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => context.push('/activity/$activityId'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.tint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_rounded, size: 14, color: palette.accentDeep),
              const SizedBox(width: 6),
              Text(
                'TRÙNG · ƯU TIÊN STRAVA',
                style: TextStyle(
                  color: palette.accentDeep,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
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
    final palette = context.runNowPalette;
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: palette.secondary.withValues(alpha: 0.16),
          backgroundImage: avatarUrl == null
              ? null
              : cachedAvatarImage(context, avatarUrl!, 26),
          child: avatarUrl == null
              ? Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: TextStyle(
                    color: palette.secondary,
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
  const _TimelineRail({required this.activity, required this.height});

  final ActivitySummary activity;
  final double height;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final palette = context.runNowPalette;
    return SizedBox(
      width: 38,
      height: height,
      child: Column(
        children: [
          Text(
            _dayLabel(activity.startedAt),
            style: TextStyle(
              color: onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _monthLabel(activity.startedAt),
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
              color: palette.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.32),
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
                color: palette.accent.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nhãn nhỏ cho biết buổi chạy này lấy từ đâu: Strava hay do 3i Run tự ghi.
///
/// Strava **không phát hành logo dạng mark đứng riêng** — bộ asset chính
/// thức chỉ có khối "Powered by Strava"/"Compatible with Strava", mà brand
/// guideline lại cấm cắt lấy một phần logo. Nên phía Strava dùng chữ đặt
/// trong màu cam thương hiệu `#FC5200`, đúng cỡ nhỏ hơn tên hoạt động như
/// guideline yêu cầu. Phía 3i thì dùng thẳng app icon.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final ActivitySource source;

  @override
  Widget build(BuildContext context) {
    if (source == ActivitySource.strava) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: RunNowBrandColors.strava.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            'STRAVA',
            style: TextStyle(
              color: RunNowBrandColors.strava,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.asset(
        'assets/brand/3i-mark.png',
        width: 16,
        height: 16,
        fit: BoxFit.cover,
        semanticLabel: '3i Run',
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
  const _TileMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final resolvedValueColor = context.runNowPalette.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
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

  factory _ActivityVisual.fromKind(ActivityKind kind, RunNowPalette palette) {
    return switch (kind) {
      ActivityKind.walk => _ActivityVisual(
        icon: Icons.directions_walk,
        color: palette.accent,
        code: 'WALK',
      ),
      ActivityKind.hike => _ActivityVisual(
        icon: Icons.terrain,
        color: palette.accent,
        code: 'HIKE',
      ),
      ActivityKind.trailRun => _ActivityVisual(
        icon: Icons.terrain,
        color: palette.accent,
        code: 'TRAIL',
      ),
      ActivityKind.virtualRun => _ActivityVisual(
        icon: Icons.bolt,
        color: palette.accent,
        code: 'VIRTUAL',
      ),
      ActivityKind.run => _ActivityVisual(
        icon: Icons.directions_run,
        color: palette.accent,
        code: 'RUN',
      ),
      ActivityKind.ride => _ActivityVisual(
        icon: Icons.directions_bike,
        color: palette.accent,
        code: 'RIDE',
      ),
      ActivityKind.swim => _ActivityVisual(
        icon: Icons.pool,
        color: palette.accent,
        code: 'SWIM',
      ),
      ActivityKind.gym => _ActivityVisual(
        icon: Icons.fitness_center,
        color: palette.accent,
        code: 'GYM',
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

String _dayLabel(DateTime date) => date.day.toString().padLeft(2, '0');

String _monthLabel(DateTime date) => switch (date.month) {
  1 => 'JAN',
  2 => 'FEB',
  3 => 'MAR',
  4 => 'APR',
  5 => 'MAY',
  6 => 'JUN',
  7 => 'JUL',
  8 => 'AUG',
  9 => 'SEP',
  10 => 'OCT',
  11 => 'NOV',
  _ => 'DEC',
};
