import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  serverTimestamp,
  setDoc,
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

const run = 'run_owner1_act42';
const live = 'live_sess9';

function heart(db, target, uid) {
  return doc(db, 'hearts', target, 'by', uid);
}

test('thả tim buổi chạy bằng uid của mình, ai đăng nhập cũng đọc được', async () => {
  const fan = environment.authenticatedContext('fan').firestore();
  await assertSucceeds(
    setDoc(heart(fan, run, 'fan'), { uid: 'fan', at: serverTimestamp() }),
  );
  const other = environment.authenticatedContext('other').firestore();
  await assertSucceeds(getDocs(collection(other, 'hearts', run, 'by')));
  const anon = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(anon, 'hearts', run, 'by')));
});

test('không thả tim thay người khác', async () => {
  const fan = environment.authenticatedContext('fan').firestore();
  await assertFails(
    setDoc(heart(fan, run, 'other'), { uid: 'other', at: serverTimestamp() }),
  );
  await assertFails(
    setDoc(heart(fan, run, 'fan'), { uid: 'other', at: serverTimestamp() }),
  );
});

test('chỉ uid và giờ server, không field nào khác', async () => {
  const fan = environment.authenticatedContext('fan').firestore();
  await assertFails(
    setDoc(heart(fan, run, 'fan'), {
      uid: 'fan',
      at: serverTimestamp(),
      count: 99,
    }),
  );
  await assertFails(
    setDoc(heart(fan, run, 'fan'), { uid: 'fan', at: new Date('2020-01-01') }),
  );
});

test('target phải là run_, card_ hoặc live_', async () => {
  const fan = environment.authenticatedContext('fan').firestore();
  for (const target of ['card_owner1_act42', live]) {
    await assertSucceeds(
      setDoc(heart(fan, target, 'fan'), { uid: 'fan', at: serverTimestamp() }),
    );
  }
  for (const target of ['junk', 'run_', 'run_owner1', 'post_owner1_x']) {
    await assertFails(
      setDoc(heart(fan, target, 'fan'), { uid: 'fan', at: serverTimestamp() }),
    );
  }
});

test('bấm lại khi đã thả tim không lỗi', async () => {
  const fan = environment.authenticatedContext('fan').firestore();
  await setDoc(heart(fan, run, 'fan'), { uid: 'fan', at: serverTimestamp() });
  await assertSucceeds(
    setDoc(heart(fan, run, 'fan'), { uid: 'fan', at: serverTimestamp() }),
  );
});

test('gỡ tim của mình được, trừ tim live; không gỡ tim người khác', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [target, uid] of [
      [run, 'fan'],
      [live, 'fan'],
      [run, 'other'],
    ]) {
      await setDoc(heart(db, target, uid), { uid, at: new Date() });
    }
  });
  const fan = environment.authenticatedContext('fan').firestore();
  await assertSucceeds(deleteDoc(heart(fan, run, 'fan')));
  await assertFails(deleteDoc(heart(fan, live, 'fan')));
  await assertFails(deleteDoc(heart(fan, run, 'other')));
});
