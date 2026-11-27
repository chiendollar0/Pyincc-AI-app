'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const Module = require('node:module');

const {
  getAiKeys,
  isAiReplyEnabled,
  callGemini,
} = require('../src/ai/gemini');
const { canReplyFreeform } = require('../src/chat/window');

test('Task 0.3: customer scope NEVER selects or falls back to free internal key', async () => {
  const calls = [];
  const mockHttp = {
    async post(url, _body, opts) {
      calls.push({ url, apiKey: opts?.headers?.['x-goog-api-key'] });
      const err = new Error('Quota exceeded');
      err.response = { status: 429 };
      throw err;
    },
  };

  // Case 1: Only GEMINI_FREE_KEY is set -> customer scope must fail with AI_QUOTA_EXHAUSTED without calling Gemini
  await assert.rejects(
    () => callGemini('customer', { contents: [] }, {
      env: { GEMINI_FREE_KEY: 'free-only-key' },
      httpClient: mockHttp,
    }),
    (err) => err.code === 'AI_QUOTA_EXHAUSTED',
  );
  assert.equal(calls.length, 0);

  // Case 2: Both Pro keys return 429 -> customer scope throws AI_QUOTA_EXHAUSTED and NEVER calls GEMINI_FREE_KEY
  await assert.rejects(
    () => callGemini('customer', { contents: [] }, {
      env: {
        GEMINI_PRO_KEY_1: 'pro-key-1',
        GEMINI_PRO_KEY_2: 'pro-key-2',
        GEMINI_FREE_KEY: 'free-key-forbidden',
      },
      httpClient: mockHttp,
    }),
    (err) => err.code === 'AI_QUOTA_EXHAUSTED',
  );
  assert.deepEqual(
    calls.map((c) => c.apiKey),
    ['pro-key-1', 'pro-key-2'],
  );
  assert.equal(calls.some((c) => c.apiKey === 'free-key-forbidden'), false);

  // Case 3: Pro key 1 hits 429, Pro key 2 succeeds
  const failoverCalls = [];
  const failoverHttp = {
    async post(_url, _body, opts) {
      const key = opts?.headers?.['x-goog-api-key'];
      failoverCalls.push(key);
      if (key === 'pro-key-1') {
        const err = new Error('429');
        err.response = { status: 429 };
        throw err;
      }
      return { data: { candidates: [{ content: { parts: [{ text: '{}' }] } }] } };
    },
  };
  const result = await callGemini('customer', { contents: [] }, {
    env: {
      GEMINI_PRO_KEY_1: 'pro-key-1',
      GEMINI_PRO_KEY_2: 'pro-key-2',
      GEMINI_FREE_KEY: 'free-key-forbidden',
    },
    httpClient: failoverHttp,
  });
  assert.ok(result.candidates);
  assert.deepEqual(failoverCalls, ['pro-key-1', 'pro-key-2']);
});

test('Task 0.3: internal scope uses GEMINI_FREE_KEY and AI_REPLY_ENABLED defaults to false', async () => {
  assert.equal(isAiReplyEnabled({}), false);
  assert.equal(isAiReplyEnabled({ AI_REPLY_ENABLED: 'false' }), false);
  assert.equal(isAiReplyEnabled({ AI_REPLY_ENABLED: 'true' }), true);

  const keys = getAiKeys({
    GEMINI_PRO_KEY_1: 'pro-1',
    GEMINI_FREE_KEY: 'free-1',
  });
  assert.deepEqual(keys.customer, ['pro-1']);
  assert.deepEqual(keys.internal, ['free-1']);

  const used = [];
  await callGemini('internal', { contents: [] }, {
    env: { GEMINI_PRO_KEY_1: 'pro-1', GEMINI_FREE_KEY: 'free-1' },
    httpClient: {
      async post(_url, _body, opts) {
        used.push(opts?.headers?.['x-goog-api-key']);
        return { data: { ok: true } };
      },
    },
  });
  assert.deepEqual(used, ['free-1']);
});

test('Task 0.5: canReplyFreeform returns true within 24h and false past 24h', () => {
  const now = new Date('2026-11-26T12:00:00Z');
  const within24h = new Date('2026-11-25T12:01:00Z');
  const exactly24h = new Date('2026-11-25T12:00:00Z');
  const past24h = new Date('2026-11-25T11:59:59Z');

  assert.equal(canReplyFreeform(within24h, now), true);
  assert.equal(canReplyFreeform(exactly24h, now), false);
  assert.equal(canReplyFreeform(past24h, now), false);
  assert.equal(canReplyFreeform(null, now), false);
  assert.equal(canReplyFreeform('not-a-date', now), false);
});

test('Task 0.5: invalid Meta webhook signature is rejected', async () => {
  const origLoad = Module._load;
  const routes = [];
  function makeExpress() {
    const app = {
      disable() {},
      set() {},
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

  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === 'express') return makeExpress;
    if (request === 'express-rate-limit') return () => (_req, _res, next) => next();
    if (request === 'axios') return { post: async () => ({ data: {} }), get: async () => ({ data: {} }) };
    if (request === '@supabase/supabase-js') return { createClient: () => ({ from: () => ({}), auth: {} }) };
    return origLoad.call(this, request, parent, isMain);
  };

  process.env.NODE_ENV = 'test';
  process.env.SUPABASE_URL = 'https://test.supabase.co';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-role';
  process.env.META_APP_SECRET = 'test-meta-secret';
  process.env.VERIFY_TOKEN = 'test-verify-token';

  const indexPath = require.resolve('../index.js');
  delete require.cache[indexPath];
  const mod = require('../index.js');
  Module._load = origLoad;

  const rawBody = Buffer.from(JSON.stringify({ object: 'page', entry: [] }), 'utf8');
  const validSig = `sha256=${crypto.createHmac('sha256', 'test-meta-secret').update(rawBody).digest('hex')}`;
  const invalidSig = `sha256=${'0'.repeat(64)}`;

  assert.equal(mod.verifyMetaSignature(rawBody, validSig), true);
  assert.equal(mod.verifyMetaSignature(rawBody, invalidSig), false);
  assert.equal(mod.verifyMetaSignature(rawBody, undefined), false);

  const webhookRoute = routes.find((r) => r.method === 'POST' && r.path === '/webhook');
  assert.ok(webhookRoute);

  const req = {
    body: rawBody,
    get(name) {
      return String(name).toLowerCase() === 'x-hub-signature-256' ? invalidSig : undefined;
    },
  };
  const res = {
    statusCode: 200,
    body: null,
    finished: false,
    status(code) { this.statusCode = code; return this; },
    send(data) { this.body = data; this.finished = true; return this; },
  };
  for (const handler of webhookRoute.handlers) {
    if (res.finished) break;
    await new Promise((resolve, reject) => {
      const ret = handler(req, res, (err) => (err ? reject(err) : resolve()));
      if (ret && typeof ret.then === 'function') {
        ret.then(() => resolve(), reject);
      } else if (res.finished) {
        resolve();
      }
    });
  }
  assert.equal(res.statusCode, 403);
  assert.equal(res.body, 'Forbidden');
});
