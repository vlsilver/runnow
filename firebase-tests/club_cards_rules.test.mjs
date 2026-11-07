import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc } from 'firebase/firestore';
import { getMetadata, ref, uploadString } from 'firebase/storage';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-runnow',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.clearStorage();
  await environment.withSecurityRulesDisabled(async (admin) => {
    const storage = admin.storage();
    for (const name of ['art-1.png', 'src.jpg']) {
      await uploadString(ref(storage, `users/owner1/runCards/act42/${name}`), 'x');
    }
  });
});
after(async () => environment.cleanup());

async function share() {
  await environment.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'clubCards', 'owner1_act42'), {
      ownerUid: 'owner1',
    });
  });
}

function file(context, name) {
  return ref(context.storage(), `users/owner1/runCards/act42/${name}`);
}

test('thẻ khoe: ai đăng nhập cũng đọc, client không ghi', async () => {
  await share();
  const fan = environment.authenticatedContext('fan').firestore();
  await assertSucceeds(getDoc(doc(fan, 'clubCards', 'owner1_act42')));
  const anon = environment.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'clubCards', 'owner1_act42')));
  const owner = environment.authenticatedContext('owner1').firestore();
  await assertFails(
    setDoc(doc(owner, 'clubCards', 'owner1_act43'), { ownerUid: 'owner1' }),
  );
  await assertFails(deleteDoc(doc(owner, 'clubCards', 'owner1_act42')));
});

test('tranh thẻ: người khác chỉ xem khi thẻ đang khoe', async () => {
  const fan = environment.authenticatedContext('fan');
  await assertFails(getMetadata(file(fan, 'art-1.png')));
  const owner = environment.authenticatedContext('owner1');
  await assertSucceeds(getMetadata(file(owner, 'art-1.png')));

  await share();
  await assertSucceeds(getMetadata(file(fan, 'art-1.png')));
  await assertFails(
    getMetadata(file(environment.unauthenticatedContext(), 'art-1.png')),
  );
});

test('ảnh gốc của chủ thẻ không mở theo thẻ khoe', async () => {
  await share();
  const fan = environment.authenticatedContext('fan');
  await assertFails(getMetadata(file(fan, 'src.jpg')));
  const owner = environment.authenticatedContext('owner1');
  await assertSucceeds(getMetadata(file(owner, 'src.jpg')));
});
