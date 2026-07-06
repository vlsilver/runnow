import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const projectId = 'demo-runnow';
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

beforeEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function contractData(uid, id, visibility = 'private') {
  return {
    id,
    schemaVersion: 1,
    type: 'group',
    creatorUid: uid,
    title: 'Kèo 10km',
    templateId: 'weekly_10k',
    metric: 'distance',
    targetValue: 10,
    periodType: 'weekly',
    timezone: 'Asia/Ho_Chi_Minh',
    timezoneOffsetMinutes: 420,
    startAt: new Date('2026-06-21T17:00:00Z'),
    endAtExclusive: new Date('2026-06-28T17:00:00Z'),
    finalizeAt: new Date('2026-06-28T23:00:00Z'),
    status: 'active',
    visibility,
    sourcePolicy: 'official_activity',
    progressValue: 0,
    participantUids: [uid],
    participants: {
      [uid]: {
        uid,
        progressValue: 0,
        countedActivityIds: [],
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
    },
    eligibilityVersion: 2,
    lastCalculatedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

async function createContract(db, uid, id, visibility = 'private') {
  const contractRef = doc(db, 'runContracts', id);
  await setDoc(contractRef, contractData(uid, id, visibility));
}

test('creates a contract with the creator as first participant', async () => {
  const db = environment.authenticatedContext('owner').firestore();
  await assertSucceeds(createContract(db, 'owner', 'contract-a'));
});

test('rejects creating a contract on behalf of another user', async () => {
  const db = environment.authenticatedContext('attacker').firestore();
  await assertFails(createContract(db, 'owner', 'contract-a'));
});

test('private contract is owner-only while club contract is authenticated-readable', async () => {
  const ownerDb = environment.authenticatedContext('owner').firestore();
  const memberDb = environment.authenticatedContext('member').firestore();
  await createContract(ownerDb, 'owner', 'private-contract');
  await assertFails(getDoc(doc(memberDb, 'runContracts', 'private-contract')));

  await environment.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();
    await runTransaction(adminDb, async (transaction) => {
      transaction.update(doc(adminDb, 'runContracts', 'private-contract'), {
        visibility: 'club',
      });
    });
  });
  await assertSucceeds(
    getDoc(doc(memberDb, 'runContracts', 'private-contract')),
  );
});

test('member can list club contracts with the production query shape', async () => {
  const ownerDb = environment.authenticatedContext('owner').firestore();
  const memberDb = environment.authenticatedContext('member').firestore();
  await createContract(ownerDb, 'owner', 'club-contract', 'club');

  const snapshot = await assertSucceeds(
    getDocs(
      query(
        collection(memberDb, 'runContracts'),
        where('visibility', '==', 'club'),
        where('status', '==', 'active'),
      ),
    ),
  );
  assert.equal(snapshot.size, 1);
  assert.equal(snapshot.docs[0].id, 'club-contract');
});

test('participant can join and update only their own progress', async () => {
  const ownerDb = environment.authenticatedContext('owner').firestore();
  const memberDb = environment.authenticatedContext('member').firestore();
  const attackerDb = environment.authenticatedContext('attacker').firestore();
  await createContract(ownerDb, 'owner', 'group-contract', 'club');
  const memberRef = doc(memberDb, 'runContracts', 'group-contract');

  await assertSucceeds(
    updateDoc(memberRef, {
      'participants.member': {
        uid: 'member',
        progressValue: 2,
        countedActivityIds: [],
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      },
      participantUids: ['owner', 'member'],
      updatedAt: serverTimestamp(),
    }),
  );

  const joined = await getDoc(memberRef);
  const joinedAt = joined.data().participants.member.joinedAt;
  await assertSucceeds(
    updateDoc(memberRef, {
      'participants.member': {
        uid: 'member',
        progressValue: 6,
        countedActivityIds: [],
        joinedAt,
        updatedAt: serverTimestamp(),
      },
      updatedAt: serverTimestamp(),
    }),
  );

  await assertFails(
    updateDoc(doc(attackerDb, 'runContracts', 'group-contract'), {
      'participants.member': {
        uid: 'member',
        progressValue: 10,
        countedActivityIds: [],
        joinedAt,
        updatedAt: serverTimestamp(),
      },
      updatedAt: serverTimestamp(),
    }),
  );
});

test('creator can update personal progress without changing contract shape', async () => {
  const db = environment.authenticatedContext('owner').firestore();
  await createContract(db, 'owner', 'completed-slot', 'club');
  const contractRef = doc(db, 'runContracts', 'completed-slot');

  const before = await getDoc(contractRef);
  const joinedAt = before.data().participants.owner.joinedAt;
  await assertSucceeds(
    updateDoc(contractRef, {
      progressValue: 10,
      'participants.owner': {
        uid: 'owner',
        progressValue: 10,
        countedActivityIds: [],
        joinedAt,
        updatedAt: serverTimestamp(),
      },
      lastCalculatedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  const after = await getDoc(contractRef);
  assert.equal(after.data().participants.owner.progressValue, 10);
});

test('only the creator can finalize a contract', async () => {
  const ownerDb = environment.authenticatedContext('owner').firestore();
  const memberDb = environment.authenticatedContext('member').firestore();
  await createContract(ownerDb, 'owner', 'contract-a', 'club');
  const ownerRef = doc(ownerDb, 'runContracts', 'contract-a');
  const memberRef = doc(memberDb, 'runContracts', 'contract-a');

  await assertFails(
    updateDoc(memberRef, {
      status: 'completed',
      progressValue: 10,
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(ownerRef, {
      status: 'completed',
      progressValue: 10,
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  const snapshot = await getDoc(ownerRef);
  assert.equal(snapshot.data().status, 'completed');
});
