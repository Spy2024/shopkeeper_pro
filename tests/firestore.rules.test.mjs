import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc } from 'firebase/firestore';

const projectId = 'demo-shopkeeper-pro-rules';
let env;

before(async () => {
  const rules = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
  env = await initializeTestEnvironment({
    projectId,
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

test('authenticated user can read and write own business documents', async () => {
  const db = env.authenticatedContext('user-a').firestore();
  const ref = doc(db, 'users/user-a/products/product-1');
  await assertSucceeds(setDoc(ref, { name: 'Tea', stockQuantity: 3 }));
  const snapshot = await assertSucceeds(getDoc(ref));
  assert.equal(snapshot.data().name, 'Tea');
  await assertSucceeds(deleteDoc(ref));
});

test('user cannot read or write another account data', async () => {
  const db = env.authenticatedContext('user-a').firestore();
  await assertFails(getDoc(doc(db, 'users/user-b/products/private-product')));
  await assertFails(setDoc(doc(db, 'users/user-b/products/attack'), { name: 'Injected' }));
});

test('unauthenticated access is denied', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users/user-a/products/product-1')));
  await assertFails(setDoc(doc(db, 'users/user-a/products/product-1'), { name: 'Tea' }));
});

test('known bill and supplier order child paths remain owner-scoped', async () => {
  const ownDb = env.authenticatedContext('user-a').firestore();
  const otherDb = env.authenticatedContext('user-b').firestore();
  await assertSucceeds(setDoc(doc(ownDb, 'users/user-a/bills/bill-1/items/item-1'), { quantity: 2 }));
  await assertSucceeds(setDoc(doc(ownDb, 'users/user-a/supplier_orders/order-1/items/item-1'), { quantity: 2 }));
  await assertFails(getDoc(doc(ownDb, 'users/user-b/bills/bill-1/items/item-1')));
  await assertFails(setDoc(doc(otherDb, 'users/user-a/bills/bill-1/items/injected'), { quantity: 1 }));
});

test('unknown collections and root-level documents are denied', async () => {
  const db = env.authenticatedContext('user-a').firestore();
  await assertFails(setDoc(doc(db, 'users/user-a/arbitrary-secret-collection/item'), { value: 1 }));
  await assertFails(setDoc(doc(db, 'private-data/item'), { value: 1 }));
});
