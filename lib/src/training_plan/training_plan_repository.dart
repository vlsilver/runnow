import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../runnow_api_client.dart';
import 'training_plan_models.dart';

/// Giáo án AI Coach người dùng đang SỞ HỮU — top-level `coachPlans/{uid}`
/// (mỗi người tối đa 1 giáo án owned). null = chưa tạo. `done` mỗi buổi phản
/// ánh tiến độ của chính chủ (parse với currentUid = uid).
final coachPlanProvider = StreamProvider<TrainingPlan?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('coachPlans')
      .doc(uid)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (data == null) return null;
        final created = data['createdAt'];
        return TrainingPlan.fromMap(
          snap.id,
          data,
          createdAt: created is Timestamp ? created.toDate() : null,
          currentUid: uid,
        );
      });
});

/// Giáo án PUBLIC (visibility=club) — hiện thành card trên feed Kèo cho mọi
/// người xem/tham gia. Một filter equality, không cần composite index.
final publicCoachPlansProvider = StreamProvider<List<TrainingPlan>>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return FirebaseFirestore.instance
      .collection('coachPlans')
      .where('visibility', isEqualTo: 'club')
      .snapshots()
      .map(
        (snap) => snap.docs.map((d) {
          final created = d.data()['createdAt'];
          return TrainingPlan.fromMap(
            d.id,
            d.data(),
            createdAt: created is Timestamp ? created.toDate() : null,
            currentUid: uid,
          );
        }).toList(),
      );
});

/// Một giáo án bất kỳ theo id (= ownerUid) — dùng cho màn chi tiết coach. `done`
/// mỗi buổi phản ánh tiến độ của người đang xem (nếu họ đã tham gia).
final coachPlanByIdProvider = StreamProvider.family<TrainingPlan?, String>((
  ref,
  planId,
) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return FirebaseFirestore.instance
      .collection('coachPlans')
      .doc(planId)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (data == null) return null;
        final created = data['createdAt'];
        return TrainingPlan.fromMap(
          snap.id,
          data,
          createdAt: created is Timestamp ? created.toDate() : null,
          currentUid: uid,
        );
      });
});

/// Bản nháp chờ user xác nhận — stream từ users/{uid}/coach/draft.
/// null = không có đề xuất nào đang treo.
final coachDraftProvider = StreamProvider<TrainingPlan?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('coach')
      .doc('draft')
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (data == null) return null;
        final created = data['createdAt'];
        return TrainingPlan.fromMap(
          'draft',
          data,
          createdAt: created is Timestamp ? created.toDate() : null,
        );
      });
});

/// Lịch sử hỏi đáp với coach cho một giáo án cụ thể (cũ → mới). Mỗi thành viên
/// có kênh RIÊNG theo từng giáo án: users/{uid}/coachChats/{planId}/messages.
final coachChatProvider =
    StreamProvider.family<List<CoachChatMessage>, String>((ref, planId) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('coachChats')
      .doc(planId)
      .collection('messages')
      .orderBy('createdAt')
      .limitToLast(100)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map((d) => CoachChatMessage.fromMap(d.id, d.data()))
            .toList(),
      );
});

/// Một lượt trong hội thoại với coach.
class CoachChatMessage {
  const CoachChatMessage({
    required this.id,
    required this.text,
    required this.fromCoach,
    this.createdAt,
  });

  final String id;
  final String text;
  final bool fromCoach;
  final DateTime? createdAt;

  factory CoachChatMessage.fromMap(String id, Map<String, dynamic> map) {
    final created = map['createdAt'];
    return CoachChatMessage(
      id: id,
      text: map['text'] as String? ?? '',
      fromCoach: map['role'] == 'coach',
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

final coachControllerProvider = Provider<CoachController>(
  (ref) => CoachController(
    FirebaseFirestore.instance,
    ref.watch(runNowApiClientProvider),
  ),
);

class CoachController {
  CoachController(this._db, this._api);
  final FirebaseFirestore _db;
  final RunNowApiClient _api;

  /// Nhờ backend sinh ĐỀ XUẤT giáo án. Kết quả vào coach/draft — giáo án đang
  /// chạy không bị đụng tới cho tới khi [confirmDraft]. [coachDraftProvider]
  /// cập nhật khi xong.
  Future<void> generate(
    String goal, {
    CoachVisibility visibility = CoachVisibility.private,
  }) => _api.generateTrainingPlan(goal: goal, visibility: visibility.value);

  /// User đồng ý với đề xuất → thành giáo án đang chạy.
  Future<void> confirmDraft() => _api.confirmTrainingPlan();

  /// User không đồng ý → bỏ đề xuất, giữ nguyên giáo án cũ.
  Future<void> discardDraft() => _api.discardTrainingPlan();

  /// Hỏi coach một câu về giáo án [planId]. Trả về câu trả lời; cả hỏi lẫn đáp
  /// được backend lưu vào kênh chat riêng của user cho giáo án đó nên
  /// [coachChatProvider] tự cập nhật.
  Future<String> ask(String planId, String question) =>
      _api.askCoach(planId: planId, question: question);

  /// Chủ giáo án đổi Riêng tư ↔ Công khai. Công khai → lên feed Kèo, mọi người
  /// tham gia được + roster hiện. Luật Firestore cho owner đổi (branch A).
  Future<void> setVisibility(String planId, CoachVisibility visibility) async {
    await _db.collection('coachPlans').doc(planId).update({
      'visibility': visibility.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Tham gia một giáo án PUBLIC của người khác — thêm mình vào participants với
  /// tiến độ rỗng. Luật Firestore chỉ cho ghi đúng subtree uid của mình.
  Future<void> join(String planId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('coachPlans').doc(planId).update({
      'participants.$uid': {
        'joinedAt': FieldValue.serverTimestamp(),
        'doneIndices': <int>[],
      },
      'participantUids': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rời giáo án (không phải chủ) — xoá subtree tiến độ của mình.
  Future<void> leave(String planId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('coachPlans').doc(planId).update({
      'participants.$uid': FieldValue.delete(),
      'participantUids': FieldValue.arrayRemove([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Xoá giáo án mình sở hữu (coachPlans/{uid}). Chỉ owner mới gọi được (luật
  /// Firestore chặn người khác).
  Future<void> delete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('coachPlans').doc(uid).delete();
  }

  /// Tick/bỏ tick 1 buổi cho CHÍNH MÌNH trong giáo án [planId]. Tiến độ nằm ở
  /// participants.{uid}.doneIndices — mỗi người một tiến độ, không đụng lịch
  /// chung. Luật Firestore chỉ cho ghi đúng subtree uid của mình.
  Future<void> toggleDone(String planId, int dayIndex, bool done) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('coachPlans').doc(planId).update({
      'participants.$uid.doneIndices': done
          ? FieldValue.arrayUnion([dayIndex])
          : FieldValue.arrayRemove([dayIndex]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
