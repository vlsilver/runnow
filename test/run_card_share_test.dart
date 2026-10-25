import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/achievements/run_card_share.dart';

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
}
