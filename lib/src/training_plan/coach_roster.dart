import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'training_plan_models.dart';

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
        borderRadius: BorderRadius.circular(16),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
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
              borderRadius: BorderRadius.circular(999),
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
