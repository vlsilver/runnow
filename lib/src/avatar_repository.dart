import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class AvatarRepository {
  const AvatarRepository(this._auth, this._storage);

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  /// Mở thư viện ảnh, upload ảnh đã chọn và trả về URL tải về. Trả `null`
  /// nếu người dùng huỷ chọn ảnh.
  Future<String?> pickAndUpload() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 800,
    );
    if (image == null) return null;
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    final bytes = await image.readAsBytes();
    // Tên file có timestamp để mỗi lần đổi avatar sinh ra 1 URL mới, tránh
    // trình duyệt cache ảnh cũ khi ghi đè cùng 1 path.
    final path =
        'users/$uid/avatar/${DateTime.now().toUtc().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg', customMetadata: {'uid': uid}),
    );
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
        return await ref.getDownloadURL();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found' || attempt == maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw StateError('Không thể lấy URL ảnh vừa tải lên.');
  }
}
