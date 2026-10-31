import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';

/// Target của tim. Rules chỉ nhận đúng ba dạng này (`firestore.rules`,
/// `match /hearts/{targetKey}/by/{uid}`).
String runHeartTarget(String ownerUid, String activityId) =>
    'run_${ownerUid}_$activityId';

String cardHeartTarget(String ownerUid, String activityId) =>
    'card_${ownerUid}_$activityId';

String liveHeartTarget(String sessionId) => 'live_$sessionId';

/// Ai đã thả tim cho một target, người thả gần nhất đứng đầu.
class Hearts {
  const Hearts({required this.uids, required this.mine});

  static const empty = Hearts(uids: [], mine: false);

  final List<String> uids;
  final bool mine;

  int get count => uids.length;
}

/// Tim vừa ghi trên máy chưa có giờ server (`at` null) thì coi là mới nhất.
Hearts heartsFrom(
  List<({String uid, DateTime? at})> entries, {
  required String? myUid,
}) {
  final sorted = [...entries]
    ..sort((left, right) {
      final l = left.at;
      final r = right.at;
      if (l == null) return r == null ? 0 : -1;
      if (r == null) return 1;
      return r.compareTo(l);
    });
  final uids = [for (final entry in sorted) entry.uid];
  return Hearts(uids: uids, mine: myUid != null && uids.contains(myUid));
}

/// Người vừa thả tim giữa hai lần nhận dữ liệu, trừ chính mình. Lần nhận đầu
/// tiên ([previous] null) không tính, để mở màn không báo lại tim cũ.
List<String> newHeartUids(
  Hearts? previous,
  Hearts next, {
  required String myUid,
}) {
  if (previous == null) return const [];
  final seen = previous.uids.toSet();
  return [
    for (final uid in next.uids)
      if (uid != myUid && !seen.contains(uid)) uid,
  ];
}

abstract interface class HeartRepository {
  Stream<Hearts> watch(String target);
  Future<void> like(String target);
  Future<void> unlike(String target);
}

class FirestoreHeartRepository implements HeartRepository {
  FirestoreHeartRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _by(String target) =>
      _firestore.collection('hearts').doc(target).collection('by');

  // Đọc hết document của target: mỗi người một document nên số document
  // không vượt số thành viên club.
  @override
  Stream<Hearts> watch(String target) {
    return _by(target).snapshots().map((snapshot) {
      final entries = [
        for (final document in snapshot.docs)
          (
            uid: document.id,
            at: switch (document.data()['at']) {
              final Timestamp at => at.toDate(),
              _ => null,
            },
          ),
      ];
      return heartsFrom(entries, myUid: _auth.currentUser?.uid);
    });
  }

  @override
  Future<void> like(String target) {
    final uid = _uid;
    return _by(
      target,
    ).doc(uid).set({'uid': uid, 'at': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> unlike(String target) => _by(target).doc(_uid).delete();
}

final heartRepositoryProvider = Provider<HeartRepository>((ref) {
  return FirestoreHeartRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final heartsProvider = StreamProvider.autoDispose.family<Hearts, String>((
  ref,
  target,
) {
  ref.watch(firebaseUserProvider);
  return ref.watch(heartRepositoryProvider).watch(target);
});
