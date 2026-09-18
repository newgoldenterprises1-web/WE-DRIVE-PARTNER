const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

function sanitizeMetadata(metadata = {}) {
  const source = metadata && typeof metadata === 'object' && !Array.isArray(metadata) ? metadata : {};
  const safe = {};
  for (const [key, value] of Object.entries(source)) {
    if (/token|secret|password|authorization|api.?key/i.test(key)) continue;
    if (typeof value === 'string') safe[key] = value.slice(0, 500);
    else if (typeof value === 'number' || typeof value === 'boolean' || value === null) safe[key] = value;
  }
  return safe;
}

async function recordAudit({ requestId, actorId = null, tool = null, status, outcome, metadata = {} }) {
  await db.collection('aiAuditLogs').add({
    requestId,
    actorId,
    tool,
    status: Number(status) || 500,
    outcome,
    metadata: sanitizeMetadata(metadata),
    createdAt: FieldValue.serverTimestamp(),
  });
}

module.exports = { recordAudit, sanitizeMetadata };
