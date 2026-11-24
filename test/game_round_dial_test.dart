import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_round_dial.dart';

void main() {
  // Lịch gốc: Đêm 22h–0h, Rạng sáng 0h–10h, Ngày 10h–20h, Biểu quyết 20h–22h.
  const base = [120, 600, 600, 120];

  test('moving a middle mark trades minutes between the two phases', () {
    // Đêm kết thúc lúc 1h (phút 180 tính từ 22h): Đêm 3 tiếng, Rạng sáng 9 tiếng.
    expect(gameMoveMark(base, 1, 180, lockEnd: true, maxTotal: 1440), [
      180,
      540,
      600,
      120,
    ]);
    // Kéo quá thì dừng ở chỗ Rạng sáng còn 1 tiếng: mốc 2 ở phút 720.
    expect(gameMoveMark(base, 1, 700, lockEnd: true, maxTotal: 1440), [
      660,
      60,
      600,
      120,
    ]);
    // Không đổi gì thì trả null.
    expect(gameMoveMark(base, 1, 120, lockEnd: true, maxTotal: 1440), isNull);
  });

  test('the end mark changes the round length by whole hours', () {
    // Vòng 8 tiếng. Kéo tới phút 510 (8h30) thì làm tròn lên 9 tiếng, phần
    // thêm vào Biểu quyết.
    const short = [60, 120, 240, 60];
    expect(gameMoveMark(short, 4, 510, lockEnd: false, maxTotal: 1440), [
      60,
      120,
      240,
      120,
    ]);
    // Không quá maxTotal (2 vòng một ngày thì vòng tối đa 12 tiếng).
    expect(gameMoveMark(short, 4, 900, lockEnd: false, maxTotal: 720), [
      60,
      120,
      240,
      300,
    ]);
    // Ván km khoá mốc cuối.
    expect(gameMoveMark(short, 4, 540, lockEnd: true, maxTotal: 1440), isNull);
  });

  test('fitting phases to a new round length keeps their proportions', () {
    // 3 vòng một ngày (8 tiếng): lịch gốc thu theo tỉ lệ 1:5:5:1 rồi làm tròn
    // về bước 30 phút, pha nào cũng còn ít nhất 1 tiếng.
    expect(gameFitPhases(base, 480), [60, 180, 180, 60]);
    // 6 vòng một ngày (4 tiếng): pha nào cũng 1 tiếng.
    expect(gameFitPhases(base, 240), [60, 60, 60, 60]);
    // 2 vòng một ngày (12 tiếng).
    expect(gameFitPhases(base, 720), [60, 300, 300, 60]);
    // Đã đúng tổng thì giữ nguyên.
    expect(gameFitPhases(base, 1440), base);
  });

  test('a base-schedule mark lands at the same share of its phase', () {
    // Lịch gốc theo giờ: Đêm 0–2, Rạng sáng 2–12, Ngày 12–22, Biểu quyết 22–24.
    const baseHours = [(0.0, 2.0), (2.0, 12.0), (12.0, 22.0), (22.0, 24.0)];
    const fitted = [60, 180, 180, 60];
    // Nhắc đề cử ở giờ 20 gốc: 80% pha Ngày. Ngày mới từ phút 240, dài 180.
    expect(gameMarkAt(baseHours, fitted, 20), 240 + 144);
    // Nhắc biểu quyết ở giờ 23 gốc: nửa pha Biểu quyết, từ phút 420 dài 60.
    expect(gameMarkAt(baseHours, fitted, 23), 450);
  });

  test('a km round keeps its length when the start moves', () {
    // Ván km: cả vòng dời theo giờ mở, không pha nào đổi độ dài.
    final later = gameMoveStart(
      22 * 60,
      base,
      1,
      lockEnd: true,
      maxTotal: 1440,
    );
    expect(later?.start, 23 * 60);
    expect(later?.phases, base);
    expect(
      gameMoveStart(23 * 60, base, 1, lockEnd: true, maxTotal: 1440)?.start,
      0,
    );
    expect(
      gameMoveStart(0, base, -1, lockEnd: true, maxTotal: 1440)?.start,
      23 * 60,
    );
  });

  test('the +/- of a phase row moves its end, or its start when locked', () {
    // Pha giữa: + nửa tiếng lấy từ pha sau.
    expect(gameStepPhase(base, 1, 1, lockEnd: true, maxTotal: 1440), [
      120,
      630,
      570,
      120,
    ]);
    // Pha cuối ván km (vòng khoá 24h): + lấy từ pha trước.
    expect(gameStepPhase(base, 3, 1, lockEnd: true, maxTotal: 1440), [
      120,
      600,
      570,
      150,
    ]);
    // Pha cuối ván cổ điển: − bớt cả vòng đi 1 tiếng.
    expect(gameStepPhase(base, 3, -1, lockEnd: false, maxTotal: 1440), [
      120,
      600,
      600,
      60,
    ]);
    // Pha đã 1 tiếng thì không bớt được nữa.
    expect(
      gameStepPhase(
        const [60, 600, 600, 180],
        0,
        -1,
        lockEnd: true,
        maxTotal: 1440,
      ),
      isNull,
    );
  });

  group('dragging the start handle on the dial', () {
    const plan = GameRoundPlan(
      phases: [
        GameRoundPhase(
          key: 'night',
          label: 'Đêm',
          description: '',
          from: 0,
          to: 0,
        ),
        GameRoundPhase(
          key: 'dawn',
          label: 'Rạng sáng',
          description: '',
          from: 0,
          to: 0,
        ),
        GameRoundPhase(
          key: 'day',
          label: 'Ngày',
          description: '',
          from: 0,
          to: 0,
        ),
        GameRoundPhase(
          key: 'trial',
          label: 'Biểu quyết',
          description: '',
          from: 0,
          to: 0,
        ),
      ],
    );

    // Bán kính vòng trong khung 280: 140 - 18/2 - 22 = 109.
    const at22h = Offset(-54.5, -94.4); // 240 độ
    const at6h = Offset(109, 0);

    Future<({int start, List<int> phases})> drag(
      WidgetTester tester, {
      required List<int> phases,
      required bool lockEnd,
      required bool canMoveStart,
      Offset from = at22h,
      Offset to = at6h,
    }) async {
      var now = (start: 22 * 60, phases: phases);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => GameRoundDial(
                  plan: plan,
                  phases: now.phases,
                  startMinute: now.start,
                  lockEnd: lockEnd,
                  maxTotal: 1440,
                  onChanged: (_) {},
                  onStart: canMoveStart
                      ? (start, phases) =>
                            setState(() => now = (start: start, phases: phases))
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
      final centre = tester.getCenter(
        find
            .descendant(
              of: find.byType(GameRoundDial),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      final finger = await tester.startGesture(centre + from);
      await tester.pump();
      await finger.moveTo(centre + to);
      await tester.pump();
      await finger.up();
      await tester.pump();
      return now;
    }

    testWidgets('a km round turns as a whole, keeping every phase', (
      tester,
    ) async {
      final out = await drag(
        tester,
        phases: base,
        lockEnd: true,
        canMoveStart: true,
      );
      expect(out.start, 6 * 60);
      expect(out.phases, base);
    });

    testWidgets('the end handle of a km round turns the whole round too', (
      tester,
    ) async {
      // Vòng 12 tiếng mở 22h chốt 10h. Kéo mốc chốt từ 10h tới 12h: dời 2 tiếng.
      final out = await drag(
        tester,
        phases: const [60, 300, 300, 60],
        lockEnd: true,
        canMoveStart: true,
        from: const Offset(54.5, 94.4), // 10h, 60 độ
        to: const Offset(0, 109), // 12h, 90 độ
      );
      expect(out.start, 0);
      expect(out.phases, const [60, 300, 300, 60]);
    });

    testWidgets('open and closed locks follow what can move', (tester) async {
      await drag(tester, phases: base, lockEnd: true, canMoveStart: true);
      expect(find.byIcon(Icons.lock_open_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      await drag(tester, phases: base, lockEnd: true, canMoveStart: false);
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    });

    testWidgets('a free round stops once Night is down to one hour', (
      tester,
    ) async {
      final out = await drag(
        tester,
        phases: const [120, 600, 600, 60],
        lockEnd: false,
        canMoveStart: true,
      );
      expect(out.start, 23 * 60);
      expect(out.phases, const [60, 600, 600, 60]);
    });

    testWidgets('the handle stays put when the start cannot move', (
      tester,
    ) async {
      final out = await drag(
        tester,
        phases: base,
        lockEnd: true,
        canMoveStart: false,
      );
      expect(out.start, 22 * 60);
    });
  });
}
