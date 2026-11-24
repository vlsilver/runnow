import 'dart:typed_data';

import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';

/// Quà chủ kèo treo cho kèo công khai, ở contractGifts/{contractId}. Backend ghi
/// (contract_gift.go); app chỉ đọc doc và gọi API.
enum ContractGiftKind {
  draw('draw', 'Bốc thăm', 'Đạt mục tiêu là có vé, chốt kèo thì bốc'),
  rank('rank', 'Theo hạng', 'Hạng 1, 2, 3 trong số người đạt');

  const ContractGiftKind(this.value, this.label, this.hint);

  final String value;
  final String label;
  final String hint;

  static ContractGiftKind? from(Object? value) =>
      values.where((k) => k.value == value).firstOrNull;
}

/// Giới hạn backend nhận (contractGiftMaxItems, contractGiftMaxSlots).
const contractGiftMaxItems = 5;
const contractGiftMaxSlots = 20;

/// Kèo nào treo quà được: kèo công khai trong Club, trừ kèo theo tuyến (backend
/// không tính lại tiến độ kèo tuyến nên không chia quà được).
bool contractGiftAllowed(
  RunContractVisibility visibility,
  RunContractMetric metric,
) =>
    visibility == RunContractVisibility.club &&
    metric != RunContractMetric.routeCompletion;

class ContractGiftItem {
  const ContractGiftItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.slots,
    this.photos = const [],
  });

  static ContractGiftItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final slots = (raw['slots'] as num?)?.toInt();
    if (name is! String || slots == null) return null;
    return ContractGiftItem(
      id: raw['id'] as String? ?? '',
      name: name,
      icon: raw['icon'] as String? ?? 'other',
      slots: slots,
      photos: rewardStrings(raw['photos']),
    );
  }

  final String id;
  final String name;
  final String icon;
  final int slots;
  final List<String> photos;
}

class ContractGiftWinner {
  const ContractGiftWinner({
    required this.slot,
    required this.itemId,
    required this.uid,
    this.rank,
    this.givenAt,
    this.receivedAt,
  });

  static ContractGiftWinner? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    final itemId = raw['itemId'];
    if (uid is! String || itemId is! String) return null;
    return ContractGiftWinner(
      slot: (raw['slot'] as num?)?.toInt() ?? 0,
      itemId: itemId,
      uid: uid,
      rank: (raw['rank'] as num?)?.toInt(),
      givenAt: rewardTime(raw['givenAt']),
      receivedAt: rewardTime(raw['receivedAt']),
    );
  }

  final int slot;
  final String itemId;
  final String uid;

  /// Hạng trong số người đạt, chỉ kiểu Theo hạng.
  final int? rank;
  final DateTime? givenAt;
  final DateTime? receivedAt;

  /// Đã nhận: người trúng bấm, hoặc đã trao quá [rankRewardAutoReceived].
  bool receivedBy(DateTime now) => rewardReceived(receivedAt, givenAt, now);
}

class ContractGift {
  const ContractGift({
    required this.contractId,
    required this.creatorUid,
    required this.kind,
    required this.giverName,
    required this.items,
    this.resolvedAt,
    this.entrants = const [],
    this.winners = const [],
  });

  static ContractGift? fromJson(String contractId, Map<String, dynamic> raw) {
    final kind = ContractGiftKind.from(raw['kind']);
    if (kind == null) return null;
    return ContractGift(
      contractId: contractId,
      creatorUid: raw['creatorUid'] as String? ?? '',
      kind: kind,
      giverName: raw['giverName'] as String? ?? '',
      items: [
        for (final v in raw['items'] as List? ?? const [])
          ?ContractGiftItem.fromJson(v),
      ],
      resolvedAt: rewardTime(raw['resolvedAt']),
      entrants: rewardStrings(raw['entrants']),
      winners: [
        for (final v in raw['winners'] as List? ?? const [])
          ?ContractGiftWinner.fromJson(v),
      ],
    );
  }

  final String contractId;
  final String creatorUid;
  final ContractGiftKind kind;
  final String giverName;
  final List<ContractGiftItem> items;

  /// Lúc job chốt kèo chia quà; null khi kèo còn chạy.
  final DateTime? resolvedAt;

  /// Người đạt lúc chốt (có vé / có hạng), không kể chủ kèo.
  final List<String> entrants;
  final List<ContractGiftWinner> winners;

  int get slots => items.fold(0, (sum, it) => sum + it.slots);
  bool get resolved => resolvedAt != null;

  ContractGiftItem? item(String id) =>
      items.where((it) => it.id == id).firstOrNull;

  ContractGiftWinner? winnerFor(String uid) =>
      winners.where((w) => w.uid == uid).firstOrNull;

  /// "4 quà" trên thẻ kèo: đếm suất, không đếm món.
  String get badge => '$slots quà';
}

/// Người đang đạt mục tiêu theo số trên doc kèo (trừ chủ kèo), ai đạt sớm hơn
/// không biết được ở app nên xếp theo tiến độ. Đây chỉ là số hiển thị lúc kèo
/// còn chạy; lúc chốt backend tính lại từ buổi chạy.
List<RunContractParticipant> contractGiftQualified(RunContract contract) {
  final out = [
    for (final p in contract.participants.values)
      if (p.uid != contract.creatorUid &&
          contractTargetMet(contract, p.progressValue))
        p,
  ]..sort((a, b) => b.progressValue.compareTo(a.progressValue));
  return out;
}

/// Ảnh của một món đang sửa: đã có trên Storage ([path]) hay mới chọn, chờ
/// tải lên khi lưu ([bytes], JPEG).
class ContractGiftPhoto {
  const ContractGiftPhoto.stored(String this.path) : bytes = null;
  const ContractGiftPhoto.picked(Uint8List this.bytes) : path = null;

  final String? path;
  final Uint8List? bytes;
}

/// Một món trong bản nháp. [id] rỗng là món mới.
class ContractGiftDraftItem {
  const ContractGiftDraftItem({
    this.id = '',
    this.name = '',
    this.icon = 'other',
    this.slots = 1,
    this.photos = const [],
  });

  factory ContractGiftDraftItem.of(ContractGiftItem item) =>
      ContractGiftDraftItem(
        id: item.id,
        name: item.name,
        icon: item.icon,
        slots: item.slots,
        photos: [for (final p in item.photos) ContractGiftPhoto.stored(p)],
      );

  final String id;
  final String name;
  final String icon;
  final int slots;
  final List<ContractGiftPhoto> photos;

  ContractGiftDraftItem copyWith({
    String? name,
    String? icon,
    int? slots,
    List<ContractGiftPhoto>? photos,
  }) => ContractGiftDraftItem(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    slots: slots ?? this.slots,
    photos: photos ?? this.photos,
  );
}

class ContractGiftDraft {
  const ContractGiftDraft({required this.kind, required this.items});

  factory ContractGiftDraft.of(ContractGift gift) => ContractGiftDraft(
    kind: gift.kind,
    items: [for (final it in gift.items) ContractGiftDraftItem.of(it)],
  );

  final ContractGiftKind kind;
  final List<ContractGiftDraftItem> items;

  int get slots => items.fold(0, (sum, it) => sum + it.slots);

  /// "Bốc thăm · 4 suất".
  String get summary => '${kind.label} · $slots suất';
}
