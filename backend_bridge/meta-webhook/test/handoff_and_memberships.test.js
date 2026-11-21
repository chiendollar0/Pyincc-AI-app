'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const Module = require('node:module');

// Minimal valid JPEG magic-byte buffer for capture tests
const SAMPLE_JPEG_BASE64 = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xd9,
]).toString('base64');

function makeFakeJwt(sub) {
  const h = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const p = Buffer.from(JSON.stringify({ sub, exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url');
  return `${h}.${p}.sig`;
}

function createMockEnv() {
  const state = {
    usersByToken: {},
    tables: {
      memberships: [],
      handoff_cases: [],
      connected_pages: [],
      catalog_items: [],
      audit_logs: [],
      organizations: [{ id: 'org-1', name: 'PYINCC Test Salon' }],
    },
    uploads: [],
    axiosCalls: [],
    geminiResponse: {
      summary: 'Khách cần tư vấn dáng mày tự nhiên',
      risk: 'low',
      face_detected: true,
      recommended_item_id: '1',
      draft_reply: 'Dạ mẫu Mày sợi Hairstroke rất hợp dáng mặt chị ạ.',
    },
    metaError: null,
  };

  function encryptToken(plain, encKey) {
    const key = crypto.createHash('sha256').update(String(encKey)).digest();
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `v1:${iv.toString('base64')}:${tag.toString('base64')}:${enc.toString('base64')}`;
  }

  function buildQuery(tableName) {
    const filters = [];
    let action = 'select';
    let payload = null;
    let selectOpts = {};
    let singleMode = null;
    let orderSpec = null;
    let limitNum = null;

    const matchRows = () => (state.tables[tableName] || []).filter((row) =>
      filters.every((fn) => fn(row)),
    );

    const exec = async () => {
      if (!state.tables[tableName]) state.tables[tableName] = [];
      if (action === 'select') {
        let rows = matchRows().map((r) => ({ ...r }));
        if (orderSpec) {
          rows.sort((a, b) => {
            const av = String(a[orderSpec.col] || '');
            const bv = String(b[orderSpec.col] || '');
            return orderSpec.ascending ? av.localeCompare(bv) : bv.localeCompare(av);
          });
        }
        if (typeof limitNum === 'number') rows = rows.slice(0, limitNum);
        if (selectOpts.head && selectOpts.count === 'exact') {
          return { data: null, count: rows.length, error: null };
        }
        if (singleMode === 'maybeSingle') return { data: rows[0] || null, error: null };
        if (singleMode === 'single') {
          return rows[0] ? { data: rows[0], error: null } : { data: null, error: { message: 'not found' } };
        }
        return { data: rows, count: rows.length, error: null };
      }

      if (action === 'insert') {
        const items = Array.isArray(payload) ? payload : [payload];
        const inserted = items.map((item) => {
          const row = {
            id: item.id || crypto.randomUUID(),
            created_at: item.created_at || new Date().toISOString(),
            ...item,
          };
          state.tables[tableName].push(row);
          return { ...row };
        });
        if (singleMode === 'single' || singleMode === 'maybeSingle') {
          return { data: inserted[0], error: null };
        }
        return { data: inserted, error: null };
      }

      if (action === 'update') {
        const matched = matchRows();
        const updated = matched.map((row) => {
          Object.assign(row, payload);
          return { ...row };
        });
        if (singleMode === 'maybeSingle') return { data: updated[0] || null, error: null };
        if (singleMode === 'single') {
          return updated[0] ? { data: updated[0], error: null } : { data: null, error: { message: 'not found' } };
        }
        return { data: updated, error: null };
      }

      if (action === 'delete') {
        const matched = matchRows();
        const matchedSet = new Set(matched);
        state.tables[tableName] = (state.tables[tableName] || []).filter((r) => !matchedSet.has(r));
        const deleted = matched.map((r) => ({ ...r }));
        if (singleMode === 'maybeSingle') return { data: deleted[0] || null, error: null };
        if (singleMode === 'single') {
          return deleted[0] ? { data: deleted[0], error: null } : { data: null, error: { message: 'not found' } };
        }
        return { data: deleted, error: null };
      }

      return { data: null, error: null };
    };

    const q = {
      select(_cols, opts = {}) {
        if (action === 'select') selectOpts = opts || {};
        return q;
      },
      insert(data) {
        action = 'insert';
        payload = data;
        return q;
      },
      update(data) {
        action = 'update';
        payload = data;
        return q;
      },
      delete() {
        action = 'delete';
        return q;
      },
      eq(col, val) {
        filters.push((r) => String(r[col] ?? '') === String(val ?? ''));
        return q;
      },
      neq(col, val) {
        filters.push((r) => String(r[col] ?? '') !== String(val ?? ''));
        return q;
      },
      is(col, val) {
        filters.push((r) => (val === null ? (r[col] === null || r[col] === undefined) : r[col] === val));
        return q;
      },
      gte(col, val) {
        filters.push((r) => String(r[col] ?? '') >= String(val ?? ''));
        return q;
      },
      lte(col, val) {
        filters.push((r) => String(r[col] ?? '') <= String(val ?? ''));
        return q;
      },
      or(expr) {
        const evalLeaf = (row, leaf) => {
          const parts = leaf.split('.');
          const col = parts[0];
          const op = parts[1];
          const val = parts.slice(2).join('.');
          if (op === 'eq') return String(row[col] ?? '') === val;
          if (op === 'lte') return row[col] != null && String(row[col]) <= val;
          if (op === 'gte') return row[col] != null && String(row[col]) >= val;
          if (op === 'is' && val === 'null') return row[col] === null || row[col] === undefined;
          return true;
        };
        const splitTop = (s) => {
          const out = [];
          let depth = 0;
          let cur = '';
          for (const ch of s) {
            if (ch === '(') depth += 1;
            else if (ch === ')') depth -= 1;
            if (ch === ',' && depth === 0) {
              out.push(cur);
              cur = '';
            } else {
              cur += ch;
            }
          }
          if (cur) out.push(cur);
          return out;
        };
        const branches = splitTop(expr);
        filters.push((row) => branches.some((b) => {
          if (b.startsWith('and(') && b.endsWith(')')) {
            return splitTop(b.slice(4, -1)).every((leaf) => evalLeaf(row, leaf));
          }
          return evalLeaf(row, b);
        }));
        return q;
      },
      in(col, list) {
        const set = new Set(list.map(String));
        filters.push((r) => set.has(String(r[col] ?? '')));
        return q;
      },
      order(col, opts = {}) {
        orderSpec = { col, ascending: opts.ascending !== false };
        return q;
      },
      limit(n) {
        limitNum = n;
        return q;
      },
      maybeSingle() {
        singleMode = 'maybeSingle';
        return exec();
      },
      single() {
        singleMode = 'single';
        return exec();
      },
      then(resolve, reject) {
        return exec().then(resolve, reject);
      },
    };
    return q;
  }

  const supabaseStub = {
    auth: {
      async getUser(token) {
        const u = state.usersByToken[token];
        if (!u) return { data: { user: null }, error: { message: 'Invalid token' } };
        return { data: { user: u }, error: null };
      },
    },
    from(tableName) {
      return buildQuery(tableName);
    },
    storage: {
      from() {
        return {
          async upload(path, buffer, opts) {
            state.uploads.push({ path, size: buffer.length, contentType: opts?.contentType });
            return { error: null };
          },
          async createSignedUrl(path) {
            return { data: { signedUrl: `https://signed.local/${path}` }, error: null };
          },
          async download() {
            return { data: null, error: { message: 'not mocked' } };
          },
        };
      },
    },
  };

  const routes = [];
  function makeExpress() {
    const app = {
      settings: {},
      disable() {},
      set(k, v) { this.settings[k] = v; },
      use() {},
      get(path, ...handlers) { routes.push({ method: 'GET', path, handlers }); },
      post(path, ...handlers) { routes.push({ method: 'POST', path, handlers }); },
      put(path, ...handlers) { routes.push({ method: 'PUT', path, handlers }); },
      patch(path, ...handlers) { routes.push({ method: 'PATCH', path, handlers }); },
      delete(path, ...handlers) { routes.push({ method: 'DELETE', path, handlers }); },
    };
    return app;
  }
  makeExpress.json = () => (_req, _res, next) => next();
  makeExpress.urlencoded = () => (_req, _res, next) => next();
  makeExpress.raw = () => (_req, _res, next) => next();

  const axiosStub = {
    async post(url, body, opts) {
      state.axiosCalls.push({ method: 'POST', url, body, opts });
      if (url.includes('generativelanguage.googleapis.com')) {
        return {
          data: {
            candidates: [{ content: { parts: [{ text: JSON.stringify(state.geminiResponse) }] } }],
          },
        };
      }
      if (url.includes('graph.facebook.com')) {
        if (state.metaError) throw state.metaError;
        return { data: { message_id: 'm_test_1' } };
      }
      return { data: {} };
    },
    async get(url) {
      state.axiosCalls.push({ method: 'GET', url });
      return { data: {} };
    },
  };

  const origLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === 'express') return makeExpress;
    if (request === 'express-rate-limit') return () => (_req, _res, next) => next();
    if (request === 'axios') return axiosStub;
    if (request === '@supabase/supabase-js') return { createClient: () => supabaseStub };
    return origLoad.call(this, request, parent, isMain);
  };

  process.env.NODE_ENV = 'test';
  process.env.SUPABASE_URL = 'https://test.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-role';
  process.env.META_APP_ID = '1555273769742937';
  process.env.META_APP_SECRET = 'test-meta-secret';
  process.env.VERIFY_TOKEN = 'test-verify-token';
  process.env.PAGE_TOKEN_ENC_KEY = 'test-enc-key';
  process.env.GEMINI_API_KEY = 'test-gemini-key';

  const indexPath = require.resolve('../index.js');
  delete require.cache[indexPath];
  process.removeAllListeners('unhandledRejection');
  const mod = require('../index.js');
  Module._load = origLoad;

  function matchRoute(method, fullPath) {
    const [pathname, qs] = fullPath.split('?');
    const query = Object.fromEntries(new URLSearchParams(qs || '').entries());
    for (const r of routes) {
      if (r.method !== method) continue;
      const rParts = r.path.split('/').filter(Boolean);
      const pParts = pathname.split('/').filter(Boolean);
      if (rParts.length !== pParts.length) continue;
      const params = {};
      let ok = true;
      for (let i = 0; i < rParts.length; i += 1) {
        if (rParts[i].startsWith(':')) {
          params[rParts[i].slice(1)] = decodeURIComponent(pParts[i]);
        } else if (rParts[i] !== pParts[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return { route: r, params, query };
    }
    throw new Error(`No route matched ${method} ${fullPath}`);
  }

  async function invoke(method, fullPath, { token = null, body = {} } = {}) {
    const { route, params, query } = matchRoute(method, fullPath);
    const headers = {};
    if (token) headers.authorization = `Bearer ${token}`;
    const req = {
      method,
      path: fullPath,
      params,
      query,
      body,
      get(name) { return headers[String(name).toLowerCase()]; },
    };
    let finishHandler = null;
    const markFinished = () => {
      res.finished = true;
      if (finishHandler) {
        const fn = finishHandler;
        finishHandler = null;
        fn();
      }
    };
    const res = {
      statusCode: 200,
      contentType: 'application/json',
      body: null,
      finished: false,
      status(code) { this.statusCode = code; return this; },
      type(t) { this.contentType = t; return this; },
      json(data) { this.body = data; markFinished(); return this; },
      send(data) { this.body = data; markFinished(); return this; },
      sendStatus(code) { this.statusCode = code; markFinished(); return this; },
    };

    for (const handler of route.handlers) {
      if (res.finished) break;
      await new Promise((resolve, reject) => {
        let settled = false;
        const done = (err) => {
          if (settled) return;
          settled = true;
          finishHandler = null;
          if (err) reject(err);
          else resolve();
        };
        finishHandler = () => done();
        try {
          const ret = handler(req, res, (err) => done(err));
          if (ret && typeof ret.then === 'function') {
            ret.then(() => {
              if (res.finished) done();
            }, done);
          } else if (res.finished) {
            done();
          }
        } catch (err) {
          done(err);
        }
      });
    }
    return res;
  }

  // Seed default active owner, active staff, revoked staff, catalog & encrypted page
  const ownerToken = makeFakeJwt('user-owner');
  const staffToken = makeFakeJwt('user-staff');
  const revokedToken = makeFakeJwt('user-revoked');

  state.usersByToken[ownerToken] = {
    id: 'user-owner',
    email: 'owner@salon.vn',
    email_confirmed_at: '2026-01-01T00:00:00Z',
  };
  state.usersByToken[staffToken] = {
    id: 'user-staff',
    email: 'staff@salon.vn',
    email_confirmed_at: '2026-01-01T00:00:00Z',
  };
  state.usersByToken[revokedToken] = {
    id: 'user-revoked',
    email: 'revoked@salon.vn',
    email_confirmed_at: '2026-01-01T00:00:00Z',
  };

  state.tables.memberships.push(
    {
      id: 'mem-owner',
      org_id: 'org-1',
      user_id: 'user-owner',
      invited_email: 'owner@salon.vn',
      role: 'owner',
      status: 'active',
      created_at: '2026-11-01T00:00:00Z',
    },
    {
      id: 'mem-staff',
      org_id: 'org-1',
      user_id: 'user-staff',
      invited_email: 'staff@salon.vn',
      role: 'staff',
      status: 'active',
      created_at: '2026-11-02T00:00:00Z',
    },
    {
      id: 'mem-revoked',
      org_id: 'org-1',
      user_id: 'user-revoked',
      invited_email: 'revoked@salon.vn',
      role: 'staff',
      status: 'revoked',
      created_at: '2026-11-03T00:00:00Z',
    },
  );

  state.tables.catalog_items.push(
    { id: '1', org_id: 'org-1', name: 'Mày sợi Hairstroke', category: 'eyebrow', price: 3500000 },
  );

  state.tables.connected_pages.push({
    org_id: 'org-1',
    page_id: 'page-test-1',
    page_name: 'PYINCC Test Page',
    page_access_token: encryptToken('EAAG-test-page-token', process.env.PAGE_TOKEN_ENC_KEY),
  });

  return { state, mod, invoke, tokens: { ownerToken, staffToken, revokedToken } };
}

test('Luồng B1-B3: capture -> pending_review (no send) -> send before approve (403) -> approve (no send) -> send once (200) -> duplicate send (409)', async () => {
  const { state, invoke, tokens } = createMockEnv();

  // 1. Capture creates pending_review case, calls Gemini, NEVER calls Meta Send API
  const capRes = await invoke('POST', '/handoff-cases/capture', {
    token: tokens.ownerToken,
    body: {
      image_base64: SAMPLE_JPEG_BASE64,
      customer_text: 'Khách hỏi dáng mày tự nhiên',
      psid: 'psid-customer-1',
      page_id: 'page-test-1',
    },
  });
  assert.equal(capRes.statusCode, 200);
  assert.equal(capRes.body.status, 'pending_review');
  assert.equal(state.uploads.length, 1);
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('graph.facebook.com')).length, 0);

  const caseId = capRes.body.id;

  // 2. Send BEFORE approve -> 403 NOT_APPROVED
  const earlySend = await invoke('POST', `/handoff-cases/${caseId}/send`, {
    token: tokens.ownerToken,
  });
  assert.equal(earlySend.statusCode, 403);
  assert.equal(earlySend.body.error, 'NOT_APPROVED');
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('graph.facebook.com')).length, 0);

  // 3. Approve by owner -> marks approved + approved_by + audit_log, still does NOT send
  const staffApprove = await invoke('POST', `/handoff-cases/${caseId}/approve`, {
    token: tokens.staffToken,
    body: { draft_reply: 'Staff cannot approve in single-owner v1' },
  });
  assert.equal(staffApprove.statusCode, 403);
  assert.equal(staffApprove.body.error, 'FORBIDDEN_ROLE');

  const approveRes = await invoke('POST', `/handoff-cases/${caseId}/approve`, {
    token: tokens.ownerToken,
    body: { draft_reply: 'Chào chị, bên em tư vấn mẫu Hairstroke tự nhiên ạ.' },
  });
  assert.equal(approveRes.statusCode, 200);
  assert.equal(approveRes.body.status, 'approved');
  const approvedRow = state.tables.handoff_cases.find((r) => r.id === caseId);
  assert.equal(approvedRow.approved_by, 'user-owner');
  assert.ok(approvedRow.approved_at);
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('graph.facebook.com')).length, 0);
  assert.ok(state.tables.audit_logs.some((l) => l.action === 'handoff_case.approve' && l.target_id === caseId));

  // 4. Send after approve -> dispatches once to Meta Send API and marks sent
  const sendRes = await invoke('POST', `/handoff-cases/${caseId}/send`, {
    token: tokens.ownerToken,
  });
  assert.equal(sendRes.statusCode, 200);
  assert.equal(sendRes.body.success, true);
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('graph.facebook.com')).length, 1);
  assert.equal(state.tables.handoff_cases.find((r) => r.id === caseId).status, 'sent');
  assert.ok(state.tables.audit_logs.some((l) => l.action === 'handoff_case.send' && l.target_id === caseId));

  // 5. Duplicate send -> 409 ALREADY_SENDING, no second Meta call
  const dupSend = await invoke('POST', `/handoff-cases/${caseId}/send`, {
    token: tokens.ownerToken,
  });
  assert.equal(dupSend.statusCode, 409);
  assert.equal(dupSend.body.error, 'ALREADY_SENDING');
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('graph.facebook.com')).length, 1);
});

