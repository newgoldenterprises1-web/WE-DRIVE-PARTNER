const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

if (!getApps().length) initializeApp();
const db = getFirestore();

function optionalString(value, max = 500) {
  if (value == null) return null;
  const text = String(value).trim();
  return text ? text.slice(0, max) : null;
}

function fail(status, message) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function optionalNumber(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function safeList(value, maxItems = 10) {
  if (!Array.isArray(value)) return [];
  return value.map((item) => optionalString(item, 80)).filter(Boolean).slice(0, maxItems);
}

async function createBookingForAI(input) {
  const customerId = optionalString(input.customerId, 160);
  if (!customerId) fail(400, 'Customer ID is required.');
  const serviceDate = optionalString(input.serviceDate, 40);
  const startTime = optionalString(input.startTime, 50);
  const pickupLocation = optionalString(input.location, 500);
  if (!serviceDate || !startTime || !pickupLocation) fail(400, 'Service date, start time and pickup location are required.');

  const customerSnap = await db.collection('users').doc(customerId).get();
  if (!customerSnap.exists) fail(404, 'Customer not found.');

  const customer = customerSnap.data() || {};
  const ref = db.collection('bookings').doc();
  const durationMinutes = input.durationMinutes == null ? null : Number(input.durationMinutes);
  if (durationMinutes != null && (!Number.isFinite(durationMinutes) || durationMinutes <= 0)) fail(400, 'Invalid duration.');

  await ref.create({
    bookingId: ref.id,
    customerId,
    customerName: customer.name || 'WE DRIVE Customer',
    customerPhone: customer.phone || null,
    customerEmail: customer.email || null,
    serviceType: 'Driver on Demand',
    vehicleType: null,
    transmission: null,
    fuelType: null,
    pickupLocation,
    dropLocation: null,
    pickupLatitude: optionalNumber(input.latitude),
    pickupLongitude: optionalNumber(input.longitude),
    dropLatitude: null,
    dropLongitude: null,
    bookingDate: serviceDate,
    bookingTime: startTime,
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
    specialInstruction: optionalString(input.notes, 1000),
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
      preferredLanguages: safeList([]),
      multipleStops: [],
      recurringBooking: null,
    },
    signatureMatchRequested: true,
    matchStatus: 'WAITING',
    source: 'AI_GATEWAY',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true, bookingId: ref.id, status: 'REQUESTED' };
}

async function assignBookingForAI({ bookingId, driverId }) {
  const id = optionalString(bookingId, 160);
  const driver = optionalString(driverId, 160);
  if (!id || !driver) fail(400, 'Booking ID and driver ID are required.');

  const bookingRef = db.collection('bookings').doc(id);
  const driverRef = db.collection('partners').doc(driver);

  await db.runTransaction(async (tx) => {
    const [bookingSnap, driverSnap] = await Promise.all([tx.get(bookingRef), tx.get(driverRef)]);
    if (!bookingSnap.exists) fail(404, 'Booking not found.');
    if (!driverSnap.exists) fail(404, 'Driver not found.');

    const booking = bookingSnap.data() || {};
    const driverData = driverSnap.data() || {};
    const status = String(booking.status || '').toUpperCase();

    if (!['REQUESTED', 'SEARCHING'].includes(status)) fail(409, 'Booking is not available for assignment.');
    if (driverData.online !== true) fail(409, 'Driver is not online.');

    tx.set(bookingRef, {
      partnerId: driver,
      driverId: driver,
      status: 'ACCEPTED',
      bookingStatus: 'ACCEPTED',
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      source: 'AI_GATEWAY',
    }, { merge: true });
  });

  return { ok: true, bookingId: id, driverId: driver, status: 'ACCEPTED' };
}

module.exports = { createBookingForAI, assignBookingForAI };
