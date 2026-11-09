import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_flow.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/run_contracts/contract_card_models.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_panel.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/widgets/run_now_empty.dart';

/// Tên in trên thẻ của chính mình.
String runCardOwnerName(WidgetRef ref) =>
    ref.watch(
      userProfileProvider.select((p) => p.asData?.value?.displayName),
    ) ??
    '3i member';

/// Một thẻ trong bộ: thẻ buổi chạy, thẻ Ma Sói của ván phe mình thắng, thẻ
/// Hành trình của chặng đã về đích, thẻ BXH hay thẻ Kèo đã lật.
sealed class CollectedCard {
  const CollectedCard();

  String get id;
  GameCardTier get tier;

  /// Lúc có thẻ: lật thẻ buổi chạy, ván Ma Sói kết thúc, hay backend trao
  /// thẻ chặng.
  DateTime? get at;

  /// Tên thẻ và dòng phụ cạnh thẻ mới nhất ở Hồ sơ.
  String get title;
  String get subtitle;

  /// Nhãn đọc màn hình của thẻ thu nhỏ.
  String get label;

  AchievementCardData data(String owner);

  /// Xem 3D, khoe từ đó. [reaction] là hàng tim khi mở từ thẻ đã khoe.
  void open(BuildContext context, AchievementCardData data, {Widget? reaction});
}

class CollectedRunCard extends CollectedCard {
  const CollectedRunCard(this.card);

  final RunCard card;

  @override
  String get id => card.id;
  @override
  GameCardTier get tier => card.tier;
  @override
  DateTime? get at => card.rolledAt;
  @override
  String get title => card.snapshot.name;
  @override
  String get subtitle =>
      '${gameCardTiers[tier]!.label} · ${runCardKm(card.km)} km';
  @override
  String get label =>
      'Thẻ ${gameCardTiers[tier]!.label} ${runCardKm(card.km)} km';
  @override
  AchievementCardData data(String owner) => runCardData(card, owner: owner);
  @override
  void open(
    BuildContext context,
    AchievementCardData data, {
    Widget? reaction,
  }) => showRunCardViewer(
    context,
    card,
    data,
    reaction: reaction,
    onDraw: () => showRunCardDraw(context, card),
  );
}

class CollectedGameCard extends CollectedCard {
  const CollectedGameCard(this.card);

  final GamePlayerCard card;

  @override
  String get id => 'masoi-${card.gameId}';
  @override
  GameCardTier get tier => card.tier;
  @override
  DateTime? get at => card.endedAt;
  @override
  String get title => 'Ma Sói · ${card.label}';
  @override
  String get subtitle =>
      '${gameCardTiers[tier]!.label} · ${card.teamLabel} thắng';
  @override
  String get label => 'Thẻ Ma Sói ${gameCardTiers[tier]!.label} ${card.label}';
  @override
  AchievementCardData data(String owner) => gameCardData(card, owner: owner);
  @override
  void open(
    BuildContext context,
    AchievementCardData data, {
    Widget? reaction,
  }) => showGameCardViewer(
    context,
    card: card,
    data: data,
    secret: false,
    chips: [gameCardTiers[tier]!.label, 'Ma Sói'],
    reaction: reaction,
  );
}

class CollectedJourneyCard extends CollectedCard {
  const CollectedJourneyCard(this.card);

  final JourneyCard card;

  @override
  String get id => 'journey-${card.campaign}';
  @override
  GameCardTier get tier => card.tier;
  @override
  DateTime? get at => card.awardedAt;
  @override
  String get title => 'Hành trình · ${card.name}';
  @override
  String get subtitle =>
      '${gameCardTiers[tier]!.label} · Level ${card.level} · ${card.km} km';
  @override
  String get label =>
      'Thẻ Hành trình ${gameCardTiers[tier]!.label} ${card.name}';
  @override
  AchievementCardData data(String owner) => journeyCardData(card, owner: owner);
  @override
  void open(
    BuildContext context,
    AchievementCardData data, {
    Widget? reaction,
  }) => showJourneyCardViewer(context, card, data, reaction: reaction);
}

