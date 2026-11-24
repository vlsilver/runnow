import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';

/// Đọc dữ liệu lãnh địa. Chỉ backend ghi các doc này (docs/territory_design.md
/// mục 3), app không ghi gì.
class TerritoryRepository {
  TerritoryRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<List<TerritoryCell>> watchChunk(TileXY chunk) => _firestore
      .collection('territoryChunks')
      .doc(chunk.id)
      .snapshots()
      .map((doc) => parseTerritoryCells(doc.data()));

  Stream<TerritoryOwner> watchOwner(String uid) => _firestore
      .collection('territoryOwners')
      .doc(uid)
      .snapshots()
      .map((doc) => TerritoryOwner.fromMap(doc.data()));

  Stream<bool> watchEnabled() => _firestore
      .collection('config')
      .doc('territory')
      .snapshots()
      .map((doc) => doc.data()?['enabled'] == true);

  /// Các ô [uid] đang giữ trong [chunks], đọc một lần cho thẻ khoe.
  Future<List<TileXY>> fetchOwnedCells(
    String uid,
    Iterable<TileXY> chunks,
  ) async {
    final docs = await Future.wait([
      for (final chunk in chunks)
        _firestore.collection('territoryChunks').doc(chunk.id).get(),
    ]);
    return [
      for (final doc in docs)
        for (final cell in parseTerritoryCells(doc.data()))
          if (cell.ownerUid == uid) cell.tile,
    ];
  }

  /// Kết quả lãnh địa của một buổi, đọc doc nhỏ `territoryResults` thay vì
  /// doc buổi (tới 800 KB vì có tuyến). Backend ghi vài giây sau khi lưu buổi,
  /// và ghi lại khi buổi đổi từ không được tính sang được tính, nên nghe tiếp.
  Stream<TerritoryResult?> watchActivityResult(String uid, String activityId) =>
      _firestore
          .collection('territoryResults')
          .doc('${uid}_$activityId')
          .snapshots()
          .map((doc) => TerritoryResult.fromMap(doc.data()));
}

final territoryRepositoryProvider = Provider<TerritoryRepository>(
  (ref) => TerritoryRepository(FirebaseFirestore.instance),
);

/// Lãnh địa bật hay tắt, đọc từ `config/territory.enabled`: cùng một cờ với
/// backend (backend chỉ có kết quả và push khi cờ này bật), nên ra mắt chỉ cần
/// bật một chỗ, và bản web cũng theo được. Chưa có doc, lỗi đọc hay chưa đăng
/// nhập thì coi như tắt.
final territoryEnabledProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
  if (uid == null) return Stream.value(false);
  return ref.watch(territoryRepositoryProvider).watchEnabled();
});

/// Các ô của một chunk z13. autoDispose để chunk ra khỏi khung nhìn thì thôi
/// nghe.
final territoryChunkProvider = StreamProvider.autoDispose
    .family<List<TerritoryCell>, TileXY>(
      (ref, chunk) => ref.watch(territoryRepositoryProvider).watchChunk(chunk),
    );

/// Số ô của người đang đăng nhập; null khi chưa đăng nhập.
final myTerritoryProvider = StreamProvider.autoDispose<TerritoryOwner?>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref.watch(territoryRepositoryProvider).watchOwner(uid);
});

/// Kết quả lãnh địa của buổi [activityId] thuộc [uid].
final activityTerritoryResultProvider = StreamProvider.autoDispose
    .family<TerritoryResult?, ({String uid, String activityId})>(
      (ref, key) => ref
          .watch(territoryRepositoryProvider)
          .watchActivityResult(key.uid, key.activityId),
    );

/// Tên và avatar theo uid, đọc từ `leaderboardEntries` mà app đã tải cho BXH.
/// Chưa tải xong thì rỗng, chỗ hiện tên dùng tên mặc định.
final territoryNamesProvider =
    Provider.autoDispose<Map<String, ({String name, String? avatarUrl})>>((
      ref,
    ) {
      final docs = ref.watch(leaderboardDocsProvider).value ?? const [];
      return {
        for (final doc in docs)
          doc.id: (
            name: switch ((doc.data()['displayName'] as String?)?.trim()) {
              final String name when name.isNotEmpty => name,
              _ => territoryDefaultName,
            },
            avatarUrl: doc.data()['avatarUrl'] as String?,
          ),
      };
    });

const territoryDefaultName = '3i member';
