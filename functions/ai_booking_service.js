const { getFirestore, FieldValue } = require('firebase-admin/firestore');

const db = getFirestore();

function optionalString(value, max = 500) {
  if (value == null) return null;
  const text = String(value).trim();
  return text ? text.slice(0, max) : null;
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
  if (!customerId) throw new Error('Customer ID is required.');
  const serviceDate = optionalString(input.serviceDate, 40);
  const startTime = optionalString(input.startTime, 50);
  const pickupLocation = optionalString(input.location, 500);
  if (!serviceDate || !startTime || !pickupLocation) {
    throw new Error('Service date, start time and pickup location are required.');
  }

  const customerSnap = await db.collection('users').doc(customerId).get();
  if (!customerSnap.exists) throw new Error('Customer not found.');
  const customer = customerSnap.data() || {};
  const ref = db.collection('bookings').doc();
  const durationMinutes = input.durationMinutes == null ? null : Number(input.durationMinutes);
  if (durationMinutes != null && (!Number.isFinite(durationMinutes) || durationMinutes <= 0)) {
    throw new Error('Invalid duration.');
  }

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
  if (!id || !driver) throw new Error('Booking ID and driver ID are required.');

  const bookingRef = db.collection('bookings').doc(id);
  const driverRef = db.collection('partners').doc(driver);
  await db.runTransaction(async (tx) => {
    const [bookingSnap, driverSnap] = await Promise.all([tx.get(bookingRef), tx.get(driverRef)]);
    if (!bookingSnap.exists) throw new Error('Booking not found.');
    if (!driverSnap.exists) throw new Error('Driver not found.');
    const booking = bookingSnap.data() || {};
    const driverData = driverSnap.data() || {};
    if (!['REQUESTED', 'SEARCHING'].includes(String(booking.status || '').toUpperCase())) {
      throw new Error('Booking is not available for assignment.');
    }
    if (driverData.online !== true) throw new Error('Driver is not online.');
    tx.set(bookingRef, {
      partnerId: driver,
      driverId: driver,
      status: 'ACCEPTED',
      bookingStatus: 'ACCEPTED',
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { ok: true, bookingId: id, driverId: driver, status: 'ACCEPTED' };
}

module.exports = { createBookingForAI, assignBookingForAI };