class CollectedRankCard extends CollectedCard {
  const CollectedRankCard(this.card);

  final RankCard card;

  @override
  String get id => 'rank-${card.boardId}';
  @override
  GameCardTier get tier => card.tier;

  /// Lúc lật, như thẻ buổi chạy: lật xong là thẻ mới nhất.
  @override
  DateTime? get at => card.revealedAt;
  @override
  String get title =>
      'BXH ${card.month ? 'tháng' : 'tuần'} · ${rankTitle(card.rank)}';
  @override
  String get subtitle =>
      '${gameCardTiers[tier]!.label} · ${pastRankingPeriodLabel(card.period)}';
  @override
  String get label => 'Thẻ BXH ${gameCardTiers[tier]!.label} $title';

  /// Thẻ in tên lúc chốt, không theo tên hiện tại.
  @override
  AchievementCardData data(String owner) => rankCardData(card);
  @override
  void open(
    BuildContext context,
    AchievementCardData data, {
    Widget? reaction,
  }) => showRankCardViewer(context, card, canShare: true, reaction: reaction);
}

class CollectedContractCard extends CollectedCard {
  const CollectedContractCard(this.card);

  final ContractCard card;

  @override
  String get id => 'contract-${card.contractId}';
  @override
  GameCardTier get tier => card.tier;
  @override
  DateTime? get at => card.rolledAt;
  @override
  String get title => 'Kèo · ${card.snapshot.title}';
  @override
  String get subtitle =>
      '${gameCardTiers[tier]!.label} · ${runCardKm(card.km)} km';
  @override
  String get label =>
      'Thẻ Kèo ${gameCardTiers[tier]!.label} ${card.snapshot.title}';

  /// Thẻ in tên lúc lật, không theo tên hiện tại. Ảnh chụp kèo không giữ giờ
  /// hẹn, nên kèo hẹn chạy ở đây không có dòng giờ hẹn.
  @override
  AchievementCardData data(String owner) => contractCardData(card);
  @override
  void open(
    BuildContext context,
    AchievementCardData data, {
    Widget? reaction,
  }) => showContractCardViewer(context, card, data, reaction: reaction);
}

/// Cả bộ thẻ, mới có trước. Một nguồn lỗi thì cả bộ báo lỗi chứ không hiện
/// thiếu.
final collectedCardsProvider =
    Provider.autoDispose<AsyncValue<List<CollectedCard>>>((ref) {
      final runs = ref.watch(runCardsProvider);
      final games = ref.watch(gameCardsProvider);
      final journeys = ref.watch(journeyCardsProvider);
      final ranks = ref.watch(myRankCardsProvider);
      final contracts = ref.watch(contractCardsProvider);
      for (final source in [runs, games, journeys, ranks, contracts]) {
        if (source case AsyncError(:final error, :final stackTrace)) {
          return AsyncError(error, stackTrace);
        }
      }
      if (!runs.hasValue ||
          !games.hasValue ||
          !journeys.hasValue ||
          !ranks.hasValue ||
          !contracts.hasValue) {
        return const AsyncLoading();
      }
      final cards = <CollectedCard>[
        for (final card in runs.requireValue) CollectedRunCard(card),
        for (final card in games.requireValue) CollectedGameCard(card),
        for (final card in journeys.requireValue) CollectedJourneyCard(card),
        // Thẻ còn úp chưa vào bộ: chủ thẻ lật ở mục Kỳ trước của BXH.
        for (final card in ranks.requireValue)
          if (card.revealed) CollectedRankCard(card),
        for (final card in contracts.requireValue) CollectedContractCard(card),
      ];
      // Thẻ thiếu mốc thời gian xếp cuối.
      final never = DateTime.fromMillisecondsSinceEpoch(0);
      cards.sort((a, b) => (b.at ?? never).compareTo(a.at ?? never));
      return AsyncData(cards);
    });

/// Câu khi bộ thẻ còn trống.
const collectedCardsEmpty = 'Chưa có thẻ nào';

