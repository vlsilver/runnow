import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/rank/rank_gift_card.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/storage_image.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Thêm 3,2 km để lên #3 nhận Tất chạy" cho người ở [index], nhắm món gần
/// nhất tốt hơn món đang giữ. Null khi đã giữ món tốt nhất hay không còn món
/// nào với tới. Bằng số người ở hạng đích là chung hạng, nên khoảng cách tính
/// tới đúng số của họ.
String? rankRewardGapLabel(
  List<ClubRankedMember> ranked,
  int index,
  RankRewards rewards,
  ClubRankingSport sport,
) {
  final me = ranked[index];
  final others = [
    for (var i = 0; i < ranked.length; i++)
      if (i != index) ranked[i],
  ];
  RankRewardItem? target;
  for (final item in rewards.items) {
    // Chỉ món nằm hẳn trên hạng mình; các món không chồng nhau nên món có
    // toRank lớn nhất trong số đó là món gần nhất.
    if (item.toRank >= me.rank) continue;
    if (target == null || item.toRank > target.toRank) target = item;
  }
  if (target == null || others.length < target.toRank) return null;
  final gap = others[target.toRank - 1].score - me.score;
  if (gap <= 0) return null;
  return 'Thêm ${clubRankingValueLabel(gap, sport)} để lên '
      '#${target.toRank} nhận ${target.name}';
}

/// Dải quà trên BXH đang chạy: mỗi món một ô biểu tượng, hạng và tên.
class RankRewardStrip extends StatelessWidget {
  const RankRewardStrip({required this.rewards, super.key});

  final RankRewards rewards;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: palette.radius(18),
        onTap: () => showRankRewardsSheet(context, rewards),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(Icons.card_giftcard, size: 18, color: palette.accentDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final item in rewards.items)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(rankRewardIcon(item.icon), size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${item.ranks} ${item.name}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô ảnh quà: ảnh đầu khi có, không thì biểu tượng.
class RankRewardThumb extends StatelessWidget {
  const RankRewardThumb({
    required this.icon,
    required this.photos,
    this.size = 56,
    super.key,
  });

  final String icon;
  final List<String> photos;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final placeholder = Center(
      child: Icon(
        rankRewardIcon(icon),
        size: size * 0.5,
        color: palette.accentDeep,
      ),
    );
    return ClipRRect(
      borderRadius: palette.radius(12),
      child: Container(
        width: size,
        height: size,
        color: palette.wash(palette.accent, 0.12),
        child: photos.isEmpty
            ? placeholder
            : StorageImage(
                path: photos.first,
                cacheWidth: (size * 3).round(),
                placeholder: placeholder,
              ),
      ),
    );
  }
}

/// Ảnh thật của một món, lướt ngang.
class RankRewardPhotos extends StatelessWidget {
  const RankRewardPhotos({required this.icon, required this.photos, super.key});

  final String icon;
  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: RankRewardThumb(icon: icon, photos: const []),
      );
    }
    return SizedBox(
      height: 220,
      child: PageView(
        controller: PageController(viewportFraction: 0.86),
        children: [
          for (final path in photos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: context.runNowPalette.radius(16),
                child: StorageImage(path: path, cacheWidth: 1200),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showRankRewardsSheet(BuildContext context, RankRewards rewards) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Quà kỳ này', style: Theme.of(context).textTheme.titleLarge),
          if (rewards.giverName.isNotEmpty)
            Text(
              '${rewards.giverName} trao',
              style: TextStyle(color: context.runNowPalette.textMuted),
            ),
          for (final item in rewards.items) ...[
            const SizedBox(height: 16),
            Text(
              '${item.ranks} · ${item.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            RankRewardPhotos(icon: item.icon, photos: item.photos),
          ],
        ],
      ),
    ),
  );
}

/// Dòng quà dưới thẻ hạng của mình; chạm mở thẻ quà, từ đó khoe hay nhận quà.
class RankCardRewardLine extends StatelessWidget {
  const RankCardRewardLine({required this.card, super.key});

  final RankCard card;

