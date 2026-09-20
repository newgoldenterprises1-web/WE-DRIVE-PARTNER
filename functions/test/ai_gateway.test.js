const test = require('node:test');
const assert = require('node:assert/strict');

process.env.WE_DRIVE_AI_GATEWAY_TOKEN = 'test-token';
const gateway = require('../ai_gateway');
const approval = require('../ai_approval');

const { validateArgs, ALLOWED_TOOLS, READ_ONLY_TOOLS, idempotencyDocId, argumentsFingerprint, executeApprovedAction } = gateway._test;
const { normalizeExecutionMetadata, fingerprint, assertExecutionMatchesAction, approvalDecisionState, approvalConsumptionState } = approval;

test('AI gateway exposes only the approved tool set', () => {
  assert.equal(ALLOWED_TOOLS.has('get_booking'), true);
  assert.equal(ALLOWED_TOOLS.has('create_job'), true);
  assert.equal(ALLOWED_TOOLS.has('request_approval'), true);
  assert.equal(ALLOWED_TOOLS.has('get_approval'), true);
  assert.equal(ALLOWED_TOOLS.has('execute_approved_action'), true);
  assert.equal(ALLOWED_TOOLS.has('delete_everything'), false);
});

test('read-only tools are classified correctly', () => {
  assert.equal(READ_ONLY_TOOLS.has('get_booking'), true);
  assert.equal(READ_ONLY_TOOLS.has('get_system_health'), true);
  assert.equal(READ_ONLY_TOOLS.has('get_approval'), true);
  assert.equal(READ_ONLY_TOOLS.has('create_job'), false);
  assert.equal(READ_ONLY_TOOLS.has('request_approval'), false);
  assert.equal(READ_ONLY_TOOLS.has('execute_approved_action'), false);
});

test('create_job validates required arguments', () => {
  const args = validateArgs('create_job', { customer_id: 'customer-1', service_date: '2026-09-20', start_time: '18:00', location: 'Hyderabad' });
  assert.deepEqual(args, { customerId: 'customer-1', serviceDate: '2026-09-20', startTime: '18:00', location: 'Hyderabad', durationMinutes: null, notes: null });
});

test('create_job rejects a non-positive duration', () => {
  assert.throws(() => validateArgs('create_job', { customer_id: 'customer-1', service_date: '2026-09-20', start_time: '18:00', location: 'Hyderabad', duration_minutes: 0 }), /duration_minutes must be greater than zero/);
});

test('get_available_drivers accepts optional matching coordinates and service', () => {
  const args = validateArgs('get_available_drivers', { service_date: '2026-09-20', start_time: '18:00', location: 'Hyderabad', duration_minutes: 120, latitude: 17.385, longitude: 78.4867, required_service: 'standard' });
  assert.equal(args.latitude, 17.385);
  assert.equal(args.longitude, 78.4867);
  assert.equal(args.requiredService, 'standard');
});

test('invalid coordinates are rejected', () => {
  assert.throws(() => validateArgs('get_available_drivers', { service_date: '2026-09-20', start_time: '18:00', location: 'Hyderabad', latitude: 91 }), /latitude is out of range/);
});

test('invalid tool arguments are rejected', () => {
  assert.throws(() => validateArgs('get_booking', {}), /booking_id is required/);
});

test('notification channel is normalized during validation', () => {
  const args = validateArgs('send_notification', { recipient_id: 'user-1', channel: 'PUSH', message: 'Test' });
  assert.equal(args.channel, 'push');
});

test('Development Agent patch tool is allowlisted but not read-only', () => {
  assert.equal(ALLOWED_TOOLS.has('github_apply_patch'), true);
  assert.equal(READ_ONLY_TOOLS.has('github_apply_patch'), false);
  const args = validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI',
    branch: 'ai-dev/security-hardening',
    path: 'src/example.py',
    content: 'print("ok")',
    message: 'test patch',
    sha: 'abc123',
  });
  assert.equal(args.branch, 'ai-dev/security-hardening');
  assert.equal(args.path, 'src/example.py');
});

test('Development Agent cannot write outside ai-dev branches', () => {
  assert.throws(() => validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI',
    branch: 'main',
    path: 'src/example.py',
    content: 'print("ok")',
    message: 'unsafe patch',
    sha: 'abc123',
  }), /ai-dev/);
});

test('marketing actions are approval-gated and status/draft are read-only', () => {
  assert.equal(ALLOWED_TOOLS.has('get_marketing_status'), true);
  assert.equal(ALLOWED_TOOLS.has('create_social_content'), true);
  assert.equal(READ_ONLY_TOOLS.has('get_marketing_status'), true);
  assert.equal(READ_ONLY_TOOLS.has('create_social_content'), true);
  assert.equal(READ_ONLY_TOOLS.has('publish_social_content'), false);
  assert.equal(READ_ONLY_TOOLS.has('send_whatsapp_campaign'), false);
});

