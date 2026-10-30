import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';
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

CollectionReference<Map<String, dynamic>> get _clubCards =>
    FirebaseFirestore.instance.collection('clubCards');

/// Club vài chục người nên một lô này đủ cho cả mục Thẻ mới ở trang Kèo lẫn
/// trang Thẻ của club.
const _clubCardLimit = 60;

/// Thẻ cả club đang khoe, khoe mới trước.
final clubCardsProvider = StreamProvider.autoDispose<List<ClubCard>>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(const []);
  return _clubCards
      .orderBy('sharedAt', descending: true)
      .limit(_clubCardLimit)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            ?ClubCard.fromJson(_plain(doc.data()) as Map<String, dynamic>),
        ],
      );
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

/// Thẻ Ma Sói của các ván phe mình thắng, ván mới kết thúc trước. Backend ghi
/// lúc ván kết thúc, app chỉ đọc.
final gameCardsProvider = StreamProvider.autoDispose<List<GamePlayerCard>>((
  ref,
) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('gameCards')
      .orderBy('endedAt', descending: true)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            GamePlayerCard.fromJson(
              doc.id,
              _plain(doc.data()) as Map<String, dynamic>,
            ),
        ],
      );
});

/// Thẻ Hành trình của các chặng đã về đích, theo thứ tự chặng. Backend ghi
/// lúc về đích, app chỉ đọc.
final journeyCardsProvider = StreamProvider.autoDispose<List<JourneyCard>>((
  ref,
) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('journeyCards')
      .orderBy('level')
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            JourneyCard.fromJson(
              doc.id,
              _plain(doc.data()) as Map<String, dynamic>,
            ),
        ],
      );
});

/// Bảng đã chốt của kỳ trước, null khi backend chưa chốt.
final rankBoardProvider = StreamProvider.autoDispose.family<RankBoard?, String>(
  (ref, boardId) {
    return FirebaseFirestore.instance
        .collection('rankBoards')
        .doc(boardId)
        .snapshots()
        .map(
          (doc) => doc.exists
              ? RankBoard.fromJson(_plain(doc.data()) as Map<String, dynamic>)
              : null,
        );
  },
);

RankCard? _rankCardFrom(
  String uid,
  DocumentSnapshot<Map<String, dynamic>> doc,
) => doc.exists
    ? RankCard.fromJson(uid, doc.id, _plain(doc.data()) as Map<String, dynamic>)
    : null;

/// Thẻ BXH của một người trên một bảng. Ai đăng nhập cũng đọc được để thấy thẻ
/// đã lật của top 10; nghe doc để chủ thẻ lật thì mọi người thấy ngay.
final rankCardProvider = StreamProvider.autoDispose
    .family<RankCard?, ({String uid, String boardId})>((ref, key) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(key.uid)
          .collection('rankCards')
          .doc(key.boardId)
          .snapshots()
          .map((doc) => _rankCardFrom(key.uid, doc));
    });

/// Thẻ BXH của mình, mới nhất trước.
final myRankCardsProvider = StreamProvider.autoDispose<List<RankCard>>((ref) {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('rankCards')
      .orderBy('awardedAt', descending: true)
      .snapshots()
      .map((snap) => [for (final doc in snap.docs) ?_rankCardFrom(uid, doc)]);
});

/// Chủ thẻ lật thẻ của mình. Rules chỉ cho ghi revealedAt một lần, bằng giờ
/// server, nên lật hai lần thì lần sau bị từ chối và lỗi trả về nơi gọi.
Future<void> revealRankCard(String uid, String boardId) => FirebaseFirestore
    .instance
    .collection('users')
    .doc(uid)
    .collection('rankCards')
    .doc(boardId)
    .update({'revealedAt': FieldValue.serverTimestamp()});

/// Phong cách vẽ đang bật, giữ suốt phiên để mở lại bảng chọn là hiện ngay.
/// Bảng chọn tải lại ngầm mỗi lần mở, để backend tắt một phong cách thì app
/// thôi hiện sau lần tải đó.
final runCardStylesProvider = FutureProvider<ArtStyleList>(
  (ref) => ref.watch(runNowApiClientProvider).getRunCardStyles(),
);

/// Ảnh gốc người dùng tải lên cho tranh thẻ.
class RunCardPhotos {
  const RunCardPhotos();

  /// Ảnh từ thư viện, đã thu về cạnh dài 1600; null khi huỷ chọn.
  Future<Uint8List?> pick() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    return image?.readAsBytes();
  }

  /// Ghi đè ảnh gốc của thẻ [activityId], trả đường dẫn gửi kèm lệnh vẽ. Tên
  /// file cố định vì backend chỉ nhận đúng đường dẫn này.
  Future<String> upload(
    String activityId,
    Uint8List bytes,
    String contentType,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    final path = 'users/$uid/runCards/$activityId/src.jpg';
    await FirebaseStorage.instance
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: contentType));
    return path;
  }
}

final runCardPhotosProvider = Provider((ref) => const RunCardPhotos());

/// Lựa chọn bộ màu thẻ của máy này.
final runCardSkinControllerProvider =
    ChangeNotifierProvider<RunCardSkinController>(
      (ref) => RunCardSkinController(),
    );

/// Bộ màu thẻ đang dùng: lựa chọn riêng nếu có, không thì theo theme app.
final runCardSkinProvider = Provider<RunCardSkin>((ref) {
  final app = ref.watch(themeControllerProvider);
  return resolveRunCardSkin(
    appAppearance: app.appearance,
    appElement: app.element,
    choice: ref.watch(runCardSkinControllerProvider).choice,
  );
});
