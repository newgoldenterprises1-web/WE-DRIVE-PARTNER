const crypto = require('crypto');
const { onRequest } = require('firebase-functions/v2/https');
const { getApps, initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { createBookingForAI, assignBookingForAI } = require('./ai_booking_service');
const { createApproval, getApproval, decideApproval, consumeApproval, normalizeExecutionMetadata } = require('./ai_approval');
const { recordAudit } = require('./ai_audit');
const { idempotencyDocId, argumentsFingerprint, beginIdempotentOperation, completeIdempotentOperation, failIdempotentOperation } = require('./ai_idempotency');

if (!getApps().length) initializeApp();
const db = getFirestore();

const ALLOWED_TOOLS = new Set(['list_bookings', 'list_drivers', 'get_operations_overview', 'get_booking', 'get_available_drivers', 'get_driver_status', 'get_customer', 'create_job', 'assign_driver', 'send_notification', 'get_business_report', 'get_system_health', 'github_analyze', 'get_marketing_status', 'create_social_content', 'publish_social_content', 'send_whatsapp_campaign', 'request_approval', 'get_approval', 'decide_approval', 'execute_approved_action']);
const READ_ONLY_TOOLS = new Set(['list_bookings', 'list_drivers', 'get_booking', 'get_available_drivers', 'get_driver_status', 'get_customer', 'get_business_report', 'get_system_health', 'github_analyze', 'get_marketing_status', 'create_social_content', 'get_approval']);
const ARGUMENT_KEYS = {
  list_bookings: ['status', 'limit'],
  list_drivers: ['online', 'limit'],
  get_operations_overview: ['limit'],
  get_booking: ['booking_id'], get_customer: ['customer_id'], get_driver_status: ['driver_id'],
  get_available_drivers: ['service_date', 'start_time', 'location', 'duration_minutes', 'latitude', 'longitude', 'required_service'],
  create_job: ['customer_id', 'service_date', 'start_time', 'location', 'duration_minutes', 'notes'],
  assign_driver: ['job_id', 'driver_id'], send_notification: ['recipient_id', 'channel', 'message', 'job_id'],
  get_business_report: ['period_start', 'period_end', 'metrics'], get_system_health: [], github_analyze: ['repository', 'task'],
  get_marketing_status: [],
  create_social_content: ['platform', 'content_type', 'topic', 'tone', 'cta', 'media_url'],
  publish_social_content: ['platform', 'content', 'media_url', 'scheduled_at'],
  send_whatsapp_campaign: ['audience', 'message', 'scheduled_at'],
  request_approval: ['action', 'reason', 'metadata'], get_approval: ['approval_id'],
  decide_approval: ['approval_id', 'approved', 'decision_reason'],
  execute_approved_action: ['approval_id', 'action', 'metadata'],
};
function fail(status, message) { const error = new Error(message); error.status = status; throw error; }
function text(value, name, max = 500) { if (typeof value !== 'string' || !value.trim()) fail(400, `${name} is required.`); return value.trim().slice(0, max); }
function optionalText(value, max = 500) { if (value == null) return null; if (typeof value !== 'string') fail(400, 'Invalid text value.'); const v = value.trim(); return v ? v.slice(0, max) : null; }
function finiteNumber(value, name) { const number = Number(value); if (!Number.isFinite(number)) fail(400, `${name} must be a valid number.`); return number; }
function optionalPositiveNumber(value, name) { if (value == null) return null; const number = finiteNumber(value, name); if (number <= 0) fail(400, `${name} must be greater than zero.`); return number; }
function optionalCoordinate(value, name, min, max) { if (value == null) return null; const number = finiteNumber(value, name); if (number < min || number > max) fail(400, `${name} is out of range.`); return number; }
function validateArgs(tool, args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) fail(400, 'arguments must be an object.');
  const allowed = new Set(ARGUMENT_KEYS[tool] || []); const unknown = Object.keys(args).filter((key) => !allowed.has(key));
  if (unknown.length) fail(400, `Unknown argument(s): ${unknown.join(', ')}.`);
  switch (tool) {
    case 'list_bookings': return { status: optionalText(args.status, 40)?.toUpperCase() || null, limit: Math.min(Math.max(Number(args.limit || 50), 1), 100) };
    case 'list_drivers': return { online: args.online !== false, limit: Math.min(Math.max(Number(args.limit || 50), 1), 100) };
    case 'get_booking': return { bookingId: text(args.booking_id, 'booking_id', 160) };
    case 'get_customer': return { customerId: text(args.customer_id, 'customer_id', 160) };
    case 'get_driver_status': return { driverId: text(args.driver_id, 'driver_id', 160) };
    case 'get_available_drivers': return { serviceDate: text(args.service_date, 'service_date', 40), startTime: text(args.start_time, 'start_time', 40), location: text(args.location, 'location', 500), durationMinutes: optionalPositiveNumber(args.duration_minutes, 'duration_minutes'), latitude: optionalCoordinate(args.latitude, 'latitude', -90, 90), longitude: optionalCoordinate(args.longitude, 'longitude', -180, 180), requiredService: optionalText(args.required_service, 80) };
    case 'create_job': return { customerId: text(args.customer_id, 'customer_id', 160), serviceDate: text(args.service_date, 'service_date', 40), startTime: text(args.start_time, 'start_time', 40), location: text(args.location, 'location', 500), durationMinutes: optionalPositiveNumber(args.duration_minutes, 'duration_minutes'), notes: optionalText(args.notes, 1000) };
    case 'assign_driver': return { jobId: text(args.job_id, 'job_id', 160), driverId: text(args.driver_id, 'driver_id', 160) };
    case 'send_notification': return { recipientId: text(args.recipient_id, 'recipient_id', 160), channel: text(args.channel, 'channel', 40).toLowerCase(), message: text(args.message, 'message', 2000), jobId: optionalText(args.job_id, 160) };
    case 'get_business_report': return { periodStart: text(args.period_start, 'period_start', 40), periodEnd: text(args.period_end, 'period_end', 40), metrics: Array.isArray(args.metrics) ? args.metrics.slice(0, 30).map((m) => String(m).slice(0, 80)) : null };
    case 'get_system_health': return {};
    case 'github_analyze': return { repository: githubRepository(args.repository), task: text(args.task, 'task', 2000) };
    case 'get_marketing_status': return {};
    case 'create_social_content': return { platform: text(args.platform, 'platform', 40).toLowerCase(), contentType: text(args.content_type, 'content_type', 40).toLowerCase(), topic: text(args.topic, 'topic', 500), tone: optionalText(args.tone, 80), cta: optionalText(args.cta, 200), mediaUrl: optionalText(args.media_url, 2000) };
    case 'publish_social_content': return { platform: text(args.platform, 'platform', 40).toLowerCase(), content: text(args.content, 'content', 10000), mediaUrl: optionalText(args.media_url, 2000), scheduledAt: optionalText(args.scheduled_at, 80) };
    case 'send_whatsapp_campaign': return { audience: text(args.audience, 'audience', 5000), message: text(args.message, 'message', 4000), scheduledAt: optionalText(args.scheduled_at, 80) };
    case 'request_approval': return { action: text(args.action, 'action', 100), reason: text(args.reason, 'reason', 1000), metadata: args.metadata && typeof args.metadata === 'object' && !Array.isArray(args.metadata) ? args.metadata : {} };
    case 'decide_approval': if (typeof args.approved !== 'boolean') fail(400, 'approved must be a boolean.'); return { approvalId: text(args.approval_id, 'approval_id', 160), approved: args.approved, decisionReason: optionalText(args.decision_reason, 1000) || '' };
    case 'get_approval': return { approvalId: text(args.approval_id, 'approval_id', 160) };
    case 'execute_approved_action': return { approvalId: text(args.approval_id, 'approval_id', 160), action: text(args.action, 'action', 100), metadata: args.metadata && typeof args.metadata === 'object' && !Array.isArray(args.metadata) ? args.metadata : {} };
    default: fail(403, 'Tool is not allowed.');
  }
}
function authenticate(request) { const configured = process.env.WE_DRIVE_AI_GATEWAY_TOKEN; const header = request.get('authorization') || ''; const match = /^Bearer\s+(.+)$/i.exec(header.trim()); const supplied = match ? match[1].trim() : ''; if (!configured || !supplied) fail(401, 'AI gateway authentication failed.'); const expected = Buffer.from(configured); const actual = Buffer.from(supplied); if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) fail(401, 'AI gateway authentication failed.'); }
function idempotencyKey(request) { const key = request.get('x-idempotency-key'); if (!key || key.length > 200) fail(400, 'X-Idempotency-Key is required for write operations.'); return key; }
function actorId(request) { const actor = request.get('x-we-drive-ai-actor-id'); if (!actor || actor.length > 160) fail(400, 'X-WE-DRIVE-AI-Actor-ID is required.'); return actor.trim(); }


