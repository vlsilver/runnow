import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/screens/feed_screen.dart';

void main() {
  testWidgets('renders a published activity with product branding', (
    tester,
  ) async {
    final repository = DemoFeedRepository();
    await repository.publish(
      ActivitySummary(
        id: '42',
        name: 'Chạy buổi sáng',
        kind: ActivityKind.run,
        startedAt: DateTime(2026, 5, 31),
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
        elapsedTimeSeconds: 1600,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: FeedScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Demo runner'), findsOneWidget);
    expect(find.text('Chạy buổi sáng'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text("P'RC"), findsOneWidget);
  });
}
