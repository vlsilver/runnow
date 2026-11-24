import 'package:flutter/material.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/steps_format.dart';

/// Biểu tượng quà backend nhận (rankRewardIcons trong rank_reward.go). Key lạ
/// từ backend mới thì vẽ như `other`.
const rankRewardIcons = <String, IconData>{
  'shirt': Icons.checkroom,
  'socks': Icons.dry_cleaning_outlined,
  'cap': Icons.face_retouching_natural,
  'shoes': Icons.directions_run,
  'bottle': Icons.local_drink_outlined,
  'medal': Icons.military_tech_outlined,
  'voucher': Icons.confirmation_number_outlined,
  'watch': Icons.watch_outlined,
  'bag': Icons.backpack_outlined,
  'other': Icons.card_giftcard,
};

IconData rankRewardIcon(String? key) =>
    rankRewardIcons[key] ?? Icons.card_giftcard;

/// Quá 14 ngày từ lúc trao mà người nhận chưa bấm thì coi như đã nhận.
const rankRewardAutoReceived = Duration(days: 14);

/// Giới hạn một món quà backend nhận (rankRewardNameMaxRunes,
/// rankRewardMaxPhotos), dùng chung cho quà BXH và quà kèo.
const rankRewardNameMaxRunes = 40;
const rankRewardMaxPhotos = 5;

/// Luật đã nhận chung cho quà BXH và quà kèo; backend dùng cùng luật
/// (rewardReceived) để chặn bỏ đánh dấu đã trao.
bool rewardReceived(DateTime? receivedAt, DateTime? givenAt, DateTime now) =>
    receivedAt != null ||
    (givenAt != null && now.difference(givenAt) >= rankRewardAutoReceived);

DateTime? rewardTime(Object? value) => switch (value) {
  final DateTime d => d,
  final String s => DateTime.tryParse(s),
  _ => null,
};

List<String> rewardStrings(Object? value) => [
  for (final v in value as List? ?? const []) ?(v is String ? v : null),
];

/// Kiểu món bốc thăm, khớp rankRewardDraw trong rank_reward.go.
const rankRewardDrawKind = 'draw';

/// Tổng suất bốc thăm tối đa của một bảng, khớp rankDrawMaxSlots.
const rankRewardMaxDrawSlots = 20;

/// Một món treo cho một bảng. Món theo hạng trao cho dải hạng
/// [fromRank]..[toRank]. Món bốc thăm ([isDraw]) không có hạng: lúc chốt,
/// backend bốc [slots] người trong số ai đạt từ [minScore] (mét, hay bước ở
/// Bước chân), trừ người đã có quà theo hạng.
class RankRewardItem {
  const RankRewardItem({
    required this.id,
    this.fromRank = 0,
    this.toRank = 0,
    required this.name,
    required this.icon,
    this.photos = const [],
    this.kind = '',
    this.minScore = 0,
    this.slots = 0,
  });

