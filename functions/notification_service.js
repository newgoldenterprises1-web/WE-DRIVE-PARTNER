const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

const db = getFirestore();

async function sendToTokens(tokens, notification, data = {}) {
  const uniqueTokens = [...new Set((tokens || []).filter((token) => typeof token === 'string' && token.trim()))];
  if (uniqueTokens.length === 0) return { successCount: 0, failureCount: 0 };

  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < uniqueTokens.length; i += 500) {
    const batch = uniqueTokens.slice(i, i + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: batch,
      notification,
      data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value ?? '')])),
      android: {
        priority: 'high',
        notification: {
          channelId: 'wedrive_booking_high',
          sound: 'default',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    });
    successCount += response.successCount;
    failureCount += response.failureCount;
  }

  return { successCount, failureCount };
}

async function notifyAvailableDrivers({ bookingId, title, message }) {
  const snapshot = await db.collection('partners').where('online', '==', true).limit(500).get();
  const tokens = [];
  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const list = Array.isArray(data.pushTokens) ? data.pushTokens : [];
    tokens.push(...list);
  });

  return sendToTokens(
    tokens,
    { title, body: message },
    {
      type: 'booking_request',
      bookingId,
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
  );
}

module.exports = { sendToTokens, notifyAvailableDrivers };