function githubRepository(value) {
  const repository = text(value, 'repository', 200);
  const allowed = new Set([
    'newgoldenterprises1-web/WE-DRIVE-AI',
    'newgoldenterprises1-web/WE-DRIVE-PARTNER',
    'newgoldenterprises1-web/WE-DRIVE-CUSTOMER',
  ]);
  if (!allowed.has(repository)) fail(403, 'Repository is not authorized for Development Agent analysis.');
  return repository;
}

async function githubGet(path) {
  const token = process.env.GITHUB_TOKEN;
  if (!token) fail(503, 'GITHUB_TOKEN is not configured.');
  const result = await fetch(`https://api.github.com/${path.replace(/^\/+/, '')}`, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'WE-DRIVE-AI-Development-Agent',
    },
  });
  const payload = await result.json().catch(() => ({}));
  if (!result.ok) {
    const error = new Error(payload?.message || `GitHub API request failed with HTTP ${result.status}.`);
    error.status = result.status >= 400 && result.status < 500 ? 400 : 502;
    throw error;
  }
  return payload;
}

async function githubAnalyze(args) {
  const repository = githubRepository(args.repository);
  const task = text(args.task, 'task', 2000);
  const repo = await githubGet(`repos/${repository}`);
  const branch = repo.default_branch || 'main';
  const [commits, runs, tree] = await Promise.all([
    githubGet(`repos/${repository}/commits?per_page=8`),
    githubGet(`repos/${repository}/actions/runs?per_page=8`),
    githubGet(`repos/${repository}/git/trees/${encodeURIComponent(branch)}?recursive=1`),
  ]);

  const terms = task.toLowerCase().split(/[^a-z0-9_]+/).filter((term) => term.length >= 4).slice(0, 12);
  const paths = Array.isArray(tree.tree) ? tree.tree
    .filter((item) => item.type === 'blob' && typeof item.path === 'string')
    .map((item) => item.path)
    .filter((path) => ['.py', '.js', '.ts', '.tsx', '.json', '.yml', '.yaml', '.md'].some((ext) => path.toLowerCase().endsWith(ext)))
    .filter((path) => terms.some((term) => path.toLowerCase().includes(term)) ||
      path.startsWith('src/') || path.startsWith('functions/') || path.startsWith('ai-office/') || path.startsWith('.github/'))
    .slice(0, 12) : [];

  const files = [];
  for (const path of paths) {
    try {
      const file = await githubGet(`repos/${repository}/contents/${path}?ref=${encodeURIComponent(branch)}`);
      if (file && file.encoding === 'base64' && file.content) {
        const content = Buffer.from(file.content.replace(/\s/g, ''), 'base64').toString('utf8');
        files.push({ path, content: content.slice(0, 12000) });
      }
    } catch (error) {
      files.push({ path, error: error.message });
    }
    if (files.length >= 8) break;
  }

  const workflowRuns = Array.isArray(runs.workflow_runs) ? runs.workflow_runs.slice(0, 8).map((run) => ({
    id: run.id, name: run.name, status: run.status, conclusion: run.conclusion,
    headBranch: run.head_branch, headSha: run.head_sha, createdAt: run.created_at, updatedAt: run.updated_at,
  })) : [];

  return {
    ok: true,
    repository,
    branch,
    task,
    repositoryInfo: {
      private: repo.private === true,
      defaultBranch: branch,
      openIssues: repo.open_issues_count || 0,
      updatedAt: repo.updated_at || null,
    },
    recentCommits: Array.isArray(commits) ? commits.slice(0, 8).map((commit) => ({
      sha: commit.sha,
      message: String(commit.commit?.message || '').split('\n')[0].slice(0, 300),
      author: commit.commit?.author?.name || commit.author?.login || null,
      date: commit.commit?.author?.date || null,
    })) : [],
    workflowRuns,
    relevantFiles: files,
    writeAccess: false,
    note: 'Development Agent analysis is read-only. Code changes, branch creation, commits, and deployments require a separate approved workflow.',
  };
}

