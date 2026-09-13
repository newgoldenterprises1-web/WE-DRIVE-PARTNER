const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();

const MSG91_AUTHKEY = defineSecret('MSG91_AUTHKEY');

function normalizePhone(phoneNumber) {
  const digits = String(phoneNumber || '').replace(/\D/g, '');
  if (!/^91\d{10}$/.test(digits)) {
    throw new HttpsError('invalid-argument', 'Use a valid Indian mobile number.');
  }
  return `+${digits}`;
}

async function verifyWithMsg91(accessToken) {
  if (!accessToken || typeof accessToken !== 'string') {
    throw new HttpsError('unauthenticated', 'MSG91 verification token is missing.');
  }

  const response = await fetch('https://control.msg91.com/api/v5/widget/verifyAccessToken', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      authkey: MSG91_AUTHKEY.value(),
      'access-token': accessToken,
    }),
  });

  const body = await response.json().catch(() => ({}));
  const statusText = String(body?.type || body?.status || '').toLowerCase();

  if (!response.ok || (statusText && !['success', 'ok'].includes(statusText))) {
    throw new HttpsError('unauthenticated', 'MSG91 OTP verification could not be completed.');
  }

  return body;
}

async function createFirebaseSession({ accessToken, phoneNumber, role }) {
  const phone = normalizePhone(phoneNumber);
  await verifyWithMsg91(accessToken);

  let user;
  try {
    user = await admin.auth().getUserByPhoneNumber(phone);
  } catch (error) {
    if (error?.code !== 'auth/user-not-found') throw error;
    user = await admin.auth().createUser({ phoneNumber: phone });
  }

  await admin.auth().setCustomUserClaims(user.uid, { role });
  const customToken = await admin.auth().createCustomToken(user.uid, { role });

  return {
    customToken,
    uid: user.uid,
    role,
  };
}

exports.verifyDriverMsg91AccessToken = onCall(
  { secrets: [MSG91_AUTHKEY], region: 'asia-south1' },
  async (request) => {
    const { accessToken, phoneNumber } = request.data || {};
    return createFirebaseSession({
      accessToken,
      phoneNumber,
      role: 'driver',
    });
  },
);

exports.verifyCustomerMsg91AccessToken = onCall(
  { secrets: [MSG91_AUTHKEY], region: 'asia-south1' },
  async (request) => {
    const { accessToken, phoneNumber } = request.data || {};
    return createFirebaseSession({
      accessToken,
      phoneNumber,
      role: 'customer',
    });
  },
);
