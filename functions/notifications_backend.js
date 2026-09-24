const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();

const db = getFirestore();
const messaging = getMessaging();

function requireAuth(request) {
  if (!request.auth?.uid) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return request.auth.uid;
}

exports.registerFcmToken = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireAuth(request);
    const token = String(request.data?.token || '').trim();
    if (!token || token.length < 20) {
      throw new HttpsError('invalid-argument', 'A valid FCM registration token is required.');
    }

    const role = String(request.auth?.token?.role || '').toLowerCase();
    const collection = role === 'driver' ? 'partners' : role === 'customer' ? 'users' : null;
    if (!collection) {
      throw new HttpsError('permission-denied', 'A customer or driver role is required.');
    }

    await db.collection(collection).doc(uid).set(
      {
        fcmTokens: FieldValue.arrayUnion(token),
        fcmTokenUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { ok: true };
  },
);

async function sendPushToUser(userId, {
  title,
  body,
  data = {},
  role = null,
}) {
  if (!userId) return;

  const collections = role === 'driver'
      ? ['partners']
      : role === 'customer'
          ? ['users']
          : ['partners', 'users'];

  for (const collection of collections) {
    const snap = await db.collection(collection).doc(userId).get();
    if (!snap.exists) continue;

    const tokens = Array.isArray(snap.data()?.fcmTokens)
        ? snap.data().fcmTokens.filter((value) => typeof value === 'string' && value.trim())
        : [];
    if (!tokens.length) continue;

    const response = await messaging.sendEachForMulticast({
      tokens: tokens.slice(0, 500),
      notification: {
        title: String(title || 'WE DRIVE'),
        body: String(body || ''),
      },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([key, value]) => [String(key), String(value ?? '')]),
      ),
      android: {
        priority: 'high',
        notification: {
          channelId: 'we_drive_alerts',
          sound: 'default',
        },
      },
    });

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const code = result.error?.code || '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          invalidTokens.push(tokens[index]);
        }
      }
    });

    if (invalidTokens.length) {
      await db.collection(collection).doc(userId).set(
        { fcmTokens: FieldValue.arrayRemove(...invalidTokens) },
        { merge: true },
      );
    }

    return;
  }
}

module.exports.sendPushToUser = sendPushToUser;
