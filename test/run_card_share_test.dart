import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/achievements/card_share.dart';

/// Khung RGBA một màu.
Uint8List _frame(int w, int h, int r, int g, int b) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  return out;
}

void main() {
  test('a frame a little off the video size is centered, padded or cut', () {
    // Khung 1×2: điểm trên đỏ, điểm dưới xanh lá.
    final tall = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]);
    // Đặt vào 1×4: thừa hai hàng, mỗi đầu một hàng màu nền xanh dương.
    expect(fitRgbaFrame(tall, 1, 2, 1, 4, const Color(0xFF0000FF)), [
      0, 0, 255, 255, //
      255, 0, 0, 255, //
      0, 255, 0, 255, //
      0, 0, 255, 255, //
    ]);
    // Khung 3×1 đỏ, xanh lá, xanh dương cắt về 1×1: giữ điểm giữa.
    final wide = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, //
    ]);
    expect(fitRgbaFrame(wide, 3, 1, 1, 1, const Color(0xFF000000)), [
      0,
      255,
      0,
      255,
    ]);
  });

  test('frames become a looping GIF with one image per frame', () {
    final gif = encodeCardGif(
      CardGifFrames(
        width: 8,
        height: 12,
        frameMs: 80,
        frames: [
          _frame(8, 12, 255, 0, 0),
          _frame(8, 12, 0, 255, 0),
          _frame(8, 12, 0, 0, 255),
        ],
      ),
    );
    expect(String.fromCharCodes(gif.take(6)), 'GIF89a');
    final decoded = img.GifDecoder().decode(gif)!;
    expect(decoded.numFrames, 3);
    expect(decoded.width, 8);
    expect(decoded.height, 12);
    // 80 ms là 8 phần trăm giây trong GIF.
    expect(decoded.frames[1].frameDuration, 80);
    final mid = decoded.frames[1].getPixel(4, 6);
    expect([mid.r, mid.g, mid.b], [0, 255, 0]);
  });

  test('share progress fills to 90% with the frames and waits there', () {
    expect(cardShareProgress(step: 0, steps: 0), 0);
    expect(cardShareProgress(step: 0, steps: 108), 0);
    expect(cardShareProgress(step: 54, steps: 108), closeTo(0.45, 1e-9));
    expect(cardShareProgress(step: 108, steps: 108), closeTo(0.9, 1e-9));
    expect(cardShareProgress(step: 109, steps: 108), closeTo(0.9, 1e-9));
  });

  testWidgets('the making bar fills only its share of the button', (
    tester,
  ) async {
    Future<double> filled(double progress) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: CardShareMakingBar(progress: progress, pulsing: false),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(ClipRect)).width;
    }

    expect(await filled(0), 0);
    expect(await filled(0.45), closeTo(180, 0.01));
    expect(await filled(0.9), closeTo(360, 0.01));
  });
}
