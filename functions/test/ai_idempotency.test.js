const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp } = require('firebase-admin/app');

// The production idempotency module uses Firestore. Initialize the Admin app
// here so importing the module is safe in the isolated CI unit-test process.
if (!process.env.FIREBASE_CONFIG) {
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'we-drive-ci-test' });
}
initializeApp();

const { idempotencyDocId, argumentsFingerprint } = require('../ai_idempotency');

test('idempotency document is isolated by actor, tool and key', () => {
  const base = idempotencyDocId('create_job', 'same-key', 'actor-1');
  assert.notEqual(base, idempotencyDocId('create_job', 'same-key', 'actor-2'));
  assert.notEqual(base, idempotencyDocId('assign_driver', 'same-key', 'actor-1'));
  assert.notEqual(base, idempotencyDocId('create_job', 'other-key', 'actor-1'));
});

test('idempotency fingerprint is stable for identical input', () => {
  const args = { customerId: 'customer-1', location: 'Hyderabad' };
  assert.equal(argumentsFingerprint('create_job', args), argumentsFingerprint('create_job', args));
});

test('idempotency fingerprint changes when tool or arguments change', () => {
  const args = { customerId: 'customer-1', location: 'Hyderabad' };
  assert.notEqual(argumentsFingerprint('create_job', args), argumentsFingerprint('assign_driver', args));
  assert.notEqual(argumentsFingerprint('create_job', args), argumentsFingerprint('create_job', { ...args, location: 'Secunderabad' }));
});
