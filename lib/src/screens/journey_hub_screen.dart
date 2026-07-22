import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_power.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

class JourneyHubScreen extends ConsumerWidget {
  const JourneyHubScreen({super.key, this.memberUid, this.member});

  final String? memberUid;
  final MemberProfile? member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = memberUid;
    final lifetimeState = uid == null
        ? ref.watch(journeyLifetimeDistanceProvider)
        : ref.watch(memberJourneyLifetimeDistanceProvider(uid));
    final selectedRouteId = uid == null
        ? parseJourneyRouteId(
            ref.watch(userProfileProvider).value?.journeyRouteId,
          )
        : parseJourneyRouteId(member?.journeyRouteId);
    // Chỉ Xuyên Việt cho chọn 1 trong 2 cung; các chiến dịch khác luôn dùng
    // cung duy nhất của nó.
    JourneyRouteId routeIdFor(JourneyCampaignId campaign) {
      if (selectedRouteId != null &&
          campaign.routeChoices.contains(selectedRouteId)) {
        return selectedRouteId;
      }
      return campaign.routeChoices.first;
    }

    final levels = [
      for (final campaign in journeyCampaignOrder)
        _JourneyLevelDraft(
          campaign: campaign,
          offsetState: ref.watch(journeyCampaignOffsetProvider(campaign)),
          routeState: ref.watch(
            journeyRouteSummaryProvider(routeIdFor(campaign)),
          ),
        ),
    ];

    final error = lifetimeState.error;
    final loadedLevels = [
      for (final level in levels)
        if (level.routeState.value != null && level.offsetState.value != null)
          _JourneyLevel(
            campaign: level.campaign,
            route: level.routeState.value!,
            offsetMeters: level.offsetState.value!,
          ),
    ];
    final levelsLoading = loadedLevels.length != levels.length;

    final palette = context.runNowPalette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: lifetimeState.value == null && error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Không tải được hành trình: $error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            : _JourneyHubContent(
                memberUid: uid,
                title: member?.displayName ?? 'Hành Trình',
                subtitle: member == null ? null : 'Hành trình',
                totalDistanceMeters: lifetimeState.value ?? 0,
                distanceLoading: lifetimeState.value == null,
                levels: loadedLevels,
                levelsLoading: levelsLoading,
              ),
      ),
    );
  }
}

class _JourneyHubContent extends StatelessWidget {
  const _JourneyHubContent({
    required this.memberUid,
    required this.title,
    required this.subtitle,
    required this.totalDistanceMeters,
    required this.distanceLoading,
    required this.levels,
    required this.levelsLoading,
  });

  final String? memberUid;
  final String title;
  final String? subtitle;
  final double totalDistanceMeters;
  final bool distanceLoading;
  final List<_JourneyLevel> levels;
  final bool levelsLoading;

  @override
  Widget build(BuildContext context) {
    final states = [
      for (final level in levels)
        level.toState(totalDistanceMeters: totalDistanceMeters),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Column(
            children: [
              _JourneyHeader(
                title: title,
                subtitle: subtitle,
                onJournalTap: () => memberUid == null
                    ? context.push('/profile/journal')
                    : context.push('/club/$memberUid/journal'),
              ),
              const SizedBox(height: 14),
              _JourneyHero(memberUid: memberUid),
              const SizedBox(height: 10),
              const _DailyQuoteCard(),
            ],
          ),
        ),
        Expanded(
          child: states.isEmpty && levelsLoading
              ? const RunNowLoading(compact: true, label: 'Đang mở hành trình')
              : _JourneyLevelList(
                  states: states,
                  enableDetail: memberUid == null,
                ),
        ),
      ],
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
                  loading ? '--' : _formatHoursMinutes(stats!.movingTimeSeconds),
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
                fontWeight: option == scope
                    ? FontWeight.w900
                    : FontWeight.w700,
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

class _JourneyLevelList extends StatelessWidget {
  const _JourneyLevelList({required this.states, required this.enableDetail});

  final List<_JourneyLevelState> states;
  final bool enableDetail;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      itemCount: states.length,
      itemBuilder: (context, index) {
        return _JourneyLevelRow(
          state: states[index],
          enableDetail: enableDetail,
          isFirst: index == 0,
          isLast: index == states.length - 1,
        );
      },
    );
  }
}

class _JourneyLevelRow extends StatelessWidget {
  const _JourneyLevelRow({
    required this.state,
    required this.enableDetail,
    required this.isFirst,
    required this.isLast,
  });

  final _JourneyLevelState state;
  final bool enableDetail;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    // Timeline vẽ theo từng hàng: mỗi node tự vẽ đoạn nối lên node trên và
    // xuống node dưới — nhờ IntrinsicHeight, cột trái luôn cao bằng card nên
    // đường kẻ luôn nối liền đúng các chấm dù card cao thấp khác nhau. Đoạn
    // đã đi qua (tới level đã/đang chạy) tô màu nhấn, đoạn chưa tới để xám.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineColumn(state: state, isFirst: isFirst, isLast: isLast),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: _LevelCard(state: state, enableDetail: enableDetail),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cột timeline bên trái 1 hàng: đoạn nối trên + node + đoạn nối dưới. Node
/// ghim gần đỉnh card (canh với tiêu đề); hai đoạn nối kéo hết phần còn lại
/// nên nối liền mạch với hàng kề trên/dưới.
class _TimelineColumn extends StatelessWidget {
  const _TimelineColumn({
    required this.state,
    required this.isFirst,
    required this.isLast,
  });

