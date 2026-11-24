import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/avatar_crop.dart';

void main() {
  // Ảnh 2000×1000 trong khung 300: cạnh ngắn vừa khung, ảnh hiện rộng 600.
  const image = Size(2000, 1000);

  test('a centered 2x zoom keeps the middle half of the short side', () {
    final transform = Matrix4.identity()
      ..translateByDouble(-450, -150, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    expect(
      avatarCropRect(imageSize: image, viewport: 300, transform: transform),
      const Rect.fromLTWH(750, 250, 500, 500),
    );
  });

  testWidgets(
    'the crop is cut from the turned photo and saved as a square JPEG',
    (tester) async {
      // Nửa trái đỏ, nửa phải xanh. Xoay 90° theo chiều kim đồng hồ thì cạnh
      // trái lên trên: nửa trên đỏ, nửa dưới xanh.
      final source = img.Image(width: 200, height: 100);
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 99,
        y2: 99,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.fillRect(
        source,
        x1: 100,
        y1: 0,
        x2: 199,
        y2: 99,
        color: img.ColorRgb8(0, 0, 255),
      );
      final jpeg = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(img.encodePng(source));
        final photo = (await codec.getNextFrame()).image;
        return encodeAvatarJpeg(
          photo,
          quarterTurns: 1,
          crop: const Rect.fromLTWH(0, 100, 100, 100),
        );
      });
      final out = img.decodeJpg(jpeg!)!;
      expect((out.width, out.height), (avatarSize, avatarSize));
      final center = out.getPixel(avatarSize ~/ 2, avatarSize ~/ 2);
      expect(center.b, greaterThan(200));
      expect(center.r, lessThan(60));
    },
  );
}
