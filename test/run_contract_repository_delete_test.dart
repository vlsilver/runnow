import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';

/// Covers `FirestoreRunContractRepository.delete` — cho phép người tạo kèo
/// xóa hẳn kèo của mình, nhưng chỉ khi chưa ai khác tham gia, và dọn luôn các
/// activity claim của chính họ đang trỏ vào kèo đó.
void main() {
  const creatorUid = 'creator-1';
  const otherUid = 'runner-2';

  late FakeFirebaseFirestore firestore;

  FirestoreRunContractRepository repositoryFor(String uid) =>
      FirestoreRunContractRepository(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
        firestore,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedContract({
    required String contractId,
    required String creatorUid,
    required Map<String, dynamic> participants,
  }) => firestore.collection('runContracts').doc(contractId).set({
    'id': contractId,
    'creatorUid': creatorUid,
    'status': 'active',
    'participants': participants,
    'participantUids': participants.keys.toList(),
  });

  Future<void> seedClaim(String uid, String activityId, String contractId) =>
      firestore
          .collection('users')
          .doc(uid)
          .collection('runContractActivityClaims')
          .doc(activityId)
          .set({'activityId': activityId, 'contractId': contractId});

  test('deletes a solo-participant contract and its own claims', () async {
    await seedContract(
      contractId: 'c1',
      creatorUid: creatorUid,
      participants: {
        creatorUid: {'uid': creatorUid, 'progressValue': 5},
      },
    );
    await seedClaim(creatorUid, 'act-1', 'c1');
    await seedClaim(creatorUid, 'act-2', 'c1');

    await repositoryFor(creatorUid).delete('c1');

    final contractDoc = await firestore.collection('runContracts').doc('c1').get();
    expect(contractDoc.exists, isFalse);
    final claims = await firestore
        .collection('users')
        .doc(creatorUid)
        .collection('runContractActivityClaims')
        .get();
    expect(claims.docs, isEmpty);
  });

  test('throws when someone else has already joined', () async {
    await seedContract(
      contractId: 'c2',
      creatorUid: creatorUid,
      participants: {
        creatorUid: {'uid': creatorUid, 'progressValue': 5},
        otherUid: {'uid': otherUid, 'progressValue': 0},
      },
    );

    await expectLater(
      repositoryFor(creatorUid).delete('c2'),
      throwsA(isA<StateError>()),
    );
    final contractDoc = await firestore.collection('runContracts').doc('c2').get();
    expect(contractDoc.exists, isTrue);
  });

  test('throws when the caller is not the creator', () async {
    await seedContract(
      contractId: 'c3',
      creatorUid: creatorUid,
      participants: {
        creatorUid: {'uid': creatorUid, 'progressValue': 5},
      },
    );

    await expectLater(
      repositoryFor(otherUid).delete('c3'),
      throwsA(isA<StateError>()),
    );
    final contractDoc = await firestore.collection('runContracts').doc('c3').get();
    expect(contractDoc.exists, isTrue);
  });

  test('is a no-op when the contract no longer exists', () async {
    await expectLater(repositoryFor(creatorUid).delete('missing'), completes);
  });
}
