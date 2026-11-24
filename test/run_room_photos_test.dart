import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/run_room_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/storage_image.dart';

void main() {
  final start = DateTime(2026, 10, 31, 6);

  ActivityPhoto photo(String id, int minute) => ActivityPhoto(
    id: id,
    capturedAt: start.add(Duration(minutes: minute)),
    latitude: 21.05,
    longitude: 105.82,
    distanceMeters: minute * 160,
    storagePath: 'users/u/activities/a/photos/$id.jpg',
  );

  LiveTrackingSession session(String owner, List<ActivityPhoto> photos) =>
      LiveTrackingSession(
        id: 'live-$owner',
        ownerUid: owner,
        ownerName: owner,
        visibility: LiveTrackingVisibility.private,
        status: LiveTrackingStatus.running,
        startedAt: start,
        updatedAt: start.add(const Duration(minutes: 30)),
        distanceMeters: 5000,
        movingTimeSeconds: 1800,
        livePhotos: photos,
      );

  setUp(() {
    for (final id in ['p1', 'p2', 'p3']) {
      StorageImage.debugPutDownloadUrl(
        'users/u/activities/a/photos/$id.jpg',
        'https://storage.example.test/$id.jpg',
      );
    }
  });

  Future<void> pump(WidgetTester tester, List<LiveTrackingSession> sessions) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: Scaffold(body: RunRoomPhotoStrip(sessions: sessions)),
        ),
      );

  testWidgets('gom ảnh mọi người trong phòng, ảnh mới chụp đứng đầu', (
    tester,
  ) async {
    await pump(tester, [
      session('Gia Huy', [photo('p2', 15)]),
      session('Minh Anh', [photo('p1', 5), photo('p3', 25)]),
    ]);

    expect(find.text('Ảnh (3)'), findsOneWidget);
    // Phút 25 (4 km) của Minh Anh, rồi phút 15 (2,4 km) của Gia Huy, rồi
    // phút 5 (0,8 km) của Minh Anh.
    final x = [
      for (final caption in [
        'Minh Anh · 4.00 km',
        'Gia Huy · 2.40 km',
        'Minh Anh · 0.80 km',
      ])
        tester.getTopLeft(find.text(caption)).dx,
    ];
    expect(x[0], lessThan(x[1]));
    expect(x[1], lessThan(x[2]));
  });

  testWidgets('chưa ai chụp thì không có mục ảnh', (tester) async {
    await pump(tester, [session('Minh Anh', const [])]);

    expect(find.textContaining('Ảnh'), findsNothing);
  });
}
