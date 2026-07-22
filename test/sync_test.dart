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

  test('reports that backend repair was queued', () async {
    final controller = SyncController(_StubRepository(queued: true));

    await controller.sync();

    expect(
      controller.message,
      'Backend đã nhận yêu cầu đồng bộ. Dữ liệu sẽ tự cập nhật.',
    );
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
  _StubRepository({this.imported = 0, this.error, this.queued = false});
  final int imported;
  final Object? error;
  final bool queued;
  int syncCalls = 0;

  @override
  Future<ActivityDetail> getDetail(String activityId) =>
      throw UnimplementedError();

  @override
  Future<List<ActivitySummary>> listOfficialActivities({
    required DateTime start,
    required DateTime endExclusive,
    int? limit,
  }) async => const [];

  @override
  Future<Map<String, ActivitySummary>> getActivitiesByIds(
    Set<String> ids,
  ) async => const {};

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() =>
      const Stream.empty();

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async => const JournalActivityPage(entries: [], hasMore: false);

  @override
  Future<ActivitySyncOutcome> sync({bool fullResync = false}) async {
    syncCalls += 1;
    if (error != null) throw error!;
    return ActivitySyncOutcome(changedCount: imported, queued: queued);
  }

  @override
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async => const TrackedActivitySaveResult(
    status: TrackedActivitySaveStatus.counted,
  );

  @override
  Stream<List<ActivitySummary>> watchActivities({int? limit}) =>
      const Stream.empty();
}
