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

/// Câu nhắc dưới tên mình, nhắm mục tiêu gần nhất: lên hạng của món theo hạng
/// tốt hơn món đang giữ ("Thêm 3,2 km để lên #3 nhận Tất chạy"), hay đạt mốc
/// của món bốc thăm ("Thêm 2,1 km để vào lượt bốc Áo"). Chưa có món theo hạng
/// mà đã đủ mốc thì báo "Đã vào lượt bốc Áo"; người giữ quà theo hạng không
/// vào lượt bốc. Null khi không còn gì để nhắc. Bằng số người ở hạng đích là
/// chung hạng, nên khoảng cách tính tới đúng số của họ.
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
  RankRewardItem? rankTarget;
  for (final item in rewards.items) {
    // Chỉ món nằm hẳn trên hạng mình; các món không chồng nhau nên món có
    // toRank lớn nhất trong số đó là món gần nhất.
    if (item.isDraw || item.toRank >= me.rank) continue;
    if (rankTarget == null || item.toRank > rankTarget.toRank) {
      rankTarget = item;
    }
  }
  double? rankGap;
  if (rankTarget != null && others.length >= rankTarget.toRank) {
    final gap = others[rankTarget.toRank - 1].score - me.score;
    if (gap > 0) rankGap = gap;
  }

  RankRewardItem? drawTarget;
  RankRewardItem? entered;
  if (rewards.itemFor(me.rank) == null) {
    for (final item in rewards.items) {
      if (!item.isDraw) continue;
      if (me.score >= item.minScore) {
        entered ??= item;
      } else if (drawTarget == null || item.minScore < drawTarget.minScore) {
        drawTarget = item;
      }
    }
  }
  final drawGap = drawTarget == null ? null : drawTarget.minScore - me.score;

  if (rankGap != null && (drawGap == null || rankGap <= drawGap)) {
    return 'Thêm ${clubRankingValueLabel(_roundUp(rankGap, sport), sport)} để lên '
        '#${rankTarget!.toRank} nhận ${rankTarget.name}';
  }
  if (drawGap != null) {
    return 'Thêm ${clubRankingValueLabel(_roundUp(drawGap, sport), sport)} '
        'để vào lượt bốc '
        '${drawTarget!.name}';
  }
  if (entered != null) return 'Đã vào lượt bốc ${entered.name}';
  return null;
}

/// Làm tròn lên tới số nhỏ nhất in ra được (10 m vì km in 2 số lẻ, 1 bước),
/// kẻo thiếu vài mét mà in "Thêm 0.00 km".
double _roundUp(double gap, ClubRankingSport sport) =>
    sport == ClubRankingSport.steps
    ? gap.ceilToDouble()
    : (gap / 10).ceilToDouble() * 10;

/// Dòng của mình trong sheet quà, [rank] null là đã vào lượt bốc (vẽ dấu
/// tích thay số hạng).
typedef RankRewardMe = ({String? rank, String title, String detail});

/// Mình đang ở đâu so với quà: giữ quà theo hạng, đã vào lượt bốc, hay còn
/// thiếu bao nhiêu (câu của [rankRewardGapLabel]). Null khi không còn quà nào
/// để nhắm.
RankRewardMe? rankRewardMe(
  List<ClubRankedMember> ranked,
  int index,
  RankRewards rewards,
  ClubRankingSport sport,
) {
  final me = ranked[index];
  final gap = rankRewardGapLabel(ranked, index, rewards, sport);
  final held = rewards.itemFor(me.rank);
  if (held != null) {
    final schedule = rankRewardSchedule(rewards);
    return (
      rank: '#${me.rank}',
      title: 'Đang giữ ${held.name}',
      detail:
          gap ??
          (schedule.isEmpty
              ? 'Giữ hạng tới lúc chốt'
              : 'Giữ hạng tới hết ${schedule.first.$1}'),
    );
  }
  final have = 'Bạn đang có ${clubRankingValueLabel(me.score, sport)}';
  for (final item in rewards.items) {
    if (!item.isDraw || me.score < item.minScore) continue;
    final title = 'Đã vào lượt bốc ${item.name}';
    // Câu nhắc khác câu đã vào thì là mục tiêu cao hơn, như lên hạng.
    return (
      rank: null,
      title: title,
      detail: gap == null || gap == title ? have : gap,
    );
  }
  if (gap == null) return null;
  return (rank: '#${me.rank}', title: gap, detail: have);
}

