'use strict';

const DEFAULT_MODEL = 'gemini-2.5-flash';
const VALID_SCOPES = new Set(['customer', 'internal']);

function normalizeKey(value) {
  return String(value || '').trim();
}

function getAiKeys(env = process.env) {
  return {
    customer: [normalizeKey(env.GEMINI_PRO_KEY_1), normalizeKey(env.GEMINI_PRO_KEY_2)].filter(Boolean),
    internal: [normalizeKey(env.GEMINI_FREE_KEY)].filter(Boolean), // dev-only, never used for customer traffic
  };
}

function isAiReplyEnabled(env = process.env) {
  return String(env.AI_REPLY_ENABLED || '').trim().toLowerCase() === 'true';
}

const AI_KEYS = getAiKeys();
const AI_REPLY_ENABLED = isAiReplyEnabled();

function isQuotaOrAvailabilityError(err) {
  const status = err?.response?.status;
  return status === 429 || status === 503;
}

/**
 * Call Google Gemini API with strict scope-isolated key routing.
 * - scope === 'customer': ONLY uses GEMINI_PRO_KEY_1 / GEMINI_PRO_KEY_2.
 *   NEVER falls back to 'internal' (GEMINI_FREE_KEY).
 *   Throws { code: 'AI_QUOTA_EXHAUSTED' } if no customer keys are available or all are exhausted.
 * - scope === 'internal': ONLY uses GEMINI_FREE_KEY (dev/internal tasks only).
 */
async function callGemini(scope, body, options = {}) {
  if (!VALID_SCOPES.has(scope)) {
    throw Object.assign(new Error(`INVALID_AI_SCOPE: ${String(scope)}`), { code: 'INVALID_AI_SCOPE' });
  }

  const env = options.env || process.env;
  const httpClient = options.httpClient || require('axios');
  const model = options.model || DEFAULT_MODEL;
  const timeout = options.timeout || 30000;
  const keys = getAiKeys(env)[scope];

  if (!keys.length) {
    const code = scope === 'customer' ? 'AI_QUOTA_EXHAUSTED' : 'GEMINI_NOT_CONFIGURED';
    throw Object.assign(new Error(code), { code });
  }

  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  let lastQuotaError = null;

  for (let i = 0; i < keys.length; i += 1) {
    const apiKey = keys[i];
    try {
      const response = await httpClient.post(endpoint, body, {
        headers: { 'x-goog-api-key': apiKey },
        timeout,
      });
      return response.data;
    } catch (err) {
      if (isQuotaOrAvailabilityError(err)) {
        lastQuotaError = err;
        continue;
      }
      throw err;
    }
  }

  const exhausted = Object.assign(new Error('AI_QUOTA_EXHAUSTED'), {
    code: 'AI_QUOTA_EXHAUSTED',
    cause: lastQuotaError,
  });
  throw exhausted;
}

module.exports = {
  AI_KEYS,
  AI_REPLY_ENABLED,
  DEFAULT_MODEL,
  getAiKeys,
  isAiReplyEnabled,
  callGemini,
};
