import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// Cạnh ảnh avatar tải lên. Avatar hiện to nhất vài trăm pixel vật lý.
const avatarSize = 512;

/// Vùng ảnh nằm trong khung cắt vuông cạnh [viewport], tính theo pixel của
/// ảnh đã xoay ([imageSize] là cỡ sau khi xoay).
///
/// Ở tỉ lệ 1, cạnh ngắn của ảnh vừa khít khung; [transform] là ma trận của
/// InteractiveViewer, đặt lên ảnh đã thu về cỡ đó.
Rect avatarCropRect({
  required Size imageSize,
  required double viewport,
  required Matrix4 transform,
}) {
  final fit = viewport / imageSize.shortestSide;
  final inverse = Matrix4.inverted(transform);
  final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero) / fit;
  final bottomRight =
      MatrixUtils.transformPoint(inverse, Offset(viewport, viewport)) / fit;
  return Rect.fromPoints(topLeft, bottomRight);
}

/// Cỡ của ảnh [size] sau khi xoay [quarterTurns] lần 90° theo chiều kim đồng hồ.
Size rotatedSize(Size size, int quarterTurns) =>
    quarterTurns.isOdd ? size.flipped : size;

/// Cắt [crop] (pixel của ảnh đã xoay [quarterTurns] lần) từ [photo], thu về
/// ảnh vuông [avatarSize] và nén JPEG.
///
/// Vẽ bằng chính ảnh đã giải mã cho khung cắt, nên ảnh tải lên đúng như user
/// thấy, kể cả HEIC hay ảnh có cờ xoay EXIF.
Future<Uint8List> encodeAvatarJpeg(
  ui.Image photo, {
  required int quarterTurns,
  required Rect crop,
}) async {
  final turned = rotatedSize(
    Size(photo.width.toDouble(), photo.height.toDouble()),
    quarterTurns,
  );
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..scale(avatarSize / crop.width)
    ..translate(-crop.left, -crop.top)
    ..translate(turned.width / 2, turned.height / 2)
    ..rotate(quarterTurns * math.pi / 2)
    ..drawImage(
      photo,
      Offset(-photo.width / 2, -photo.height / 2),
      Paint()..filterQuality = FilterQuality.high,
    );
  final picture = recorder.endRecording();
  final square = await picture.toImage(avatarSize, avatarSize);
  picture.dispose();
  try {
    final data = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
    return compute(_encodeJpeg, data!.buffer.asUint8List());
  } finally {
    square.dispose();
  }
}

Uint8List _encodeJpeg(Uint8List rgba) => img.encodeJpg(
  img.Image.fromBytes(
    width: avatarSize,
    height: avatarSize,
    bytes: rgba.buffer,
    numChannels: 4,
  ),
  quality: 85,
);
