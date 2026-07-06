import 'package:myrun/src/tracking_photo_capture_stub.dart'
    if (dart.library.io) 'package:myrun/src/tracking_photo_capture_io.dart';

class TrackingPhotoCapture {
  const TrackingPhotoCapture();

  Future<String?> capture({
    required String sessionId,
    required String photoId,
  }) {
    return captureTrackingPhoto(sessionId: sessionId, photoId: photoId);
  }

  Future<void> deleteLocal(String path) => deleteTrackingPhoto(path);
}