async function graphPost(path, token, body) {
  if (!token) fail(503, 'Meta/WhatsApp integration is not configured.');
  const version = process.env.META_GRAPH_VERSION;
  if (!version) fail(503, 'META_GRAPH_VERSION is not configured.');
  const url = `https://graph.facebook.com/${version}/${path.replace(/^\/+/, '')}`;
  const result = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await result.json().catch(() => ({}));
  if (!result.ok) {
    const error = new Error(payload?.error?.message || `Meta API request failed with HTTP ${result.status}.`);
    error.status = result.status >= 400 && result.status < 500 ? 400 : 502;
    throw error;
  }
  return payload;
}

async function publishApprovedSocialContent(args) {
  const platform = args.platform;
  if (platform === 'instagram') {
    const token = process.env.META_ACCESS_TOKEN;
    const igUserId = process.env.META_IG_USER_ID;
    if (!igUserId) fail(503, 'META_IG_USER_ID is not configured.');
    if (!args.mediaUrl) fail(400, 'Instagram publishing requires media_url.');
    const media = await graphPost(`${igUserId}/media`, token, { image_url: args.mediaUrl, caption: args.content });
    if (!media.id) fail(502, 'Instagram media container was not created.');
    return { ok: true, platform, provider: 'meta', mediaContainerId: media.id, publish: await graphPost(`${igUserId}/media_publish`, token, { creation_id: media.id }) };
  }
  if (platform === 'facebook') {
    const token = process.env.META_PAGE_ACCESS_TOKEN || process.env.META_ACCESS_TOKEN;
    const pageId = process.env.META_PAGE_ID;
    if (!pageId) fail(503, 'META_PAGE_ID is not configured.');
    const body = args.mediaUrl ? { message: args.content, link: args.mediaUrl } : { message: args.content };
    return { ok: true, platform, provider: 'meta', publish: await graphPost(`${pageId}/feed`, token, body) };
  }
  fail(400, 'Unsupported social platform. Use instagram or facebook.');
}

