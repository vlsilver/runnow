import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_models.dart';

/// Đọc phòng chạy từ Firestore theo rules; mọi thao tác ghi phòng và thành
/// viên đi qua API (`RunNowApiClient`), riêng tin cổ vũ ghi thẳng.
class RunRoomRepository {
  RunRoomRepository(this._firestore);

  final FirebaseFirestore _firestore;

  static const _publicLimit = 20;
  static const _messageLimit = 30;
  static const _liveLimit = 20;
  static const _myRoomsWindow = Duration(days: 8);

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('runRooms');

  /// Phòng public còn mở, sắp đóng trước. Phòng private và mật khẩu không
  /// nằm ở đây; người được mời vào qua link.
  Stream<List<RunRoom>> watchPublicRooms(DateTime now) => _rooms
      .where('privacy', isEqualTo: RunRoomPrivacy.public.value)
      .where('status', isEqualTo: 'open')
      .where('closesAt', isGreaterThan: Timestamp.fromDate(now))
      .orderBy('closesAt')
      .limit(_publicLimit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs) RunRoom.fromMap(doc.id, doc.data()),
        ],
      );

  Stream<RunRoom?> watchRoom(String roomId) =>
      _rooms.doc(roomId).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : RunRoom.fromMap(doc.id, data);
      });

  /// Các phòng [uid] đang ở hay đang chờ duyệt. Phòng kết thúc không đổi
  /// state thành viên, nên chỉ lấy dòng đổi trong [_myRoomsWindow]: phòng còn
  /// mở được tạo chưa quá 7 ngày 6 tiếng (hẹn trước tối đa 7 ngày, mở 6 tiếng)
  /// và mọi lần ghi thành viên đều ghi `updatedAt`.
  Stream<List<RunRoomMembership>> watchMyRooms(String uid, DateTime now) =>
      _firestore
          .collectionGroup('members')
          .where('uid', isEqualTo: uid)
          .where('state', whereIn: ['joined', 'requested'])
          .where(
            'updatedAt',
            isGreaterThan: Timestamp.fromDate(now.subtract(_myRoomsWindow)),
          )
          .snapshots()
          .map(
            (snap) => [
              for (final doc in snap.docs)
                if (doc.reference.parent.parent case final room?)
                  RunRoomMembership(
                    roomId: room.id,
                    state: RunRoomMemberState.fromValue(
                      doc.data()['state'] as String?,
                    ),
                  ),
            ],
          );

  /// Thành viên của mình, đọc được cả khi chưa vào phòng (để biết đang chờ
  /// duyệt hay bị từ chối). Null khi chưa từng xin vào.
  Stream<RunRoomMember?> watchMyMember(String roomId, String uid) =>
      _rooms.doc(roomId).collection('members').doc(uid).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : RunRoomMember.fromMap(doc.id, data);
      });

  /// Mọi thành viên; rules chỉ cho người đã vào phòng đọc.
  Stream<List<RunRoomMember>> watchMembers(String roomId) => _rooms
      .doc(roomId)
      .collection('members')
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            RunRoomMember.fromMap(doc.id, doc.data()),
        ],
      );

  /// Buổi chạy live đang gắn với phòng.
  Stream<List<LiveTrackingSession>> watchRoomLive(String roomId) => _firestore
      .collection('liveSessions')
      .where('roomId', isEqualTo: roomId)
      .where('status', whereIn: ['running', 'paused'])
      .orderBy('updatedAt', descending: true)
      .limit(_liveLimit)
      .snapshots()
      .map((snap) {
        final now = DateTime.now();
        return [
          for (final doc in snap.docs)
            if (_live(doc) case final session?
                when session.isActive && !session.isExpired(now))
              session,
        ];
      });

  static LiveTrackingSession? _live(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final startedAt = data['startedAt'];
    final updatedAt = data['updatedAt'];
    return LiveTrackingSession.fromMap({
      ...data,
      'id': doc.id,
      if (startedAt is Timestamp) 'startedAt': startedAt.toDate(),
      if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
    });
  }

  /// Tin cổ vũ mới nhất trước.
  Stream<List<RunRoomMessage>> watchMessages(String roomId) => _rooms
      .doc(roomId)
      .collection('messages')
      .orderBy('at', descending: true)
      .limit(_messageLimit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            RunRoomMessage.fromMap(doc.id, doc.data()),
        ],
      );

  /// Gửi cổ vũ. TTL dọn tin sau 6 ngày; rules cho tối đa 7 ngày tính theo giờ
  /// server, chừa một ngày cho đồng hồ máy lệch.
  Future<void> sendMessage(
    String roomId, {
    required String uid,
    required String text,
    required bool emoji,
  }) => _rooms.doc(roomId).collection('messages').add({
    'uid': uid,
    'kind': emoji ? 'emoji' : 'text',
    'text': text,
    'at': FieldValue.serverTimestamp(),
    'expiresAt': Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 6)),
    ),
  });
}

final runRoomRepositoryProvider = Provider<RunRoomRepository>(
  (ref) => RunRoomRepository(FirebaseFirestore.instance),
);

/// Phòng public còn mở. Lấy mốc giờ một lần khi mở mục, phòng quá giờ đóng
/// trong lúc xem thì `RunRoom.isOpen` lọc ở UI.
final publicRunRoomsProvider = StreamProvider.autoDispose<List<RunRoom>>(
  (ref) =>
      ref.watch(runRoomRepositoryProvider).watchPublicRooms(DateTime.now()),
);

final myRunRoomsProvider = StreamProvider.autoDispose<List<RunRoomMembership>>((
  ref,
) {
  final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
  if (uid == null) return Stream.value(const []);
  return ref.watch(runRoomRepositoryProvider).watchMyRooms(uid, DateTime.now());
});

final runRoomProvider = StreamProvider.autoDispose.family<RunRoom?, String>(
  (ref, roomId) => ref.watch(runRoomRepositoryProvider).watchRoom(roomId),
);

final myRunRoomMemberProvider = StreamProvider.autoDispose
    .family<RunRoomMember?, String>((ref, roomId) {
      final uid = ref.watch(firebaseUserProvider.select((u) => u.value?.uid));
      if (uid == null) return Stream.value(null);
      return ref.watch(runRoomRepositoryProvider).watchMyMember(roomId, uid);
    });

final runRoomMembersProvider = StreamProvider.autoDispose
    .family<List<RunRoomMember>, String>(
      (ref, roomId) =>
          ref.watch(runRoomRepositoryProvider).watchMembers(roomId),
    );

final runRoomLiveProvider = StreamProvider.autoDispose
    .family<List<LiveTrackingSession>, String>(
      (ref, roomId) =>
          ref.watch(runRoomRepositoryProvider).watchRoomLive(roomId),
    );

final runRoomMessagesProvider = StreamProvider.autoDispose
    .family<List<RunRoomMessage>, String>(
      (ref, roomId) =>
          ref.watch(runRoomRepositoryProvider).watchMessages(roomId),
    );