/// Gợi ý cách có thẻ, đi kèm [collectedCardsEmpty].
const collectedCardsEmptyHint =
    'Lật thẻ sau buổi chạy, thắng một ván Ma Sói, về đích một chặng Hành '
    'trình, đạt một kèo, hoặc vào top 10 BXH tuần, tháng để có thẻ đầu tiên.';

/// Thẻ thu nhỏ theo bề ngang [width]; chạm để xem 3D.
class CollectedCardThumb extends StatelessWidget {
  const CollectedCardThumb({
    super.key,
    required this.card,
    required this.owner,
    required this.width,
  });

  final CollectedCard card;
  final String owner;
  final double width;

  @override
  Widget build(BuildContext context) {
    final data = card.data(owner);
    return Semantics(
      button: true,
      label: card.label,
      child: GestureDetector(
        onTap: () => card.open(context, data),
        child: GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(data: data),
        ),
      ),
    );
  }
}

/// Mọi thẻ đã có, mới nhất trước, lọc theo bậc; filter Chưa lật gom các buổi
/// còn lật được.
class RunCardCollectionScreen extends ConsumerStatefulWidget {
  const RunCardCollectionScreen({super.key});

  @override
  ConsumerState<RunCardCollectionScreen> createState() =>
      _RunCardCollectionScreenState();
}

class _RunCardCollectionScreenState
    extends ConsumerState<RunCardCollectionScreen> {
  /// null là mọi bậc.
  GameCardTier? _tier;

  bool _unflippedOnly = false;

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(collectedCardsProvider);
    final owner = runCardOwnerName(ref);
    final unflipped = ref.watch(unflippedRunsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bộ thẻ'),
        actions: [
          RunCardSkinButton(
            onPressed: () => showRunCardSkinSheet(
              context,
              // Thẻ Ẩn không theo bộ màu, nên mẫu là thẻ thường đầu tiên.
              sample: cards.value
                  ?.map((card) => card.data(owner))
                  .where((data) => data.secret == null)
                  .firstOrNull,
            ),
          ),
        ],
      ),
      body: cards.when(
        loading: () => const Center(child: RunNowLoading()),
        error: (error, _) => _Note('Không tải được bộ thẻ: $error'),
        data: (cards) =>
            cards.isEmpty &&
                !unflipped.hasError &&
                (unflipped.value?.isEmpty ?? true)
            ? const RunNowEmpty(
                message: collectedCardsEmpty,
                hint: collectedCardsEmptyHint,
              )
            : _grid(cards, owner, unflipped),
      ),
    );
  }

  void _selectTier(GameCardTier? tier) => setState(() {
    _tier = tier;
    _unflippedOnly = false;
  });

  Future<void> _flip(ActivitySummary run) async {
    await showRunCardFlow(context, run);
    // Lật trượt không sinh doc thẻ nên không có stream nào báo, phải tải lại.
    if (mounted) ref.invalidate(unflippedRunsProvider);
  }

  Widget _grid(
    List<CollectedCard> cards,
    String owner,
    AsyncValue<List<ActivitySummary>> unflipped,
  ) {
    final shown = [
      for (final card in cards)
        if (_tier == null || card.tier == _tier) card,
    ];
    int count(GameCardTier tier) => cards.where((c) => c.tier == tier).length;
    final waiting = unflipped.value;
    const gap = 12.0;
    const side = 16.0;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: side),
          child: Row(
            children: [
              _SourceTab(
                label: 'Đã có',
                count: cards.length,
                selected: !_unflippedOnly,
                onTap: () => _selectTier(null),
              ),
              const SizedBox(width: 22),
              _SourceTab(
                label: 'Chưa lật',
                count: waiting?.length,
                selected: _unflippedOnly,
                onTap: waiting?.isEmpty ?? false
                    ? null
                    : () => setState(() {
                        _tier = null;
                        _unflippedOnly = true;
                      }),
              ),
            ],
          ),
        ),
        if (!_unflippedOnly) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: side),
              children: [
                _TierPill(
                  label: 'Tất cả',
                  selected: _tier == null,
                  onTap: () => _selectTier(null),
                ),
                // Bậc cao trước; bậc chưa có thẻ vẫn hiện để biết còn thiếu gì.
                for (final tier in GameCardTier.values.reversed)
                  _TierPill(
                    label: gameCardTiers[tier]!.label,
                    count: count(tier),
                    dot: runCardGlow(tier),
                    selected: _tier == tier,
                    onTap: count(tier) == 0 ? null : () => _selectTier(tier),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
    // Lưới lazy: bộ thẻ dài thì chỉ dựng thẻ gần màn hình, thẻ Thần thoại ở xa
    // cũng không chạy hiệu ứng. Số cột tính theo bề ngang hộp chứ không theo
    // SliverLayoutBuilder: sliver constraints đổi theo từng khung cuộn, dựng
    // lại cả lưới mỗi khung.
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxWidth - side * 2;
        final columns = (extent / 170).floor().clamp(2, 5);
        final width = (extent - gap * (columns - 1)) / columns;
        Widget grid(int count, Widget Function(int i, double width) item) =>
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 0, side, 32),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio:
                      achievementCardSize.width / achievementCardSize.height,
                ),
                itemCount: count,
                itemBuilder: (context, i) => item(i, width),
              ),
            );
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 8),
              sliver: SliverToBoxAdapter(child: header),
            ),
            if (!_unflippedOnly)
              grid(
                shown.length,
                (i, width) => CollectedCardThumb(
                  card: shown[i],
                  owner: owner,
                  width: width,
                ),
              )
            else if (waiting != null && waiting.isNotEmpty)
              grid(
                waiting.length,
                (i, width) => _UnflippedRunThumb(
                  run: waiting[i],
                  width: width,
                  onTap: () => _flip(waiting[i]),
                ),
              )
            else
              SliverFillRemaining(
                hasScrollBody: false,
                child: _unflippedStatus(unflipped),
              ),
          ],
        );
      },
    );
  }

  Widget _unflippedStatus(AsyncValue<List<ActivitySummary>> unflipped) {
    if (unflipped.hasValue) return const _Note('Đã lật hết thẻ');
    if (unflipped.error case final error?) {
      debugPrint('Không tải được buổi chưa lật: $error');
      return Center(
        child: TextButton(
          onPressed: () => ref.invalidate(unflippedRunsProvider),
          child: const Text('Không tải được. Chạm để thử lại.'),
        ),
      );
    }
    return const Center(child: RunNowLoading());
  }
}

