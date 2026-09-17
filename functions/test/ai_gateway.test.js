const test = require('node:test');
const assert = require('node:assert/strict');

process.env.WE_DRIVE_AI_GATEWAY_TOKEN = 'test-token';
const gateway = require('../ai_gateway');

const { validateArgs, ALLOWED_TOOLS, READ_ONLY_TOOLS, idempotencyDocId, argumentsFingerprint } = gateway._test;

test('AI gateway exposes only the approved tool set', () => {
  assert.equal(ALLOWED_TOOLS.has('get_booking'), true);
  assert.equal(ALLOWED_TOOLS.has('create_job'), true);
  assert.equal(ALLOWED_TOOLS.has('delete_everything'), false);
});

test('read-only tools are classified correctly', () => {
  assert.equal(READ_ONLY_TOOLS.has('get_booking'), true);
  assert.equal(READ_ONLY_TOOLS.has('get_system_health'), true);
  assert.equal(READ_ONLY_TOOLS.has('create_job'), false);
});

test('create_job validates required arguments', () => {
  const args = validateArgs('create_job', {
    customer_id: 'customer-1',
    service_date: '2026-09-20',
    start_time: '18:00',
    location: 'Hyderabad',
  });

  assert.deepEqual(args, {
    customerId: 'customer-1',
    serviceDate: '2026-09-20',
    startTime: '18:00',
    location: 'Hyderabad',
    durationMinutes: null,
    notes: null,
  });
});

test('invalid tool arguments are rejected', () => {
  assert.throws(
    () => validateArgs('get_booking', {}),
    /booking_id is required/,
  );
});

test('notification channel is normalized during validation', () => {
  const args = validateArgs('send_notification', {
    recipient_id: 'user-1',
    channel: 'PUSH',
    message: 'Test',
  });
  assert.equal(args.channel, 'push');
});

test('idempotency document is scoped by tool', () => {
  assert.notEqual(idempotencyDocId('create_job', 'same-key'), idempotencyDocId('assign_driver', 'same-key'));
});

test('idempotency fingerprint changes when arguments change', () => {
  assert.notEqual(
    argumentsFingerprint('create_job', { customerId: 'a', location: 'A' }),
    argumentsFingerprint('create_job', { customerId: 'a', location: 'B' }),
  );
});
