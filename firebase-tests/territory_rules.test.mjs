import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where } from 'firebase/firestore';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-runnow',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const { setDoc } = await import('firebase/firestore');
    await setDoc(doc(db, 'publicProfiles/pub'), { uid: 'pub', profileVisibility: 'public' });
    await setDoc(doc(db, 'publicProfiles/priv'), { uid: 'priv', profileVisibility: 'private' });
    for (const uid of ['pub', 'priv']) {
      await setDoc(doc(db, `territoryResults/${uid}_a1`), {
        uid,
        activityId: 'a1',
        gained: 1,
        newCells: ['1_1'],
        takenCells: {},
      });
    }
  });
});

after(async () => environment.cleanup());

test('kết quả có ô của hồ sơ công khai: ai đăng nhập cũng đọc được', async () => {
  const other = environment.authenticatedContext('other').firestore();
  await assertSucceeds(getDoc(doc(other, 'territoryResults/pub_a1')));
  const anon = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'territoryResults/pub_a1')));
});

test('hồ sơ private: chỉ chủ đọc được ô của buổi mình', async () => {
  const other = environment.authenticatedContext('other').firestore();
  await assertFails(getDoc(doc(other, 'territoryResults/priv_a1')));
  const owner = environment.authenticatedContext('priv').firestore();
  await assertSucceeds(getDoc(doc(owner, 'territoryResults/priv_a1')));
});

test('doc chưa có thì đọc được, để app nghe trước khi backend ghi', async () => {
  const other = environment.authenticatedContext('other').firestore();
  await assertSucceeds(getDoc(doc(other, 'territoryResults/pub_chua_co')));
});

test('không list được lịch sử ô của một người', async () => {
  const other = environment.authenticatedContext('other').firestore();
  await assertFails(
    getDocs(query(collection(other, 'territoryResults'), where('uid', '==', 'pub'))),
  );
});
