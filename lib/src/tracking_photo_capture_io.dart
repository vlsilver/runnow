import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> captureTrackingPhoto({
  required String sessionId,
  required String photoId,
}) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.camera,
    imageQuality: 82,
    maxWidth: 1920,
  );
  if (image == null) return null;
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/tracking_photos/$sessionId');
  await directory.create(recursive: true);
  final path = '${directory.path}/$photoId.jpg';
  await image.saveTo(path);
  return path;
}

Future<void> deleteTrackingPhoto(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
