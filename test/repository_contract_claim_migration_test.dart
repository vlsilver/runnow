import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

/// Covers `FirestoreStravaActivityRepository.migrateDuplicateContractClaims`
/// — moving a Kèo Chạy claim from a 3i-tracked activity over to its
/// newly-synced Strava duplicate. This transaction had no test coverage
/// before, despite directly mutating contract progress data.
void main() {
  const uid = 'runner-1';
  final startedAt = DateTime.utc(2026, 7, 1, 6);

  late FakeFirebaseFirestore firestore;
  late FirestoreStravaActivityRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid),
    );
    repository = FirestoreStravaActivityRepository(auth, firestore);
  });

  Future<void> seedRunNowActivity(
    String id, {
    double distanceMeters = 5000,
    int elapsedSeconds = 1800,
  }) => firestore
      .collection('users')
      .doc(uid)
      .collection('activities')
      .doc(id)
      .set({
        'id': id,
        'name': id,
        'sportType': 'Run',
        'startedAt': startedAt.toUtc().toIso8601String(),
        'distanceMeters': distanceMeters,
        'movingTimeSeconds': elapsedSeconds,
        'elapsedTimeSeconds': elapsedSeconds,
        'source': 'runnow',
      });

  ActivitySummary stravaDuplicate(String id, {int elapsedSeconds = 1800}) =>
      ActivitySummary(
        id: id,
        name: id,
        kind: ActivityKind.run,
        startedAt: startedAt,
        distanceMeters: 5000,
        movingTimeSeconds: elapsedSeconds,
        elapsedTimeSeconds: elapsedSeconds,
        source: ActivitySource.strava,
      );

  Future<void> seedClaim(String activityId, String contractId) => firestore
      .collection('users')
      .doc(uid)
      .collection('runContractActivityClaims')
      .doc(activityId)
      .set({'contractId': contractId, 'activityId': activityId});

  Future<void> seedContract({
    required String contractId,
    required List<String> countedActivityIds,
    required num progressValue,
    String status = 'active',
  }) => firestore.collection('runContracts').doc(contractId).set({
    'status': status,
    'participants': {
      uid: {
        'uid': uid,
        'progressValue': progressValue,
        'countedActivityIds': countedActivityIds,
        'joinedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      },
    },
  });

  Future<Map<String, dynamic>> participantOf(String contractId) async {
    final contract = await firestore
        .collection('runContracts')
        .doc(contractId)
        .get();
    final participants =
        contract.data()!['participants'] as Map<String, dynamic>;
    return participants[uid] as Map<String, dynamic>;
  }

  DocumentReference<Map<String, dynamic>> claimRef(String activityId) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('runContractActivityClaims')
          .doc(activityId);

  test('migrates the claim from a 3i activity to its Strava duplicate', () async {
    await seedRunNowActivity('runnow-1');
    await seedClaim('runnow-1', 'contract-1');
    await seedContract(
      contractId: 'contract-1',
      countedActivityIds: ['runnow-1'],
      progressValue: 5,
    );

    await repository.migrateDuplicateContractClaims([
      stravaDuplicate('strava-1'),
    ]);

    expect((await claimRef('runnow-1').get()).exists, isFalse);
    final newClaim = await claimRef('strava-1').get();
    expect(newClaim.data()?['contractId'], 'contract-1');
    expect(newClaim.data()?['migratedFromActivityId'], 'runnow-1');

    final participant = await participantOf('contract-1');
    expect(participant['countedActivityIds'], ['strava-1']);
  });

  test('leaves a completed contract untouched', () async {
    await seedRunNowActivity('runnow-1');
    await seedClaim('runnow-1', 'contract-1');
    await seedContract(
      contractId: 'contract-1',
      countedActivityIds: ['runnow-1'],
      progressValue: 5,
      status: 'completed',
    );

    await repository.migrateDuplicateContractClaims([
      stravaDuplicate('strava-1'),
    ]);

    expect((await claimRef('runnow-1').get()).exists, isTrue);
    expect((await claimRef('strava-1').get()).exists, isFalse);
    final participant = await participantOf('contract-1');
    expect(participant['countedActivityIds'], ['runnow-1']);
  });

  test(
    'is a no-op when the 3i activity was never claimed by a contract',
    () async {
      await seedRunNowActivity('runnow-1');

      await expectLater(
        repository.migrateDuplicateContractClaims([
          stravaDuplicate('strava-1'),
        ]),
        completes,
      );
      expect((await claimRef('strava-1').get()).exists, isFalse);
    },
  );

  test('ignores a 3i activity with no matching Strava duplicate', () async {
    await seedRunNowActivity('runnow-1');
    await seedClaim('runnow-1', 'contract-1');
    await seedContract(
      contractId: 'contract-1',
      countedActivityIds: ['runnow-1'],
      progressValue: 5,
    );
    final unrelated = ActivitySummary(
      id: 'strava-unrelated',
      name: 'strava-unrelated',
      kind: ActivityKind.run,
      startedAt: startedAt.add(const Duration(hours: 6)),
      distanceMeters: 5000,
      movingTimeSeconds: 1800,
      elapsedTimeSeconds: 1800,
      source: ActivitySource.strava,
    );

    await repository.migrateDuplicateContractClaims([unrelated]);

    expect((await claimRef('runnow-1').get()).exists, isTrue);
    final participant = await participantOf('contract-1');
    expect(participant['countedActivityIds'], ['runnow-1']);
  });

  test(
    'blocked by a conflicting claim: drops the old id but leaves '
    'progressValue unrecomputed (known limitation, see code review)',
    () async {
      await seedRunNowActivity('runnow-1');
      await seedClaim('runnow-1', 'contract-1');
      await seedContract(
        contractId: 'contract-1',
        countedActivityIds: ['runnow-1'],
        progressValue: 5,
      );
      // strava-1 is already claimed by a different, unrelated contract —
      // enforces "one session counts toward only one kèo".
      await seedClaim('strava-1', 'contract-other');

      await repository.migrateDuplicateContractClaims([
        stravaDuplicate('strava-1'),
      ]);

      expect((await claimRef('runnow-1').get()).exists, isFalse);
      final conflictingClaim = await claimRef('strava-1').get();
      expect(conflictingClaim.data()?['contractId'], 'contract-other');

      final participant = await participantOf('contract-1');
      // The old activity id is dropped without a replacement, but
      // progressValue is carried over unchanged rather than recomputed —
      // it will only self-correct on the next recalculate() pass.
      expect(participant['countedActivityIds'], isEmpty);
      expect(participant['progressValue'], 5);
    },
  );

  test('is idempotent: running twice does not throw or double-migrate', () async {
    await seedRunNowActivity('runnow-1');
    await seedClaim('runnow-1', 'contract-1');
    await seedContract(
      contractId: 'contract-1',
      countedActivityIds: ['runnow-1'],
      progressValue: 5,
    );
    final changed = [stravaDuplicate('strava-1')];

    await repository.migrateDuplicateContractClaims(changed);
    await expectLater(
      repository.migrateDuplicateContractClaims(changed),
      completes,
    );

    final participant = await participantOf('contract-1');
    expect(participant['countedActivityIds'], ['strava-1']);
  });
}
