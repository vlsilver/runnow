import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_card_viewer.dart';

void main() {
  testWidgets('tắt đung đưa thì lá đứng yên, bật lại thì đưa tiếp từ đó', (
    tester,
  ) async {
    var pose = Offset.zero;
    Widget face(Offset p) {
      pose = p;
      return const ColoredBox(color: Color(0xFF000000));
    }

    Future<void> show({required bool sway}) => tester.pumpWidget(
      Center(
        child: TiltFlipCard(front: face, back: face, width: 100, sway: sway),
      ),
    );

    await show(sway: true);
    await tester.pump(const Duration(seconds: 1));
    final stopped = pose;

    await show(sway: false);
    await tester.pump(const Duration(seconds: 2));
    expect(pose, stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await show(sway: true);
    await tester.pump(const Duration(milliseconds: 16));
    // Một vòng đưa 6 giây, ngang lệch tối đa 0.45: một khung đi chưa tới 0.01.
    // Chạy luôn trong lúc tắt thì lá nhảy 2 giây, tức cả 1/3 vòng.
    expect((pose - stopped).distance, lessThan(0.02));
    expect(pose, isNot(stopped));
  });
}
