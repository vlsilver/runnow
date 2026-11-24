import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Ảnh quà (BXH, kèo) chọn từ thư viện, đã thu nhỏ và đổi sang JPEG vì Storage
/// rules chỉ nhận JPEG. Null khi người dùng bỏ chọn.
Future<Uint8List?> pickRewardPhoto() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  if (picked == null) return null;
  return rewardPhotoJpeg(await picked.readAsBytes());
}

/// Ảnh PNG hay ảnh lạ thì đổi sang JPEG; JPEG giữ nguyên.
Uint8List rewardPhotoJpeg(Uint8List bytes) {
  if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Ảnh không đọc được.');
  return img.encodeJpg(decoded, quality: 85);
}

/// Tên file ngẫu nhiên khớp rule `[A-Za-z0-9_-]{1,64}[.]jpg`.
String rewardPhotoName() {
  final random = Random.secure();
  final hex = [
    for (var i = 0; i < 12; i++) random.nextInt(16).toRadixString(16),
  ].join();
  return '$hex.jpg';
}
