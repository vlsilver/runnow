import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/rank/rank_card_art.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// Số người mặt trước in được trong khổ thẻ 300x420: ba người trên bục,
/// còn lại là dòng.
const _rows = 10;

/// Bảng xếp hạng in lên mặt trước thẻ khoe, có quà hay không.
class RankBoardSnapshot {
  const RankBoardSnapshot({
    required this.ranked,
    required this.sport,
    required this.period,
    required this.currentUid,
  });

  final List<ClubRankedMember> ranked;
  final ClubRankingSport sport;
  final PastRankingPeriod period;
  final String? currentUid;

  bool get month => period.range == ClubRankingRange.currentMonth;

  /// Chỉ số các dòng in ở mặt trước.
  List<int> get shown {
    final mine = ranked.indexWhere((m) => m.entry.uid == currentUid);
    final top = ranked.length < _rows ? ranked.length : _rows;
    if (mine < _rows) return [for (var i = 0; i < top; i++) i];
    return [for (var i = 0; i < _rows - 1; i++) i, mine];
  }
}

/// Ảnh khoe BXH kỳ không có quà: chỉ mặt trước, không lật, chân thẻ thay cho
/// dải quà.
class RankBoardPoster extends StatelessWidget {
  const RankBoardPoster({super.key, required this.board});

  final RankBoardSnapshot board;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: achievementCardSize,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      // Khổ cố định đem in ra ảnh: chữ không theo cỡ chữ hệ thống.
      child: MediaQuery.withNoTextScaling(child: _BoardFront(board: board)),
    ),
  );
}

/// Thẻ khoe BXH đang chạy có quà: mặt trước là top 10 (người khoe ngoài top
/// thì thay dòng 10 bằng dòng của mình), mặt sau là các món quà kèm luật.
class RankBoardCard {
  const RankBoardCard({
    required this.boardId,
    required this.ranked,
    required this.sport,
    required this.period,
    required this.rewards,
    required this.currentUid,
  });

  final String boardId;
  final List<ClubRankedMember> ranked;
  final ClubRankingSport sport;
  final PastRankingPeriod period;
  final RankRewards rewards;
  final String? currentUid;

  RankBoardSnapshot get board => RankBoardSnapshot(
    ranked: ranked,
    sport: sport,
    period: period,
    currentUid: currentUid,
  );

  bool get month => board.month;

  /// Chỉ số các dòng in ở mặt trước.
  List<int> get shown => board.shown;

  AchievementCardData get data => AchievementCardData(
    tier: GameCardTier.legendary,
    art: const ColoredBox(color: _cream),
    // Thẻ là khổ cố định 300x420 đem in ra ảnh: chữ không theo cỡ chữ hệ
    // thống, kẻo cỡ lớn tràn và cắt mất dòng luật.
    frontFace: (_) => MediaQuery.withNoTextScaling(
      child: _BoardFront(
        board: board,
        band: _GiftBand(card: this),
      ),
    ),
    backFace: MediaQuery.withNoTextScaling(child: _GiftsBack(card: this)),
    kind: 'BẢNG XẾP HẠNG',
    hero: '${ranked.length}',
    heroUnit: 'NGƯỜI',
    title: pastRankingPeriodLabel(period),
    owner: '',
    serial: '',
    desc: '',
    meta: '',
    date: '',
  );

  CardShareSubject get subject => CardShareSubject(
    id: 'bxh-$boardId',
    printed: [
      for (final i in shown) ...[
        ranked[i].rank,
        ranked[i].entry.displayName,
        ranked[i].score,
      ],
      currentUid ?? '',
      for (final it in rewards.items) ...[
        it.name,
        it.icon,
        it.photos.firstOrNull ?? '',
        rankRewardRule(it, sport),
      ],
    ].join('|'),
    text:
        'BXH ${rankSportNames[sport]} ${pastRankingPeriodLabel(period)} · '
        '${rewards.items.length} quà\nChia sẻ từ 3i',
  );
}

