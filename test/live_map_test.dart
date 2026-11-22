import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/live_map.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/route_map.dart' show LiveRunnerMarker;

void main() {
  final now = DateTime.now();

  LiveTrackingSession session(String id, String name, double lat, double lng) =>
      LiveTrackingSession(
        id: id,
        ownerUid: 'u-$id',
        ownerName: name,
        visibility: LiveTrackingVisibility.club,
        status: LiveTrackingStatus.running,
        startedAt: now.subtract(const Duration(minutes: 20)),
        updatedAt: now,
        distanceMeters: 3470,
        movingTimeSeconds: 1200,
        lastLocation: RoutePoint(latitude: lat, longitude: lng, timestamp: now),
      );

  Future<List<String>> pump(
    WidgetTester tester,
    List<LiveTrackingSession> sessions,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowTheme(RunNowElement.water),
        home: Scaffold(
          body: SizedBox(
            height: 320,
            child: LiveRunnersMap(
              sessions: sessions,
              onOpen: (s) => opened.add(s.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('mỗi người có vị trí một avatar; chạm thì hiện thẻ và mở live', (
    tester,
  ) async {
    final opened = await pump(tester, [
      session('hn', 'Minh Võ Đức', 21.03, 105.85),
      session('sg', 'Nguyễn Duy Hùng', 10.78, 106.70),
      // Chưa có GPS thì không lên bản đồ.
      LiveTrackingSession(
        id: 'nogps',
        ownerUid: 'u-x',
        ownerName: 'Chưa có GPS',
        visibility: LiveTrackingVisibility.club,
        status: LiveTrackingStatus.running,
        startedAt: now,
        updatedAt: now,
        distanceMeters: 0,
        movingTimeSeconds: 0,
      ),
    ]);
    expect(find.byType(LiveRunnerMarker), findsNWidgets(2));
    expect(find.text('Tất cả · 2'), findsOneWidget);
    expect(find.text('Xem live'), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is LiveRunnerMarker && w.session.id == 'sg',
      ),
    );
    await tester.pump();
    expect(find.text('3.47 km'), findsOneWidget);

    await tester.tap(find.text('Xem live'));
    expect(opened, ['sg']);

    await tester.tap(find.text('Tất cả · 2'));
    await tester.pump();
    expect(find.text('Xem live'), findsNothing);
  });

  test(
    'người có avatar chồng lên nhau thì gộp một cụm, không chồng thì tách',
    () {
      // Toạ độ dùng thẳng làm pixel. Avatar 46px, số cụm lòi ra 8px: hai người
      // lệch nhau dưới 56px theo cả hai chiều thì avatar chạm nhau.
      final groups = groupNearby([
        session('a', 'a', 0, 0),
        session('b', 'b', 50, 0), // lệch ngang 50: chạm a
        session('c', 'c', 40, -40), // chéo ~57px nhưng hai ô vẫn chồng
        session('d', 'd', 60, 0), // lệch ngang 60: tách, dù chạm b
        session('e', 'e', 0, 60), // lệch dọc 60: tách
        session('f', 'f', 200, 200),
      ], (p) => Offset(p.latitude, p.longitude));
      expect(
        [for (final g in groups) g.map((s) => s.id).join()],
        ['abc', 'd', 'e', 'f'],
      );
    },
  );

  testWidgets('cả nước: cụm HCM hiện số người, chạm thì tách ra từng người', (
    tester,
  ) async {
    await pump(tester, [
      session('hn', 'Minh Võ Đức', 21.03, 105.85),
      session('sg1', 'Nguyễn Duy Hùng', 10.78, 106.70),
      session('sg2', 'Lan Phạm', 10.79, 106.69),
      session('sg3', 'Hà My', 10.80, 106.72),
    ]);
    // Hà Nội đứng riêng, ba người HCM chung một avatar kèm số.
    expect(find.byType(LiveRunnerMarker), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pump();
    expect(find.byType(LiveRunnerMarker), findsNWidgets(3));
    expect(find.text('Xem live'), findsNothing);
  });

  testWidgets(
    'chạy sát nhau, zoom hết cỡ vẫn chung cụm: chạm thì chọn từ danh sách',
    (tester) async {
      final opened = await pump(tester, [
        // Cách nhau khoảng 10–20 m, như cả nhóm chạy cùng.
        session('a', 'An', 10.7800, 106.7000),
        session('b', 'Bình', 10.7801, 106.7001),
        session('c', 'Chi', 10.7802, 106.7000),
      ]);
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final name in ['An', 'Bình', 'Chi']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.text('Bình'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Xem live'), findsOneWidget);
      await tester.tap(find.text('Xem live'));
      expect(opened, ['b']);
    },
  );

  testWidgets('không ai chạy thì vẫn có bản đồ và báo chưa có ai', (
    tester,
  ) async {
    await pump(tester, const []);
    expect(find.byType(LiveRunnerMarker), findsNothing);
    expect(find.text('Chưa ai đang chạy live'), findsOneWidget);
  });
}
