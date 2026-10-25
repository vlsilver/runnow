import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/share.dart';

void main() {
  testWidgets('captures a widget as PNG bytes', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const ColoredBox(color: Colors.teal),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final png = (await tester.runAsync(() => captureRecapPng(boundary)))!;
    expect(png.take(4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('a card that is not laid out yet fails instead of sharing nothing', () {
    expect(captureRecapPng(null), throwsStateError);
  });
}