  final _JourneyLevelState state;
  final bool isFirst;
  final bool isLast;

  static const _nodeTopOffset = 14.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    // Đã "đi qua" khi level không còn khoá; đã "hoàn tất" khi done.
    final reached = state.status != _JourneyLevelStatus.locked;
    final completed = state.status == _JourneyLevelStatus.done;
    final activeColor = palette.accentDeep;
    return SizedBox(
      width: 26,
      child: Column(
        children: [
          SizedBox(
            height: _nodeTopOffset,
            child: _Connector(
              color: isFirst
                  ? Colors.transparent
                  : (reached ? activeColor : palette.border),
            ),
          ),
          _LevelNode(state: state),
          Expanded(
            child: _Connector(
              color: isLast
                  ? Colors.transparent
                  : (completed ? activeColor : palette.border),
            ),
          ),
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 2.5,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _LevelNode extends StatefulWidget {
  const _LevelNode({required this.state});

  final _JourneyLevelState state;

  @override
  State<_LevelNode> createState() => _LevelNodeState();
}

class _LevelNodeState extends State<_LevelNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _LevelNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.status != widget.state.status) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.state.status == _JourneyLevelStatus.current) {
      _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final status = widget.state.status;
    if (status == _JourneyLevelStatus.done) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.tertiary, palette.accentDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.accentDeep.withValues(alpha: 0.4),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
      );
    }

    if (status == _JourneyLevelStatus.current) {
      return SizedBox(
        width: 24,
        height: 24,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final scale = 0.85 + (_pulse.value * 0.75);
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: 0.9 * (1 - _pulse.value),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.accent, width: 1.5),
                      ),
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.ink,
              shape: BoxShape.circle,
              border: Border.all(color: palette.accent, width: 1.5),
            ),
            child: Text(
              '${widget.state.level}',
              style: TextStyle(
                color: palette.accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: palette.border, shape: BoxShape.circle),
      child: Icon(
        Icons.lock_outline_rounded,
        color: palette.textMuted,
        size: 12,
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.state, required this.enableDetail});

  final _JourneyLevelState state;
  final bool enableDetail;

  @override
  Widget build(BuildContext context) {
    final locked = state.status == _JourneyLevelStatus.locked;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: locked
            ? () => _showLockedMessage(context)
            : enableDetail
            ? () => _open(context)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: _decoration(context.runNowPalette),
          child: switch (state.status) {
            _JourneyLevelStatus.done => _DoneCardContent(state: state),
            _JourneyLevelStatus.current => _CurrentCardContent(state: state),
            _JourneyLevelStatus.locked => _LockedCardContent(state: state),
          },
        ),
      ),
    );
  }

  BoxDecoration _decoration(RunNowPalette palette) {
    return switch (state.status) {
      _JourneyLevelStatus.done => BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      _JourneyLevelStatus.current => BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      _JourneyLevelStatus.locked => BoxDecoration(
        color: Color.alphaBlend(
          palette.border.withValues(alpha: 0.5),
          palette.glassStart,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
    };
  }

  void _open(BuildContext context) {
    context.push('/profile/journey/${state.campaign.value}');
  }

  void _showLockedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Chinh phục cấp trước để mở khoá ${state.campaign.name}.',
        ),
      ),
    );
  }
}

/// Khung chung cho cả 3 trạng thái card — nguyên bên trái luôn là ảnh thật
/// đại diện chặng (full chiều cao card, không phải icon nhỏ nữa), bên phải
/// là nội dung riêng từng trạng thái.
class _LevelCardShell extends StatelessWidget {
  const _LevelCardShell({required this.state, required this.child});

  final _JourneyLevelState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 104,
              child: _CampaignThumbnail(state: state),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Card "đã chinh phục" — chỉ tên + km/mộc "HOÀN THÀNH" dồn xuống góc
/// dưới-phải để nhường chỗ tối đa cho ảnh.
class _DoneCardContent extends StatelessWidget {
  const _DoneCardContent({required this.state});

