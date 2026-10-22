const fs = require('node:fs');
const path = require('node:path');
const { after, before, test } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');

let env;
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Start Firestore emulator first: firebase emulators:start --only firestore');
  }
  env = await initializeTestEnvironment({
    projectId: 'shopkeeper-2de9a',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
      host: process.env.FIRESTORE_EMULATOR_HOST.split(':')[0],
      port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':')[1]),
    },
  });
});
after(async () => { await env?.cleanup(); });

test('a signed-in user can access only their own allowed collection', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertSucceeds(setDoc(doc(alice, 'users/alice/products/p1'), { name: 'Alice product' }));
  await assertSucceeds(getDoc(doc(alice, 'users/alice/products/p1')));
});

test('a different user cannot read or write another account namespace', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  await assertFails(getDoc(doc(bob, 'users/alice/products/p1')));
  await assertFails(setDoc(doc(bob, 'users/alice/products/p2'), { name: 'unauthorized' }));
});

test('unauthenticated clients cannot access user data', async () => {
  const guest = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(guest, 'users/alice/products/p1')));
  await assertFails(setDoc(doc(guest, 'users/alice/products/p1'), { name: 'guest' }));
});

test('unknown collections and root-level documents are denied', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  await assertFails(setDoc(doc(alice, 'users/alice/private_tokens/t1'), { secret: true }));
  await assertFails(setDoc(doc(alice, 'admin/secret'), { secret: true }));
});