  static RankRewardItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String) return null;
    final id = raw['id'] as String? ?? '';
    final icon = raw['icon'] as String? ?? 'other';
    final photos = rewardStrings(raw['photos']);
    if (raw['kind'] == rankRewardDrawKind) {
      final minScore = (raw['minScore'] as num?)?.toDouble();
      final slots = (raw['slots'] as num?)?.toInt();
      if (minScore == null || slots == null) return null;
      return RankRewardItem(
        id: id,
        name: name,
        icon: icon,
        photos: photos,
        kind: rankRewardDrawKind,
        minScore: minScore,
        slots: slots,
      );
    }
    final from = (raw['fromRank'] as num?)?.toInt();
    final to = (raw['toRank'] as num?)?.toInt();
    if (from == null || to == null) return null;
    return RankRewardItem(
      id: id,
      fromRank: from,
      toRank: to,
      name: name,
      icon: icon,
      photos: photos,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    if (isDraw) ...{
      'kind': kind,
      'minScore': minScore,
      'slots': slots,
    } else ...{
      'fromRank': fromRank,
      'toRank': toRank,
    },
    'name': name,
    'icon': icon,
    'photos': photos,
  };

  /// Rỗng khi món mới, chưa lưu.
  final String id;
  final int fromRank;
  final int toRank;
  final String name;
  final String icon;

  /// Đường dẫn Storage `rankRewards/{boardId}/{tên}.jpg`.
  final List<String> photos;

  /// Rỗng là món theo hạng, [rankRewardDrawKind] là món bốc thăm.
  final String kind;
  final double minScore;
  final int slots;

  bool get isDraw => kind == rankRewardDrawKind;

  bool covers(int rank) => !isDraw && rank >= fromRank && rank <= toRank;

  /// "#1", "#2–3"; món bốc thăm thì rỗng, dùng [rankRewardRule].
  String get ranks => isDraw
      ? ''
      : fromRank == toRank
      ? '#$fromRank'
      : '#$fromRank–$toRank';

  RankRewardItem copyWith({
    int? fromRank,
    int? toRank,
    String? name,
    String? icon,
    List<String>? photos,
    String? kind,
    double? minScore,
    int? slots,
  }) => RankRewardItem(
    id: id,
    fromRank: fromRank ?? this.fromRank,
    toRank: toRank ?? this.toRank,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    photos: photos ?? this.photos,
    kind: kind ?? this.kind,
    minScore: minScore ?? this.minScore,
    slots: slots ?? this.slots,
  );
}

/// Quà treo cho một bảng ở rankRewards/{boardId}, sắp theo hạng.
class RankRewards {
  const RankRewards({
    required this.giverName,
    required this.items,
    this.periodEnd,
  });

  factory RankRewards.fromJson(Map<String, dynamic> json) => RankRewards(
    giverName: json['giverName'] as String? ?? '',
    items: [
      for (final raw in json['items'] as List? ?? const [])
        ?RankRewardItem.fromJson(raw),
    ],
    periodEnd: _day(json['periodEnd']),
  );

  final String giverName;
  final List<RankRewardItem> items;

  /// Ngày đầu sau kỳ (giờ VN), bảng chốt lúc 12:00 ngày này. Null với doc cũ.
  final DateTime? periodEnd;

  RankRewardItem? itemFor(int rank) {
    for (final item in items) {
      if (item.covers(rank)) return item;
    }
    return null;
  }
}

/// Quà gắn trên thẻ hạng lúc chốt kỳ, không đổi về sau trừ hai mốc trao, nhận.
class RankCardReward {
  const RankCardReward({
    required this.name,
    required this.icon,
    required this.photos,
    required this.giverName,
    this.givenAt,
    this.receivedAt,
    this.drawPool,
  });

  static RankCardReward? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String) return null;
    return RankCardReward(
      name: name,
      icon: raw['icon'] as String? ?? 'other',
      photos: rewardStrings(raw['photos']),
      giverName: raw['giverName'] as String? ?? '',
      givenAt: rewardTime(raw['givenAt']),
      receivedAt: rewardTime(raw['receivedAt']),
      drawPool: raw['kind'] == 'draw'
          ? (raw['pool'] as num?)?.toInt() ?? 0
          : null,
    );
  }

  final String name;
  final String icon;
  final List<String> photos;
  final String giverName;

  final DateTime? givenAt;
  final DateTime? receivedAt;

  /// Số người trong lượt bốc khi quà là món bốc thăm; null là quà theo hạng.
  final int? drawPool;

  bool receivedBy(DateTime now) => rewardReceived(receivedAt, givenAt, now);
}

/// Người trúng quà của một bảng đã chốt, admin xem để đánh dấu đã trao.
class RankRewardWinner {
  const RankRewardWinner({
    required this.uid,
    required this.displayName,
    required this.rank,
    required this.name,
    this.givenAt,
    this.receivedAt,
  });