test('Luồng B3: Meta 24h messaging window error maps to 422 OUTSIDE_24H_WINDOW and restores approved status', async () => {
  const { state, invoke, tokens } = createMockEnv();
  state.tables.handoff_cases.push({
    id: 'case-24h',
    org_id: 'org-1',
    source: 'owner_capture',
    page_id: 'page-test-1',
    psid: 'psid-old',
    status: 'approved',
    draft_reply: 'Nội dung đã duyệt',
    approved_by: 'user-owner',
    approved_at: new Date().toISOString(),
    created_at: new Date().toISOString(),
  });
  state.metaError = {
    response: { status: 400, data: { error: { code: 10, error_subcode: 2018278, message: 'Outside 24h window' } } },
  };

  const res = await invoke('POST', '/handoff-cases/case-24h/send', { token: tokens.ownerToken });
  assert.equal(res.statusCode, 422);
  assert.equal(res.body.error, 'OUTSIDE_24H_WINDOW');
  assert.equal(state.tables.handoff_cases.find((r) => r.id === 'case-24h').status, 'approved');
});

test('Luồng B1: 50/day Gemini cap allows exact 50th case and blocks 51st with 429 before uploading image', async () => {
  const { state, invoke, tokens } = createMockEnv();
  const nowIso = new Date().toISOString();

  // Seed 49 completed cases today
  for (let i = 0; i < 49; i += 1) {
    state.tables.handoff_cases.push({
      id: `existing-${i}`,
      org_id: 'org-1',
      source: 'owner_capture',
      status: 'pending_review',
      created_at: nowIso,
    });
  }

  // 50th case MUST succeed (verifies off-by-one fix)
  const fiftieth = await invoke('POST', '/handoff-cases/capture', {
    token: tokens.ownerToken,
    body: { image_base64: SAMPLE_JPEG_BASE64 },
  });
  assert.equal(fiftieth.statusCode, 200);
  assert.equal(fiftieth.body.status, 'pending_review');
  assert.equal(state.uploads.length, 1);

  // 51st case MUST be rejected with 429 AI_DAILY_CAP without uploading or calling Gemini
  const uploadsBefore = state.uploads.length;
  const geminiCallsBefore = state.axiosCalls.filter((c) => c.url.includes('generativelanguage')).length;
  const fiftyFirst = await invoke('POST', '/handoff-cases/capture', {
    token: tokens.ownerToken,
    body: { image_base64: SAMPLE_JPEG_BASE64 },
  });
  assert.equal(fiftyFirst.statusCode, 429);
  assert.equal(fiftyFirst.body.error, 'AI_DAILY_CAP');
  assert.equal(state.uploads.length, uploadsBefore);
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('generativelanguage')).length, geminiCallsBefore);
});

