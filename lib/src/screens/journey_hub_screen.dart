import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/journey/journey_timeline.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';

class JourneyHubScreen extends StatelessWidget {
  const JourneyHubScreen({super.key, this.memberUid, this.member});

  final String? memberUid;
  final MemberProfile? member;

  @override
  Widget build(BuildContext context) {
    final uid = memberUid;
    return Scaffold(
      backgroundColor: context.runNowPalette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  _JourneyHeader(
                    title: member?.displayName ?? 'Hành Trình',
                    subtitle: member == null ? null : 'Hành trình',
                    onJournalTap: () => uid == null
                        ? context.push('/journal')
                        : context.push('/club/$uid/journal'),
                  ),
                  const SizedBox(height: 14),
                  _JourneyHero(memberUid: uid),
                  const SizedBox(height: 10),
                  const _DailyQuoteCard(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            JourneyTimeline(memberUid: uid, member: member),
          ],
        ),
      ),
    );
  }
}

class _JourneyHeader extends StatelessWidget {
  const _JourneyHeader({
    required this.title,
    required this.subtitle,
    required this.onJournalTap,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onJournalTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.ink,
                  fontSize: 27,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.55),
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        Material(
          color: palette.glassStart,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          child: IconButton(
            tooltip: 'Nhật ký chạy',
            onPressed: onJournalTap,
            icon: Icon(Icons.list_alt_rounded, color: palette.ink),
          ),
        ),
      ],
    );
  }
}

/// Card hero — 4 con số cho 1 trong 4 mốc Tuần/Tháng/Năm/Total: Quãng
/// đường + Thời gian ở trên, Sức mạnh to ở giữa, Độ cao ở dưới. Toàn bộ đọc
/// từ [journeyPowerSnapshotProvider] (gộp trên `periodStats` đã tính sẵn ở
/// backend), không kéo activity raw lên tính lại.
class _JourneyHero extends ConsumerWidget {
  const _JourneyHero({required this.memberUid});

  final String? memberUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUid = ref.watch(firebaseUserProvider).value?.uid;
    final targetUid = memberUid ?? currentUid;
    final scope = ref.watch(journeyPowerScopeProvider);
    final snapshotState = targetUid == null
        ? null
        : ref.watch(
            journeyPowerSnapshotProvider((uid: targetUid, scope: scope)),
          );
    final snapshot = snapshotState?.value;
    final loading = targetUid != null && snapshot == null;
    final stats = snapshot?.stats;
    final score = snapshot == null
        ? null
        : journeyPowerScore(
            snapshot.stats,
            scope,
            activeMonths: snapshot.activeMonths,
          );