  static RankRewardWinner? fromJson(Object? raw) {
    if (raw is! Map || raw['uid'] is! String) return null;
    return RankRewardWinner(
      uid: raw['uid'] as String,
      displayName: raw['displayName'] as String? ?? '',
      rank: (raw['rank'] as num?)?.toInt() ?? 0,
      name: raw['name'] as String? ?? '',
      givenAt: rewardTime(raw['givenAt']),
      receivedAt: rewardTime(raw['receivedAt']),
    );
  }

  final String uid;
  final String displayName;
  final int rank;
  final String name;
  final DateTime? givenAt;
  final DateTime? receivedAt;

  /// Như [RankCardReward.receivedBy]; backend dùng cùng luật để chặn bỏ
  /// đánh dấu trao.
  bool receivedBy(DateTime now) => rewardReceived(receivedAt, givenAt, now);
}

/// Trạng thái sửa quà theo kỳ: chưa bắt đầu sửa tự do, đang chạy chỉ thêm,
/// đã hết thì khoá.
enum RankRewardState { upcoming, running, closed }

/// Kết quả GET/PUT /v1/admin/rank-rewards/{board}.
class RankRewardView {
  const RankRewardView({
    required this.boardId,
    required this.state,
    required this.giverUid,
    required this.giverName,
    required this.items,
    required this.winners,
  });

  factory RankRewardView.fromJson(Map<String, dynamic> json) => RankRewardView(
    boardId: json['boardId'] as String? ?? '',
    state: RankRewardState.values.firstWhere(
      (s) => s.name == json['state'],
      orElse: () => RankRewardState.closed,
    ),
    giverUid: json['giverUid'] as String? ?? '',
    giverName: json['giverName'] as String? ?? '',
    items: [
      for (final raw in json['items'] as List? ?? const [])
        ?RankRewardItem.fromJson(raw),
    ],
    winners: [
      for (final raw in json['winners'] as List? ?? const [])
        ?RankRewardWinner.fromJson(raw),
    ],
  );

  final String boardId;
  final RankRewardState state;
  final String giverUid;
  final String giverName;
  final List<RankRewardItem> items;
  final List<RankRewardWinner> winners;
}

