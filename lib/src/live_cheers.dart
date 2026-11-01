import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';

/// Emoji người xem bấm được, theo thứ tự hiện trên hàng nút. Rules nhận đúng
/// bộ này, thêm emoji thì sửa cả hai nơi.
const liveCheerEmojis = ['👏', '🔥', '💪', '🐢', '🏁'];

/// Một người xem cổ vũ buổi live: emoji vừa bấm và số lần bấm từng emoji.
/// Đọc từ `liveCheers/{sessionId}/by/{uid}` (`firestore.rules`).
class LiveCheer {
  const LiveCheer({
    required this.uid,
    required this.emoji,
    required this.at,
    required this.counts,
  });

  final String uid;
  final String emoji;

  /// Null khi lần ghi trên máy chưa có giờ server.
  final DateTime? at;
  final Map<String, int> counts;
}

/// Tổng số lần bấm từng emoji của mọi người xem, nhiều nhất đứng đầu; bằng
/// nhau thì theo thứ tự [liveCheerEmojis]. Emoji ngoài bộ thì bỏ.
List<(String, int)> liveCheerTotals(List<LiveCheer> cheers) {
  final sum = <String, int>{};
  for (final cheer in cheers) {
    for (final MapEntry(:key, :value) in cheer.counts.entries) {
      sum[key] = (sum[key] ?? 0) + value;
    }
  }
  return [
    for (final emoji in liveCheerEmojis)
      if ((sum[emoji] ?? 0) > 0) (emoji, sum[emoji]!),
  ]..sort((a, b) {
    final byCount = b.$2.compareTo(a.$2);
    if (byCount != 0) return byCount;
    return liveCheerEmojis
        .indexOf(a.$1)
        .compareTo(liveCheerEmojis.indexOf(b.$1));
  });
}

/// Những lần bấm mới giữa hai lần nhận dữ liệu, trừ của mình. Mỗi người một
/// document nên bấm lại là đổi [LiveCheer.at] của document cũ. Lần nhận đầu
/// tiên ([previous] null) không tính, để mở màn không báo lại cổ vũ cũ.
List<LiveCheer> newLiveCheers(
  List<LiveCheer>? previous,
  List<LiveCheer> next, {
  required String myUid,
}) {
  if (previous == null) return const [];
  final seen = {for (final cheer in previous) cheer.uid: cheer.at};
  return [
    for (final cheer in next)
      if (cheer.uid != myUid && seen[cheer.uid] != cheer.at) cheer,
  ];
}

/// Đọc một document cổ vũ. Field sai kiểu thì coi như không có, để một
/// document hỏng không làm mất cả hàng tổng.
LiveCheer liveCheerFrom(String uid, Map<String, dynamic> data) => LiveCheer(
  uid: uid,
  emoji: switch (data['emoji']) {
    final String emoji => emoji,
    _ => '',
  },
  at: switch (data['at']) {
    final Timestamp at => at.toDate(),
    _ => null,
  },
  counts: switch (data['n']) {
    final Map<String, dynamic> n => {
      for (final MapEntry(:key, :value) in n.entries)
        if (value is num) key: value.toInt(),
    },
    _ => const {},
  },
);

abstract interface class LiveCheerRepository {
  Stream<List<LiveCheer>> watch(String sessionId);
  Future<void> send(String sessionId, String emoji);
}

class FirestoreLiveCheerRepository implements LiveCheerRepository {
  FirestoreLiveCheerRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _by(String sessionId) =>
      _firestore.collection('liveCheers').doc(sessionId).collection('by');

  // Mỗi người xem một document nên đọc hết không vượt số người xem.
  @override
  Stream<List<LiveCheer>> watch(String sessionId) =>
      _by(sessionId).snapshots().map(
        (snapshot) => [
          for (final document in snapshot.docs)
            liveCheerFrom(document.id, document.data()),
        ],
      );

  @override
  Future<void> send(String sessionId, String emoji) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return _by(sessionId).doc(uid).set({
      'uid': uid,
      'emoji': emoji,
      'n': {emoji: FieldValue.increment(1)},
      'at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

final liveCheerRepositoryProvider = Provider<LiveCheerRepository>((ref) {
  return FirestoreLiveCheerRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final liveCheersProvider = StreamProvider.autoDispose
    .family<List<LiveCheer>, String>((ref, sessionId) {
      ref.watch(firebaseUserProvider);
      return ref.watch(liveCheerRepositoryProvider).watch(sessionId);
    });
