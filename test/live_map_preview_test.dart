import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/live_map_preview.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 3);

  LiveTrackingSession session(String id, double lat, double lng) =>
      LiveTrackingSession(
        id: id,
        ownerUid: 'u-$id',
        ownerName: id,
        visibility: LiveTrackingVisibility.club,
        status: LiveTrackingStatus.running,
        startedAt: now.subtract(const Duration(minutes: 20)),
        updatedAt: now,
        distanceMeters: 3000,
        movingTimeSeconds: 1200,
        lastLocation: RoutePoint(latitude: lat, longitude: lng, timestamp: now),
      );

  Future<void> pump(WidgetTester tester, LiveTrackingSession s) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowTheme(RunNowElement.water),
        home: Scaffold(
          body: SizedBox(
            height: 236,
            child: LiveMapPreview(session: s, padding: EdgeInsets.zero),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  LatLng center(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(MarkerLayer))).center;

  testWidgets('ô đổi sang phiên khác thì bản đồ dời tới người đó', (
    tester,
  ) async {
    // Hai phiên cùng updatedAt: ô dùng lại state khi danh sách đổi thứ tự.
    await pump(tester, session('hanoi', 21.0285, 105.8542));
    expect(center(tester).latitude, closeTo(21.0285, 0.001));

    await pump(tester, session('cantho', 10.0452, 105.7469));
    expect(center(tester).latitude, closeTo(10.0452, 0.001));
    expect(center(tester).longitude, closeTo(105.7469, 0.001));
  });
}