DateTime? _day(Object? value) {
  if (value is! String) return null;
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final [y, m, d] = [for (final p in parts) int.tryParse(p)];
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// Mốc của món bốc thăm: "15 km", "12,5 km", "12,345 km", "70.000 bước".
/// In đủ tới mét như backend so, kẻo người chạy 12,32 km đọc "từ 12,3 km" mà
/// vẫn chưa đủ mốc 12.345 m.
String rankRewardThreshold(double score, ClubRankingSport sport) {
  if (sport == ClubRankingSport.steps) {
    return '${stepThousands(score.round())} bước';
  }
  final km = score / 1000;
  final text = km
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
  return '$text km';
}

/// Luật ngắn của một món: "#1", "#2–3", "Bốc 1 · ≥15 km".
String rankRewardRule(RankRewardItem item, ClubRankingSport sport) =>
    item.isDraw
    ? 'Bốc ${item.slots} · ≥${rankRewardThreshold(item.minScore, sport)}'
    : item.ranks;

/// Nhãn ngắn in cạnh ảnh quà ở strip và mặt sau thẻ khoe, thay cho câu luật:
/// món bốc thăm là "Random", mốc và số suất; món theo hạng là hạng. Câu đủ ý
/// nằm ở sheet quà.
List<String> rankRewardTags(RankRewardItem item, ClubRankingSport sport) =>
    item.isDraw
    ? [
        'Random',
        rankRewardThreshold(item.minScore, sport),
        '${item.slots} suất',
      ]
    : [item.ranks];

/// Luật chung in cuối sheet quà và mặt sau thẻ khoe: backend gán quà theo
/// hạng trước, người đã có quà không vào lượt bốc, món bốc sau không bốc lại
/// người món trước đã trúng.
const rankRewardFooter = 'Mỗi người nhận tối đa 1 quà.';

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// Số suất quà của cả kỳ: món theo hạng có bao nhiêu hạng thì bấy nhiêu suất,
/// món bốc thăm thì bằng số suất bốc. In là "suất" chứ không phải số người
/// nhận: chung hạng ở biên thì nhiều người hơn, bảng ít người hay ít người đạt
/// mốc thì ít hơn.
int rankRewardWinnerCount(RankRewards rewards) {
  var winners = 0;
  for (final item in rewards.items) {
    winners += item.isDraw ? item.slots : item.toRank - item.fromRank + 1;
  }
  return winners;
}

/// Ô điều kiện đầu sheet quà, dạng (giá trị, nhãn): "Top 3" theo hạng,
/// "≥15 km" đủ để bốc thăm, có cả hai thì "Top 3" hoặc "≥15 km". Dải hạng
/// liền từ 1 gọi là top, có lỗ thì kể từng dải. Nhiều món bốc thăm thì lấy
/// mốc thấp nhất, mốc riêng từng món nằm trên nhãn của món.
(String, String) rankRewardCondition(
  RankRewards rewards,
  ClubRankingSport sport,
) {
  final ranked = [
    for (final item in rewards.items)
      if (!item.isDraw) item,
  ]..sort((a, b) => a.fromRank.compareTo(b.fromRank));
  String? ranks;
  if (ranked.isNotEmpty) {
    var next = 1;
    for (final item in ranked) {
      if (item.fromRank != next) break;
      next = item.toRank + 1;
    }
    final top = ranked.last.toRank;
    ranks = next == top + 1
        ? (top == 1 ? '#1' : 'Top $top')
        : ranked.map((item) => item.ranks).join(' · ');
  }
  double? min;
  for (final item in rewards.items) {
    if (item.isDraw && (min == null || item.minScore < min)) {
      min = item.minScore;
    }
  }
  final draw = min == null ? null : '≥${rankRewardThreshold(min, sport)}';
  if (ranks != null && draw != null) return (ranks, 'hoặc $draw');
  if (draw != null) return (draw, 'đủ để bốc thăm');
  return (ranks ?? '', 'theo hạng');
}

/// Câu cuối bảng đầu sheet khi có từ 2 quà. Một quà thì không cần: không có
/// quà thứ hai để nói chuyện mỗi người một quà.
String? rankRewardSheetNote(RankRewards rewards) {
  if (rewards.items.length < 2) return null;
  final mixed =
      rewards.items.any((item) => item.isDraw) &&
      rewards.items.any((item) => !item.isDraw);
  return mixed
      ? '$rankRewardFooter Xét quà theo hạng trước, rồi bốc thăm trong số '
            'người còn lại.'
      : rankRewardFooter;
}

/// Lịch chung của kỳ, dạng (giá trị, nhãn): ngày cuối tính km và giờ chốt.
/// Backend chốt bảng, gán quà và đăng bài báo quà trong cùng một lượt tick sau
/// 12:00, nên giờ chốt cũng là giờ công bố. Rỗng khi chưa biết ngày hết kỳ.
List<(String, String)> rankRewardSchedule(RankRewards rewards) {
  final end = rewards.periodEnd;
  if (end == null) return const [];
  return [
    (_dayLabel(DateTime(end.year, end.month, end.day - 1)), 'tính tới hết'),
    ('12:00 ${_dayLabel(end)}', 'chốt và công bố'),
  ];
}

/// Ngày công bố cho ô nhỏ trên thẻ khoe: ("T2 30/11", "12:00 công bố").
/// Null khi chưa biết ngày hết kỳ.
(String, String)? rankRewardAnnounce(RankRewards rewards) {
  final end = rewards.periodEnd;
  return end == null ? null : (_dayLabel(end), '12:00 công bố');
}

String _dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day}/${d.month}';
