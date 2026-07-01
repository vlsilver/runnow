import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/sync.dart';

void main() {
  group('contract periods', () {
    test('weekly period is Monday-aligned half-open in device local time', () {
      final now = DateTime(2026, 6, 24, 12); // local Wednesday
      final period = contractPeriod(RunContractPeriodType.weekly, now);
      final start = period.startAt.toLocal();

      expect(start.weekday, DateTime.monday);
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(
        period.endAtExclusive,
        period.startAt.add(const Duration(days: 7)),
      );
      expect(
        period.finalizeAt,
        period.endAtExclusive.add(const Duration(hours: 6)),
      );
      // now nằm trong kỳ (nửa mở).
      expect(period.startAt.isAfter(now.toUtc()), isFalse);
      expect(period.endAtExclusive.isAfter(now.toUtc()), isTrue);
    });

    test('today period is the local calendar day and half-open', () {
      final now = DateTime(2026, 6, 24, 9, 30); // local
      final period = contractPeriod(RunContractPeriodType.today, now);

      expect(period.startAt.toLocal(), DateTime(2026, 6, 24));
      expect(
        period.endAtExclusive,
        period.startAt.add(const Duration(days: 1)),
      );
      expect(
        period.finalizeAt,
        period.endAtExclusive.add(const Duration(hours: 6)),
      );
    });

    test('late-today warning starts inside final two hours', () {
      final endOfToday = DateTime(2026, 6, 25); // local midnight = hết 24/6
      expect(
        isLateToday(endOfToday.subtract(const Duration(hours: 2, minutes: 1))),
        isFalse,
      );
      expect(
        isLateToday(endOfToday.subtract(const Duration(minutes: 59))),
        isTrue,
      );
    });
  });

  group('eligibility and progress', () {
    final contract = _contract(
      startAt: DateTime.utc(2026, 6, 21, 17),
      endAtExclusive: DateTime.utc(2026, 6, 28, 17),
      finalizeAt: DateTime.utc(2026, 6, 28, 23),
    );

    test('counts only non-manual Strava Run inside half-open window', () {
      final activities = [
        _activity('run', DateTime.utc(2026, 6, 22), 5000),
        _activity('manual', DateTime.utc(2026, 6, 23), 3000, manual: true),
        _activity(
          'trail',
          DateTime.utc(2026, 6, 24),
          4000,
          kind: ActivityKind.trailRun,
        ),
        _activity('boundary', DateTime.utc(2026, 6, 28, 17), 2000),
        _activity('legacy', DateTime.utc(2026, 6, 25), 1000),
      ];

      final progress = calculateRunContractProgress(contract, activities);

      expect(progress.value, 6);
      expect(progress.eligibleActivities.map((item) => item.id), [
        'run',
        'legacy',
      ]);
    });

    test('active days group by device-local calendar date', () {
      final activeDaysContract = _contract(
        metric: RunContractMetric.activeDays,
        targetValue: 2,
        startAt: contract.startAt,
        endAtExclusive: contract.endAtExclusive,
        finalizeAt: contract.finalizeAt,
      );
      final progress = calculateRunContractProgress(activeDaysContract, [
        _activity('a', DateTime(2026, 6, 22, 8), 1000),
        _activity('b', DateTime(2026, 6, 22, 20), 1000),
        _activity('c', DateTime(2026, 6, 23, 7), 1000),
      ]);

      expect(progress.value, 2);
    });

    test('longest run takes the single farthest eligible run', () {
      final longestContract = _contract(
        metric: RunContractMetric.longestRun,
        targetValue: 8,
        startAt: contract.startAt,
        endAtExclusive: contract.endAtExclusive,
        finalizeAt: contract.finalizeAt,
      );
      final progress = calculateRunContractProgress(longestContract, [
        _activity('short', DateTime(2026, 6, 22, 8), 4000),
        _activity('long', DateTime(2026, 6, 23, 8), 9000),
        _activity('mid', DateTime(2026, 6, 24, 8), 6000),
      ]);

      expect(progress.value, 9);
      // Chỉ buổi dài nhất bị ghi nhận để không khóa session khác.
      expect(progress.eligibleActivities.map((item) => item.id), ['long']);
      expect(contractTargetMet(longestContract, progress.value), isTrue);
    });
  });

  group('lifecycle', () {
    final contract = _contract(
      startAt: DateTime.utc(2026, 6, 21, 17),
      endAtExclusive: DateTime.utc(2026, 6, 28, 17),
      finalizeAt: DateTime.utc(2026, 6, 28, 23),
    );

    test('separates scheduled, running, sync grace and finalize', () {
      expect(
        contractLifecycle(contract, DateTime.utc(2026, 6, 21, 16, 59)),
        RunContractLifecycle.scheduled,
      );
      expect(
        contractLifecycle(contract, contract.startAt),
        RunContractLifecycle.running,
      );
      expect(
        contractLifecycle(contract, contract.endAtExclusive),
        RunContractLifecycle.syncGrace,
      );
      expect(
        contractLifecycle(contract, contract.finalizeAt),
        RunContractLifecycle.awaitingFinalize,
      );
    });
  });

  group('group participation', () {
    test('overall progress averages capped participant completion', () {
      final now = DateTime.utc(2026, 6, 24);
      final contract = RunContract(
        id: 'group',
        creatorUid: 'owner',
        title: 'Kèo 10km',
        template: RunContractTemplate.weekly10k,
        metric: RunContractMetric.distance,
        targetValue: 10,
        periodType: RunContractPeriodType.weekly,
        startAt: now,
        endAtExclusive: now.add(const Duration(days: 7)),
        finalizeAt: now.add(const Duration(days: 7, hours: 6)),
        status: RunContractStatus.active,
        visibility: RunContractVisibility.club,
        progressValue: 15,
        participants: {
          'owner': RunContractParticipant(
            uid: 'owner',
            progressValue: 15,
            joinedAt: now,
            updatedAt: now,
          ),
          'member': RunContractParticipant(
            uid: 'member',
            progressValue: 5,
            joinedAt: now,
            updatedAt: now,
          ),
        },
        createdAt: now,
        updatedAt: now,
      );

      expect(contract.participantCount, 2);
      expect(contract.overallProgressPercent, 75);
      expect(contract.completedBy('owner'), isTrue);
      expect(contract.completedBy('member'), isFalse);
    });

    test('legacy contract treats its creator as the first participant', () {
      final contract = RunContract.fromMap({
        'id': 'legacy',
        'creatorUid': 'owner',
        'metric': 'distance',
        'targetValue': 10,
        'progressValue': 4,
        'createdAt': DateTime.utc(2026, 6, 1),
        'updatedAt': DateTime.utc(2026, 6, 2),
      });

      expect(contract.participantCount, 1);
      expect(contract.participantFor('owner')?.progressValue, 4);
      expect(contract.overallProgressPercent, 40);
    });
  });

  group('draft validation', () {
    test('rejects invalid active-day target for today', () {
      final draft = RunContractDraft.weekly10k().copyWith(
        template: RunContractTemplate.custom,
        metric: RunContractMetric.activeDays,
        targetValue: 2,
        period: RunContractPeriodType.today,
      );

      expect(draft.validate(), isNotNull);
    });
  });

  group('controller finalize', () {
    test('does not finalize when forced Strava sync fails', () async {
      final activities = _FakeActivityRepository(error: Exception('offline'));
      final contracts = _FakeContractRepository();
      final controller = RunContractController(
        contracts,
        activities,
        SyncController(activities),
      );
      final contract = _contract(
        startAt: DateTime.utc(2026, 6, 21, 17),
        endAtExclusive: DateTime.utc(2026, 6, 28, 17),
        finalizeAt: DateTime.utc(2026, 6, 28, 23),
      );

      await expectLater(
        controller.finalize(contract, now: DateTime.utc(2026, 6, 29)),
        throwsStateError,
      );
      expect(contracts.finalizeCalls, 0);
    });

    test('finalizes once with freshly calculated progress', () async {
      final activities = _FakeActivityRepository(
        activities: [_activity('finish', DateTime.utc(2026, 6, 22), 10000)],
      );
      final contracts = _FakeContractRepository();
      final controller = RunContractController(
        contracts,
        activities,
        SyncController(activities),
      );
      final contract = _contract(
        startAt: DateTime.utc(2026, 6, 21, 17),
        endAtExclusive: DateTime.utc(2026, 6, 28, 17),
        finalizeAt: DateTime.utc(2026, 6, 28, 23),
      );

      final result = await controller.finalize(
        contract,
        now: DateTime.utc(2026, 6, 29),
      );

      expect(result, RunContractStatus.completed);
      expect(contracts.finalizeCalls, 1);
      expect(contracts.finalProgress, 10);
    });
  });
}