test('Luồng B4 & revoked/non-owner guard: /api/tryon/generate returns 501; revoked & staff accounts are blocked with 403', async () => {
  const { invoke, tokens } = createMockEnv();

  const tryonRes = await invoke('POST', '/api/tryon/generate', {
    token: tokens.ownerToken,
    body: { image_base64: SAMPLE_JPEG_BASE64 },
  });
  assert.equal(tryonRes.statusCode, 501);
  assert.equal(tryonRes.body.error, 'NOT_IMPLEMENTED');

  for (const [method, path, body] of [
    ['POST', '/handoff-cases/capture', { image_base64: SAMPLE_JPEG_BASE64 }],
    ['POST', '/handoff-cases/any-id/approve', { draft_reply: 'test' }],
    ['POST', '/handoff-cases/any-id/send', {}],
  ]) {
    const revokedRes = await invoke(method, path, { token: tokens.revokedToken, body });
    assert.equal(revokedRes.statusCode, 403);
    assert.equal(revokedRes.body.error, 'NO_MEMBERSHIP');

    const staffRes = await invoke(method, path, { token: tokens.staffToken, body });
    assert.equal(staffRes.statusCode, 403);
    assert.equal(staffRes.body.error, 'FORBIDDEN_ROLE');
  }
});

test('Single-owner v1 enforcement: invite/promote/reactivate blocked with 403 SINGLE_OWNER_ONLY; legacy staff revocable; audit_logs owner-only', async () => {
  const { state, invoke, tokens } = createMockEnv();

  // /me returns owner role; non-owner blocked
  const meOwner = await invoke('GET', '/me', { token: tokens.ownerToken });
  assert.equal(meOwner.statusCode, 200);
  assert.equal(meOwner.body.role, 'owner');
  const meStaff = await invoke('GET', '/me', { token: tokens.staffToken });
  assert.equal(meStaff.statusCode, 403);
  assert.equal(meStaff.body.error, 'FORBIDDEN_ROLE');

  // Staff cannot access /memberships or /audit-logs
  assert.equal((await invoke('GET', '/memberships', { token: tokens.staffToken })).statusCode, 403);
  assert.equal((await invoke('GET', '/audit-logs', { token: tokens.staffToken })).statusCode, 403);

  // Inviting additional accounts is locked in single-owner v1
  const inviteRes = await invoke('POST', '/memberships/invite', {
    token: tokens.ownerToken,
    body: { email: 'newstaff@salon.vn' },
  });
  assert.equal(inviteRes.statusCode, 403);
  assert.equal(inviteRes.body.error, 'SINGLE_OWNER_ONLY');

  // Promoting or reactivating via PATCH is locked in single-owner v1
  const promote = await invoke('PATCH', '/memberships/mem-staff', {
    token: tokens.ownerToken,
    body: { role: 'owner' },
  });
  assert.equal(promote.statusCode, 403);
  assert.equal(promote.body.error, 'SINGLE_OWNER_ONLY');

  const reactivate = await invoke('PATCH', '/memberships/mem-revoked', {
    token: tokens.ownerToken,
    body: { status: 'active' },
  });
  assert.equal(reactivate.statusCode, 403);
  assert.equal(reactivate.body.error, 'SINGLE_OWNER_ONLY');

  // Owner cannot revoke self
  const selfRevoke = await invoke('POST', '/memberships/mem-owner/revoke', {
    token: tokens.ownerToken,
  });
  assert.equal(selfRevoke.statusCode, 400);
  assert.equal(selfRevoke.body.error, 'CANNOT_MODIFY_SELF');

  // Owner CAN revoke a legacy non-owner membership and it is logged
  const revoke = await invoke('POST', '/memberships/mem-staff/revoke', {
    token: tokens.ownerToken,
  });
  assert.equal(revoke.statusCode, 200);
  assert.equal(revoke.body.membership.status, 'revoked');

  const auditRes = await invoke('GET', '/audit-logs', { token: tokens.ownerToken });
  assert.equal(auditRes.statusCode, 200);
  assert.ok(auditRes.body.logs.some((l) => l.action === 'membership.revoked'));
  assert.equal(state.tables.memberships.filter((m) => m.role === 'owner' && m.status === 'active').length, 1);
});