async function sendApprovedWhatsAppCampaign(args) {
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  if (!phoneNumberId) fail(503, 'WHATSAPP_PHONE_NUMBER_ID is not configured.');
  if (!token) fail(503, 'WHATSAPP_ACCESS_TOKEN is not configured.');
  const recipients = args.audience.split(',').map((value) => value.trim()).filter(Boolean);
  if (!recipients.length) fail(400, 'WhatsApp audience must contain at least one recipient.');
  if (recipients.length > 100) fail(400, 'WhatsApp campaign is limited to 100 recipients per approved execution.');
  const results = [];
  for (const to of recipients) {
    if (!/^\+[1-9]\d{7,14}$/.test(to)) fail(400, 'WhatsApp recipients must use E.164 format.');
    results.push(await graphPost(`${phoneNumberId}/messages`, token, {
      messaging_product: 'whatsapp',
      to,
      type: 'text',
      text: { body: args.message },
    }));
  }
  return { ok: true, platform: 'whatsapp', provider: 'meta', recipients: recipients.length, results };
}

async function executeApprovedAction(args, actor) {
  const safeMetadata = normalizeExecutionMetadata(args.metadata);
  if (safeMetadata.execution.tool !== args.action) {
    fail(409, 'Approval action does not match execution tool.');
  }
  // Critical executors are deliberately explicit. No critical action is executable until
  // its server-side executor is registered and independently reviewed.
  const executors = Object.freeze({
    publish_social_content: publishApprovedSocialContent,
    send_whatsapp_campaign: sendApprovedWhatsAppCampaign,
  });
  const executor = executors[args.action];
  if (typeof executor !== 'function') {
    const error = new Error(`No approved executor is registered for critical action: ${args.action}.`);
    error.status = 501;
    throw error;
  }
  // consumeApproval is the final authorization boundary: exact actor + action + arguments,
  // approved state, TTL and one-time consumption are checked transactionally before execution.
  await consumeApproval({ approvalId: args.approvalId, actorId: actor, action: args.action, metadata: safeMetadata });
  return executor(safeMetadata.execution.arguments);
}

