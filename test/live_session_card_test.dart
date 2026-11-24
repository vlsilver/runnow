import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/screens/keo_hub_screen.dart';
import 'package:myrun/src/theme.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 3);
  final session = LiveTrackingSession(
    id: 's1',
    ownerUid: 'u1',
    ownerName: 'Linh',
    visibility: LiveTrackingVisibility.club,
    status: LiveTrackingStatus.running,
    startedAt: now.subtract(const Duration(minutes: 20)),
    updatedAt: now,
    distanceMeters: 3000,
    movingTimeSeconds: 1200,
    lastLocation: RoutePoint(
      latitude: 10.7769,
      longitude: 106.7009,
      timestamp: now,
    ),
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('ghi nguồn bản đồ không đè tấm tên (chữ x$scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SizedBox(
                width: 370,
                child: LiveSessionCard(session: session),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final credit = tester.getRect(find.textContaining('OpenStreetMap'));
      // Tấm tên là khung gần nhất bọc tên người chạy.
      final pill = tester.getRect(
        find
            .ancestor(
              of: find.text('Linh'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(credit.bottom, lessThanOrEqualTo(pill.top));
    });
  }
}
