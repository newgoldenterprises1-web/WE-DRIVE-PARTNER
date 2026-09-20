const { onCall } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

exports.setPayoutPreference = onCall({ region: 'asia-south1', enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.role !== 'driver') {
    throw new Error('Driver access is required.');
  }

  const frequency = String(request.data?.frequency || '').toLowerCase();
  if (!['daily', 'weekly'].includes(frequency)) {
    throw new Error('Payout frequency must be daily or weekly.');
  }

  await db.collection('partners').doc(uid).set({
    payoutFrequency: frequency,
    payoutEnabled: true,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return { ok: true, frequency };
});

exports.requestPayout = onCall({ region: 'asia-south1', enforceAppCheck: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.role !== 'driver') {
    throw new Error('Driver access is required.');
  }

  return {
    ok: false,
    status: 'PENDING_KYC',
    message: 'Withdrawals will be enabled after RazorpayX KYC and payout setup are completed.',
    partnerId: uid,
  };
});