test('Giai đoạn 3 - C4: /privacy, /terms, and /data-deletion clarify single-owner model & Facebook removal vs Supabase deletion', async () => {
  const { invoke } = createMockEnv();

  const privacy = await invoke('GET', '/privacy');
  assert.equal(privacy.statusCode, 200);
  assert.match(privacy.body, /Supabase/);
  assert.match(privacy.body, /Google Gemini API/);
  assert.match(privacy.body, /Meta Platforms/);
  assert.match(privacy.body, /\/data-deletion/);
  assert.match(privacy.body, /không tự xóa dữ liệu hội thoại/);
  assert.match(privacy.body, /48 giờ/);

  const deletion = await invoke('GET', '/data-deletion');
  assert.equal(deletion.statusCode, 200);
  assert.match(deletion.body, /không tự xóa dữ liệu hội thoại/);
  assert.match(deletion.body, /phanhungkg03@gmail\.com/);

  const terms = await invoke('GET', '/terms');
  assert.equal(terms.statusCode, 200);
  assert.match(terms.body, /Chủ tiệm duy nhất duyệt/);
  assert.match(terms.body, /Sự đồng ý của khách hàng/);
  assert.match(terms.body, /Google Gemini/);
});

test('Codex fix: concurrent /handoff-cases/:id/analyze atomically claims case so Gemini is called once and 2nd gets 409', async () => {
  const { state, invoke, tokens } = createMockEnv();
  const nowIso = new Date().toISOString();
  for (let i = 0; i < 49; i += 1) {
    state.tables.handoff_cases.push({
      id: `counted-${i}`,
      org_id: 'org-1',
      source: 'owner_capture',
      status: 'pending_review',
      created_at: nowIso,
    });
  }
  state.tables.handoff_cases.push({
    id: 'case-reanalyze',
    org_id: 'org-1',
    source: 'owner_capture',
    customer_text: 'Khách hỏi dáng mày',
    status: 'new',
    created_at: nowIso,
  });

  const [r1, r2] = await Promise.all([
    invoke('POST', '/handoff-cases/case-reanalyze/analyze', { token: tokens.ownerToken }),
    invoke('POST', '/handoff-cases/case-reanalyze/analyze', { token: tokens.ownerToken }),
  ]);
  const statuses = [r1.statusCode, r2.statusCode].sort();
  assert.deepEqual(statuses, [200, 409]);
  assert.equal(state.axiosCalls.filter((c) => c.url.includes('generativelanguage')).length, 1);
});