/// Hai nguồn của lưới: thẻ đã có và buổi chưa lật. Chữ đậm và gạch chân để
/// khác hẳn hàng lọc bậc bên dưới.
class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface.withValues(
      alpha: onTap == null
          ? 0.3
          : selected
          ? 1
          : 0.5,
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (count case final count?)
                    TextSpan(
                      text: ' $count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ink.withValues(alpha: ink.a * 0.6),
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 3,
              width: selected ? 26 : 0,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lọc theo bậc: chấm màu bậc, tên, số thẻ.
class _TierPill extends StatelessWidget {
  const _TierPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.dot,
  });

  final String label;
  final int? count;
  final Color? dot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = selected ? scheme.surface : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.38 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot case final dot?) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text.rich(
                    TextSpan(
                      text: label,
                      children: [
                        if (count case final count?)
                          TextSpan(
                            text: ' $count',
                            style: TextStyle(
                              color: ink.withValues(alpha: 0.55),
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mặt úp của một buổi chưa lật; chạm để lật.
class _UnflippedRunThumb extends StatelessWidget {
  const _UnflippedRunThumb({
    required this.run,
    required this.width,
    required this.onTap,
  });

  final ActivitySummary run;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM').format(run.startedAt);
    return Semantics(
      button: true,
      label: 'Lật thẻ buổi ${run.name}, $date',
      child: GestureDetector(
        onTap: onTap,
        child: GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: RunCardFaceDown(
            km: (run.distanceMeters / 100).round() / 10,
            title: '${run.name} · $date',
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
