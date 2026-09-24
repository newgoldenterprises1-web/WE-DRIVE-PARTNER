const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

if (!getApps().length) initializeApp();

const db = getFirestore();

function requireDriver(request) {
  const uid = request.auth?.uid;
  if (!uid || request.auth?.token?.role !== 'driver') {
    throw new HttpsError('permission-denied', 'Driver access is required.');
  }
  return uid;
}

const fields = {
  license: { url: 'drivingLicenceUrl', status: 'dlStatus' },
  id: { url: 'governmentIdUrl', status: 'idStatus' },
  selfie: { url: 'selfieUrl', status: 'selfieStatus' },
};

exports.submitVerificationDocument = onCall(
  { region: 'asia-south1', enforceAppCheck: true },
  async (request) => {
    const uid = requireDriver(request);
    const type = String(request.data?.type || '').trim().toLowerCase();
    const url = String(request.data?.url || '').trim();

    if (!fields[type]) {
      throw new HttpsError('invalid-argument', 'Unsupported verification document type.');
    }
    if (!url || url.length > 2000) {
      throw new HttpsError('invalid-argument', 'A valid uploaded document URL is required.');
    }

    const partnerRef = db.collection('partners').doc(uid);
    const snap = await partnerRef.get();
    if (!snap.exists) {
      throw new HttpsError('failed-precondition', 'Partner profile is not initialized.');
    }

    const update = {
      [fields[type].url]: url,
      [fields[type].status]: 'SUBMITTED',
      updatedAt: FieldValue.serverTimestamp(),
    };

    await partnerRef.set(update, { merge: true });

    const latest = (await partnerRef.get()).data() || {};
    const complete = Boolean(
      latest.drivingLicenceUrl &&
      latest.governmentIdUrl &&
      latest.selfieUrl
    );

    if (complete) {
      await partnerRef.set(
        {
          verificationStatus: latest.verificationStatus === 'VERIFIED' ||
              latest.verificationStatus === 'APPROVED'
              ? latest.verificationStatus
              : 'UNDER_REVIEW',
          onboardingStatus: latest.onboardingStatus === 'APPROVED'
              ? latest.onboardingStatus
              : 'UNDER_REVIEW',
          documentsSubmittedAt: latest.documentsSubmittedAt || FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    return {
      ok: true,
      type,
      status: 'SUBMITTED',
      allDocumentsSubmitted: complete,
    };
  },
);
