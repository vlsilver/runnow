import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/club_run_row.dart';
import 'package:myrun/src/widgets/route_sketch_art.dart';

ClubRunItem _item({
  required ActivityKind kind,
  required ActivitySource source,
  List<int>? sketch,
  double? elevation,
}) => ClubRunItem(
  ownerUid: 'u1',
  activity: ActivitySummary(
    id: 'a1',
    name: 'Hồ Tây sáng',
    kind: kind,
    startedAt: DateTime(2026, 10, 30, 8, 2),
    distanceMeters: 8200,
    movingTimeSeconds: 2723,
    elapsedTimeSeconds: 2800,
    source: source,
    elevationGainMeters: elevation,
    routeSketch: sketch,
  ),
);

Future<void> _pump(WidgetTester tester, ClubRunItem item) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        membersProvider.overrideWith((ref) => Stream.value(const [])),
        heartsProvider.overrideWith(
          (ref, target) => Stream.value(Hearts.empty),
        ),
      ],
      child: MaterialApp(
        theme: buildRunNowTheme(
          RunNowElement.fire,
          appearance: RunNowAppearance.light,
        ),
        home: Scaffold(body: ClubRunPost(item: item)),
      ),
    ),
  );
}

void main() {
  testWidgets('buổi có tuyến: vẽ nền tuyến, chip 3I RUN, có độ cao', (
    tester,
  ) async {
    await _pump(
      tester,
      _item(
        kind: ActivityKind.run,
        source: ActivitySource.runnow,
        sketch: const [0, 500, 1000, 500, 1000, 0],
        elevation: 18,
      ),
    );
    expect(find.byType(RouteSketchArt), findsOneWidget);
    expect(find.text('3I RUN'), findsOneWidget);
    expect(find.byIcon(Icons.directions_run_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.textContaining('18 m'), findsOneWidget);
  });

  testWidgets(
    'buổi đi bộ từ Apple Health, không tuyến: không nền, có chip môn',
    (tester) async {
      await _pump(
        tester,
        _item(kind: ActivityKind.walk, source: ActivitySource.appleHealth),
      );
      expect(find.byType(RouteSketchArt), findsNothing);
      expect(find.text('APPLE HEALTH'), findsOneWidget);
      expect(find.text('ĐI BỘ'), findsOneWidget);
      expect(find.byIcon(Icons.directions_walk_rounded), findsOneWidget);
      expect(find.byIcon(Icons.directions_run_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    },
  );
}
