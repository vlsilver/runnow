import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

void main() {
  test('demo feed publishes idempotently and removes an activity', () async {
    final repository = DemoFeedRepository();
    final activity = ActivitySummary(
      id: '42',
      name: 'Chạy buổi sáng',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 5, 31),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
    );
    final emissions = <List<FeedPost>>[];
    final subscription = repository.watchPosts().listen(emissions.add);
    await Future<void>.delayed(Duration.zero);

    await repository.publish(activity);
    await repository.publish(activity);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, hasLength(1));
    expect(emissions.last.single.activity.id, '42');

    await repository.remove(activity);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, isEmpty);
    await subscription.cancel();
  });
}
