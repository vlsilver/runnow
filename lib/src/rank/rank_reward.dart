import 'package:flutter/material.dart';

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

/// Một món treo cho dải hạng [fromRank]..[toRank] của một bảng.
class RankRewardItem {
  const RankRewardItem({
    required this.id,
    required this.fromRank,
    required this.toRank,
    required this.name,
    required this.icon,
    this.photos = const [],
  });

  static RankRewardItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final from = (raw['fromRank'] as num?)?.toInt();
    final to = (raw['toRank'] as num?)?.toInt();
    final name = raw['name'];
    if (from == null || to == null || name is! String) return null;
    return RankRewardItem(
      id: raw['id'] as String? ?? '',
      fromRank: from,
      toRank: to,
      name: name,
      icon: raw['icon'] as String? ?? 'other',
      photos: rewardStrings(raw['photos']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'fromRank': fromRank,
    'toRank': toRank,
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

  bool covers(int rank) => rank >= fromRank && rank <= toRank;

  /// "#1", "#2–3".
  String get ranks => fromRank == toRank ? '#$fromRank' : '#$fromRank–$toRank';

  RankRewardItem copyWith({
    int? fromRank,
    int? toRank,
    String? name,
    String? icon,
    List<String>? photos,
  }) => RankRewardItem(
    id: id,
    fromRank: fromRank ?? this.fromRank,
    toRank: toRank ?? this.toRank,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    photos: photos ?? this.photos,
  );
}

/// Quà treo cho một bảng ở rankRewards/{boardId}, sắp theo hạng.
class RankRewards {
  const RankRewards({required this.giverName, required this.items});

  factory RankRewards.fromJson(Map<String, dynamic> json) => RankRewards(
    giverName: json['giverName'] as String? ?? '',
    items: [
      for (final raw in json['items'] as List? ?? const [])
        ?RankRewardItem.fromJson(raw),
    ],
  );

  final String giverName;
  final List<RankRewardItem> items;

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
