import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class AvatarRepository {
  const AvatarRepository(this._auth, this._storage);

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  /// Mở thư viện ảnh, upload ảnh đã chọn và trả về URL tải về. Trả `null`
  /// nếu người dùng huỷ chọn ảnh.
  Future<String?> pickAndUpload() async {
    _debugLog('Mở image picker (gallery)...');
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 800,
    );
    if (image == null) {
      _debugLog('Người dùng huỷ chọn ảnh.');
      return null;
    }
    _debugLog(
      'Đã chọn ảnh: path=${image.path} name=${image.name} mimeType=${image.mimeType}',
    );
    final uid = _auth.currentUser?.uid;
    _debugLog('Current uid: $uid');
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    final bytes = await image.readAsBytes();
    _debugLog('Đã đọc ${bytes.length} bytes từ ảnh.');
    // Tên file có timestamp để mỗi lần đổi avatar sinh ra 1 URL mới, tránh
    // trình duyệt cache ảnh cũ khi ghi đè cùng 1 path.
    final path =
        'users/$uid/avatar/${DateTime.now().toUtc().millisecondsSinceEpoch}.jpg';
    _debugLog('Upload path: $path, bucket: ${_storage.bucket}');
    final ref = _storage.ref(path);
    _debugLog('Reference full path: ${ref.fullPath}, bucket: ${ref.bucket}');
    try {
      final snapshot = await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'uid': uid},
        ),
      );
      _debugLog(
        'putData xong: state=${snapshot.state}, '
        'bytesTransferred=${snapshot.bytesTransferred}/${snapshot.totalBytes}, '
        'metadata.fullPath=${snapshot.metadata?.fullPath}, '
        'metadata.bucket=${snapshot.metadata?.bucket}, '
        'metadata.size=${snapshot.metadata?.size}',
      );
    } catch (error, stack) {
      _debugLog('putData LỖI: $error\n$stack');
      rethrow;
    }
    return _getDownloadUrlWithRetry(ref);
  }

  /// Trên web, `getDownloadURL()` gọi ngay sau khi `putData()` xong đôi khi
  /// báo `object-not-found` do server lan truyền trạng thái object hơi trễ
  /// so với lúc Future upload resolve (limitation đã biết của
  /// firebase_storage trên Flutter Web). Thử lại vài lần có backoff trước
  /// khi coi là lỗi thật.
  Future<String> _getDownloadUrlWithRetry(Reference ref) async {
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final url = await ref.getDownloadURL();
        _debugLog('getDownloadURL thành công ở lần thử $attempt: $url');
        return url;
      } on FirebaseException catch (error) {
        _debugLog(
          'getDownloadURL lỗi ở lần thử $attempt: code=${error.code} '
          'message=${error.message} plugin=${error.plugin}',
        );
        if (error.code != 'object-not-found' || attempt == maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw StateError('Không thể lấy URL ảnh vừa tải lên.');
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[AvatarRepository] $message');
  }
}