test('Onboarding claim: confirmed email claims one-time code, creates org + owner + audit_log, blocks reuse & unconfirmed email', async () => {
  const { state, invoke } = createMockEnv();
  const freshToken = makeFakeJwt('user-new-owner');
  const unconfirmedToken = makeFakeJwt('user-unconfirmed');
  state.usersByToken[freshToken] = {
    id: 'user-new-owner',
    email: 'newowner@salon.vn',
    email_confirmed_at: '2026-11-20T00:00:00Z',
  };
  state.usersByToken[unconfirmedToken] = {
    id: 'user-unconfirmed',
    email: 'unconfirmed@salon.vn',
    email_confirmed_at: null,
  };
  state.tables.onboarding_codes = [{
    code: 'SALON2026',
    org_name: 'Linh Beauty Studio',
    org_id: null,
    claimed_by: null,
  }];

  const unconf = await invoke('POST', '/onboarding/claim', {
    token: unconfirmedToken,
    body: { code: 'SALON2026' },
  });
  assert.equal(unconf.statusCode, 403);
  assert.equal(unconf.body.error, 'EMAIL_NOT_CONFIRMED');

  const ok = await invoke('POST', '/onboarding/claim', {
    token: freshToken,
    body: { code: 'salon2026' },
  });
  assert.equal(ok.statusCode, 200);
  assert.equal(ok.body.role, 'owner');
  assert.equal(ok.body.org_name, 'Linh Beauty Studio');
  assert.ok(state.tables.audit_logs.some((l) => l.action === 'onboarding.claim'));

  const secondToken = makeFakeJwt('user-second');
  state.usersByToken[secondToken] = {
    id: 'user-second',
    email: 'second@salon.vn',
    email_confirmed_at: '2026-11-20T00:00:00Z',
  };
  const reused = await invoke('POST', '/onboarding/claim', {
    token: secondToken,
    body: { code: 'SALON2026' },
  });
  assert.equal(reused.statusCode, 409);
  assert.equal(reused.body.error, 'ONBOARDING_CODE_ALREADY_USED');
});

