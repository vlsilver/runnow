import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/cached_avatar.dart';
import 'training_plan_models.dart';

/// Card giáo án AI Coach trên feed Kèo — ngang hàng card kèo. Bấm mở chi tiết.
///
/// Tiến độ hiển thị là của NGƯỜI ĐANG XEM khi họ là chủ / đã tham gia; nếu chưa
/// tham gia thì card mời "Tham gia".
class CoachCard extends StatelessWidget {
  const CoachCard({
    super.key,
    required this.plan,
    required this.currentUid,
    required this.onTap,
    this.ownerName,
    this.ownerAvatarUrl,
  });

  final TrainingPlan plan;
  final String? currentUid;
  final VoidCallback onTap;
  final String? ownerName;
  final String? ownerAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isMine = plan.isOwner(currentUid);
    final joined = plan.hasJoined(currentUid);
    final following = isMine || joined;

    final total = plan.totalSessions;
    final done = following ? plan.doneSessions : 0;
    final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final accent = palette.accent;

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
              // ── người tạo (HLV): avatar + tên + trạng thái, badge AI bên phải
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
                        ? null
                        : cachedAvatarImage(context, ownerAvatarUrl!, 36),
                    child: ownerAvatarUrl == null || ownerAvatarUrl!.isEmpty
                        ? Text(
                            (ownerName?.isNotEmpty ?? false)
                                ? ownerName![0].toUpperCase()
                                : '?',
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMine ? 'Bạn' : (ownerName ?? 'HLV 3i'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: palette.ink,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'HLV giáo án · ',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: palette.textMuted,
                              ),
                            ),
                            Icon(
                              plan.visibility.isPublic
                                  ? Icons.groups_rounded
                                  : Icons.lock_rounded,
                              size: 12,
                              color: palette.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              plan.visibility.isPublic ? 'Công khai' : 'Riêng tư',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: dark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 13, color: accent),
                        const SizedBox(width: 5),
                        Text(
                          'GIÁO ÁN AI',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── tên mục tiêu
              Text(
                plan.goal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${plan.weeks} tuần · $total buổi',
                style: TextStyle(fontSize: 13, color: palette.textMuted),
              ),
              const SizedBox(height: 14),
              // ── tiến độ hoặc lời mời tham gia
              if (following) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: palette.border,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '$done/$total buổi',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const Spacer(),
                    _people(palette, plan.participantCount),
                  ],
                ),
              ] else
                Row(
                  children: [
                    _people(palette, plan.participantCount),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: dark ? 0.22 : 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Tham gia',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _people(RunNowPalette palette, int count) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.person_rounded, size: 15, color: palette.textMuted),
      const SizedBox(width: 3),
      Text(
        '$count người theo',
        style: TextStyle(fontSize: 13, color: palette.textMuted),
      ),
    ],
  );
}