  final _JourneyLevelState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return _LevelCardShell(
      state: state,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardTitleStyle(palette),
          ),
          const Spacer(),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 7,
            runSpacing: 7,
            children: [
              _InfoPill(label: formatDistance(state.route.totalLengthMeters)),
              const _CompletionStampLabel(),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentCardContent extends StatelessWidget {
  const _CurrentCardContent({required this.state});

  final _JourneyLevelState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return _LevelCardShell(
      state: state,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _StatusChip(label: '● Đang chạy'),
          const SizedBox(height: 5),
          Text(
            state.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardTitleStyle(palette),
          ),
          const SizedBox(height: 8),
          Text(
            formatDistance(state.route.totalLengthMeters),
            style: TextStyle(
              color: palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _LevelProgressBar(value: state.ratio),
          const SizedBox(height: 7),
          Text(
            '${(state.ratio * 100).round()}% · còn ${formatDistance(state.remainingMeters)} nữa',
            style: TextStyle(
              color: palette.accentDeep,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedCardContent extends StatelessWidget {
  const _LockedCardContent({required this.state});

  final _JourneyLevelState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return _LevelCardShell(
      state: state,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LockedChip(),
          const SizedBox(height: 5),
          Text(
            'Hành trình bí mật',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 17,
              height: 1.18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chinh phục cấp trước để hé lộ cung đường này.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 11),
          _LevelProgressBar(value: state.ratio, locked: true),
          const SizedBox(height: 7),
          Text(
            'Còn thiếu ${formatDistance(state.remainingMeters)} để mở khoá',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _cardTitleStyle(RunNowPalette palette) => TextStyle(
  color: palette.ink,
  fontSize: 17,
  height: 1.2,
  fontWeight: FontWeight.w900,
);

class _CompletionStampLabel extends StatelessWidget {
  const _CompletionStampLabel();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Transform.rotate(
      angle: -0.16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: palette.accentDeep, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'HOÀN THÀNH',
          style: TextStyle(
            color: palette.accentDeep,
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CampaignThumbnail extends StatelessWidget {
  const _CampaignThumbnail({required this.state});

  final _JourneyLevelState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final locked = state.status == _JourneyLevelStatus.locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (locked)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.border.withValues(alpha: 0.78),
                  palette.glassStart,
                ],
              ),
            ),
          )
        else
          Image.asset(
            _campaignImageAsset(state.campaign),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: locked ? 0 : 0.04),
                Colors.black.withValues(alpha: locked ? 0 : 0.22),
              ],
            ),
          ),
        ),
        if (locked)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.glassStart,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: palette.textMuted,
                  size: 22,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _campaignImageAsset(JourneyCampaignId campaign) {
  return switch (campaign) {
    JourneyCampaignId.marathon => 'assets/journey/images/athens_marathon.jpg',
    JourneyCampaignId.montBlanc =>
      'assets/journey/images/tour_du_mont_blanc.jpg',
    JourneyCampaignId.xuyenViet => 'assets/journey/images/xuyen_viet_coast.jpg',
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.accentDeep,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LockedChip extends StatelessWidget {
  const _LockedChip();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.border,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Bí mật',
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.border.withValues(alpha: 0.5),
          palette.glassStart,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.ink,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LevelProgressBar extends StatelessWidget {
  const _LevelProgressBar({required this.value, this.locked = false});

  final double value;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 7, color: palette.border),
          AnimatedFractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: locked ? palette.border : null,
                gradient: locked
                    ? null
                    : LinearGradient(
                        colors: [palette.accentDeep, palette.tertiary],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyLevelDraft {
  const _JourneyLevelDraft({
    required this.campaign,
    required this.offsetState,
    required this.routeState,
  });

  final JourneyCampaignId campaign;
  final AsyncValue<double> offsetState;
  final AsyncValue<JourneyRouteSummary> routeState;
}

class _JourneyLevel {
  const _JourneyLevel({
    required this.campaign,
    required this.route,
    required this.offsetMeters,
  });

  final JourneyCampaignId campaign;
  final JourneyRouteSummary route;
  final double offsetMeters;

  _JourneyLevelState toState({required double totalDistanceMeters}) {
    final distanceIntoLevel = totalDistanceMeters - offsetMeters;
    final status = totalDistanceMeters < offsetMeters
        ? _JourneyLevelStatus.locked
        : totalDistanceMeters >= offsetMeters + route.totalLengthMeters
        ? _JourneyLevelStatus.done
        : _JourneyLevelStatus.current;
    final thresholdMeters = offsetMeters + route.totalLengthMeters;
    final ratio = status == _JourneyLevelStatus.locked
        ? _safeRatio(totalDistanceMeters, thresholdMeters)
        : _safeRatio(distanceIntoLevel, route.totalLengthMeters);
    return _JourneyLevelState(
      campaign: campaign,
      route: route,
      status: status,
      level: campaign.level,
      ratio: ratio,
      remainingMeters: (thresholdMeters - totalDistanceMeters).clamp(
        0.0,
        route.totalLengthMeters,
      ),
    );
  }
}

class _JourneyLevelState {
  const _JourneyLevelState({
    required this.campaign,
    required this.route,
    required this.status,
    required this.level,
    required this.ratio,
    required this.remainingMeters,
  });

  final JourneyCampaignId campaign;
  final JourneyRouteSummary route;
  final _JourneyLevelStatus status;
  final int level;
  final double ratio;
  final double remainingMeters;

  String get displayName => status == _JourneyLevelStatus.locked
      ? 'Hành trình bí mật'
      : campaign.name;
}

enum _JourneyLevelStatus { done, current, locked }

double _safeRatio(double value, double total) {
  if (total <= 0) return 0;
  return (value / total).clamp(0.0, 1.0);
}