async function runTool(tool, args, actor) {
  if (tool === 'request_approval') return createApproval({ actorId: actor, action: args.action, reason: args.reason, metadata: args.metadata });
  if (tool === 'get_approval') return getApproval(args.approvalId);
  if (tool === 'decide_approval') return decideApproval({ approvalId: args.approvalId, approverId: actor, approved: args.approved, decisionReason: args.decisionReason || '' });
  if (tool === 'execute_approved_action') return executeApprovedAction(args, actor);
  if (tool === 'github_analyze') return githubAnalyze(args);
  if (tool === 'get_operations_overview') {
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
    const dayStart = new Date(today + 'T00:00:00+05:30');
    const limit = Math.min(Math.max(Number(args.limit || 100), 1), 100);
    const snap = await db.collection('bookings').where('createdAt', '>=', Timestamp.fromDate(dayStart)).limit(limit).get();
    const normalize = (v) => String(v || '').trim().toUpperCase();
    const activeStatuses = new Set(['ACCEPTED', 'ASSIGNED', 'DRIVER_ASSIGNED', 'EN_ROUTE', 'STARTED', 'IN_PROGRESS', 'ONGOING', 'ARRIVED']);
    const pendingStatuses = new Set(['PENDING', 'REQUESTED', 'SEARCHING', 'UNASSIGNED', 'PENDING_ASSIGNMENT', 'AWAITING_DRIVER']);
    const completedStatuses = new Set(['COMPLETED', 'COMPLETE']);
    const cancelledStatuses = new Set(['CANCELLED', 'CANCELED']);
    let activeJobs = 0, pendingJobs = 0, completedJobs = 0, cancelledJobs = 0;
    const active = [], pending = [], alerts = [];
    for (const doc of snap.docs) {
      const b = doc.data() || {};
      const status = normalize(b.status);
      const item = { id: doc.id, status: status || 'UNKNOWN', driverId: b.driverId || b.partnerId || null, pickupLocation: b.pickupLocation || b.location || null, fare: Number(b.fare || 0) };
      if (activeStatuses.has(status)) { activeJobs += 1; active.push(item); }
      else if (pendingStatuses.has(status)) { pendingJobs += 1; pending.push(item); alerts.push({ id: doc.id, status, reason: 'Pending or unassigned job needs attention.' }); }
      else if (completedStatuses.has(status)) completedJobs += 1;
      else if (cancelledStatuses.has(status)) { cancelledJobs += 1; alerts.push({ id: doc.id, status, reason: 'Cancelled job recorded today.' }); }
    }
    return { ok: true, date: today, summary: { activeJobs, pendingJobs, completedJobs, cancelledJobs, alerts: alerts.length }, activeJobs: active.slice(0, 50), pendingJobs: pending.slice(0, 50), alerts: alerts.slice(0, 50) };
  }
  if (tool === 'get_marketing_status') {
    return {
      ok: true,
      channels: {
        facebook: { configured: Boolean(process.env.META_PAGE_ID && (process.env.META_PAGE_ACCESS_TOKEN || process.env.META_ACCESS_TOKEN)) },
        instagram: { configured: Boolean(process.env.META_IG_USER_ID && process.env.META_ACCESS_TOKEN) },
        whatsapp: { configured: Boolean(process.env.WHATSAPP_PHONE_NUMBER_ID && process.env.WHATSAPP_ACCESS_TOKEN) },
      },
      publishing: 'approval_required',
      note: 'Secrets remain server-side; publishing and WhatsApp sending require an approved execution.',
    };
  }
  if (tool === 'create_social_content') {
    return {
      ok: true,
      draft: {
        platform: args.platform,
        contentType: args.contentType,
        topic: args.topic,
        tone: args.tone,
        cta: args.cta,
        mediaUrl: args.mediaUrl,
      },
      publish: 'not_published',
    };
  }
  if (tool === 'get_system_health') {
    const today = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Kolkata',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());

    // Count bookings created today, including immediate jobs where bookingDate is null.
    const dayStart = new Date(today + 'T00:00:00+05:30');
    const [todayBookingsSnap, onlineDriversSnap] = await Promise.all([
      db.collection('bookings').where('createdAt', '>=', Timestamp.fromDate(dayStart)).limit(500).get(),
      db.collection('partners').where('online', '==', true).limit(500).get(),
    ]);

    const bookings = todayBookingsSnap.docs.map((doc) => doc.data() || {});
    const normalizedStatus = (value) => String(value || '').trim().toUpperCase();
    const activeStatuses = new Set([
      'ACCEPTED', 'ASSIGNED', 'DRIVER_ASSIGNED', 'EN_ROUTE',
      'STARTED', 'IN_PROGRESS', 'ONGOING', 'ARRIVED',
    ]);
    const pendingStatuses = new Set([
      'PENDING', 'REQUESTED', 'SEARCHING', 'UNASSIGNED',
      'PENDING_ASSIGNMENT', 'AWAITING_DRIVER',
    ]);
    const cancelledStatuses = new Set(['CANCELLED', 'CANCELED']);
    const completedStatuses = new Set(['COMPLETED', 'COMPLETE']);

    let activeJobs = 0;
    let pendingJobs = 0;
    let completedJobs = 0;
    let cancelledJobs = 0;

    for (const booking of bookings) {
      const status = normalizedStatus(booking.status);
      if (activeStatuses.has(status)) activeJobs += 1;
      else if (pendingStatuses.has(status)) pendingJobs += 1;
      else if (completedStatuses.has(status)) completedJobs += 1;
      else if (cancelledStatuses.has(status)) cancelledJobs += 1;
    }

    return {
      ok: true,
      firestore: 'ok',
      region: 'asia-south1',
      date: today,
      summary: {
        todaysBookings: bookings.length,
        activeJobs,
        driversOnline: onlineDriversSnap.size,
        pendingJobs,
        completedJobs,
        cancelledJobs,
        alerts: pendingJobs + cancelledJobs,
      },
    };
  }
  if (tool === 'list_bookings') {
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
    const dayStart = new Date(today + 'T00:00:00+05:30');
    const snap = await db.collection('bookings').where('createdAt', '>=', Timestamp.fromDate(dayStart)).limit(args.limit).get();
    const normalize = (v) => String(v || '').trim().toUpperCase();
    const bookings = snap.docs
      .map(doc => {
        const b = doc.data() || {};
        return {
          id: doc.id,
          status: normalize(b.status) || 'UNKNOWN',
          customerId: b.customerId || b.userId || null,
          driverId: b.driverId || b.partnerId || null,
          pickupLocation: b.pickupLocation || b.location || null,
          bookingDate: b.bookingDate || null,
          startTime: b.startTime || null,
          fare: Number(b.fare || 0),
          createdAt: b.createdAt || null,
        };
      })
      .filter(b => !args.status || b.status === args.status)
      .sort((a,b) => String(b.id).localeCompare(String(a.id)));
    return { ok: true, date: today, bookings };
  }
  if (tool === 'list_drivers') {
    const limit = Math.min(Math.max(Number(args.limit || 50), 1), 100);
    const onlineOnly = args.online !== false;
    const query = db.collection('partners');
    const snap = onlineOnly
      ? await query.where('online', '==', true).limit(limit).get()
      : await query.limit(limit).get();
    const drivers = snap.docs.map((doc) => {
      const d = doc.data() || {};
      return {
        id: doc.id,
        name: d.name || d.fullName || 'WE DRIVE Chauffeur',
        online: d.online === true,
        verified: d.verified === true || d.verificationStatus === 'VERIFIED',
        rating: Number(d.rating || 0),
        lastSeenAt: d.lastSeenAt || null,
        latitude: d.latitude ?? null,
        longitude: d.longitude ?? null,
      };
    });
    return { ok: true, onlineOnly, drivers };
  }
  if (tool === 'get_booking') { const snap = await db.collection('bookings').doc(args.bookingId).get(); if (!snap.exists) fail(404, 'Booking not found.'); return { ok: true, booking: { id: snap.id, ...snap.data() } }; }
  if (tool === 'get_customer') {
    const [u, p] = await Promise.all([db.collection('users').doc(args.customerId).get(), db.collection('profiles').doc(args.customerId).get()]);
    if (!u.exists && !p.exists) fail(404, 'Customer not found.');
    const user = u.data() || {}, profile = p.data() || {};
    const rawPhone = user.phoneNumber || profile.phoneNumber || user.phone || profile.phone || '';
    const phone = String(rawPhone || '');
    const maskedPhone = phone ? (phone.length > 4 ? `${phone.slice(0, 2)}******${phone.slice(-2)}` : '****') : null;
    return { ok: true, customer: {
      id: args.customerId,
      name: user.name || user.fullName || profile.name || profile.fullName || null,
      email: user.email || profile.email || null,
      phone: maskedPhone,
      city: user.city || profile.city || null,
      status: user.status || profile.status || null,
      createdAt: user.createdAt || profile.createdAt || null,
    } };
  }
  if (tool === 'get_driver_status') { const snap = await db.collection('partners').doc(args.driverId).get(); if (!snap.exists) fail(404, 'Driver not found.'); const d = snap.data() || {}; return { ok: true, driver: { id: snap.id, online: d.online === true, lastSeenAt: d.lastSeenAt || null, latitude: d.latitude ?? null, longitude: d.longitude ?? null } }; }
  if (tool === 'get_available_drivers') { const snap = await db.collection('partners').where('online', '==', true).limit(50).get(); const drivers = snap.docs.map((doc) => { const d = doc.data() || {}; return { id: doc.id, name: d.name || d.fullName || 'WE DRIVE Chauffeur', phoneNumber: d.phoneNumber || null, rating: Number(d.rating || 0), latitude: d.latitude ?? null, longitude: d.longitude ?? null, verified: d.verified === true }; }); return { ok: true, serviceDate: args.serviceDate, startTime: args.startTime, durationMinutes: args.durationMinutes, location: args.location, requestedLatitude: args.latitude, requestedLongitude: args.longitude, requiredService: args.requiredService, drivers }; }
  if (tool === 'create_job') return createBookingForAI(args);
  if (tool === 'assign_driver') return assignBookingForAI({ bookingId: args.jobId, driverId: args.driverId });
  if (tool === 'send_notification') { if (!new Set(['in_app', 'push', 'whatsapp']).has(args.channel)) fail(400, 'Unsupported notification channel.'); const ref = await db.collection('notifications').add({ userId: args.recipientId, type: 'ai', channel: args.channel, message: args.message, bookingId: args.jobId || null, read: false, source: 'AI_GATEWAY', createdAt: FieldValue.serverTimestamp() }); return { ok: true, notificationId: ref.id }; }
  if (tool === 'get_business_report') {
    const periodStart = text(args.periodStart, 'period_start', 40);
    const periodEnd = text(args.periodEnd, 'period_end', 40);
    const snap = await db.collection('bookings')
      .where('bookingDate', '>=', periodStart)
      .where('bookingDate', '<=', periodEnd)
      .limit(500)
      .get();
    const bookings = snap.docs.map((doc) => doc.data() || {});
    const status = (b) => String(b.status || '').trim().toUpperCase();
    const completed = bookings.filter((b) => status(b) === 'COMPLETED' || status(b) === 'COMPLETE').length;
    const cancelled = bookings.filter((b) => status(b) === 'CANCELLED' || status(b) === 'CANCELED').length;
    const activeStatuses = new Set(['ACCEPTED', 'ASSIGNED', 'DRIVER_ASSIGNED', 'EN_ROUTE', 'STARTED', 'IN_PROGRESS', 'ONGOING', 'ARRIVED']);
    const pendingStatuses = new Set(['PENDING', 'REQUESTED', 'SEARCHING', 'UNASSIGNED', 'PENDING_ASSIGNMENT', 'AWAITING_DRIVER']);
    const active = bookings.filter((b) => activeStatuses.has(status(b))).length;
    const pending = bookings.filter((b) => pendingStatuses.has(status(b))).length;
    const requested = bookings.length;
    const revenue = bookings.reduce((sum, b) => sum + Math.max(0, Number(b.fare || 0)), 0);
    return {
      ok: true,
      periodStart,
      periodEnd,
      metrics: {
        bookings: requested,
        completed,
        cancelled,
        pending,
        active,
        grossFare: revenue,
        averageFare: requested ? revenue / requested : 0,
      },
    };
  }
  fail(403, 'Tool is not allowed.');
}
async function executeWrite(tool, args, actor, key, requestId, response) {
  const operation = await beginIdempotentOperation({ tool, key, actor, args });
  if (operation.replay) {
    response.status(200).json({ ...operation.response, replayed: true, requestId });
    return true;
  }
  try {
    const result = await runTool(tool, args, actor);
    await completeIdempotentOperation(operation.ref, result);
    response.status(200).json({ ...result, requestId });
    return true;
  } catch (error) {
    await failIdempotentOperation(operation.ref, error).catch((persistError) => console.error('WE DRIVE AI idempotency failure persistence failed', { requestId, message: persistError.message }));
    throw error;
  }
}
exports.aiGateway = onRequest({ region: 'asia-south1' }, async (request, response) => {
  const requestId = request.get('x-we-drive-ai-request-id') || crypto.randomUUID();
  let auditTool = request.body?.tool || null;
  let auditActor = null;
  response.on('finish', () => {
    recordAudit({ requestId, actorId: auditActor, tool: auditTool, status: response.statusCode, outcome: response.statusCode >= 400 ? 'error' : 'success' }).catch((auditError) => console.error('WE DRIVE AI audit logging failed', { requestId, message: auditError.message }));
  });
  try {
    authenticate(request);
    if (request.method !== 'POST') fail(405, 'POST is required.');
    if (Number(request.get('content-length') || 0) > 1024 * 1024) fail(413, 'Request body is too large.');
    const tool = request.body?.tool;
    auditTool = tool || null;
    if (!ALLOWED_TOOLS.has(tool)) fail(403, 'Tool is not allowed.');
    const args = validateArgs(tool, request.body?.arguments || {});
    // Every AI tool request carries the authenticated office actor so the
    // gateway can audit and authorize read operations as well as writes.
    const actor = actorId(request);
    auditActor = actor;
    if (tool === 'get_approval') {
      const result = await runTool(tool, args, actor);
      response.status(200).json({ ...result, requestId });
      return;
    }
    if (!READ_ONLY_TOOLS.has(tool)) {
      const key = idempotencyKey(request);
      await executeWrite(tool, args, actor, key, requestId, response);
      return;
    }
    const result = await runTool(tool, args, actor);
    response.status(200).json({ ...result, requestId });
  } catch (error) {
    const status = Number(error.status) || 500;
    console.error('WE DRIVE AI gateway error', { requestId, status, message: error.message });
    response.status(status).json({ ok: false, error: error.message || 'Internal gateway error.', requestId });
  }
});
exports._test = { validateArgs, authenticate, ALLOWED_TOOLS, READ_ONLY_TOOLS, idempotencyDocId, argumentsFingerprint, consumeApproval, executeApprovedAction };