test('Price-free /catalog CRUD: owner manages items with audit_logs; non-owner blocked with 403 on read & write', async () => {
  const { state, invoke, tokens } = createMockEnv();

  const staffRead = await invoke('GET', '/catalog', { token: tokens.staffToken });
  assert.equal(staffRead.statusCode, 403);
  const staffWrite = await invoke('POST', '/catalog', {
    token: tokens.staffToken,
    body: { name: 'Môi Collagen', category: 'lip' },
  });
  assert.equal(staffWrite.statusCode, 403);

  const ownerRead = await invoke('GET', '/catalog', { token: tokens.ownerToken });
  assert.equal(ownerRead.statusCode, 200);
  assert.equal(ownerRead.body.items.length, 1);

  const created = await invoke('POST', '/catalog', {
    token: tokens.ownerToken,
    body: { name: 'Môi Collagen Cam Đào', category: 'lip', description: 'Tự nhiên, ít sưng' },
  });
  assert.equal(created.statusCode, 201);
  const itemId = created.body.item.id;
  assert.equal(created.body.item.category, 'lip');

  const updated = await invoke('PUT', `/catalog/${itemId}`, {
    token: tokens.ownerToken,
    body: { name: 'Môi Collagen Hồng Baby', category: 'lip', description: 'Màu trong nhẹ' },
  });
  assert.equal(updated.statusCode, 200);
  assert.equal(updated.body.item.name, 'Môi Collagen Hồng Baby');

  const deleted = await invoke('DELETE', `/catalog/${itemId}`, { token: tokens.ownerToken });
  assert.equal(deleted.statusCode, 200);

  const actions = state.tables.audit_logs.map((l) => l.action);
  assert.ok(actions.includes('catalog.create'));
  assert.ok(actions.includes('catalog.update'));
  assert.ok(actions.includes('catalog.delete'));
});

