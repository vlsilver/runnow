import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/tracking_session.dart';

class TrackingPhotoRepository {
  const TrackingPhotoRepository(this._auth, this._storage);

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<ActivityPhoto> upload({
    required String activityId,
    required TrackingPhotoDraft draft,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    final storagePath =
        'users/$uid/activities/$activityId/photos/${draft.id}.jpg';
    final bytes = await XFile(draft.localPath).readAsBytes();
    await _storage
        .ref(storagePath)
        .putData(
          bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {'uid': uid, 'activityId': activityId},
          ),
        );
    final photo = ActivityPhoto(
      id: draft.id,
      capturedAt: draft.capturedAt,
      latitude: draft.latitude,
      longitude: draft.longitude,
      distanceMeters: draft.distanceMeters,
      storagePath: storagePath,
    );
    return photo;
  }
}
