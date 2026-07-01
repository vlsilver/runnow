import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/sync.dart';

void main() {
  test('reports imported activity count after a successful sync', () async {
    final controller = SyncController(_StubRepository(imported: 3));
    await controller.sync();
    expect(controller.lastSyncSucceeded, isTrue);
    expect(
      controller.message,
      'Đồng bộ Strava hoàn tất: cập nhật 3 hoạt động.',
    );
  });

  test('reports repository failures', () async {
    final controller = SyncController(
      _StubRepository(error: StateError('offline')),
    );
    await controller.sync();
    expect(controller.lastSyncSucceeded, isFalse);
    expect(controller.message, contains('offline'));
  });

  test('starts sync in the background without awaiting completion', () async {
    final repository = _StubRepository(imported: 3);
    final controller = SyncController(repository);

    controller.startBackgroundSync();

    expect(controller.syncing, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(controller.lastSyncSucceeded, isTrue);
  });

  test('runs automatic background sync once per controller', () async {
    final repository = _StubRepository(imported: 0);
    final controller = SyncController(repository);

    controller.startBackgroundSync();
    await Future<void>.delayed(Duration.zero);
    controller.startBackgroundSync();
    await Future<void>.delayed(Duration.zero);

    expect(repository.syncCalls, 1);

    controller.startBackgroundSync(force: true);
    await Future<void>.delayed(Duration.zero);

    expect(repository.syncCalls, 2);
  });
}

class _StubRepository implements ActivityRepository {
  _StubRepository({this.imported = 0, this.error});
  final int imported;
  final Object? error;
  int syncCalls = 0;

  @override
  Future<ActivityDetail> getDetail(String activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivitySummary>> listStravaActivities({
    required DateTime start,
    required DateTime endExclusive,
  }) async => const [];

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() =>
      const Stream.empty();

  @override
  Future<int> sync() async {
    syncCalls += 1;
    if (error != null) throw error!;
    return imported;
  }

  @override
  Future<void> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {}

  @override
  Stream<List<ActivitySummary>> watchActivities() => const Stream.empty();
}
