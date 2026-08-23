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

    test('counts official Strava and RunNow runs inside half-open window', () {
      final activities = [
        _activity('run', DateTime.utc(2026, 6, 22), 5000),
        _activity(
          'runnow',
          DateTime.utc(2026, 6, 22, 12),
          500,
          source: ActivitySource.runnow,
        ),
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

      expect(progress.value, 6.5);
      expect(progress.eligibleActivities.map((item) => item.id), [
        'run',
        'runnow',
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
        _activity('a', DateTime(2026, 6, 22, 8), 1001),
        _activity('b', DateTime(2026, 6, 22, 20), 1001),
        _activity('c', DateTime(2026, 6, 23, 7), 1001),
      ]);

      expect(progress.value, 2);
    });

    test('count and active-day metrics require each run to exceed 1 km', () {
      final activities = [
        _activity('under', DateTime.utc(2026, 6, 22, 1), 999),
        _activity('exact', DateTime.utc(2026, 6, 22, 2), 1000),
        _activity('over-a', DateTime.utc(2026, 6, 22, 3), 1001),
        _activity('over-b', DateTime.utc(2026, 6, 23, 3), 1500),
      ];
      final countContract = _contract(
        metric: RunContractMetric.activityCount,
        targetValue: 2,
        startAt: contract.startAt,
        endAtExclusive: contract.endAtExclusive,
        finalizeAt: contract.finalizeAt,
      );
      final activeDaysContract = _contract(
        metric: RunContractMetric.activeDays,
        targetValue: 2,
        startAt: contract.startAt,
        endAtExclusive: contract.endAtExclusive,
        finalizeAt: contract.finalizeAt,
      );

      final count = calculateRunContractProgress(countContract, activities);
      final activeDays = calculateRunContractProgress(
        activeDaysContract,
        activities,
      );

      expect(count.value, 2);
      expect(count.eligibleActivities.map((item) => item.id), [
        'over-a',
        'over-b',
      ]);
      expect(activeDays.value, 2);
      expect(activeDays.eligibleActivities.map((item) => item.id), [
        'over-a',
        'over-b',
      ]);
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

  group('route completion', () {
    const routeStart = (lat: 10.0, lng: 106.0);
    const routeEnd = (lat: 10.009, lng: 106.0); // ~1000m về hướng bắc
    final route = RunContractRoute(
      points: [
        RunContractRoutePoint(
          latitude: routeStart.lat,
          longitude: routeStart.lng,
        ),
        RunContractRoutePoint(latitude: routeEnd.lat, longitude: routeEnd.lng),
      ],
      distanceMeters: 1000,
    );
    final contract = _contract(
      metric: RunContractMetric.routeCompletion,
      targetValue: 2,
      startAt: DateTime.utc(2026, 6, 21, 17),
      endAtExclusive: DateTime.utc(2026, 6, 28, 17),
      finalizeAt: DateTime.utc(2026, 6, 28, 23),
      route: route,
    );

    List<RoutePoint> pointsAlongRoute(DateTime startedAt) => [
      for (var i = 0; i <= 20; i++)
        RoutePoint(
          latitude: routeStart.lat + (routeEnd.lat - routeStart.lat) * i / 20,
          longitude: routeStart.lng,
          timestamp: startedAt.add(Duration(seconds: i * 10)),
        ),
    ];

    test(
      'chỉ đếm activity chạy đúng tuyến, bỏ qua activity lệch tuyến hoặc chưa có GPS',
      () {
        final matchingA = _activity(
          'matching-a',
          DateTime.utc(2026, 6, 22, 8),
          1000,
          routePoints: pointsAlongRoute(DateTime.utc(2026, 6, 22, 8)),
        );
        final matchingB = _activity(
          'matching-b',
          DateTime.utc(2026, 6, 23, 8),
          1000,
          routePoints: pointsAlongRoute(DateTime.utc(2026, 6, 23, 8)),
        );
        final offRoute = _activity(
          'off-route',
          DateTime.utc(2026, 6, 24, 8),
          1000,
          routePoints: [
            for (final point in pointsAlongRoute(DateTime.utc(2026, 6, 24, 8)))
              RoutePoint(
                latitude: point.latitude,
                // Lệch ~110m theo kinh độ — vượt xa hành lang mặc định.
                longitude: point.longitude + 0.001,
                timestamp: point.timestamp,
              ),
          ],
        );
        final noGps = _activity('no-gps', DateTime.utc(2026, 6, 25, 8), 1000);

        final progress = calculateRunContractProgress(contract, [
          matchingA,
          matchingB,
          offRoute,
          noGps,
        ]);

        expect(progress.value, 2);
        expect(progress.eligibleActivities.map((item) => item.id).toSet(), {
          'matching-a',
          'matching-b',
        });
        expect(contractTargetMet(contract, progress.value), isTrue);
      },
    );

    test('không có route thì không tính activity nào', () {
      final contractWithoutRoute = _contract(
        metric: RunContractMetric.routeCompletion,
        targetValue: 1,
        startAt: contract.startAt,
        endAtExclusive: contract.endAtExclusive,
        finalizeAt: contract.finalizeAt,
      );
      final progress = calculateRunContractProgress(contractWithoutRoute, [
        _activity(
          'matching',
          DateTime.utc(2026, 6, 22, 8),
          1000,
          routePoints: pointsAlongRoute(DateTime.utc(2026, 6, 22, 8)),
        ),
      ]);
      expect(progress.value, 0);
      expect(progress.eligibleActivities, isEmpty);
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

  group('controller assignment and finalize', () {
    test(
      'recalculate persists only activities assigned to this contract',
      () async {
        final activities = _FakeActivityRepository(
          activities: [
            _activity('claimed', DateTime.utc(2026, 6, 22), 4000),
            _activity('available', DateTime.utc(2026, 6, 23), 3000),
          ],
        );
        final contracts = _FakeContractRepository(
          assignments: {'claimed': 'another-contract', 'available': 'contract'},
        );
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

        final progress = await controller.recalculate(contract);

        expect(progress.value, 3);
        expect(contracts.updatedProgress, 3);
        expect(contracts.updatedActivityIds, ['available']);
      },
    );

    test(
      'manual assignment rejects a session owned by another contract',
      () async {
        final activities = _FakeActivityRepository(
          activities: [_activity('taken', DateTime.utc(2026, 6, 22), 5000)],
        );
        final contracts = _FakeContractRepository(
          assignments: {'taken': 'another-contract'},
        );
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
          controller.replaceActivityAssignments(contract, {'taken'}),
          throwsStateError,
        );
      },
    );

    test('finalize does not depend on client-side Strava sync', () async {
      final activities = _FakeActivityRepository(error: Exception('offline'));
      final contracts = _FakeContractRepository(
        assignments: {'finish': 'contract'},
      );
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

      expect(result, RunContractStatus.failed);
      expect(contracts.finalizeCalls, 1);
    });

    test('finalizes once with freshly calculated progress', () async {
      final activities = _FakeActivityRepository(
        activities: [_activity('finish', DateTime.utc(2026, 6, 22), 10000)],
      );
      final contracts = _FakeContractRepository(
        assignments: {'finish': 'contract'},
      );
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

  group('processChangedActivities', () {
    test(
      'recalculates only the contract containing a changed activity',
      () async {
        final changed = _activity('changed', DateTime.utc(2026, 6, 22), 4000);
        final unchanged = _activity(
          'unchanged',
          DateTime.utc(2026, 6, 23),
          5000,
        );
        final activities = _FakeActivityRepository(
          activities: [changed, unchanged],
        );
        final contracts = _FakeContractRepository(
          assignments: {'changed': 'contract-a', 'unchanged': 'contract-b'},
        );
        final controller = RunContractController(
          contracts,
          activities,
          SyncController(activities),
        );
        final contractA = _contract(
          id: 'contract-a',
          countedActivityIds: const ['changed'],
          startAt: DateTime.utc(2026, 6, 21, 17),
          endAtExclusive: DateTime.utc(2026, 6, 28, 17),
          finalizeAt: DateTime.utc(2026, 6, 28, 23),
        );
        final contractB = _contract(
          id: 'contract-b',
          countedActivityIds: const ['unchanged'],
          startAt: DateTime.utc(2026, 6, 21, 17),
          endAtExclusive: DateTime.utc(2026, 6, 28, 17),
          finalizeAt: DateTime.utc(2026, 6, 28, 23),
        );

        await controller.processChangedActivities(
          activeContracts: [contractA, contractB],
          changedActivities: [changed],
          currentUid: 'user',
        );

        expect(contracts.updatedContractIds, ['contract-a']);
      },
    );
  });

  group('applyOptionsFor', () {
    test('computes current and preview progress for an eligible kèo', () async {
      final existing = _activity('existing', DateTime.utc(2026, 6, 22), 4000);
      final candidate = _activity('candidate', DateTime.utc(2026, 6, 23), 5000);
      final activities = _FakeActivityRepository(
        activities: [existing, candidate],
      );
      final contracts = _FakeContractRepository(
        assignments: {'existing': 'contract'},
      );
      final controller = RunContractController(
        contracts,
        activities,
        SyncController(activities),
      );
      final contract = _contract(
        targetValue: 10,
        startAt: DateTime.utc(2026, 6, 21, 17),
        endAtExclusive: DateTime.utc(2026, 6, 28, 17),
        finalizeAt: DateTime.utc(2026, 6, 28, 23),
      );

      final options = await controller.applyOptionsFor(candidate, [contract]);

      expect(options, hasLength(1));
      final option = options.single;
      expect(option.eligible, isTrue);
      expect(option.ineligibleReason, isNull);
      expect(option.currentValue, 4);
      expect(option.previewValue, 9);
    });

    test(
      'marks a kèo ineligible when the activity is outside its window',
      () async {
        final candidate = _activity(
          'candidate',
          DateTime.utc(2026, 7, 10),
          5000,
        );
        final activities = _FakeActivityRepository(activities: [candidate]);
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

        final options = await controller.applyOptionsFor(candidate, [contract]);

        expect(options.single.eligible, isFalse);
        expect(options.single.ineligibleReason, 'Ngoài khoảng thời gian kèo');
        expect(options.single.previewValue, isNull);
      },
    );

    test(
      'marks a kèo ineligible when below the per-session distance threshold',
      () async {
        final candidate = _activity(
          'candidate',
          DateTime.utc(2026, 6, 22),
          800,
        );
        final activities = _FakeActivityRepository(activities: [candidate]);
        final contracts = _FakeContractRepository();
        final controller = RunContractController(
          contracts,
          activities,
          SyncController(activities),
        );
        final contract = _contract(
          metric: RunContractMetric.activityCount,
          startAt: DateTime.utc(2026, 6, 21, 17),
          endAtExclusive: DateTime.utc(2026, 6, 28, 17),
          finalizeAt: DateTime.utc(2026, 6, 28, 23),
        );

        final options = await controller.applyOptionsFor(candidate, [contract]);

        expect(options.single.eligible, isFalse);
        expect(
          options.single.ineligibleReason,
          'Chưa đạt ngưỡng tối thiểu 1km/buổi',
        );
      },
    );
  });

  group('applyActivityToContract / removeActivityFromContract', () {
    test(
      'applies an activity while keeping previously assigned ones',
      () async {
        final existing = _activity('existing', DateTime.utc(2026, 6, 22), 4000);
        final candidate = _activity(
          'candidate',
          DateTime.utc(2026, 6, 23),
          5000,
        );
        final activities = _FakeActivityRepository(
          activities: [existing, candidate],
        );
        final contracts = _FakeContractRepository(
          assignments: {'existing': 'contract'},
        );
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

        await controller.applyActivityToContract(contract, candidate);

        expect(
          contracts.updatedActivityIds,
          containsAll(['existing', 'candidate']),
        );
      },
    );

    test(
      'throws when the activity was just claimed by another kèo (race lost)',
      () async {
        final candidate = _activity(
          'candidate',
          DateTime.utc(2026, 6, 23),
          5000,
        );
        final activities = _FakeActivityRepository(activities: [candidate]);
        final contracts = _FakeContractRepository(
          assignments: {'candidate': 'another-contract'},
        );
        final controller = RunContractController(
          contracts,
          activities,
          SyncController(activities),
        );
        final contract = _contract(
          id: 'contract',
          startAt: DateTime.utc(2026, 6, 21, 17),
          endAtExclusive: DateTime.utc(2026, 6, 28, 17),
          finalizeAt: DateTime.utc(2026, 6, 28, 23),
        );

        await expectLater(
          controller.applyActivityToContract(contract, candidate),
          throwsStateError,
        );
      },
    );

    test(
      'throws when applying a Strava activity duplicating an already-claimed '
      '3i one (no auto-replace — user must remove the old claim first)',
      () async {
        final startedAt = DateTime.utc(2026, 6, 23, 6);
        final runNowClaimed = _activity(
          'runnow-claimed',
          startedAt,
          5000,
          source: ActivitySource.runnow,
          duplicateOfActivityId: 'strava-duplicate',
        );
        final stravaDuplicate = _activity(
          'strava-duplicate',
          startedAt,
          5050,
        );
        final activities = _FakeActivityRepository(
          activities: [runNowClaimed, stravaDuplicate],
        );
        final contracts = _FakeContractRepository(
          assignments: {'runnow-claimed': 'other-contract'},
        );
        final controller = RunContractController(
          contracts,
          activities,
          SyncController(activities),
        );
        final contract = _contract(
          id: 'contract',
          startAt: DateTime.utc(2026, 6, 21, 17),
          endAtExclusive: DateTime.utc(2026, 6, 28, 17),
          finalizeAt: DateTime.utc(2026, 6, 28, 23),
        );

        await expectLater(
          controller.applyActivityToContract(contract, stravaDuplicate),
          throwsStateError,
        );
      },
    );

    test('removes an activity while keeping the others assigned', () async {
      final keep = _activity('keep', DateTime.utc(2026, 6, 22), 4000);
      final toRemove = _activity('to-remove', DateTime.utc(2026, 6, 23), 5000);
      final activities = _FakeActivityRepository(activities: [keep, toRemove]);
      final contracts = _FakeContractRepository(
        assignments: {'keep': 'contract', 'to-remove': 'contract'},
      );
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

      await controller.removeActivityFromContract(contract, toRemove);

      expect(contracts.updatedActivityIds, ['keep']);
    });
  });
}

RunContract _contract({
  String id = 'contract',
  RunContractMetric metric = RunContractMetric.distance,
  double targetValue = 10,
  required DateTime startAt,
  required DateTime endAtExclusive,
  required DateTime finalizeAt,
  RunContractRoute? route,
  List<String> countedActivityIds = const [],
}) => RunContract(
  id: id,
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
  participants: {
    'user': RunContractParticipant(
      uid: 'user',
      progressValue: 0,
      countedActivityIds: countedActivityIds,
      joinedAt: startAt,
      updatedAt: startAt,
    ),
  },
  createdAt: startAt,
  updatedAt: startAt,
  route: route,
);

ActivitySummary _activity(
  String id,
  DateTime startedAt,
  double distanceMeters, {
  ActivityKind kind = ActivityKind.run,
  ActivitySource source = ActivitySource.strava,
  bool? manual,
  List<RoutePoint> routePoints = const [],
  String? duplicateOfActivityId,
}) => ActivitySummary(
  id: id,
  name: id,
  kind: kind,
  startedAt: startedAt,
  distanceMeters: distanceMeters,
  movingTimeSeconds: 600,
  elapsedTimeSeconds: 600,
  source: source,
  manual: manual,
  routePoints: routePoints,
  duplicateOfActivityId: duplicateOfActivityId,
);

class _FakeActivityRepository implements ActivityRepository {
  _FakeActivityRepository({this.activities = const [], this.error});

  final List<ActivitySummary> activities;
  final Object? error;

  @override
  Future<ActivitySyncOutcome> sync({bool fullResync = false}) async {
    if (error != null) throw error!;
    return const ActivitySyncOutcome(changedCount: 0);
  }

  @override
  Future<List<ActivitySummary>> listOfficialActivities({
    required DateTime start,
    required DateTime endExclusive,
    int? limit,
  }) async => activities;

  @override
  Future<Map<String, ActivitySummary>> getActivitiesByIds(
    Set<String> ids,
  ) async => {
    for (final activity in activities)
      if (ids.contains(activity.id)) activity.id: activity,
  };

  @override
  Future<ActivityDetail> getDetail(String activityId) =>
      throw UnimplementedError();

  @override
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async => const TrackedActivitySaveResult(
    status: TrackedActivitySaveStatus.counted,
  );

  @override
  Future<void> appendTrackChunk({
    required String activityId,
    required int seq,
    required List<Map<String, dynamic>> points,
  }) async {}

  @override
  Future<({int nextSeq, int flushedPoints})> trackChunkState(
    String activityId,
  ) async => (nextSeq: 0, flushedPoints: 0);

  @override
  Future<TrackedActivitySaveResult> finalizeTrackedActivity(
    ActivityDetail detail,
  ) => saveTrackedActivity(detail);

  @override
  Stream<List<ActivitySummary>> watchActivities({int? limit}) => Stream.value(
    limit == null ? activities : activities.take(limit).toList(),
  );

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    final start = cursor is int ? cursor : 0;
    final end = start + limit > activities.length
        ? activities.length
        : start + limit;
    final pageActivities = activities.sublist(start, end);
    return JournalActivityPage(
      entries: buildJournalActivityEntries(pageActivities),
      nextCursor: end,
      hasMore: end < activities.length,
    );
  }

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() =>
      const Stream.empty();
}

class _FakeContractRepository implements RunContractRepository {
  _FakeContractRepository({this.assignments = const {}});

  int finalizeCalls = 0;
  double? finalProgress;
  double? updatedProgress;
  List<String> updatedActivityIds = const [];
  final List<String> updatedContractIds = [];
  final Map<String, String> assignments;

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
  Future<Map<String, String>> activityAssignments() async => assignments;

  @override
  Future<RunContractRoute?> fetchContractRoute(String contractId) async => null;

  @override
  Future<void> replaceActivityAssignments(
    String contractId, {
    required List<String> activityIds,
    required double progressValue,
  }) async {
    updatedContractIds.add(contractId);
    updatedProgress = progressValue;
    updatedActivityIds = activityIds;
  }

  @override
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
    List<String> countedActivityIds = const [],
  }) async => 'created';

  @override
  Future<void> updateProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {
    updatedContractIds.add(contractId);
    updatedProgress = progressValue;
    updatedActivityIds = countedActivityIds;
  }

  @override
  Future<void> join(
    String contractId,
    double initialProgress, {
    List<String> countedActivityIds = const [],
  }) async {}

  @override
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {
    updatedContractIds.add(contractId);
  }

  @override
  Stream<List<RunContract>> watchMyActiveContracts() => Stream.value(const []);

  @override
  Future<RunContractPage> fetchClubContractsPage({
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => const RunContractPage(contracts: [], hasMore: false);

  @override
  Stream<RunContract?> watchContract(String contractId) => Stream.value(null);

  @override
  Future<void> delete(String contractId) async {}

  @override
  Future<RunContractPage> fetchMyContractHistoryPage({
    required RunContractStatus status,
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => const RunContractPage(contracts: [], hasMore: false);
}