/// Mở thẻ BXH toàn màn hình, lật xem quà, khoe ba file như mọi thẻ.
Future<void> showRankBoardCard(BuildContext context, RankBoardCard card) {
  final data = card.data;
  return showCardViewer(
    context,
    front: (pose) => AchievementCard(data: data, pose: pose),
    back: (pose) => AchievementCard(data: data, pose: pose, back: true),
    chips: ['Bảng xếp hạng', '${card.rewards.items.length} quà'],
    cardSize: achievementCardSize,
    onShare: (_, origin) =>
        showCardShare(origin, subject: card.subject, data: data),
  );
}

typedef _T = RunNowRankBoardCardTokens;

// Thẻ in ra ảnh nên giữ một kiểu riêng, không theo theme (Pixel, tối, sáng).
const _cream = _T.paper;
const _ink = _T.ink;
const _red = _T.red;
const _redBright = _T.redBright;
const _muted = _T.muted;
const _rule = _T.rule;
const _photoBg = _T.photo;
const _body = 'Exo 2';
const _narrow = 'Barlow Condensed';

TextStyle _caps(Color color, double size) => TextStyle(
  fontFamily: _body,
  color: color,
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: 1.2,
);

TextStyle _num(double size, {Color color = _ink, FontWeight? weight}) =>
    TextStyle(
      fontFamily: _narrow,
      color: color,
      fontSize: size,
      fontWeight: weight ?? FontWeight.w800,
      height: 1,
    );

/// "23–29/11" cho tuần, "11/2026" cho tháng: chữ "BXH TUẦN" đã nói là tuần.
String _periodShort(RankBoardSnapshot board) => board.month
    ? '${board.period.start.month}/${board.period.start.year}'
    : pastRankingPeriodLabel(
        board.period,
      ).replaceFirst('Tuần ', '').replaceAll(' – ', '–');

/// Đầu cả hai mặt: môn, tiêu đề lớn, kỳ bên phải.
class _Header extends StatelessWidget {
  const _Header({required this.kicker, required this.title, this.period});

  final String kicker;
  final String title;
  final String? period;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kicker,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _caps(_red, 11),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _num(period == null ? 26 : 36),
            ),
          ],
        ),
      ),
      if (period case final period?)
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 3),
          child: Text(
            period,
            style: _num(17, color: _muted, weight: FontWeight.w700),
          ),
        ),
    ],
  );
}

/// Số và đơn vị tách cỡ: "10.62" to, "km" nhỏ.
Widget _score(String label, double size) {
  final cut = label.indexOf(' ');
  final (value, unit) = cut < 0
      ? (label, '')
      : (label.substring(0, cut), label.substring(cut));
  return Text.rich(
    TextSpan(
      text: value,
      style: _num(size),
      children: [
        TextSpan(
          text: unit,
          style: _num(size * 0.55, color: _muted, weight: FontWeight.w700),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _BoardFront extends StatelessWidget {
  const _BoardFront({required this.board, this.band});

  final RankBoardSnapshot board;

  /// Dải quà cuối thẻ; null thì in chân thẻ 3I RUN.
  final Widget? band;

  @override
  Widget build(BuildContext context) {
    final shown = board.shown;
    final podium = shown.take(3).toList();
    final rows = shown.skip(3).toList();
    return ColoredBox(
      color: _cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _Header(
              kicker: rankSportNames[board.sport] ?? '',
              title: board.month ? 'BXH THÁNG' : 'BXH TUẦN',
              period: _periodShort(board),
            ),
          ),
          // Khổ thẻ cố định nên bục và dòng vừa khít; font hay tên dài làm
          // cao hơn thì thu nhỏ cả khối thay vì tràn đè dải quà.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: LayoutBuilder(
                builder: (context, box) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (podium.isNotEmpty)
                          _Podium(board: board, podium: podium),
                        if (rows.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: _ink)),
                            ),
                            child: Column(
                              children: [
                                for (final (n, i) in rows.indexed)
                                  _row(
                                    board.ranked[i],
                                    last: n == rows.length - 1,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          band ??
              Container(
                margin: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _ink, width: 1.5)),
                ),
                alignment: Alignment.centerRight,
                child: Text(
                  '3I RUN',
                  style: _num(13, color: _muted).copyWith(letterSpacing: 1),
                ),
              ),
        ],
      ),
    );
  }

  Widget _row(ClubRankedMember m, {required bool last}) {
    final me = m.entry.uid == board.currentUid;
    return Container(
      height: 20,
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: _rule, width: 0.5)),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${m.rank}', style: _num(14, color: _muted)),
          ),
          Expanded(
            child: Text(
              m.entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _body,
                color: me ? _red : _ink,
                fontSize: 12,
                fontWeight: me ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            clubRankingValueLabel(m.score, board.sport),
            style: _num(14, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Bục ba người, xếp 2-1-3. Thiếu người thì để trống cột.
class _Podium extends StatelessWidget {
  const _Podium({required this.board, required this.podium});

  final RankBoardSnapshot board;
  final List<int> podium;

  // Theo vị trí bục: hạng nhì, nhất, ba.
  static const _order = [1, 0, 2];
  static const _blocks = [48.0, 70.0, 36.0];
  static const _colors = [_T.podiumSecond, _ink, _T.podiumThird];
  static const _numbers = [30.0, 40.0, 26.0];

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (final (slot, place) in _order.indexed) ...[
        if (slot > 0) const SizedBox(width: 6),
        Expanded(
          child: place < podium.length
              ? _column(board.ranked[podium[place]], slot)
              : const SizedBox.shrink(),
        ),
      ],
    ],
  );

  Widget _column(ClubRankedMember m, int slot) {
    final me = m.entry.uid == board.currentUid;
    final centre = slot == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _body,
                  color: me ? _red : _ink,
                  fontSize: 12,
                  fontWeight: me ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
              _score(
                clubRankingValueLabel(m.score, board.sport),
                centre ? 23 : 19,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: _blocks[slot],
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: _colors[slot],
            border: centre
                ? const Border(top: BorderSide(color: _redBright, width: 4))
                : null,
          ),
          child: Text('${m.rank}', style: _num(_numbers[slot], color: _cream)),
        ),
      ],
    );
  }
}

