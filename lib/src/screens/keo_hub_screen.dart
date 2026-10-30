import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/club_card_widgets.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_insights.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart'
    show runContractStateColor;
import 'package:myrun/src/screens/run_contract_home_screen.dart'
    show ContractSyncAction, startCreateContract;
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';
import 'package:myrun/src/training_plan/training_plan_repository.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/club_run_row.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/live_map_preview.dart';
import 'package:myrun/src/widgets/hub_scene.dart';

/// Trang đầu của app: ai trong club đang chạy, các kèo đang diễn ra, ai dẫn
/// BXH tuần, thẻ vừa khoe, rồi các buổi chạy gần đây. Mục nào rỗng thì ẩn, riêng Kèo và Thẻ rỗng
/// thì còn một dòng mời đặt kèo, khoe thẻ.
class KeoHubScreen extends ConsumerWidget {
  const KeoHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(stravaConnectionProvider);
    final sync = ref.watch(syncControllerProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(hubClubContractsProvider);
            ref.invalidate(gameListProvider);
            ref.invalidate(hubClubRunsProvider);
            ref.invalidate(stepLeaderboardDocsProvider);
            await ref
                .read(hubClubContractsProvider.future)
                .catchError(
                  (Object _) =>
                      const RunContractPage(contracts: [], hasMore: false),
                );
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 130),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 14),
                child: Row(
                  children: [
                    const Spacer(),
                    if (connected)
                      ContractSyncAction(
                        syncing: sync.syncing,
                        synced: sync.lastSyncSucceeded,
                        onPressed: () => ref
                            .read(syncControllerProvider)
                            .startBackgroundSync(force: true),
                      ),
                  ],
                ),
              ),
              const _LiveSection(),
              const _KeoSection(),
              const _RankSection(),
              const _CardsSection(),
              const _RunsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trang đầu của danh sách kèo club. Lỗi thì để mục Kèo báo, không nuốt.
final hubClubContractsProvider = FutureProvider.autoDispose<RunContractPage>(
  (ref) => ref
      .watch(runContractRepositoryProvider)
      .fetchClubContractsPage(limit: 20),
);

class HubSectionHeader extends StatelessWidget {
  const HubSectionHeader({
    required this.title,
    this.onMore,
    this.action,
    super.key,
  });

  final String title;
  final VoidCallback? onMore;

  /// Nút cạnh tiêu đề, vd đặt kèo.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onMore,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            ?action,
            if (onMore != null)
              Icon(
                Icons.chevron_right_rounded,
                color: onSurface.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- LIVE

class _LiveSection extends ConsumerWidget {
  const _LiveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final live = ref.watch(clubLiveSessionsProvider);
    return live.when(
      data: (sessions) {
        final others = [
          for (final session in sessions)
            if (session.ownerUid != uid) session,
        ];
        if (others.isEmpty) {
          // Chính mình đang live thì thôi mời. Web không có tab Chạy.
          final meLive = sessions.length > others.length;
          if (meLive || kIsWeb) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _InviteRow(
              title: 'Chưa ai đang chạy live',
              subtitle: 'Chạm để bắt đầu buổi chạy của bạn.',
              icon: Icons.directions_run_rounded,
              // Sang tab Chạy như nút ở thanh dưới, không mở thêm màn ghi.
              onTap: () => StatefulNavigationShell.of(context).goBranch(2),
            ),
          );
        }
        if (others.length == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LiveSessionCard(session: others.single),
          );
        }
        final width = MediaQuery.sizeOf(context).width - 60;
        return SizedBox(
          height: LiveSessionCard.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: others.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: LiveSessionCard(session: others[index]),
            ),
          ),
        );
      },
      // Live chỉ là phần thêm: lỗi thì báo một dòng, phần còn lại vẫn dùng
      // được.
      error: (error, stack) {
        debugPrint('club live sessions: $error');
        return _RetryRow(
          label: 'Không tải được ai đang chạy. Chạm để thử lại.',
          onTap: () => ref.invalidate(clubLiveSessionsProvider),
        );
      },
      loading: () => const SizedBox.shrink(),
    );
  }
}

