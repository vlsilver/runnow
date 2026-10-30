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

/// Một dòng gọn ở mục "Buổi chạy" của trang Kèo.
class ClubRunRow extends ConsumerWidget {
  const ClubRunRow({required this.item, super.key});

  final ClubRunItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = _who(ref, item);
    final activity = item.activity;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return InkWell(
      onTap: () => context.push(who.path),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            ClubAvatar(member: who.member, size: 38),
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
                    '${feedWhenLabel(activity.startedAt, DateTime.now())} · '
                    '${clubRunDetail(activity)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            _Km(meters: activity.distanceMeters, size: 24),
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

/// Một buổi ở trang "Buổi chạy": ai, giờ, tim, rồi km và thời gian, pace.
class ClubRunPost extends ConsumerWidget {
  const ClubRunPost({required this.item, super.key});

  final ClubRunItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final who = _who(ref, item);
    final activity = item.activity;
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final time = DateFormat('HH:mm').format(activity.startedAt.toLocal());
    final name = activity.name.trim();
    return Material(
      color: palette.glassStart,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(who.path),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClubAvatar(member: who.member, size: 36),
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
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
                  HeartButton(
                    target: runHeartTarget(item.ownerUid, activity.id),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: _Km(meters: activity.distanceMeters, size: 34),
                    ),
                    Text(
                      '${formatDuration(activity.movingTimeSeconds)} · '
                      '${clubRunDetail(activity)}',
                      style: TextStyle(
                        color: muted,
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