    // Nền tối nhưng nhuốm màu theo hành đang chọn (Kim/Thủy/Mộc/Hỏa/Thổ) thay
    // vì đen phẳng — dùng đúng công thức "tint" tối của RunNowPalette, chỉ
    // ép appearance=dark vì hero luôn tối bất kể app đang sáng hay tối.
    final elementDarkPalette = RunNowPalette.forSelection(
      context.runNowPalette.element,
      appearance: RunNowAppearance.dark,
    );
    final cardColor = elementDarkPalette.tint;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JourneyPowerScopeSelector(
            palette: elementDarkPalette,
            scope: scope,
            onChanged: (next) =>
                ref.read(journeyPowerScopeProvider.notifier).state = next,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showPowerScoreHint(context, scope),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  loading ? '--' : '$score',
                  style: TextStyle(
                    color: elementDarkPalette.ink,
                    fontSize: 64,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'điểm sức mạnh',
                    style: TextStyle(
                      color: elementDarkPalette.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: elementDarkPalette.ink.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  elementDarkPalette,
                  loading
                      ? '--'
                      : (stats!.distanceMeters / 1000)
                            .toStringAsFixed(1)
                            .replaceAll('.', ','),
                  'km',
                ),
              ),
              Expanded(
                child: _heroStat(
                  elementDarkPalette,
                  loading
                      ? '--'
                      : _formatHoursMinutes(stats!.movingTimeSeconds),
                  'giờ',
                ),
              ),
              Expanded(
                child: _heroStat(
                  elementDarkPalette,
                  loading ? '--' : '${stats!.elevationGainMeters.round()}',
                  'm cao',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _heroStat(RunNowPalette palette, String value, String unit) =>
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                color: palette.ink,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: ' $unit',
              style: TextStyle(
                color: palette.ink.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  static String _formatHoursMinutes(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  void _showPowerScoreHint(BuildContext context, JourneyPowerScope scope) {
    final isWeekly = scope == JourneyPowerScope.week;
    final volumeTarget = isWeekly ? '15km' : '40km';
    final loadTarget = isWeekly ? '3 giờ' : '12 giờ';
    final activeTarget = isWeekly ? '7 ngày' : '30 ngày';
    final periodNote = switch (scope) {
      JourneyPowerScope.week => 'tuần này',
      JourneyPowerScope.month => 'tháng này',
      JourneyPowerScope.year => 'trung bình mỗi tháng có hoạt động, năm nay',
      JourneyPowerScope.total =>
        'trung bình mỗi tháng có hoạt động, từ trước đến nay',
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final palette = context.runNowPalette;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Material(
              color: palette.glassStart,
              borderRadius: BorderRadius.circular(24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sức mạnh cá nhân',
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Trung bình cộng 5 chỉ số của $periodNote, mỗi chỉ '
                      'số quy về thang 0-100% rồi lấy trung bình:',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _PowerScoreFactorRow(
                      label: 'Khối lượng',
                      detail: 'tổng km / mục tiêu $volumeTarget',
                    ),
                    _PowerScoreFactorRow(
                      label: 'Đều đặn',
                      detail: 'số ngày có chạy / $activeTarget',
                    ),
                    _PowerScoreFactorRow(
                      label: 'Thời lượng',
                      detail: 'tổng thời gian chạy / mục tiêu $loadTarget',
                    ),
                    _PowerScoreFactorRow(
                      label: 'Quãng đường TB',
                      detail: 'trung bình mỗi buổi / mục tiêu 5km',
                    ),
                    _PowerScoreFactorRow(
                      label: 'Tốc độ',
                      detail: 'pace nhanh nhất, giữa 9:00 và 5:00 /km',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Đã hiểu'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Toggle Tuần/Tháng/Năm/Total — chữ thường, không viền/chip, mốc đang chọn
/// tô đậm màu vàng, đúng kiểu tab chữ đơn giản (không phải nút bấm nổi).
class _JourneyPowerScopeSelector extends StatelessWidget {
  const _JourneyPowerScopeSelector({
    required this.palette,
    required this.scope,
    required this.onChanged,
  });

  final RunNowPalette palette;
  final JourneyPowerScope scope;
  final ValueChanged<JourneyPowerScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final option in JourneyPowerScope.values)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(option),
            child: Text(
              journeyPowerScopeLabel(option),
              style: TextStyle(
                color: option == scope
                    ? palette.accent
                    : palette.ink.withValues(alpha: 0.45),
                fontSize: 15,
                fontWeight: option == scope ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// 1 dòng "tên chỉ số — cách tính" trong popup giải thích điểm Sức mạnh —
/// tách riêng để 5 chỉ số hiện đồng nhất thay vì lặp lại y hệt 1 khối Text.
class _PowerScoreFactorRow extends StatelessWidget {
  const _PowerScoreFactorRow({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 4, color: palette.accentDeep),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                      color: palette.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: detail,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card "Châm ngôn hôm nay" — tách riêng, nền vàng nhạt, đúng nguyên bản
/// thiết kế (không lồng vào trong card hero tối như bản trước).
class _DailyQuoteCard extends StatelessWidget {
  const _DailyQuoteCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"',
            style: TextStyle(
              color: palette.accentDeep,
              fontSize: 20,
              height: 0.7,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHÂM NGÔN HÔM NAY',
                  style: TextStyle(
                    color: palette.accentDeep,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mỗi kilomet là một dấu chân đặt lên bản đồ. Đi đủ lâu, '
                  'đường xa cũng thành câu chuyện của mình.',
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
