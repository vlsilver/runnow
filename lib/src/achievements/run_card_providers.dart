import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Doc Firestore sang map thường: Timestamp thành DateTime, kể cả trong map
/// con như `art`, để model parse giống JSON của API.
Object? _plain(Object? value) => switch (value) {
  final Timestamp t => t.toDate(),
  final Map<dynamic, dynamic> m => {
    for (final e in m.entries) '${e.key}': _plain(e.value),
  },
  final List<dynamic> l => [for (final v in l) _plain(v)],
  _ => value,
};

RunCard _cardFrom(DocumentSnapshot<Map<String, dynamic>> doc) =>
    RunCard.fromJson({
      ...(_plain(doc.data()) as Map<String, dynamic>),
      'id': doc.id,
    });

CollectionReference<Map<String, dynamic>> _cards(String uid) =>
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('runCards');

/// Thẻ của buổi [activityId] của chính mình, null khi chưa lật. Nghe doc để
/// lúc backend vẽ xong tranh thì thẻ tự đổi.
final runCardProvider = StreamProvider.autoDispose.family<RunCard?, String>((
  ref,
  activityId,
) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(null);
  return _cards(uid)
      .doc(activityId)
      .snapshots()
      .map((doc) => doc.exists ? _cardFrom(doc) : null);
});

/// Tỉ lệ sẽ quay, hoặc lý do buổi này không lật được. Chỉ đọc khi chưa có thẻ.
final runCardViewProvider = FutureProvider.autoDispose
    .family<RunCardView, String>(
      (ref, activityId) =>
          ref.watch(runNowApiClientProvider).getRunCard(activityId),
    );

/// Bộ thẻ của mình, mới lật trước.
final runCardsProvider = StreamProvider.autoDispose<List<RunCard>>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(const []);
  return _cards(uid)
      .orderBy('rolledAt', descending: true)
      .snapshots()
      .map((snap) => [for (final doc in snap.docs) _cardFrom(doc)]);
});

/// Phong cách vẽ đang bật. Đọc mỗi lần mở bảng chọn, không cache lâu, để
/// backend tắt một phong cách thì app thôi hiện ngay.
final runCardStylesProvider = FutureProvider.autoDispose<ArtStyleList>(
  (ref) => ref.watch(runNowApiClientProvider).getRunCardStyles(),
);
