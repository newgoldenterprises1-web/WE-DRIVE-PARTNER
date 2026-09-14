const { onCall } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const RAZORPAY_KEY_ID = defineSecret('RAZORPAY_KEY_ID');
const RAZORPAY_KEY_SECRET = defineSecret('RAZORPAY_KEY_SECRET');
const RAZORPAYX_ACCOUNT_NUMBER = defineSecret('RAZORPAYX_ACCOUNT_NUMBER');

const db = getFirestore();

const ACTIVE_PAYOUT_STATUSES = ['REQUESTED', 'QUEUED', 'PENDING', 'PROCESSING'];
const FINAL_SUCCESS_STATUSES = ['PROCESSED'];
const FINAL_FAILURE_STATUSES = ['FAILED', 'CANCELLED', 'REVERSED', 'REJECTED'];

function normalizePhone(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.startsWith('91') && digits.length === 12) return digits.slice(2);
  return digits;
}

function configReady() {
  return Boolean(
    RAZORPAY_KEY_ID.value() &&
    RAZORPAY_KEY_SECRET.value() &&
    RAZORPAYX_ACCOUNT_NUMBER.value(),
  );
}

async function razorpayRequest(path, method, body, idempotencyKey) {
  const key = RAZORPAY_KEY_ID.value();
  const secret = RAZORPAY_KEY_SECRET.value();
  const headers = {
    Authorization: `Basic ${Buffer.from(`${key}:${secret}`).toString('base64')}`,
    'Content-Type': 'application/json',
  };
  if (idempotencyKey) headers['X-Payout-Idempotency'] = idempotencyKey;

  const response = await fetch(`https://api.razorpay.com/v1${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch (_) {
    data = { error: { description: text } };
  }

  if (!response.ok) {
    const message = data?.error?.description || `Razorpay request failed with ${response.status}`;
    throw new Error(message);
  }
  return data;
}

async function calculateAvailableBalance(uid) {
  const earningsSnap = await db.collection('partners').doc(uid).collection('earnings').get();
  const payoutSnap = await db.collection('payoutRequests')
    .where('partnerId', '==', uid)
    .limit(1000)
    .get();

  let earned = 0;
  for (const doc of earningsSnap.docs) {
    const value = Number(doc.data()?.earnings || 0);
    if (Number.isFinite(value) && value > 0) earned += value;
  }

  let reserved = 0;
  for (const doc of payoutSnap.docs) {
    const data = doc.data() || {};
    const value = Number(data.amount || 0);
    if (FINAL_SUCCESS_STATUSES.includes(data.status) || ACTIVE_PAYOUT_STATUSES.includes(data.status)) {
      reserved += Math.max(0, value);
    }
  }

  return Math.max(0, Math.floor(earned - reserved));
}

async function submitPayoutForDriver(uid, requestedAmount, reason) {
  if (!configReady()) {
    throw new Error('RazorpayX payout configuration is not ready.');
  }

  const partnerRef = db.collection('partners').doc(uid);
  const partnerSnap = await partnerRef.get();
  if (!partnerSnap.exists) throw new Error('Partner account not found.');
  const partner = partnerSnap.data() || {};

  const accountNumber = String(partner.bankAccountNo || '').replace(/\s/g, '');
  const ifsc = String(partner.ifscCode || '').trim().toUpperCase();
  const holder = String(partner.accountHolder || partner.name || '').trim();
  const phone = normalizePhone(partner.phoneNumber);

  if (!/^\d{9,20}$/.test(accountNumber) || !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(ifsc) || holder.length < 3) {
    throw new Error('Complete and valid bank payout details are required.');
  }

  const available = await calculateAvailableBalance(uid);
  const amount = requestedAmount == null ? available : Math.floor(Number(requestedAmount));
  if (!Number.isFinite(amount) || amount < 100) throw new Error('Minimum withdrawal amount is ₹100.');
  if (amount > available) throw new Error(`Insufficient available balance. Available: ₹${available}.`);

  const payoutRef = db.collection('payoutRequests').doc();
  const payoutId = payoutRef.id;

  await payoutRef.set({
    partnerId: uid,
    amount,
    frequency: String(partner.payoutFrequency || 'weekly').toLowerCase(),
    reason: reason || 'manual',
    status: 'REQUESTED',
    currency: 'INR',
    bankLast4: accountNumber.slice(-4),
    ifsc,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  try {
    const contact = await razorpayRequest('/contacts', 'POST', {
      name: holder,
      email: String(partner.email || 'partner@wedrive.in'),
      contact: phone,
      type: 'employee',
      reference_id: uid.slice(0, 40),
    });

    const fundAccount = await razorpayRequest('/fund_accounts', 'POST', {
      contact_id: contact.id,
      account_type: 'bank_account',
      bank_account: {
        name: holder,
        ifsc,
        account_number: accountNumber,
      },
    });

    const payout = await razorpayRequest('/payouts', 'POST', {
      account_number: RAZORPAYX_ACCOUNT_NUMBER.value(),
      fund_account_id: fundAccount.id,
      amount: amount * 100,
      currency: 'INR',
      mode: 'IMPS',
      purpose: 'payout',
      queue_if_low_balance: true,
      reference_id: payoutId.slice(0, 40),
      narration: 'WE DRIVE Partner Payout',
      notes: {
        partner_id: uid.slice(0, 80),
        payout_request: payoutId.slice(0, 80),
      },
    }, payoutId);

    const providerStatus = String(payout.status || 'queued').toUpperCase();
    const mappedStatus = providerStatus === 'PROCESSED'
      ? 'PROCESSED'
      : FINAL_FAILURE_STATUSES.includes(providerStatus)
        ? providerStatus
        : providerStatus === 'PROCESSING'
          ? 'PROCESSING'
          : 'QUEUED';

    await payoutRef.set({
      status: mappedStatus,
      provider: 'razorpayx',
      providerPayoutId: payout.id || null,
      providerFundAccountId: fundAccount.id || null,
      providerContactId: contact.id || null,
      providerStatus: payout.status || null,
      utr: payout.utr || null,
      fees: Number(payout.fees || 0),
      tax: Number(payout.tax || 0),
      statusDetails: payout.status_details || null,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { payoutId, status: mappedStatus, amount, providerPayoutId: payout.id || null };
  } catch (error) {
    await payoutRef.set({
      status: 'FAILED',
      errorMessage: String(error.message || error).slice(0, 500),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    throw error;
  }
}

exports.setPayoutPreference = onCall(
  { region: 'asia-south1' },
  async (request) => {
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
  },
);

exports.requestPayout = onCall(
  {
    region: 'asia-south1',
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAYX_ACCOUNT_NUMBER],
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid || request.auth?.token?.role !== 'driver') {
      throw new Error('Driver access is required.');
    }
    if (!configReady()) {
      throw new Error('Payout service is not configured yet.');
    }
    const amount = request.data?.amount == null ? null : Number(request.data.amount);
    return submitPayoutForDriver(uid, amount, 'manual');
  },
);

exports.processScheduledPayouts = onSchedule(
  {
    schedule: '0 23 * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAYX_ACCOUNT_NUMBER],
  },
  async () => {
    if (!configReady()) return;
    const today = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Kolkata',
      weekday: 'short',
    }).format(new Date());

    const partners = await db.collection('partners').where('payoutEnabled', '==', true).limit(500).get();
    const jobs = [];
    for (const doc of partners.docs) {
      const data = doc.data() || {};
      const frequency = String(data.payoutFrequency || 'weekly').toLowerCase();
      const shouldRun = frequency === 'daily' || (frequency === 'weekly' && today === 'Sun');
      if (!shouldRun) continue;
      jobs.push(submitPayoutForDriver(doc.id, null, 'scheduled'));
    }
    await Promise.allSettled(jobs);
  },
);

exports.syncPayoutStatuses = onSchedule(
  {
    schedule: '*/30 * * * *',
    timeZone: 'Asia/Kolkata',
    region: 'asia-south1',
    secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAYX_ACCOUNT_NUMBER],
  },
  async () => {
    if (!configReady()) return;
    const snapshot = await db.collection('payoutRequests')
      .where('status', 'in', ['QUEUED', 'PENDING', 'PROCESSING'])
      .limit(100)
      .get();

    await Promise.all(snapshot.docs.map(async (doc) => {
      const data = doc.data() || {};
      if (!data.providerPayoutId) return;
      try {
        const payout = await razorpayRequest(`/payouts/${data.providerPayoutId}`, 'GET');
        const providerStatus = String(payout.status || '').toUpperCase();
        let status = data.status;
        if (providerStatus === 'PROCESSED') status = 'PROCESSED';
        else if (FINAL_FAILURE_STATUSES.includes(providerStatus)) status = providerStatus;
        else if (providerStatus === 'PROCESSING') status = 'PROCESSING';
        else if (providerStatus === 'PENDING') status = 'PENDING';
        else if (providerStatus === 'QUEUED') status = 'QUEUED';

        await doc.ref.set({
          status,
          providerStatus: payout.status || null,
          utr: payout.utr || null,
          fees: Number(payout.fees || 0),
          tax: Number(payout.tax || 0),
          statusDetails: payout.status_details || null,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      } catch (_) {
        // Keep the current state and retry on the next scheduled run.
      }
    }));
  },
);
