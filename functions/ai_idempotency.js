const crypto = require('crypto');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

function idempotencyDocId(tool, key, actor) {
  return crypto.createHash('sha256').update(`${actor}:${tool}:${key}`).digest('hex');
}

function argumentsFingerprint(tool, args) {
  return crypto.createHash('sha256').update(JSON.stringify({ tool, args })).digest('hex');
}

async function beginIdempotentOperation({ tool, key, actor, args }) {
  const ref = db.collection('aiIdempotency').doc(idempotencyDocId(tool, key, actor));
  const fingerprint = argumentsFingerprint(tool, args);
  const result = await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(ref);
    if (snap.exists) {
      const stored = snap.data() || {};
      if (stored.fingerprint !== fingerprint) {
        const error = new Error('Idempotency key was already used for a different request.');
        error.status = 409;
        throw error;
      }
      if (stored.state === 'COMPLETED') return { replay: true, response: stored.response };
      if (stored.state === 'PROCESSING') {
        const error = new Error('An identical operation is already in progress.');
        error.status = 409;
        throw error;
      }
      if (stored.state === 'FAILED') {
        transaction.update(ref, {
          state: 'PROCESSING',
          retryCount: Number(stored.retryCount || 0) + 1,
          lastError: stored.error || null,
          error: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { replay: false, ref, retry: true };
      }
      const error = new Error('Invalid idempotency operation state.');
      error.status = 409;
      throw error;
    }
    transaction.create(ref, {
      tool,
      actor,
      fingerprint,
      state: 'PROCESSING',
      retryCount: 0,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { replay: false, ref, retry: false };
  });
  return result;
}

async function completeIdempotentOperation(ref, response) {
  await ref.update({ state: 'COMPLETED', response, error: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
}

async function failIdempotentOperation(ref, error) {
  await ref.update({ state: 'FAILED', error: { status: Number(error.status) || 500, message: error.message || 'Operation failed.' }, updatedAt: FieldValue.serverTimestamp() });
}

module.exports = { idempotencyDocId, argumentsFingerprint, beginIdempotentOperation, completeIdempotentOperation, failIdempotentOperation };
