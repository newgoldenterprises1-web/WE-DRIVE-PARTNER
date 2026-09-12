const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

const db = admin.firestore();

function setCors(response) {
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
}

exports.registerFcmToken = onRequest(
  {
    region: 'asia-south1',
    memory: '256MiB',
    timeoutSeconds: 30,
  },
  async (req, res) => {
    setCors(res);
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ ok: false, error: 'METHOD_NOT_ALLOWED' });
      return;
    }

    try {
      const authorization = (req.get('Authorization') || '').trim();
      if (!authorization.startsWith('Bearer ')) {
        res.status(401).json({ ok: false, error: 'UNAUTHENTICATED' });
        return;
      }

      const idToken = authorization.substring('Bearer '.length).trim();
      const decoded = await admin.auth().verifyIdToken(idToken);
      const token = (req.body?.token || '').toString().trim();

      if (!token || token.length > 4096) {
        res.status(400).json({ ok: false, error: 'INVALID_TOKEN' });
        return;
      }

      const ref = db.collection('partners').doc(decoded.uid);
      const snapshot = await ref.get();
      if (!snapshot.exists) {
        res.status(404).json({ ok: false, error: 'PARTNER_NOT_FOUND' });
        return;
      }

      await ref.set(
        {
          fcmToken: token,
          fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      logger.info('FCM token registered', { partnerId: decoded.uid });
      res.status(200).json({ ok: true });
    } catch (error) {
      logger.error('FCM token registration failed', error);
      res.status(401).json({ ok: false, error: 'INVALID_AUTH' });
    }
  },
);