/// Dải đen cuối mặt trước: cho người xem biết có quà và lật thẻ ra xem.
class _GiftBand extends StatelessWidget {
  const _GiftBand({required this.card});

  final RankBoardCard card;

  @override
  Widget build(BuildContext context) {
    final rewards = card.rewards;
    final items = rewards.items;
    final String title;
    final String line;
    if (items.length == 1) {
      final item = items.first;
      title = item.name;
      line = item.isDraw
          ? 'Bốc thăm ${item.slots} người đạt '
                '≥${rankRewardThreshold(item.minScore, card.sport)}'
          : 'Trao cho hạng ${item.ranks.substring(1)}';
    } else {
      final (value, label) = rankRewardCondition(rewards, card.sport);
      title = '${items.length} quà · ${rankRewardWinnerCount(rewards)} suất';
      line = '$value $label';
    }
    return Container(
      color: _ink,
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: _Photo(item: items.first, cover: true, cacheWidth: 150),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.month
                      ? 'QUÀ THÁNG NÀY · LẬT THẺ'
                      : 'QUÀ TUẦN NÀY · LẬT THẺ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _caps(_T.bandKicker, 10),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _body,
                    color: _cream,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: _body,
                    color: _T.bandText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '3I',
            style: _num(13, color: _T.bandMark).copyWith(letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

/// Mặt sau: một món thì ảnh lớn, nhiều món thì danh sách. Cuối mặt là ô số
/// chung để người xem biết ngay điều kiện, số suất và ngày công bố.
class _GiftsBack extends StatelessWidget {
  const _GiftsBack({required this.card});

  final RankBoardCard card;

  @override
  Widget build(BuildContext context) {
    final rewards = card.rewards;
    final items = rewards.items;
    final single = items.length == 1;
    final announce = rankRewardAnnounce(rewards);
    final cells = <(String, String, bool)>[
      if (single)
        switch (rankRewardCondition(rewards, card.sport)) {
          (final v, final l) => (v, l, true),
        }
      else
        ('${items.length}', 'quà', false),
      ('${rankRewardWinnerCount(rewards)}', 'suất', false),
      if (announce case (final v, final l)) (v, l, false),
    ];
    final kind = card.month ? 'QUÀ THÁNG' : 'QUÀ TUẦN';
    return ColoredBox(
      color: _cream,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (single)
              _Header(
                kicker: '$kind · ${_periodShort(card.board)}',
                title: items.first.name,
              )
            else
              _Header(
                kicker: rankSportNames[card.sport] ?? '',
                title: kind,
                period: _periodShort(card.board),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: single
                  ? _Photo(item: items.first)
                  : _GiftList(items: items, sport: card.sport),
            ),
            const SizedBox(height: 10),
            _Cells(cells: cells),
            if (!single) ...[
              const SizedBox(height: 6),
              const Text(
                'Mỗi người nhận tối đa 1 quà · 3I RUN',
                style: TextStyle(
                  fontFamily: _body,
                  color: _muted,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GiftList extends StatelessWidget {
  const _GiftList({required this.items, required this.sport});

  final List<RankRewardItem> items;
  final ClubRankingSport sport;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _ink, width: 1.5)),
    ),
    child: Column(
      children: [
        for (final (n, item) in items.indexed)
          // Ít món thì mỗi dòng cao tối đa 76 px kèm ảnh; nhiều món thì chia
          // đều phần còn lại, dòng thấp quá thì bỏ ảnh, tên và luật một hàng.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 76),
              child: DecoratedBox(
                decoration: n == items.length - 1
                    ? const BoxDecoration()
                    : const BoxDecoration(
                        border: Border(bottom: BorderSide(color: _rule)),
                      ),
                child: LayoutBuilder(
                  builder: (context, box) => box.maxHeight < 34
                      ? _compactLine(item, box)
                      : _photoLine(item),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _photoLine(RankRewardItem item) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: _Photo(item: item, cover: true, cacheWidth: 200),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: _itemName(15)),
                const SizedBox(height: 3),
                Text(rankRewardRule(item, sport), style: _num(17, color: _red)),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _compactLine(RankRewardItem item, BoxConstraints box) => SizedBox(
    // Dòng giãn đều phần còn lại nhưng không cao quá 28 px.
    height: box.maxHeight < 28 ? box.maxHeight : 28,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: box.maxWidth,
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _itemName(12),
              ),
            ),
            const SizedBox(width: 8),
            Text(rankRewardRule(item, sport), style: _num(14, color: _red)),
          ],
        ),
      ),
    ),
  );
}

TextStyle _itemName(double size) => TextStyle(
  fontFamily: _body,
  color: _ink,
  fontSize: size,
  fontWeight: FontWeight.w700,
);

/// Hàng ô số viền đen: giá trị lớn, nhãn nhỏ.
class _Cells extends StatelessWidget {
  const _Cells({required this.cells});

  final List<(String, String, bool)> cells;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _ink, width: 1.5),
    ),
    // Cao cố định đủ cho giá trị và nhãn hai dòng, để vạch chia các ô bằng nhau.
    child: SizedBox(
      height: 62,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (n, (value, label, accent)) in cells.indexed)
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
                decoration: n == 0
                    ? null
                    : const BoxDecoration(
                        border: Border(left: BorderSide(color: _rule)),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: _num(26, color: accent ? _red : _ink),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: _body,
                        color: _muted,
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Ảnh quà, chưa có ảnh thì biểu tượng. Ảnh lớn để nguyên khung (contain) cho
/// khỏi cắt mất đầu đuôi món quà; ô vuông nhỏ thì cắt cho đầy ô.
class _Photo extends StatelessWidget {
  const _Photo({required this.item, this.cover = false, this.cacheWidth = 600});

  final RankRewardItem item;
  final bool cover;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final icon = ColoredBox(
      color: _T.photoEmpty,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.45,
          heightFactor: 0.45,
          child: FittedBox(
            child: Icon(rankRewardIcon(item.icon), color: _muted),
          ),
        ),
      ),
    );
    final photo = item.photos.firstOrNull;
    if (photo == null) return icon;
    return ColoredBox(
      color: _photoBg,
      child: StorageImage(
        path: photo,
        fit: cover ? BoxFit.cover : BoxFit.contain,
        cacheWidth: cacheWidth,
        placeholder: icon,
      ),
    );
  }
}