test('marketing publish and WhatsApp arguments normalize safely', () => {
  const publish = validateArgs('publish_social_content', { platform: 'Instagram', content: 'Launch', media_url: 'https://example.com/a.jpg' });
  assert.deepEqual(publish, { platform: 'instagram', content: 'Launch', mediaUrl: 'https://example.com/a.jpg', scheduledAt: null });
  const wa = validateArgs('send_whatsapp_campaign', { audience: '+919999999999', message: 'Hello' });
  assert.deepEqual(wa, { audience: '+919999999999', message: 'Hello', scheduledAt: null });
});

test('approval decisions require a boolean and approval id', () => {
  assert.deepEqual(validateArgs('decide_approval', { approval_id: 'approval-1', approved: true }), {
    approvalId: 'approval-1', approved: true, decisionReason: ''
  });
  assert.throws(() => validateArgs('decide_approval', { approval_id: 'approval-1', approved: 'true' }), /approved must be a boolean/);
});

test('request_approval validates the critical action payload', () => {
  const args = validateArgs('request_approval', { action: 'production_deploy', reason: 'Release approved build', metadata: { execution: { tool: 'production_deploy', arguments: { environment: 'production', version: 'v1.2.3' } } } });
  assert.equal(args.action, 'production_deploy');
  assert.equal(args.metadata.execution.tool, 'production_deploy');
});

test('execute_approved_action validates the exact execution manifest shape', () => {
  const args = validateArgs('execute_approved_action', { approval_id: 'approval-1', action: 'production_deploy', metadata: { execution: { tool: 'production_deploy', arguments: { environment: 'production', version: 'v1.2.3' } } } });
  assert.equal(args.approvalId, 'approval-1');
  assert.equal(args.action, 'production_deploy');
  assert.deepEqual(args.metadata.execution.arguments, { environment: 'production', version: 'v1.2.3' });
});

test('approved execution rejects a mismatched action and execution tool before approval consumption', async () => {
  await assert.rejects(executeApprovedAction({ approvalId: 'approval-1', action: 'production_deploy', metadata: { execution: { tool: 'large_financial_action', arguments: { amount: 100 } } } }, 'ai-agent'), /Approval action does not match execution tool/);
});

test('approved execution does not provide an unregistered critical executor', async () => {
  await assert.rejects(executeApprovedAction({ approvalId: 'approval-1', action: 'production_deploy', metadata: { execution: { tool: 'production_deploy', arguments: { environment: 'production', version: 'v1.2.3' } } } }, 'ai-agent'), /No approved executor is registered for critical action/);
});

test('approval execution metadata requires an exact tool and arguments object', () => {
  assert.throws(() => normalizeExecutionMetadata({}), /metadata.execution is required/);
  assert.throws(() => normalizeExecutionMetadata({ execution: { tool: 'production_deploy' } }), /metadata.execution.arguments is required/);
});

test('approval fingerprint changes when action or execution arguments change', () => {
  const base = { execution: { tool: 'production_deploy', arguments: { version: 'v1' } } };
  assert.notEqual(fingerprint('production_deploy', base), fingerprint('production_deploy', { execution: { tool: 'production_deploy', arguments: { version: 'v2' } } }));
  assert.notEqual(fingerprint('production_deploy', base), fingerprint('large_financial_action', base));
});

test('audit log query is allowlisted, read-only and normalized', () => {
  assert.equal(ALLOWED_TOOLS.has('get_audit_logs'), true);
  assert.equal(READ_ONLY_TOOLS.has('get_audit_logs'), true);
  assert.deepEqual(validateArgs('get_audit_logs', {
    limit: 25,
    actor_id: 'admin-1',
    tool: 'publish_social_content',
    outcome: 'approval_consumed',
  }), {
    limit: 25,
    actorId: 'admin-1',
    tool: 'publish_social_content',
    outcome: 'approval_consumed',
  });
});

test('approval metadata binds the approval action to the execution tool', () => {
  const metadata = { execution: { tool: 'publish_social_content', arguments: { platform: 'instagram', content: 'Hello' } } };
  assert.deepEqual(assertExecutionMatchesAction('publish_social_content', metadata), metadata);
  assert.throws(() => assertExecutionMatchesAction('send_whatsapp_campaign', metadata), /Approval action does not match execution tool/);
});

test('approval metadata rejects prototype-pollution keys', () => {
  assert.throws(() => normalizeExecutionMetadata({
    execution: {
      tool: 'production_deploy',
      arguments: { constructor: { polluted: true } }
    }
  }), /Unsafe metadata key is not permitted/);
});

