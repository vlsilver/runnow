import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  addDoc,
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-runnow',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

beforeEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

// Phòng r1 private của host; u1 đã vào, u2 đang chờ duyệt, u3 bị mời ra.
// u1 và u3 có buổi chạy live gắn r1. Phòng r2 public.
async function seedRooms() {
  await environment.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'runRooms/r1'), { hostUid: 'host', privacy: 'private', status: 'open' });
    await setDoc(doc(db, 'runRooms/r2'), { hostUid: 'host', privacy: 'public', status: 'open' });
    await setDoc(doc(db, 'runRooms/r1/secret/password'), { hash: 'x' });
    for (const [uid, state] of [['host', 'joined'], ['u1', 'joined'], ['u2', 'requested'], ['u3', 'kicked']]) {
      await setDoc(doc(db, `runRooms/r1/members/${uid}`), { uid, state });
    }
    for (const uid of ['u1', 'u3']) {
      await setDoc(doc(db, `liveSessions/s_${uid}`), {
        ownerUid: uid, visibility: 'private', status: 'running', roomId: 'r1', updatedAt: new Date(),
      });
    }
    await setDoc(doc(db, 'runRooms/r1/messages/m1'), { uid: 'u1', kind: 'emoji', text: '🔥' });
  });
}

function as(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function message(uid, extra = {}) {
  return {
    uid, kind: 'text', text: 'cố lên', at: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 3 * 24 * 3600 * 1000), ...extra,
  };
}

test('room by id is readable, list shows only public rooms, client never writes', async () => {
  await seedRooms();
  const db = as('stranger');
  await assertSucceeds(getDoc(doc(db, 'runRooms/r1')));
  await assertSucceeds(getDocs(query(collection(db, 'runRooms'), where('privacy', '==', 'public'))));
  await assertFails(getDocs(collection(db, 'runRooms')));
  await assertFails(setDoc(doc(db, 'runRooms/r3'), { hostUid: 'stranger', privacy: 'public' }));
  await assertFails(setDoc(doc(as('host'), 'runRooms/r1'), { hostUid: 'host', privacy: 'public', status: 'open' }));
  await assertFails(getDoc(doc(as('unauth-check'), 'runRooms/r1/secret/password')));
  await assertFails(getDoc(doc(as('host'), 'runRooms/r1/secret/password')));
  await assertFails(getDoc(doc(environment.unauthenticatedContext().firestore(), 'runRooms/r1')));
});

test('members: joined members list everyone, others see only their own doc, nobody writes', async () => {
  await seedRooms();
  await assertSucceeds(getDocs(collection(as('u1'), 'runRooms/r1/members')));
  await assertSucceeds(getDocs(query(collection(as('host'), 'runRooms/r1/members'), where('state', '==', 'requested'))));
  await assertFails(getDocs(collection(as('u2'), 'runRooms/r1/members')));
  await assertSucceeds(getDoc(doc(as('u2'), 'runRooms/r1/members/u2')));
  await assertFails(getDoc(doc(as('u2'), 'runRooms/r1/members/u1')));
  await assertFails(getDocs(collection(as('u3'), 'runRooms/r1/members')));
  await assertFails(setDoc(doc(as('u2'), 'runRooms/r1/members/u2'), { uid: 'u2', state: 'joined' }));
});

test('live sessions of a room are visible to joined members only', async () => {
  await seedRooms();
  const roomLive = (db) => getDocs(query(collection(db, 'liveSessions'), where('roomId', '==', 'r1'), where('status', 'in', ['running', 'paused'])));
  await assertSucceeds(roomLive(as('u1')));
  await assertSucceeds(roomLive(as('host')));
  await assertSucceeds(getDoc(doc(as('host'), 'liveSessions/s_u1')));
  await assertFails(roomLive(as('u2')));
  await assertFails(roomLive(as('u3')));
  await assertFails(roomLive(as('stranger')));
  await assertFails(getDoc(doc(as('stranger'), 'liveSessions/s_u1')));
});

test('room messages: joined members read and post short pings as themselves', async () => {
  await seedRooms();
  const msgs = (db) => collection(db, 'runRooms/r1/messages');
  await assertSucceeds(getDocs(msgs(as('u1'))));
  await assertFails(getDocs(msgs(as('u2'))));
  await assertFails(getDocs(msgs(as('stranger'))));
  await assertSucceeds(addDoc(msgs(as('u1')), message('u1')));
  await assertSucceeds(addDoc(msgs(as('host')), message('host', { kind: 'emoji', text: '👏' })));
  await assertFails(addDoc(msgs(as('u2')), message('u2')));
  await assertFails(addDoc(msgs(as('u3')), message('u3')));
  await assertFails(addDoc(msgs(as('u1')), message('host')));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { text: '' })));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { text: 'a'.repeat(121) })));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { kind: 'voice' })));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { name: 'giả tên' })));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { at: new Date('2026-01-01') })));
  await assertFails(addDoc(msgs(as('u1')), message('u1', { expiresAt: Timestamp.fromMillis(Date.now() + 8 * 24 * 3600 * 1000) })));
  await assertFails(setDoc(doc(as('u1'), 'runRooms/r1/messages/m1'), message('u1')));
});

test('my rooms: a user finds only their own memberships across rooms', async () => {
  await seedRooms();
  const mine = (db, uid) => getDocs(query(collectionGroup(db, 'members'), where('uid', '==', uid), where('state', 'in', ['joined', 'requested'])));
  await assertSucceeds(mine(as('u2'), 'u2'));
  await assertFails(mine(as('u2'), 'u1'));
  await assertFails(getDocs(collectionGroup(as('u1'), 'members')));
});

test('only joined members can attach a live session to a room', async () => {
  await seedRooms();
  const live = (uid, extra = {}) => ({ ownerUid: uid, visibility: 'private', status: 'running', updatedAt: new Date(), ...extra });
  await assertSucceeds(setDoc(doc(as('u1'), 'liveSessions/new_u1'), live('u1', { roomId: 'r1' })));
  await assertFails(setDoc(doc(as('stranger'), 'liveSessions/new_x'), live('stranger', { roomId: 'r1' })));
  await assertFails(setDoc(doc(as('u2'), 'liveSessions/new_u2'), live('u2', { roomId: 'r1' })));
  await assertFails(setDoc(doc(as('u3'), 'liveSessions/new_u3'), live('u3', { roomId: 'r1' })));
  await assertSucceeds(setDoc(doc(as('stranger'), 'liveSessions/plain'), live('stranger')));
  // Buổi cũ giữ nguyên roomId thì vẫn cập nhật được, kể cả khi đã bị mời ra.
  await assertSucceeds(updateDoc(doc(as('u3'), 'liveSessions/s_u3'), { distanceMeters: 1200 }));
  await assertFails(updateDoc(doc(as('stranger'), 'liveSessions/plain'), { roomId: 'r1' }));
});

test('no cheering in a room that has ended', async () => {
  await seedRooms();
  await environment.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), 'runRooms/r1'), { status: 'ended' }));
  await assertFails(addDoc(collection(as('u1'), 'runRooms/r1/messages'), message('u1')));
});