class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({required this.session, super.key});

  static const height = 236.0;

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: height,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(26),
        color: palette.tint,
        child: InkWell(
          onTap: () => context.push('/live/${session.id}'),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.tint, palette.glassStart],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: LiveMapPreview(
                  session: session,
                  // Chừa hàng nhãn LIVE ở trên và tấm tên, số km ở dưới.
                  padding: const EdgeInsets.fromLTRB(28, 56, 28, 76),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                top: 14,
                child: Row(
                  children: [
                    const LiveBadge(),
                    const Spacer(),
                    _GlassPill(
                      child: EverySecond(
                        builder: (context, now) => Text(
                          formatDuration(liveElapsedSeconds(session, now)),
                          style: const TextStyle(
                            fontFamily: 'Barlow Condensed',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _GlassPill(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
                  child: Row(
                    children: [
                      _Avatar(
                        url: session.ownerAvatarUrl,
                        name: session.ownerName,
                        size: 34,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.ownerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              formatPace(session.averagePaceSecondsPerKm),
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _BigNumber(
                        value: (session.distanceMeters / 1000).toStringAsFixed(
                          2,
                        ),
                        unit: 'km',
                        size: 34,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- KÈO

class _KeoSection extends ConsumerWidget {
  const _KeoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final mine = ref.watch(myActiveContractsProvider);
    final club = ref.watch(hubClubContractsProvider);
    final games =
        ref.watch(gameListProvider).value?.items ?? const <GameListItem>[];
    final coach = ref.watch(coachPlanProvider).value;
    final error = mine.error ?? club.error;
    if (error != null) debugPrint('hub contracts: $error');
    final contracts = _mergeActive(
      club.value?.contracts ?? const [],
      mine.value ?? const [],
      uid,
    );
    final showCoach = coach != null && !coach.isDraft && !coach.completed;
    final loading =
        (mine.isLoading && !mine.hasValue) ||
        (club.isLoading && !club.hasValue);

    Future<void> create() async {
      final created = await startCreateContract(
        context,
        ref,
        mine.value ?? const [],
        uid,
      );
      if (created) ref.invalidate(hubClubContractsProvider);
    }

    final cards = <Widget>[
      for (final game in games)
        _GameMiniCard(
          game: game,
          onTap: () async {
            await context.push('/games/${game.id}');
            ref.invalidate(gameListProvider);
          },
        ),
      if (showCoach)
        _CoachMiniCard(
          plan: coach,
          onTap: () => context.push('/coach/${coach.id}'),
        ),
      for (final contract in contracts)
        _ContractMiniCard(contract: contract, currentUid: uid),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionHeader(
          title: 'Kèo đang chạy',
          onMore: () => context.push('/contracts'),
          // Rỗng thì dòng mời bên dưới đã có nút đặt kèo.
          action: cards.isEmpty ? null : _AddButton(onTap: create),
        ),
        if (error != null && cards.isEmpty)
          _RetryRow(
            label: 'Không tải được kèo. Chạm để thử lại.',
            onTap: () {
              ref.invalidate(myActiveContractsProvider);
              ref.invalidate(hubClubContractsProvider);
            },
          )
        else if (loading && cards.isEmpty)
          const SizedBox(height: _MiniCard.height)
        else if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _InviteRow(
              title: 'Đặt kèo tuần này',
              subtitle: 'tự đặt hay rủ club',
              icon: Icons.add_rounded,
              onTap: create,
            ),
          )
        else
          SizedBox(
            height: _MiniCard.height + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => cards[index],
            ),
          ),
      ],
    );
  }
}

/// Kèo đang chạy của club cộng kèo của mình (bản của mình mới hơn). Kèo mình
/// tham gia đứng trước, rồi kèo nào sắp hết hạn trước.
List<RunContract> _mergeActive(
  List<RunContract> club,
  List<RunContract> mine,
  String? uid,
) {
  final byId = {
    for (final contract in club)
      if (contract.isActive) contract.id: contract,
  };
  for (final contract in mine) {
    if (contract.isActive) byId[contract.id] = contract;
  }
  int rank(RunContract c) => c.participantFor(uid) == null ? 1 : 0;
  return byId.values.toList()..sort((a, b) {
    final byMine = rank(a).compareTo(rank(b));
    if (byMine != 0) return byMine;
    if (a.openEnded != b.openEnded) return a.openEnded ? 1 : -1;
    return a.endAtExclusive.compareTo(b.endAtExclusive);
  });
}

/// Thẻ đứng ở hàng Kèo, nền là tranh [scene].
class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.child,
    required this.onTap,
    required this.scene,
  });

  static const width = 164.0;
  static const height = 208.0;

  final Widget child;
  final VoidCallback onTap;
  final HubScene scene;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: HubSceneCard(
        scene: scene,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _ContractMiniCard extends StatelessWidget {
  const _ContractMiniCard({required this.contract, required this.currentUid});

  final RunContract contract;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final state = contractUiStateFor(contract, now, currentUid);
    final color = runContractStateColor(context, state);
    final percent = contractPercentFor(contract, currentUid);
    final joined = contract.participantFor(currentUid) != null;
    return _MiniCard(
      onTap: () => context.push('/contracts/${contract.id}'),
      scene: _contractScene(contract.metric),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Ring(
            ratio: percent / 100,
            color: color,
            label: '${percent.clamp(0, 999).toStringAsFixed(0)}%',
          ),
          const Spacer(),
          Text(
            contract.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          _MutedLine(
            joined
                ? (contract.openEnded
                      ? 'không hạn'
                      : timeLeftLabel(timeRemaining(contract, now)))
                : '${contract.participantCount} người · chưa vào',
          ),
        ],
      ),
    );
  }
}

HubScene _contractScene(RunContractMetric metric) => switch (metric) {
  RunContractMetric.distance => HubScene.road,
  RunContractMetric.activeDays => HubScene.sunrise,
  RunContractMetric.activityCount => HubScene.city,
  RunContractMetric.longestRun => HubScene.summit,
  RunContractMetric.routeCompletion => HubScene.map,
};

class _CoachMiniCard extends StatelessWidget {
  const _CoachMiniCard({required this.plan, required this.onTap});

  final TrainingPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = plan.totalSessions;
    final ratio = total == 0 ? 0.0 : plan.doneSessions / total;
    final color = context.runNowPalette.secondary;
    return _MiniCard(
      onTap: onTap,
      scene: HubScene.track,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Ring(
            ratio: ratio,
            color: color,
            label: '${plan.doneSessions}/$total',
          ),
          const Spacer(),
          Text(
            plan.goal,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          _Joiners(plan: plan),
        ],
      ),
    );
  }
}

class _GameMiniCard extends StatelessWidget {
  const _GameMiniCard({required this.game, required this.onTap});

  final GameListItem game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _MiniCard(
      onTap: onTap,
      scene: HubScene.werewolf,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🐺', style: TextStyle(fontSize: 34)),
              const Spacer(),
              if (game.hasTodo)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: RunNowGameTokens.gold,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RunNowGameTokens.nightInk,
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            game.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: RunNowGameTokens.nightMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút đặt kèo trên tiêu đề mục Kèo, để thấy ngay chứ không phải lướt tới
/// cuối hàng thẻ.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.runNowPalette.accent;
    return IconButton(
      tooltip: 'Đặt kèo',
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: _onColor(accent),
        minimumSize: const Size.square(32),
        fixedSize: const Size.square(32),
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(Icons.add_rounded, size: 22),
    );
  }
}

/// Màu chữ, icon đọc được trên nền [background].
Color _onColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
    ? Colors.white
    : Colors.black;

/// Dòng mời ở mục còn rỗng: tiêu đề, dòng phụ và nút tròn bên phải.
class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// null thì dòng chỉ để nhắc, chạm không đi đâu.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Material(
      color: palette.glassStart,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _MutedLine(subtitle),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 19,
                backgroundColor: palette.accent,
                child: Icon(icon, color: _onColor(palette.accent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- bits

// ---------------------------------------------------------------- BXH TUẦN

/// Ba người dẫn BXH Chạy/Đi bộ tuần này và hạng của mình. Đọc chung bảng với
/// tab Club (đã tải sẵn lúc mở app). Tuần chưa ai có km thì ẩn.
class _RankSection extends ConsumerWidget {
  const _RankSection();

  static const _sport = ClubRankingSport.run;
  static const _range = ClubRankingRange.currentWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(totalKmLeaderboardProvider);
    if (board.error case final error?) {
      debugPrint('Không tải được BXH tuần: $error');
      return _RetryRow(
        label: 'Không tải được bảng xếp hạng. Chạm để thử lại.',
        onTap: () => ref.invalidate(stepLeaderboardDocsProvider),
      );
    }
    final entries = board.value ?? const <LeaderboardEntry>[];
    final ranked = rankClubMembers(entries, _sport, _range);
    if (ranked.isEmpty) return const SizedBox.shrink();
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final myIndex = ranked.indexWhere((member) => member.entry.uid == uid);
    final private = entries.any((e) => e.uid == uid && !e.isPublic);
    void open() {
      ref.read(clubRankingSportProvider.notifier).state = _sport;
      ref.read(clubRankingRangeProvider.notifier).state = _range;
      StatefulNavigationShell.of(context).goBranch(1);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionHeader(title: 'BXH tuần', onMore: open),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: context.runNowPalette.tint,
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Podium(top: ranked.take(3).toList()),
                    const SizedBox(height: 14),
                    _MyRankLine(
                      me: myIndex < 0 ? null : ranked[myIndex],
                      gap: myIndex < 0
                          ? null
                          : clubRankingGapLabel(ranked, myIndex, _sport),
                      private: private,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bục nhận giải: hạng 2 bên trái, hạng 1 giữa và cao nhất, hạng 3 bên phải.
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  final List<ClubRankedMember> top;

  @override
  Widget build(BuildContext context) {
    Widget place(int index) => Expanded(
      child: index < top.length
          ? _PodiumPlace(member: top[index], place: index + 1)
          : const SizedBox.shrink(),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [place(1), place(0), place(2)],
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  const _PodiumPlace({required this.member, required this.place});

  final ClubRankedMember member;

  /// Chỗ đứng trên bục (1–3), quyết định cỡ avatar và độ cao bục. Hạng in
  /// trên bục là [ClubRankedMember.rank], bằng điểm thì chung hạng.
  final int place;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final medal = (light
        ? RunNowRankColors.light
        : RunNowRankColors.dark)[place - 1];
    final entry = member.entry;
    final avatar = place == 1 ? 58.0 : 46.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: medal),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: _Avatar(
                url: entry.avatarUrl,
                name: entry.displayName,
                size: avatar,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          _BigNumber(
            value: (member.score / 1000).toStringAsFixed(1),
            unit: 'km',
            size: place == 1 ? 24 : 20,
          ),
          const SizedBox(height: 6),
          Container(
            height: switch (place) {
              1 => 34.0,
              2 => 24.0,
              _ => 16.0,
            },
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Text(
              '${member.rank}',
              style: TextStyle(
                fontFamily: 'Barlow Condensed',
                fontSize: place == 1 ? 20 : 15,
                height: 1,
                fontWeight: FontWeight.w800,
                color: _onColor(medal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dòng dưới bục: hạng của mình và còn bao xa để lên hạng.
class _MyRankLine extends StatelessWidget {
  const _MyRankLine({
    required this.me,
    required this.gap,
    required this.private,
  });

  final ClubRankedMember? me;
  final String? gap;

  /// Hồ sơ riêng tư thì không lên BXH, nói rõ để không tưởng là thiếu km.
  final bool private;

  @override
  Widget build(BuildContext context) {
    final me = this.me;
    final palette = context.runNowPalette;
    if (me == null) {
      return _MutedLine(
        private
            ? 'Hồ sơ của bạn đang riêng tư nên không lên BXH.'
            : 'Tuần này bạn chưa có km nào. Chạy một buổi để lên bảng.',
      );
    }
    return _GlassPill(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Text(
            '#${me.rank}',
            style: TextStyle(
              fontFamily: 'Barlow Condensed',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bạn',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                if (gap case final gap?) _MutedLine(gap),
              ],
            ),
          ),
          _BigNumber(
            value: (me.score / 1000).toStringAsFixed(1),
            unit: 'km',
            size: 24,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- BUỔI CHẠY

class _RunsSection extends ConsumerWidget {
  const _RunsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(hubClubRunsProvider);
    if (runs.error case final error?) {
      debugPrint('Không tải được buổi chạy của club: $error');
      return _RetryRow(
        label: 'Không tải được buổi chạy. Chạm để thử lại.',
        onTap: () => ref.invalidate(hubClubRunsProvider),
      );
    }
    final items = runs.value ?? const <ClubRunItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionHeader(
          title: 'Buổi chạy',
          onMore: () => context.push('/club-runs'),
        ),
        SizedBox(
          height: _MiniCard.height + 12,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: _MiniCard.width,
              child: ClubRunCard(item: items[index]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Thẻ club vừa khoe, xếp ngang.
class _CardsSection extends ConsumerWidget {
  const _CardsSection();

  static const _shown = 10;
  static const _thumbWidth = 150.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(clubCardsProvider);
    if (cards.error case final error?) {
      debugPrint('Không tải được thẻ của club: $error');
      return _RetryRow(
        label: 'Không tải được thẻ. Chạm để thử lại.',
        onTap: () => ref.invalidate(clubCardsProvider),
      );
    }
    // Chưa tải xong thì chưa hiện gì, để dòng mời không nháy lên rồi biến mất.
    if (!cards.hasValue) return const SizedBox.shrink();
    final items = cards.requireValue.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HubSectionHeader(
          title: 'Thẻ mới',
          onMore: () => context.push('/club-cards'),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _InviteRow(
              title: 'Chưa ai có thẻ mới',
              subtitle: 'chạy xong lật thẻ, thẻ tự lên đây',
              icon: Icons.style_rounded,
              // Bộ thẻ nằm ở tab Hồ sơ; chạm mà nhảy tab thì rời trang Kèo.
              onTap: null,
            ),
          )
        else
          SizedBox(
            height: clubCardThumbHeight(_thumbWidth),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) =>
                  ClubCardThumb(item: items[i], width: _thumbWidth),
            ),
          ),
      ],
    );
  }
}

class _RetryRow extends StatelessWidget {
  const _RetryRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onTap, child: Text(label)),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.ratio, required this.color, required this.label});

  final double ratio;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox.square(
      dimension: 58,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            strokeWidth: 7,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: onSurface.withValues(alpha: 0.2),
          ),
          Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Barlow Condensed',
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar những người đang theo giáo án, chủ giáo án đứng đầu.
class _Joiners extends ConsumerWidget {
  const _Joiners({required this.plan});

  final TrainingPlan plan;

  static const _size = 22.0;
  static const _step = 15.0;
  static const _shown = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = {
      for (final member in ref.watch(membersProvider).value ?? const [])
        member.uid: member,
    };
    final uids = plan.participants.keys.toList()
      ..sort((a, b) {
        if (a == plan.ownerUid) return -1;
        if (b == plan.ownerUid) return 1;
        return a.compareTo(b);
      });
    if (uids.isEmpty) return const _MutedLine('giáo án');
    final shown = uids.take(_shown).toList();
    final more = uids.length - shown.length;
    return Row(
      children: [
        SizedBox(
          width: _size + (shown.length - 1) * _step,
          height: _size,
          child: Stack(
            children: [
              for (final (i, uid) in shown.indexed)
                Positioned(
                  left: i * _step,
                  child: DecoratedBox(
                    // Viền tối tách các avatar chồng lên nhau trên tranh.
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: RunNowHubSceneTokens.shade,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: ClubAvatar(member: members[uid], size: _size - 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (more > 0) ...[const SizedBox(width: 6), _MutedLine('+$more')],
      ],
    );
  }
}

class _MutedLine extends StatelessWidget {
  const _MutedLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        fontFamily: 'Barlow Condensed',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.child,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.border.withValues(alpha: 0.5)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.value, required this.unit, this.size = 34});

  final String value;
  final String unit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value),
          TextSpan(
            text: ' $unit',
            style: TextStyle(
              fontSize: size * 0.44,
              color: onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      style: TextStyle(
        fontFamily: 'Barlow Condensed',
        fontSize: size,
        height: 0.95,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, this.size = 32});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: context.runNowPalette.accent,
      backgroundImage: hasUrl ? cachedAvatarImage(context, url!, size) : null,
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