RunContract _contract({
  RunContractMetric metric = RunContractMetric.distance,
  double targetValue = 10,
  required DateTime startAt,
  required DateTime endAtExclusive,
  required DateTime finalizeAt,
}) => RunContract(
  id: 'contract',
  creatorUid: 'user',
  title: 'Kèo 10km',
  template: RunContractTemplate.weekly10k,
  metric: metric,
  targetValue: targetValue,
  periodType: RunContractPeriodType.weekly,
  startAt: startAt,
  endAtExclusive: endAtExclusive,
  finalizeAt: finalizeAt,
  status: RunContractStatus.active,
  visibility: RunContractVisibility.club,
  progressValue: 0,
  createdAt: startAt,
  updatedAt: startAt,
);

ActivitySummary _activity(
  String id,
  DateTime startedAt,
  double distanceMeters, {
  ActivityKind kind = ActivityKind.run,
  bool? manual,
}) => ActivitySummary(
  id: id,
  name: id,
  kind: kind,
  startedAt: startedAt,
  distanceMeters: distanceMeters,
  movingTimeSeconds: 600,
  elapsedTimeSeconds: 600,
  manual: manual,
);

class _FakeActivityRepository implements ActivityRepository {
  _FakeActivityRepository({this.activities = const [], this.error});