/// Dải quà trên BXH đang chạy: mỗi món một hàng ảnh, tên và
/// luật ngắn. Chạm mở sheet đủ luật.
class RankRewardStrip extends StatelessWidget {
  const RankRewardStrip({
    required this.rewards,
    required this.sport,
    this.me,
    super.key,
  });

  final RankRewards rewards;
  final ClubRankingSport sport;

  /// Dòng của mình trong sheet; null khi mình chưa có trên bảng.
  final RankRewardMe? me;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: palette.radius(18),
        onTap: () => showRankRewardsSheet(context, rewards, sport, me: me),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.card_giftcard,
                    size: 18,
                    color: palette.accentDeep,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Quà kỳ này',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: palette.textMuted),
                ],
              ),
              for (final item in rewards.items)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      RankRewardThumb(
                        icon: item.icon,
                        photos: item.photos,
                        size: 40,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            RankRewardTags(
                              tags: rankRewardTags(item, sport),
                              color: palette.accentDeep,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hàng nhãn viền ("Random", "15 km") cạnh ảnh quà.
class RankRewardTags extends StatelessWidget {
  const RankRewardTags({
    required this.tags,
    required this.color,
    this.fontSize = 11,
    super.key,
  });

  final List<String> tags;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final tag in tags)
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              tag,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ],
  );
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
  const RankRewardPhotos({
    required this.icon,
    required this.photos,
    this.height = 220,
    super.key,
  });

  final String icon;
  final List<String> photos;

  /// Ảnh để nguyên khung trong chiều cao này, không cắt: ảnh quà thường dọc
  /// và có chữ, cắt là mất tên quà hay luật in trong ảnh.
  final double height;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: RankRewardThumb(icon: icon, photos: const []),
      );
    }
    return SizedBox(
      height: height,
      child: PageView(
        controller: PageController(viewportFraction: 0.86),
        children: [
          for (final path in photos)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ClipRRect(
                borderRadius: context.runNowPalette.radius(16),
                child: StorageImage(
                  path: path,
                  fit: BoxFit.contain,
                  cacheWidth: 1200,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showRankRewardsSheet(
  BuildContext context,
  RankRewards rewards,
  ClubRankingSport sport, {
  RankRewardMe? me,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (context, controller) => RankRewardsSheetBody(
      rewards: rewards,
      sport: sport,
      me: me,
      controller: controller,
    ),
  ),
);

/// Ruột sheet quà. Bảng đầu trả lời cả kỳ có mấy quà, mấy người nhận, điều
/// kiện gì, khi nào chốt; dòng tối nói mình đang ở đâu. Một quà thì ảnh lớn,
/// nhãn của món trùng bảng đầu nên bỏ. Nhiều quà thì mỗi món một hàng gọn có
/// nhãn riêng, chạm mở ảnh lớn.
class RankRewardsSheetBody extends StatelessWidget {
  const RankRewardsSheetBody({
    required this.rewards,
    required this.sport,
    this.me,
    this.controller,
    super.key,
  });

  final RankRewards rewards;
  final ClubRankingSport sport;
  final RankRewardMe? me;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final items = rewards.items;
    final me = this.me;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'QUÀ KỲ NÀY',
          style: TextStyle(
            fontFamily: palette.narrowFont,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 12),
        _RewardOverview(rewards: rewards, sport: sport),
        if (me != null) ...[const SizedBox(height: 12), _RewardMeRow(me: me)],
        const SizedBox(height: 12),
        if (items.length == 1)
          GlassPanel(
            borderRadius: 18,
            border: Border.all(color: palette.border),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  items.single.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                RankRewardPhotos(
                  icon: items.single.icon,
                  photos: items.single.photos,
                  height: 360,
                ),
              ],
            ),
          )
        else
          GlassPanel(
            borderRadius: 18,
            border: Border.all(color: palette.border),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _RewardRow(item: items[i], sport: sport, first: i == 0),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bảng đầu sheet: hàng số (quà, người nhận, điều kiện), hàng lịch, và câu
/// mỗi người một quà khi có từ 2 quà.
class _RewardOverview extends StatelessWidget {
  const _RewardOverview({required this.rewards, required this.sport});

  final RankRewards rewards;
  final ClubRankingSport sport;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final line = BorderSide(color: palette.border);
    final (condition, conditionLabel) = rankRewardCondition(rewards, sport);
    final schedule = rankRewardSchedule(rewards);
    final note = rankRewardSheetNote(rewards);
    Widget cell(String value, String label, {double size = 28, Color? color}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: palette.narrowFont,
                      fontSize: size,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
    Widget row(List<Widget> cells, {bool top = true}) => DecoratedBox(
      decoration: BoxDecoration(border: top ? Border(top: line) : null),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, thickness: 1, color: line.color),
              cells[i],
            ],
          ],
        ),
      ),
    );
    return GlassPanel(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      border: Border.all(color: palette.foreground, width: 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(top: false, [
            cell('${rewards.items.length}', 'quà'),
            cell('${rankRewardWinnerCount(rewards)}', 'suất'),
            cell(condition, conditionLabel, color: palette.accentDeep),
          ]),
          if (schedule.isNotEmpty)
            row([
              for (final (value, label) in schedule)
                cell(value, label, size: 20),
            ]),
          if (note != null)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: line)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Text(
                  note,
                  style: TextStyle(fontSize: 13, color: palette.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dòng tối "mình đang ở đâu": số hạng hay dấu tích, câu chính, câu phụ.
class _RewardMeRow extends StatelessWidget {
  const _RewardMeRow({required this.me});

  final RankRewardMe me;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onDark = palette.background;
    final rank = me.rank;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.foreground,
        borderRadius: palette.radius(14),
      ),
      child: Row(
        children: [
          rank == null
              ? Icon(Icons.check_rounded, size: 26, color: palette.success)
              : Text(
                  rank,
                  style: TextStyle(
                    fontFamily: palette.narrowFont,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: onDark,
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.title,
                  style: TextStyle(
                    color: onDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  me.detail,
                  style: TextStyle(
                    color: onDark.withValues(alpha: 0.72),
                    fontSize: 13,
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

/// Một món trong danh sách nhiều quà: ảnh nhỏ, tên, nhãn; chạm mở ảnh lớn.
class _RewardRow extends StatefulWidget {
  const _RewardRow({
    required this.item,
    required this.sport,
    required this.first,
  });

  final RankRewardItem item;
  final ClubRankingSport sport;
  final bool first;

  @override
  State<_RewardRow> createState() => _RewardRowState();
}

class _RewardRowState extends State<_RewardRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final item = widget.item;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: widget.first
            ? null
            : Border(top: BorderSide(color: palette.border)),
      ),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  RankRewardThumb(
                    icon: item.icon,
                    photos: item.photos,
                    size: 72,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        RankRewardTags(
                          tags: rankRewardTags(item, widget.sport),
                          color: palette.accentDeep,
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ),
                  if (item.photos.isNotEmpty)
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: palette.textMuted,
                    ),
                ],
              ),
              if (_open && item.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                RankRewardPhotos(
                  icon: item.icon,
                  photos: item.photos,
                  height: 320,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
