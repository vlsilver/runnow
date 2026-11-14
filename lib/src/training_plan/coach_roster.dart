import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/cached_avatar.dart';
import 'training_plan_models.dart';
import 'package:myrun/src/widgets/run_now_avatar.dart';

/// Bảng "đang theo giáo án" — mỗi người một dòng với tiến độ riêng. Dùng chung
/// cho màn chi tiết coach (người tham gia xem) lẫn hub của chủ giáo án (theo dõi
/// cả nhóm). Chỉ có ý nghĩa với giáo án công khai nhiều người.
class CoachRoster extends StatelessWidget {
  const CoachRoster({
    super.key,
    required this.plan,
    required this.members,
    required this.currentUid,
  });

  final TrainingPlan plan;
  final List<MemberProfile> members;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final total = plan.totalSessions;
    if (plan.participants.isEmpty) return const SizedBox.shrink();

    // Chỉ đếm index ứng với BUỔI THẬT (không rest, còn trong lịch) — khớp cách
    // summary/card đếm doneSessions, bền với index rác khi lịch bị đổi.
    final validSessions = <int>{
      for (var i = 0; i < plan.days.length; i++)
        if (!plan.days[i].isRest) i,
    };

    final names = {for (final m in members) m.uid: m.displayName};
    final entries = plan.participants.values.toList()
      ..sort((a, b) {
        if (a.uid == plan.ownerUid) return -1;
        if (b.uid == plan.ownerUid) return 1;
        return b.doneIndices.length.compareTo(a.doneIndices.length);
      });

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        borderRadius: palette.radius(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 17, color: palette.accent),
              const SizedBox(width: 7),
              Text(
                'Đang theo (${entries.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in entries)
            _row(
              palette,
              name: p.uid == currentUid
                  ? 'Bạn'
                  : (names[p.uid] ?? 'Thành viên'),
              isOwner: p.uid == plan.ownerUid,
              done: p.doneIndices.where(validSessions.contains).length,
              total: total,
            ),
        ],
      ),
    );
  }

  Widget _row(
    RunNowPalette palette, {
    required String name,
    required bool isOwner,
    required int done,
    required int total,
  }) {
    final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                ),
                if (isOwner) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: palette.wash(palette.accent, 0.14),
                      borderRadius: palette.radius(999),
                    ),
                    child: Text(
                      'HLV',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: palette.radius(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: palette.border,
                valueColor: AlwaysStoppedAnimation(palette.accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$done/$total',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chồng avatar người đang theo giáo án trên AppBar; chạm mở bảng tiến độ
/// từng người. Giáo án chưa ai theo thì không hiện gì.
class CoachFollowersButton extends StatelessWidget {
  const CoachFollowersButton({
    super.key,
    required this.plan,
    required this.members,
    required this.currentUid,
  });

  final TrainingPlan plan;
  final List<MemberProfile> members;
  final String? currentUid;

  static const _shown = 3;
  static const _size = 28.0;
  static const _step = 19.0;

  @override
  Widget build(BuildContext context) {
    final count = plan.participantCount;
    if (count == 0) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final byUid = {for (final m in members) m.uid: m};
    final uids = plan.participants.keys.take(_shown).toList();

    return Semantics(
      button: true,
      label: '$count người đang theo',
      child: InkWell(
        borderRadius: context.runNowPalette.radius(999),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: palette.background,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: CoachRoster(
                plan: plan,
                members: members,
                currentUid: currentUid,
              ),
            ),
          ),
        ),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _size + _step * (uids.length - 1),
                  height: _size,
                  child: Stack(
                    children: [
                      for (var i = 0; i < uids.length; i++)
                        Positioned(
                          left: _step * i,
                          child: _avatar(context, palette, byUid[uids[i]]),
                        ),
                    ],
                  ),
                ),
                if (count > uids.length) ...[
                  const SizedBox(width: 5),
                  Text(
                    '+${count - uids.length}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(
    BuildContext context,
    RunNowPalette palette,
    MemberProfile? member,
  ) {
    final url = member?.avatarUrl;
    final name = member?.displayName ?? '';
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: context.runNowPalette.round,
        border: Border.all(color: palette.background, width: 2),
      ),
      child: RunNowAvatar(
        backgroundColor: palette.tint,
        backgroundImage: url == null || url.isEmpty
            ? null
            : cachedAvatarImage(context, url, _size),
        child: url == null || url.isEmpty
            ? Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: palette.accentDeep,
                ),
              )
            : null,
      ),
    );
  }
}
