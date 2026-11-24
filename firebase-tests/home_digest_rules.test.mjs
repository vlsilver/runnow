import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
} from 'firebase/firestore';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-runnow',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'homeDigests/2026-10-31'), { day: '2026-10-31', title: 'Sáng', body: 'x' });
  });
});
after(async () => environment.cleanup());

const latest = (db) => query(collection(db, 'homeDigests'), orderBy('day', 'desc'), limit(1));

test('người đăng nhập đọc được bài mới nhất', async () => {
  await assertSucceeds(getDocs(latest(environment.authenticatedContext('u1').firestore())));
});

test('chưa đăng nhập thì không đọc', async () => {
  await assertFails(getDocs(latest(environment.unauthenticatedContext().firestore())));
});

test('client không tự viết điểm tin', async () => {
  const db = environment.authenticatedContext('u1').firestore();
  await assertFails(setDoc(doc(db, 'homeDigests/2026-11-01'), { day: '2026-11-01', title: 'giả', body: 'x' }));
});
