import { deepStrictEqual } from 'node:assert';
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
  increment,
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

function cheer(db, uid) {
  return doc(db, 'liveCheers', 'sess9', 'by', uid);
}

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

// Đúng cách app ghi: tăng n của emoji vừa bấm, ghi gộp vào document cũ.
function tap(uid, emoji, as = uid) {
  return setDoc(
    cheer(db(as), uid),
    { uid, emoji, n: { [emoji]: increment(1) }, at: serverTimestamp() },
    { merge: true },
  );
}

async function seed(uid, at, n) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const emoji = Object.keys(n)[0];
    await setDoc(cheer(context.firestore(), uid), { uid, emoji, n, at });
  });
}

const longAgo = () => new Date(Date.now() - 10_000);

test('cổ vũ bằng uid của mình; ai đăng nhập cũng đọc để thẻ hiện số', async () => {
  await assertSucceeds(tap('fan', '🔥'));
  await assertSucceeds(getDocs(collection(db('other'), 'liveCheers', 'sess9', 'by')));
  const anon = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(anon, 'liveCheers', 'sess9', 'by')));
});

test('không cổ vũ thay người khác, không chữ tự do, không field lạ', async () => {
  const fan = db('fan');
  const ok = { uid: 'fan', emoji: '👏', n: { '👏': 1 }, at: serverTimestamp() };
  await assertFails(tap('other', '👏', 'fan'));
  await assertFails(setDoc(cheer(fan, 'fan'), { ...ok, uid: 'other' }));
  await assertFails(tap('fan', 'chạy chậm thế'));
  await assertFails(tap('fan', '❤️'));
  await assertFails(setDoc(cheer(fan, 'fan'), { ...ok, text: 'hi' }));
  await assertFails(
    setDoc(cheer(fan, 'fan'), { ...ok, at: new Date('2020-01-01') }),
  );
  await assertFails(setDoc(cheer(fan, 'fan'), { ...ok, n: 'nhiều' }));
});

test('bấm lại được, nhưng cách lần trước ít nhất 3 giây', async () => {
  await seed('fan', longAgo(), { '👏': 1 });
  await seed('spam', new Date(), { '👏': 1 });
  await assertSucceeds(tap('fan', '💪'));
  await assertFails(tap('spam', '💪'));
});

test('mỗi lần bấm chỉ tăng 1 ở đúng emoji vừa bấm', async () => {
  const fan = db('fan');
  const at = serverTimestamp();
  await assertFails(
    setDoc(cheer(fan, 'fan'), { uid: 'fan', emoji: '🔥', n: { '🔥': 50 }, at }),
  );
  await assertFails(
    setDoc(cheer(fan, 'fan'), {
      uid: 'fan',
      emoji: '🔥',
      n: { '🔥': 1, '👏': 1 },
      at,
    }),
  );
  await assertFails(
    setDoc(cheer(fan, 'fan'), { uid: 'fan', emoji: '🔥', n: { '💪': 1 }, at }),
  );
  await assertFails(
    setDoc(cheer(fan, 'fan'), { uid: 'fan', emoji: '🔥', n: { junk: 1 }, at }),
  );

  await seed('fan', longAgo(), { '🔥': 3, '👏': 2 });
  await assertFails(
    setDoc(cheer(fan, 'fan'), {
      uid: 'fan',
      emoji: '🔥',
      n: { '🔥': 4 },
      at,
    }),
  );
  await assertSucceeds(tap('fan', '🔥'));
  const [only] = (await getDocs(collection(fan, 'liveCheers', 'sess9', 'by'))).docs;
  deepStrictEqual(only.data().n, { '🔥': 4, '👏': 2 });
});

test('không xoá được để đếm lại từ đầu', async () => {
  await seed('fan', longAgo(), { '🔥': 3 });
  await assertFails(deleteDoc(cheer(db('fan'), 'fan')));
});
