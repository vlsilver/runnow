import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Các chặng hành trình theo tổng km trọn đời: chặng đã xong, chặng đang chạy
/// và chặng bí mật chưa tới. [memberUid] null là hành trình của chính mình.
/// Không tự cuộn, để đặt được trong trang cuộn của màn gọi.
class JourneyTimeline extends ConsumerWidget {
  const JourneyTimeline({super.key, this.memberUid, this.member});

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
    final loadedLevels = [
      for (final level in levels)
        if (level.routeState.value != null && level.offsetState.value != null)
          _JourneyLevel(
            campaign: level.campaign,
            route: level.routeState.value!,
            offsetMeters: level.offsetState.value!,
          ),
    ];

    final palette = context.runNowPalette;
    final error = lifetimeState.error;
    if (lifetimeState.value == null && error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Không tải được hành trình: $error',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
        ),
      );
    }
    final total = lifetimeState.value ?? 0;
    final states = [
      for (final level in loadedLevels)
        level.toState(totalDistanceMeters: total),
    ];
    if (states.isEmpty && loadedLevels.length != levels.length) {
      return const RunNowLoading(compact: true, label: 'Đang mở hành trình');
    }
    return _JourneyLevelList(states: states, memberUid: memberUid);
  }
}

class _JourneyLevelList extends StatelessWidget {
  const _JourneyLevelList({required this.states, required this.memberUid});

  final List<_JourneyLevelState> states;
  final String? memberUid;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < states.length; index++)
          _JourneyLevelRow(
            state: states[index],
            memberUid: memberUid,
            isFirst: index == 0,
            isLast: index == states.length - 1,
          ),
      ],
    );
  }
}

class _JourneyLevelRow extends StatelessWidget {
  const _JourneyLevelRow({
    required this.state,
    required this.memberUid,
    required this.isFirst,
    required this.isLast,
  });

  final _JourneyLevelState state;
  final String? memberUid;
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
              child: _LevelCard(state: state, memberUid: memberUid),
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
  const _LevelCard({required this.state, required this.memberUid});

  final _JourneyLevelState state;
  final String? memberUid;

  @override
  Widget build(BuildContext context) {
    final locked = state.status == _JourneyLevelStatus.locked;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: locked
            ? () => _showLockedMessage(context)
            : () => _open(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: _decoration(context.runNowPalette),
          child: switch (state.status) {
            _JourneyLevelStatus.done => _DoneCardContent(
              state: state,
              own: memberUid == null,
            ),
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
    final uid = memberUid;
    context.push(
      uid == null
          ? '/journey/${state.campaign.value}'
          : '/club/$uid/journey/${state.campaign.value}',
    );
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
/// dưới-phải để nhường chỗ tối đa cho ảnh. Hành trình của mình mà backend đã
/// ghi thẻ chặng thì lá thẻ úp thay cho mộc.
class _DoneCardContent extends ConsumerWidget {
  const _DoneCardContent({required this.state, required this.own});

  final _JourneyLevelState state;

  /// Thẻ chỉ chủ đọc được, nên hành trình người khác giữ mộc.
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final card = own
        ? ref
              .watch(journeyCardsProvider)
              .value
              ?.where((card) => card.campaign == state.campaign.value)
              .firstOrNull
        : null;
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
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 7,
            runSpacing: 7,
            children: [
              _InfoPill(label: formatDistance(state.route.totalLengthMeters)),
              if (card == null)
                const _CompletionStampLabel()
              else
                _FaceDownJourneyCard(card: card),
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
    // Bố cục GỌN như card "hoàn thành" (tên trên, thông tin dồn đáy qua
    // Spacer) — nhờ vậy chiều cao card ~bằng các card khác, ô ảnh bên trái
    // giữ tỉ lệ NGANG thay vì bị kéo cao thành ~vuông.
    return _LevelCardShell(
      state: state,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _StatusChip(label: '● Đang chạy'),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatDistance(state.route.totalLengthMeters),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _cardTitleStyle(palette),
          ),
          const Spacer(),
          _LevelProgressBar(value: state.ratio),
          const SizedBox(height: 6),
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

/// Thẻ chặng nằm úp; chạm để mở, lật và khoe.
class _FaceDownJourneyCard extends ConsumerWidget {
  const _FaceDownJourneyCard({required this.card});

  final JourneyCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = journeyCardData(card, owner: runCardOwnerName(ref));
    return Semantics(
      button: true,
      label: 'Thẻ Hành trình ${card.name}, chạm để lật',
      child: GestureDetector(
        onTap: () => showJourneyCardViewer(context, card, data),
        child: GameCardScaled(
          width: 44,
          size: achievementCardSize,
          child: AchievementCard(data: data, back: true),
        ),
      ),
    );
  }
}

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
    JourneyCampaignId.dongNamA => 'assets/journey/images/dong_nam_a.jpg',
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
