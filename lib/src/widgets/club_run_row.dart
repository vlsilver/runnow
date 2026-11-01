import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_overview.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/heart_button.dart';
import 'package:myrun/src/widgets/route_sketch_art.dart';

const _runKinds = {
  ActivityKind.run,
  ActivityKind.trailRun,
  ActivityKind.virtualRun,
};

/// Chạy thì ghi pace, môn khác ghi tên môn.
String clubRunDetail(ActivitySummary activity) =>
    _runKinds.contains(activity.kind)
    ? formatPace(activity.paceSecondsPerKm).replaceAll(' /', '/')
    : activityKindLabel(activity.kind).toLowerCase();

/// Người tập của [item] và đường mở chi tiết buổi. Buổi của mình mở như buổi
/// trong nhật ký.
({MemberProfile? member, bool isMe, String path}) _who(
  WidgetRef ref,
  ClubRunItem item,
) {
  final myUid = ref.watch(firebaseUserProvider).value?.uid;
  final isMe = item.ownerUid == myUid;
  final member = ref
      .watch(membersProvider)
      .value
      ?.where((member) => member.uid == item.ownerUid)
      .firstOrNull;
  final id = Uri.encodeComponent(item.activity.id);
  return (
    member: member,
    isMe: isMe,
    path: isMe ? '/activity/$id' : '/club/${item.ownerUid}/activity/$id',
  );
}

/// Một hàng ở mục "Buổi chạy" của Trang chủ: ai, bao giờ, rồi km, thời gian,
/// pace và tim. Khối bao quanh và đường kẻ giữa các hàng do chỗ đặt vẽ.
class ClubRunTile extends ConsumerWidget {
  const ClubRunTile({required this.item, super.key});

  final ClubRunItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = _who(ref, item);
    final activity = item.activity;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final when = feedWhenLabel(activity.startedAt, DateTime.now());
    final name = activity.name.trim();
    return InkWell(
      onTap: () => context.push(who.path),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            ClubAvatar(member: who.member, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    who.isMe ? 'Bạn' : who.member?.displayName ?? 'Thành viên',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    name.isEmpty ? when : '$when · $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Km(meters: activity.distanceMeters, size: 24),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(activity.movingTimeSeconds)} · '
                  '${clubRunDetail(activity)}',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            HeartButton(
              target: runHeartTarget(item.ownerUid, activity.id),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Một buổi ở trang "Buổi chạy": ai, giờ, tim, rồi km, môn, nguồn và pace,
/// thời gian, độ cao. Buổi có dáng tuyến thì vẽ tuyến làm nền nửa phải thẻ.
class ClubRunPost extends ConsumerWidget {
  const ClubRunPost({required this.item, super.key});

  final ClubRunItem item;

  // Nền tuyến rộng cố định ở mép phải; dải mờ phủ phần trái của nó để chữ
  // bên trái luôn nằm trên nền phẳng.
  static const _artWidth = 240.0;
  static const _fadeWidth = 96.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = _who(ref, item);
    final activity = item.activity;
    final palette = context.runNowPalette;
    final muted = palette.textMuted;
    final time = DateFormat('HH:mm').format(activity.startedAt.toLocal());
    final name = activity.name.trim();
    final sketch = activity.routeSketch;
    final isRun = _runKinds.contains(activity.kind);
    final colors = RouteArtColors.of(palette, walk: !isRun);
    final elevation = activity.elevationGainMeters ?? 0;
    final stats = [
      if (isRun ||
          activity.kind == ActivityKind.walk ||
          activity.kind == ActivityKind.hike)
        formatPace(activity.paceSecondsPerKm).replaceAll(' /', '/'),
      formatDuration(activity.movingTimeSeconds),
    ].join(' · ');
    final ownSource = activity.source == ActivitySource.runnow;
    final isLight = palette.appearance == RunNowAppearance.light;
    final ramp = palette.element.ramp;
    return Material(
      color: palette.glassStart,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(who.path),
        child: Stack(
          children: [
            if (sketch != null) ...[
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: _artWidth,
                child: RouteSketchArt(sketch: sketch, colors: colors),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: _artWidth - _fadeWidth,
                width: _fadeWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        palette.glassStart,
                        palette.glassStart.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Icon môn ở góc avatar: lướt là biết chạy, đi bộ hay
                      // đạp xe, cùng màu với nét tuyến.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClubAvatar(member: who.member, size: 36),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: palette.glassStart,
                                shape: BoxShape.circle,
                                border: Border.all(color: palette.border),
                              ),
                              child: Icon(
                                activityKindIcon(activity.kind),
                                size: 13,
                                color: colors.stroke,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              who.isMe
                                  ? 'Bạn'
                                  : who.member?.displayName ?? 'Thành viên',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              name.isEmpty ? time : '$time · $name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isLight
                              ? palette.glassStart.withValues(alpha: 0.85)
                              : palette.background.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: HeartButton(
                          target: runHeartTarget(item.ownerUid, activity.id),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _Km(meters: activity.distanceMeters, size: 40),
                      if (!isRun)
                        _Chip(
                          label: activityKindLabel(activity.kind).toUpperCase(),
                          background: palette.border,
                          foreground: muted,
                        ),
                      _Chip(
                        label: _sourceLabel(activity.source),
                        background: ownSource
                            ? (isLight ? ramp[4] : ramp[1])
                            : palette.border,
                        foreground: ownSource
                            ? (isLight
                                  ? palette.glassStart
                                  : palette.background)
                            : muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Font chữ của app không có glyph "↑" nên mũi tên độ cao
                  // là icon đặt giữa dòng.
                  Text.rich(
                    TextSpan(
                      text: stats,
                      children: [
                        if (elevation >= 1) ...[
                          const TextSpan(text: ' · '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(
                              Icons.arrow_upward_rounded,
                              size: 13,
                              color: muted,
                            ),
                          ),
                          TextSpan(text: ' ${elevation.round()} m'),
                        ],
                      ],
                    ),
                    style: TextStyle(
                      color: muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
}

String _sourceLabel(ActivitySource source) => switch (source) {
  ActivitySource.runnow => '3I RUN',
  ActivitySource.strava => 'STRAVA',
  ActivitySource.garmin => 'GARMIN',
  ActivitySource.appleHealth => 'APPLE HEALTH',
  ActivitySource.healthConnect => 'HEALTH CONNECT',
};

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _Km extends StatelessWidget {
  const _Km({required this.meters, required this.size});

  final double meters;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: (meters / 1000).toStringAsFixed(1)),
          TextSpan(
            text: 'km',
            style: TextStyle(
              fontSize: size * 0.5,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      style: TextStyle(
        fontFamily: 'Barlow Condensed',
        fontSize: size,
        height: 1,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class ClubAvatar extends StatelessWidget {
  const ClubAvatar({required this.member, required this.size, super.key});

  final MemberProfile? member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = member?.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = member?.displayName ?? '';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: context.runNowPalette.accent,
      backgroundImage: hasUrl ? cachedAvatarImage(context, url, size) : null,
      child: hasUrl
          ? null
          : Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
    );
  }
}
