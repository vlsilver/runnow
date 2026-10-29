import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Tên in trên thẻ của chính mình.
String runCardOwnerName(WidgetRef ref) =>
    ref.watch(
      userProfileProvider.select((p) => p.asData?.value?.displayName),
    ) ??
    '3i member';

/// Một thẻ trong bộ: thẻ buổi chạy, thẻ Ma Sói của ván phe mình thắng, hay
/// thẻ Hành trình của chặng đã về đích.
sealed class CollectedCard {
  const CollectedCard();

  String get id;
  GameCardTier get tier;

  /// Lúc có thẻ: lật thẻ buổi chạy, ván Ma Sói kết thúc, hay về đích chặng.
  DateTime? get at;

  /// Tên thẻ và dòng phụ cạnh thẻ mới nhất ở Hồ sơ.
  String get title;
  String get subtitle;

  /// Nhãn đọc màn hình của thẻ thu nhỏ.
  String get label;

  AchievementCardData data(String owner);

  /// Xem 3D, khoe từ đó.
  void open(BuildContext context, AchievementCardData data);
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
  void open(BuildContext context, AchievementCardData data) =>
      showRunCardViewer(context, card, data);
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
  void open(BuildContext context, AchievementCardData data) =>
      showGameCardViewer(
        context,
        card: card,
        data: data,
        secret: false,
        chips: [gameCardTiers[tier]!.label, 'Ma Sói'],
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
  DateTime? get at => card.finishedAt;
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
  void open(BuildContext context, AchievementCardData data) =>
      showJourneyCardViewer(context, card, data);
}

/// Cả bộ thẻ, mới có trước. Một nguồn lỗi thì cả bộ báo lỗi chứ không hiện
/// thiếu.
final collectedCardsProvider =
    Provider.autoDispose<AsyncValue<List<CollectedCard>>>((ref) {
      final runs = ref.watch(runCardsProvider);
      final games = ref.watch(gameCardsProvider);
      final journeys = ref.watch(journeyCardsProvider);
      for (final source in [runs, games, journeys]) {
        if (source case AsyncError(:final error, :final stackTrace)) {
          return AsyncError(error, stackTrace);
        }
      }
      if (!runs.hasValue || !games.hasValue || !journeys.hasValue) {
        return const AsyncLoading();
      }
      final cards = <CollectedCard>[
        for (final card in runs.requireValue) CollectedRunCard(card),
        for (final card in games.requireValue) CollectedGameCard(card),
        for (final card in journeys.requireValue) CollectedJourneyCard(card),
      ];
      // Thẻ thiếu mốc thời gian xếp cuối.
      final never = DateTime.fromMillisecondsSinceEpoch(0);
      cards.sort((a, b) => (b.at ?? never).compareTo(a.at ?? never));
      return AsyncData(cards);
    });

/// Câu khi bộ thẻ còn trống.
const collectedCardsEmpty =
    'Chưa có thẻ nào. Lật thẻ sau buổi chạy, thắng một ván Ma Sói, hoặc về '
    'đích một chặng Hành trình để có thẻ đầu tiên.';

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

/// Mọi thẻ đã có, mới nhất trước, lọc theo bậc.
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

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(collectedCardsProvider);
    final owner = runCardOwnerName(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bộ thẻ'),
        actions: [
          IconButton(
            tooltip: 'Bộ màu thẻ',
            onPressed: () => showRunCardSkinSheet(
              context,
              // Thẻ Ẩn không theo bộ màu, nên mẫu là thẻ thường đầu tiên.
              sample: cards.value
                  ?.map((card) => card.data(owner))
                  .where((data) => data.secret == null)
                  .firstOrNull,
            ),
            icon: const Icon(Icons.palette_outlined),
          ),
        ],
      ),
      body: cards.when(
        loading: () => const Center(child: RunNowLoading()),
        error: (error, _) => _Note('Không tải được bộ thẻ: $error'),
        data: (cards) => cards.isEmpty
            ? const _Note(collectedCardsEmpty)
            : _grid(cards, owner),
      ),
    );
  }

  Widget _grid(List<CollectedCard> cards, String owner) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final shown = [
      for (final card in cards)
        if (_tier == null || card.tier == _tier) card,
    ];
    int count(GameCardTier tier) => cards.where((c) => c.tier == tier).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: Text('Tất cả · ${cards.length}'),
              selected: _tier == null,
              onSelected: (_) => setState(() => _tier = null),
            ),
            // Bậc cao trước; bậc chưa có thẻ vẫn hiện để biết còn thiếu gì.
            for (final tier in GameCardTier.values.reversed)
              ChoiceChip(
                label: Text('${gameCardTiers[tier]!.label} · ${count(tier)}'),
                selected: _tier == tier,
                onSelected: count(tier) == 0
                    ? null
                    : (_) => setState(() => _tier = tier),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Mới nhất trước. Chạm thẻ để xem 3D.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final columns = (constraints.maxWidth / 170).floor().clamp(2, 5);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in shown)
                  CollectedCardThumb(card: card, owner: owner, width: width),
              ],
            );
          },
        ),
      ],
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
