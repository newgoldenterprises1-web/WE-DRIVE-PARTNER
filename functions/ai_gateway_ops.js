const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

function optionalText(value, max = 500) {
  if (value == null) return null;
  if (typeof value !== 'string') throw new Error('Invalid text value.');
  const v = value.trim();
  return v ? v.slice(0, max) : null;
}

async function createJobForAI(args) {
  const customerSnap = await db.collection('users').doc(args.customerId).get();
  if (!customerSnap.exists) {
    const error = new Error('Customer not found.');
    error.status = 404;
    throw error;
  }

  const customer = customerSnap.data() || {};
  const ref = db.collection('bookings').doc();
  const durationMinutes = args.durationMinutes == null ? null : Number(args.durationMinutes);
  if (durationMinutes != null && (!Number.isFinite(durationMinutes) || durationMinutes <= 0)) {
    const error = new Error('duration_minutes must be a positive number.');
    error.status = 400;
    throw error;
  }

  const data = {
    bookingId: ref.id,
    customerId: args.customerId,
    customerName: customer.name || 'WE DRIVE Customer',
    customerPhone: customer.phone || null,
    customerEmail: customer.email || null,
    serviceType: 'Driver on Demand',
    vehicleType: null,
    transmission: null,
    fuelType: null,
    pickupLocation: args.location,
    dropLocation: null,
    pickupLatitude: null,
    pickupLongitude: null,
    dropLatitude: null,
    dropLongitude: null,
    bookingDate: args.serviceDate,
    bookingTime: args.startTime,
    selectedHours: durationMinutes == null ? null : durationMinutes / 60,
    fare: 0,
    currency: 'INR',
    paymentMethod: 'Cash',
    paymentStatus: 'pending',
    status: 'REQUESTED',
    bookingStatus: 'REQUESTED',
    partnerId: null,
    driverId: null,
    driverName: null,
    driverPhone: null,
    driverRating: null,
    driverExperience: null,
    driverVerified: false,
    assignedVehicle: null,
    specialInstruction: optionalText(args.notes, 1000),
    serviceMode: null,
    requestPreferences: {
      communicationStyle: 'NORMAL',
      privacyMode: false,
      preferredChauffeurId: null,
      luggageMode: 'LIGHT',
      pickupMode: 'CUSTOM_PIN',
      guestName: null,
      guestPhone: null,
      guestRelationship: null,
      trustedContactName: null,
      trustedContactPhone: null,
      eventType: null,
      corporateAccountId: null,
      conciergeMode: false,
      whiteGlove: false,
      preferredLanguages: [],
      multipleStops: [],
      recurringBooking: null,
    },
    signatureMatchRequested: true,
    matchStatus: 'WAITING',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    source: 'AI_GATEWAY',
  };

  await ref.create(data);
  return { ok: true, bookingId: ref.id, status: 'REQUESTED' };
}

async function assignDriverForAI(args) {
  const bookingRef = db.collection('bookings').doc(args.jobId);
  const driverRef = db.collection('partners').doc(args.driverId);

  await db.runTransaction(async (tx) => {
    const [bookingSnap, driverSnap] = await Promise.all([
      tx.get(bookingRef),
      tx.get(driverRef),
    ]);

    if (!bookingSnap.exists) {
      const error = new Error('Booking not found.');
      error.status = 404;
      throw error;
    }
    if (!driverSnap.exists) {
      const error = new Error('Driver not found.');
      error.status = 404;
      throw error;
    }

    const booking = bookingSnap.data() || {};
    const driver = driverSnap.data() || {};
    const status = String(booking.status || '').toUpperCase();

    if (!['REQUESTED', 'SEARCHING'].includes(status)) {
      const error = new Error('Booking is not available for assignment.');
      error.status = 409;
      throw error;
    }
    if (driver.online !== true) {
      const error = new Error('Driver is not online.');
      error.status = 409;
      throw error;
    }

    tx.set(bookingRef, {
      partnerId: args.driverId,
      driverId: args.driverId,
      status: 'ACCEPTED',
      bookingStatus: 'ACCEPTED',
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: 'AI_GATEWAY',
    }, { merge: true });
  });

  return {
    ok: true,
    bookingId: args.jobId,
    driverId: args.driverId,
    status: 'ACCEPTED',
  };
}

module.exports = { createJobForAI, assignDriverForAI };