  @override
  Widget build(BuildContext context) {
    final reward = card.reward!;
    final palette = context.runNowPalette;
    final received = reward.receivedBy(DateTime.now());
    return InkWell(
      borderRadius: palette.radius(12),
      onTap: () => showRankGiftCardViewer(context, card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            RankRewardThumb(icon: reward.icon, photos: reward.photos, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                reward.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              received
                  ? 'Đã nhận'
                  : reward.givenAt != null
                  ? 'Đã trao'
                  : 'Nhận quà',
              style: TextStyle(
                color: received ? palette.textMuted : palette.accentDeep,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

Future<void> showRankCardRewardSheet(BuildContext context, RankCard card) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RankCardRewardSheet(uid: card.uid, boardId: card.boardId),
  );
}

class _RankCardRewardSheet extends ConsumerStatefulWidget {
  const _RankCardRewardSheet({required this.uid, required this.boardId});

  final String uid;
  final String boardId;

  @override
  ConsumerState<_RankCardRewardSheet> createState() =>
      _RankCardRewardSheetState();
}

class _RankCardRewardSheetState extends ConsumerState<_RankCardRewardSheet> {
  bool _busy = false;

  /// Chạy [action], báo lỗi bằng toast; trả false khi lỗi.
  Future<bool> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _busy = true);
    try {
      await action();
      return true;
    } on RunNowApiException catch (error) {
      _toast(error.message);
    } catch (error) {
      _toast('Không gửi được: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _markReceived() => _run(
    () => ref
        .read(runNowApiClientProvider)
        .markRankRewardReceived(widget.boardId),
  );

  /// Telegram người trao không nằm trên thẻ; hỏi backend lúc bấm.
  Future<void> _message(String giverName) async {
    var tg = '';
    final ok = await _run(() async {
      tg = await ref
          .read(runNowApiClientProvider)
          .getRankRewardContact(widget.boardId);
    });
    if (!ok || !mounted) return;
    if (tg.isEmpty) {
      _toast('$giverName chưa liên kết Telegram.');
      return;
    }
    final opened = await launchUrl(
      Uri.parse('https://t.me/$tg'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _toast('Không mở được Telegram.');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    // Nghe thẻ để bấm nhận hay admin đánh dấu trao là sheet đổi ngay.
    final key = (uid: widget.uid, boardId: widget.boardId);
    final snapshot = ref.watch(rankCardProvider(key));
    final card = snapshot.asData?.value;
    final reward = card?.reward;
    if (card == null || reward == null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: snapshot.hasError
              ? TextButton(
                  onPressed: () => ref.invalidate(rankCardProvider(key)),
                  child: const Text('Không tải được quà. Chạm để thử lại.'),
                )
              : snapshot.isLoading
              ? const CircularProgressIndicator()
              : const Text('Thẻ này không có quà.'),
        ),
      );
    }
    final palette = context.runNowPalette;
    final now = DateTime.now();
    final received = reward.receivedBy(now);
    final steps = <(String, DateTime?)>[
      ('Chốt kỳ', card.awardedAt),
      ('${reward.giverName} trao quà', reward.givenAt),
      (
        'Bạn đã nhận',
        reward.receivedAt ??
            (received ? reward.givenAt!.add(rankRewardAutoReceived) : null),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(reward.name, style: Theme.of(context).textTheme.titleLarge),
          Text(
            '${rankTitle(card.rank)} ${card.month ? 'tháng' : 'tuần'} · '
            '${reward.giverName} trao',
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          RankRewardPhotos(icon: reward.icon, photos: reward.photos),
          const SizedBox(height: 16),
          for (final (label, at) in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    at != null
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: at != null ? palette.accentDeep : palette.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  if (at != null)
                    Text(
                      _day(at),
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _message(reward.giverName),
            icon: const Icon(Icons.send_outlined),
            label: Text('Nhắn ${reward.giverName}'),
          ),
          if (!received) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _markReceived,
              child: const Text('Tôi đã nhận quà'),
            ),
          ],
        ],
      ),
    );
  }
}

String _day(DateTime at) {
  final d = at.toLocal();
  return '${d.day}/${d.month}';
}