test('7-day booking reminders & case release: filters due follow-ups past 200 old rows, closes open case on release, and allows rejecting failed cases', async () => {
  const { state, invoke, tokens } = createMockEnv();
  const vnToday = new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);
  const tenDaysAgo = new Date(Date.now() + 7 * 3600 * 1000 - 10 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const thirtyDaysAgo = new Date(Date.now() + 7 * 3600 * 1000 - 30 * 24 * 3600 * 1000).toISOString().slice(0, 10);

  // Seed 220 older already-checked bookings to verify due follow-ups & today's bookings are never crowded out
  const oldChecked = Array.from({ length: 220 }, (_, i) => ({
    id: `bk-old-${i}`,
    org_id: 'org-1',
    customer_name: `Khách cũ ${i}`,
    service_name: 'Môi Collagen',
    scheduled_at: new Date(Date.now() - (40 + i) * 24 * 3600 * 1000).toISOString(),
    service_date: thirtyDaysAgo,
    followup_done: true,
    status: 'done',
  }));

  state.tables.bookings = [
    ...oldChecked,
    {
      id: 'bk-today',
      org_id: 'org-1',
      customer_name: 'Chị Lan',
      service_name: 'Hairstroke',
      scheduled_at: new Date().toISOString(),
      service_date: vnToday,
      followup_done: false,
      status: 'confirmed',
    },
    {
      id: 'bk-due',
      org_id: 'org-1',
      customer_name: 'Chị Hoa',
      service_name: 'Môi Collagen',
      scheduled_at: new Date(Date.now() - 10 * 24 * 3600 * 1000).toISOString(),
      service_date: tenDaysAgo,
      followup_done: false,
      status: 'done',
    },
  ];

  const rem1 = await invoke('GET', '/bookings/reminders', { token: tokens.ownerToken });
  assert.equal(rem1.statusCode, 200);
  assert.equal(rem1.body.today.length, 1);
  assert.equal(rem1.body.today[0].id, 'bk-today');
  assert.equal(rem1.body.dueFollowups.length, 1);
  assert.equal(rem1.body.dueFollowups[0].id, 'bk-due');

  const mark = await invoke('PATCH', '/bookings/bk-due/followup', {
    token: tokens.ownerToken,
    body: { done: true },
  });
  assert.equal(mark.statusCode, 200);
  assert.equal(mark.body.booking.followup_done, true);

  const rem2 = await invoke('GET', '/bookings/reminders', { token: tokens.ownerToken });
  assert.equal(rem2.body.dueFollowups.length, 0);

  // Release thread control on an approved case: must close case so a subsequent send is blocked
  state.tables.handoff_cases.push({
    id: 'case-rel-1',
    org_id: 'org-1',
    source: 'business_ai_handover',
    page_id: 'page-test-1',
    psid: 'psid-rel-1',
    status: 'approved',
    draft_reply: 'Nháp đã duyệt',
    approved_by: 'owner-user-1',
    approved_at: new Date().toISOString(),
  });
  state.tables.handover_threads = [{
    org_id: 'org-1',
    page_id: 'page-test-1',
    psid: 'psid-rel-1',
    active: true,
  }];
  const rel = await invoke('POST', '/handoff-cases/case-rel-1/release', { token: tokens.ownerToken });
  assert.equal(rel.statusCode, 200);
  assert.equal(rel.body.released, true);
  assert.equal(rel.body.status, 'rejected');
  assert.equal(state.tables.handover_threads[0].active, false);
  const relCase = state.tables.handoff_cases.find((c) => c.id === 'case-rel-1');
  assert.equal(relCase.status, 'rejected');
  assert.ok(state.axiosCalls.some((c) => c.url.includes('/release_thread_control')));
  assert.ok(state.tables.audit_logs.some((l) => l.action === 'handoff_case.release'));

  const sendAfterRelease = await invoke('POST', '/handoff-cases/case-rel-1/send', { token: tokens.ownerToken });
  assert.equal(sendAfterRelease.statusCode, 403);
  assert.equal(sendAfterRelease.body.error, 'NOT_APPROVED');

  // Failed handoff case can be rejected/dismissed from inbox
  state.tables.handoff_cases.push({
    id: 'case-failed-1',
    org_id: 'org-1',
    source: 'business_ai_handover',
    page_id: 'page-test-1',
    psid: 'psid-fail-1',
    status: 'failed',
  });
  const rejFailed = await invoke('POST', '/handoff-cases/case-failed-1/reject', { token: tokens.ownerToken });
  assert.equal(rejFailed.statusCode, 200);
  assert.equal(rejFailed.body.status, 'rejected');
});