  final List<ActivitySummary> activities;
  final Object? error;

  @override
  Future<int> sync() async {
    if (error != null) throw error!;
    return 0;
  }

  @override
  Future<List<ActivitySummary>> listStravaActivities({
    required DateTime start,
    required DateTime endExclusive,
  }) async => activities;

  @override
  Future<ActivityDetail> getDetail(String activityId) =>
      throw UnimplementedError();

  @override
  Future<void> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {}

  @override
  Stream<List<ActivitySummary>> watchActivities() => Stream.value(activities);

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() =>
      const Stream.empty();
}

class _FakeContractRepository implements RunContractRepository {
  int finalizeCalls = 0;
  double? finalProgress;

  @override
  Future<RunContractStatus> finalize(
    String contractId, {
    required double finalProgress,
    required bool targetMet,
    List<String> countedActivityIds = const [],
  }) async {
    finalizeCalls += 1;
    this.finalProgress = finalProgress;
    return targetMet ? RunContractStatus.completed : RunContractStatus.failed;
  }

  @override
  Future<Set<String>> claimedActivityIds({
    required String excludeContractId,
  }) async => const {};

  @override
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
  }) async => 'created';

  @override
  Future<void> updateProgress(String contractId, double progressValue) async {}

  @override
  Future<void> join(String contractId, double initialProgress) async {}

  @override
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {}

  @override
  Stream<List<RunContract>> watchMyActiveContracts() => Stream.value(const []);

  @override
  Stream<List<RunContract>> watchClubContracts() => Stream.value(const []);

  @override
  Stream<RunContract?> watchContract(String contractId) => Stream.value(null);
}
