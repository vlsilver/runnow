import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myrun/src/screens/avatar_crop_screen.dart';

/// Ảnh 300×100 chia ba dải dọc: đỏ, xanh lá, xanh dương.
Uint8List _stripes() {
  final source = img.Image(width: 300, height: 100);
  final colors = [
    img.ColorRgb8(255, 0, 0),
    img.ColorRgb8(0, 255, 0),
    img.ColorRgb8(0, 0, 255),
  ];
  for (var i = 0; i < 3; i++) {
    img.fillRect(
      source,
      x1: i * 100,
      y1: 0,
      x2: i * 100 + 99,
      y2: 99,
      color: colors[i],
    );
  }
  return img.encodePng(source);
}

String _name(num r, num g, num b) {
  if (r > 200 && g < 60 && b < 60) return 'đỏ';
  if (g > 200 && r < 60 && b < 60) return 'xanh lá';
  if (b > 200 && r < 60 && g < 60) return 'xanh dương';
  return 'khác ($r, $g, $b)';
}

/// Màu ở giữa avatar đã cắt.
String _centerColor(Uint8List jpeg) {
  final out = img.decodeJpg(jpeg)!;
  final p = out.getPixel(out.width ~/ 2, out.height ~/ 2);
  return _name(p.r, p.g, p.b);
}

/// Màu ở tâm khung cắt mà user đang thấy.
Future<String> _previewCenterColor(WidgetTester tester) async {
  final viewer = tester.renderObject<RenderBox>(find.byType(InteractiveViewer));
  RenderObject node = viewer;
  while (node is! RenderRepaintBoundary) {
    node = node.parent!;
  }
  final boundary = node;
  final at =
      viewer.localToGlobal(viewer.size.center(Offset.zero)) -
      boundary.localToGlobal(Offset.zero);
  final rgba = (await tester.runAsync(() async {
    final shot = await boundary.toImage();
    final data = await shot.toByteData(format: ui.ImageByteFormat.rawRgba);
    final i = (at.dy.round() * shot.width + at.dx.round()) * 4;
    shot.dispose();
    return data!.buffer.asUint8List(i, 3);
  }))!;
  return _name(rgba[0], rgba[1], rgba[2]);
}

void main() {
  /// Mở màn cắt, chạy [act], bấm Xong và trả JPEG nhận về.
  Future<Uint8List?> crop(
    WidgetTester tester,
    Future<void> Function() act,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final photo = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(_stripes());
      return (await codec.getNextFrame()).image;
    }))!;
    Uint8List? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => AvatarCropScreen(photo: photo),
                ),
              );
              done = true;
            },
            child: const Text('Mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await act();
    await tester.tap(find.text('Xong'));
    // Vẽ và nén ảnh chạy bất đồng bộ thật, ngoài đồng hồ giả của test.
    for (var i = 0; i < 50 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Xong right away keeps the middle of the photo', (tester) async {
    final jpeg = await crop(tester, () async {});
    expect(_centerColor(jpeg!), 'xanh lá');
  });

  testWidgets('dragging the photo right picks its left end', (tester) async {
    final jpeg = await crop(tester, () async {
      await tester.drag(find.byType(InteractiveViewer), const Offset(1000, 0));
      await tester.pumpAndSettle();
    });
    expect(_centerColor(jpeg!), 'đỏ');
  });

  testWidgets('a turned photo is cut as shown', (tester) async {
    // Xoay theo chiều kim đồng hồ đưa dải xanh dương bên phải xuống dưới; kéo
    // ảnh lên hết cỡ là lấy đầu dưới. Chưa xoay thì ảnh không kéo dọc được.
    final jpeg = await crop(tester, () async {
      await tester.tap(find.byTooltip('Xoay'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(await _previewCenterColor(tester), 'xanh dương');
    });
    expect(_centerColor(jpeg!), 'xanh dương');
  });
}