test('approval metadata rejects credential-like fields and excessive nesting', () => {
  assert.throws(() => normalizeExecutionMetadata({
    execution: { tool: 'production_deploy', arguments: { api_key: 'should-not-be-here' } }
  }), /Sensitive credentials are not permitted/);
  assert.throws(() => normalizeExecutionMetadata({
    execution: { tool: 'production_deploy', arguments: { nested: { nested: { nested: { nested: { nested: { nested: true } } } } } } }
  }), /too deeply nested/);
});

test('get_approval validates approval id', () => {
  const args = validateArgs('get_approval', { approval_id: 'approval-1' });
  assert.deepEqual(args, { approvalId: 'approval-1' });
});

test('idempotency document is scoped by tool', () => {
  assert.notEqual(idempotencyDocId('create_job', 'same-key'), idempotencyDocId('assign_driver', 'same-key'));
});

test('idempotency fingerprint changes when arguments change', () => {
  assert.notEqual(argumentsFingerprint('create_job', { customerId: 'a', location: 'A' }), argumentsFingerprint('create_job', { customerId: 'a', location: 'B' }));
});

test('Development Agent GitHub analysis is allowlisted and read-only', () => {
  assert.equal(ALLOWED_TOOLS.has('github_analyze'), true);
  assert.equal(READ_ONLY_TOOLS.has('github_analyze'), true);
  assert.deepEqual(validateArgs('github_analyze', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI',
    task: 'inspect CI workflow failures',
  }), {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI',
    task: 'inspect CI workflow failures',
  });
  assert.throws(() => validateArgs('github_analyze', {
    repository: 'example/unauthorized',
    task: 'inspect code',
  }), /repository is required|Repository is not authorized/);
});


test('approval decision remains write-only and approval requester cannot self-approve', () => {
  assert.equal(READ_ONLY_TOOLS.has('decide_approval'), false);
});


test('approval decision state enforces four-eyes, pending-only and expiry rules', () => {
  const now = Date.now();
  const pending = { actorId: 'requester-1', status: 'PENDING', expiresAt: new Date(now + 60000) };
  assert.equal(approvalDecisionState(pending, 'approver-1', true, now), 'APPROVED');
  assert.equal(approvalDecisionState(pending, 'approver-1', false, now), 'REJECTED');
  assert.throws(() => approvalDecisionState(pending, 'requester-1', true, now), /cannot approve or reject their own request/);
  assert.throws(() => approvalDecisionState({ ...pending, status: 'APPROVED' }, 'approver-1', true, now), /already been decided/);
  assert.throws(() => approvalDecisionState({ ...pending, expiresAt: new Date(now - 1) }, 'approver-1', true, now), /expired/);
});

test('approval consumption state enforces approved-only, actor, fingerprint, expiry and one-time boundaries', () => {
  const now = Date.now();
  const current = {
    actorId: 'requester-1',
    status: 'APPROVED',
    actionFingerprint: 'fingerprint-1',
    expiresAt: new Date(now + 60000),
  };
  assert.equal(approvalConsumptionState(current, 'requester-1', 'github_apply_patch', 'fingerprint-1', now), 'CONSUMED');
  assert.throws(() => approvalConsumptionState({ ...current, status: 'PENDING' }, 'requester-1', 'github_apply_patch', 'fingerprint-1', now), /not approved/);
  assert.throws(() => approvalConsumptionState(current, 'other-actor', 'github_apply_patch', 'fingerprint-1', now), /does not match execution actor/);
  assert.throws(() => approvalConsumptionState(current, 'requester-1', 'github_apply_patch', 'different', now), /does not match the requested action or arguments/);
  assert.throws(() => approvalConsumptionState({ ...current, expiresAt: new Date(now - 1) }, 'requester-1', 'github_apply_patch', 'fingerprint-1', now), /expired/);
  assert.throws(() => approvalConsumptionState({ ...current, status: 'CONSUMED' }, 'requester-1', 'github_apply_patch', 'fingerprint-1', now), /not approved/);
});

test('Development Agent blocks unsafe branches, protected paths and credential-like patch content', () => {
  assert.throws(() => validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI', branch: 'ai-dev/../main',
    path: 'src/example.py', content: 'print("ok")', message: 'unsafe', sha: 'abc1234'
  }), /safe ai-dev/);
  assert.throws(() => validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI', branch: 'ai-dev/security',
    path: '.env.production', content: 'print("ok")', message: 'unsafe', sha: 'abc1234'
  }), /protected or secret-bearing/);
  assert.throws(() => validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI', branch: 'ai-dev/security',
    path: 'src/key.py', content: '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----', message: 'unsafe', sha: 'abc1234'
  }), /credential-like/);
  assert.throws(() => validateArgs('github_apply_patch', {
    repository: 'newgoldenterprises1-web/WE-DRIVE-AI', branch: 'ai-dev/security',
    path: 'src/example.py', content: 'print("ok")', message: 'unsafe', sha: 'not-a-sha'
  }), /Git blob SHA/);
});
