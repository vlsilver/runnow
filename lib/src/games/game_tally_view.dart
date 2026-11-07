import 'package:flutter/material.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Bảng kiểm phiếu dưới một action (đề cử, biểu quyết, sói bầu cắn): mỗi lựa
/// chọn có số phiếu, tổng km nhóm phiếu và người bầu; phiếu bị cắt gạch tên.
/// Hàng đang dẫn có nhãn, dòng lý do nói vì sao. Bảng cắn chỉ phe Sói thấy.
class GameTallyView extends StatelessWidget {
  const GameTallyView({super.key, required this.kind, required this.tally});

  final String kind;
  final GameTally tally;

  bool get _wolf => kind == 'wolf_bite';

  String _tag(GameTallyRow row) => switch (kind) {
    'nominate' => 'LÊN GIÀN',
    'wolf_bite' => 'CẮN',
    _ => row.id == 'spare' ? 'THA' : 'TREO',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final accent = _wolf ? RunNowSemanticColors.danger : palette.accentDeep;
    final most = tally.rows.fold<int>(1, (m, r) => r.votes > m ? r.votes : m);
    final reason = tally.reason;
    final note = tally.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'KIỂM PHIẾU',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
                color: palette.textMuted,
              ),
            ),
            if (tally.seats > 1) ...[
              const SizedBox(width: 6),
              Text(
                '· ${tally.seats} suất',
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ],
            const Spacer(),
            if (_wolf)
              const Text(
                'CHỈ PHE SÓI',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: RunNowSemanticColors.danger,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final row in tally.rows) ...[
          _Row(
            row: row,
            share: row.votes / most,
            accent: accent,
            tag: row.lead ? _tag(row) : null,
          ),
          const SizedBox(height: 8),
        ],
        if (reason != null && reason.isNotEmpty)
          Text(
            '● $reason',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: palette.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.share,
    required this.accent,
    required this.tag,
  });

  final GameTallyRow row;

  /// Phần thanh nền theo số phiếu, so với hàng nhiều phiếu nhất.
  final double share;
  final Color accent;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final tag = this.tag;
    return Container(
      decoration: BoxDecoration(
        color: palette.tint.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tag != null ? accent : palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: share.clamp(0, 1),
              child: ColoredBox(color: accent.withValues(alpha: 0.12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    if (tag != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                            color: palette.background,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        text: '${row.votes}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: palette.ink,
                        ),
                        children: [
                          TextSpan(
                            text: ' phiếu',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  '${gameTallyKm(row.km)} km',
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
                if (row.voters.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final v in row.voters) _VoterChip(v)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoterChip extends StatelessWidget {
  const _VoterChip(this.voter);

  final GameTallyVoter voter;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final v = voter;
    final weight = v.weight > 1 && !v.cut ? ' · x${v.weight}' : '';
    return Opacity(
      opacity: v.cut ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${v.name} · ${gameTallyKm(v.km)}$weight',
          style: TextStyle(
            fontSize: 11,
            color: palette.textMuted,
            decoration: v.cut ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

/// Km một chữ số lẻ, bỏ ".0".
String gameTallyKm(double km) {
  final r = (km * 10).roundToDouble() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toStringAsFixed(1);
}
