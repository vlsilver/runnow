import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Tên in trên thẻ của chính mình.
String runCardOwnerName(WidgetRef ref) =>
    ref.watch(
      userProfileProvider.select((p) => p.asData?.value?.displayName),
    ) ??
    '3i member';

/// Thẻ thu nhỏ theo bề ngang [width]; chạm để xem 3D.
class RunCardThumb extends StatelessWidget {
  const RunCardThumb({
    super.key,
    required this.card,
    required this.owner,
    required this.width,
  });

  final RunCard card;
  final String owner;
  final double width;

  @override
  Widget build(BuildContext context) {
    final data = runCardData(card, owner: owner);
    return Semantics(
      button: true,
      label: 'Thẻ ${gameCardTiers[card.tier]!.label} ${runCardKm(card.km)} km',
      child: GestureDetector(
        onTap: () => showRunCardViewer(context, card, data),
        child: GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(data: data),
        ),
      ),
    );
  }
}

/// Mọi thẻ đã lật, mới nhất trước, lọc theo bậc.
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
    final cards = ref.watch(runCardsProvider);
    final owner = runCardOwnerName(ref);
    return Scaffold(
      appBar: AppBar(title: const Text('Bộ thẻ')),
      body: cards.when(
        loading: () => const Center(child: RunNowLoading()),
        error: (error, _) => _Note('Không tải được bộ thẻ: $error'),
        data: (cards) => cards.isEmpty
            ? const _Note(
                'Chưa có thẻ nào. Mở một buổi chạy và lật thẻ để bắt đầu bộ '
                'sưu tập.',
              )
            : _grid(cards, owner),
      ),
    );
  }

  Widget _grid(List<RunCard> cards, String owner) {
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
                  RunCardThumb(card: card, owner: owner, width: width),
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
