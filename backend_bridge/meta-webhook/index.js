const express = require('express');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
const port = Number(process.env.PORT) || 3000;
const config = {
  nodeEnv: process.env.NODE_ENV || 'development',
  supabaseUrl: process.env.SUPABASE_URL || 'https://ihufvqrxdswgbagzhydb.supabase.co',
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  metaAppId: process.env.META_APP_ID,
  metaAppSecret: process.env.META_APP_SECRET,
  verifyToken: process.env.VERIFY_TOKEN,
  pageTokenEncKey: process.env.PAGE_TOKEN_ENC_KEY || '',
  apiKey: process.env.API_KEY,
  bootstrapOwnerEmail: (process.env.BOOTSTRAP_OWNER_EMAIL || '').trim().toLowerCase(),
  graphApiVersion: process.env.META_GRAPH_API_VERSION || 'v21.0',
  storageBucket: process.env.SUPABASE_STORAGE_BUCKET || 'customer-media',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || 'https://pyincccrm.bothelper.vn',
};

const authWriteLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'RATE_LIMITED' },
});

const writeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'RATE_LIMITED' },
});

const requiredConfig = [
  ['SUPABASE_URL', config.supabaseUrl],
  ['SUPABASE_SERVICE_ROLE_KEY', config.supabaseServiceRoleKey],
  ['META_APP_SECRET', config.metaAppSecret],
  ['VERIFY_TOKEN', config.verifyToken],
];
const missingConfig = requiredConfig.filter(([, value]) => !value).map(([name]) => name);
if (missingConfig.length) {
  console.error(JSON.stringify({ event: 'config_missing', missing: missingConfig }));
  if (config.nodeEnv === 'production') {
    process.exit(1);
  }
}

process.on('unhandledRejection', (reason) => {
  console.error(JSON.stringify({
    event: 'unhandled_rejection',
    message: reason instanceof Error ? reason.message : String(reason),
  }));
});

const supabase = config.supabaseUrl && config.supabaseServiceRoleKey
  ? createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })
  : null;

const webhookDiagnostics = { received: 0, lastReceivedAt: null, lastPageId: null, lastKinds: [] };

function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

function getEncryptionKey() {
  const secretMaterial = config.pageTokenEncKey || config.metaAppSecret;
  if (!secretMaterial) throw new Error('Missing PAGE_TOKEN_ENC_KEY or META_APP_SECRET for token encryption');
  return crypto.createHash('sha256').update(`pyincc-page-token-key:${secretMaterial}`).digest();
}

function encryptPageToken(plainToken) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(String(plainToken), 'utf8'), cipher.final()]);
  return `enc:v1:${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${encrypted.toString('base64')}`;
}

function decryptPageToken(storedValue) {
  const raw = String(storedValue || '');
  if (!raw.startsWith('enc:v1:')) return raw;
  const parts = raw.split(':');
  if (parts.length !== 5) throw new Error('Invalid encrypted page token format');
  const decipher = crypto.createDecipheriv('aes-256-gcm', getEncryptionKey(), Buffer.from(parts[2], 'base64'));
  decipher.setAuthTag(Buffer.from(parts[3], 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(parts[4], 'base64')), decipher.final()]).toString('utf8');
}

function hasValidJwtFormat(token) {
  const parts = String(token).split('.');
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) return false;
  try {
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return Boolean(header && typeof header === 'object' && header.alg && payload &&
      typeof payload === 'object' && typeof payload.sub === 'string' &&
      !(typeof payload.exp === 'number' && payload.exp * 1000 <= Date.now()));
  } catch { return false; }
}

function fbIdentityId(user) {
  const identity = (Array.isArray(user?.identities) ? user.identities : [])
    .find((item) => item && item.provider === 'facebook');
  return String(identity?.identity_data?.sub || identity?.identity_data?.id || identity?.id || '').trim();
}

async function resolveOrActivateMembership(user) {
  const { data: activeRow } = await supabase.from('memberships')
    .select('id, org_id, role, status').eq('user_id', user.id).eq('status', 'active').maybeSingle();
  if (activeRow?.org_id && activeRow.role) return activeRow;

  const email = typeof user.email === 'string' ? user.email.trim().toLowerCase() : '';
  const verifiedEmail = user.email_confirmed_at ? email : '';
  const fbUserId = fbIdentityId(user);
  let pendingRow = null;
  if (verifiedEmail) {
    const { data } = await supabase.from('memberships').select('id, org_id, role, status')
      .eq('invited_email', verifiedEmail).eq('status', 'pending').maybeSingle();
    pendingRow = data || null;
  }
  if (!pendingRow && fbUserId) {
    const { data } = await supabase.from('memberships').select('id, org_id, role, status')
      .eq('invited_fb_user_id', fbUserId).eq('status', 'pending').maybeSingle();
    pendingRow = data || null;
  }
  if (pendingRow) {
    const { data: activated } = await supabase.from('memberships').update({
      user_id: user.id, status: 'active', updated_at: new Date().toISOString(),
    }).eq('id', pendingRow.id).select('id, org_id, role, status').single();
    if (activated) return activated;
  }

  // Safe owner bootstrap: requires confirmed email matching BOOTSTRAP_OWNER_EMAIL
  if (config.bootstrapOwnerEmail && verifiedEmail && verifiedEmail === config.bootstrapOwnerEmail) {
    const { count } = await supabase.from('organizations').select('id', { count: 'exact', head: true });
    if (count === 0) {
      const { data: newOrg } = await supabase.from('organizations').insert({ name: 'PYINCC Salon' }).select('id').single();
      if (newOrg?.id) {
        const { data: ownerMembership } = await supabase.from('memberships').insert({
          org_id: newOrg.id, user_id: user.id, invited_email: verifiedEmail,
          invited_fb_user_id: fbUserId || null, role: 'owner', status: 'active',
        }).select('id, org_id, role, status').single();
        return ownerMembership || null;
      }
    }
  }
  return null;
}

async function requireAuth(req, res, next) {
  if (!supabase) return res.status(503).json({ error: 'Service Unavailable' });
  const match = /^Bearer\s+(.+)$/i.exec((req.get('authorization') || '').trim());
  const token = match ? match[1].trim() : '';
  if (!token || !hasValidJwtFormat(token)) return res.status(401).json({ error: 'Unauthorized' });
  try {
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data?.user) return res.status(401).json({ error: 'Unauthorized' });
    const membership = await resolveOrActivateMembership(data.user);
    if (!membership?.org_id || !membership.role) return res.status(403).json({ error: 'NO_MEMBERSHIP' });
    req.authUser = data.user;
    req.orgId = membership.org_id;
    req.userRole = membership.role;
    return next();
  } catch {
    return res.status(401).json({ error: 'Unauthorized' });
  }
}

function requireRole(...allowedRoles) {
  return (req, res, next) => req.userRole && allowedRoles.includes(req.userRole)
    ? next() : res.status(403).json({ error: 'FORBIDDEN_ROLE' });
}

function safeEqual(received, expected) {
  if (typeof received !== 'string' || typeof expected !== 'string') return false;
  const a = Buffer.from(received);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function requireInternalApiKey(req, res, next) {
  if (config.apiKey && safeEqual(req.get('x-api-key'), config.apiKey)) return next();
  if (config.nodeEnv === 'production') return res.status(404).json({ error: 'Not Found' });
  return res.status(401).json({ error: 'Unauthorized' });
}

function verifyMetaSignature(rawBody, signature) {
  if (!config.metaAppSecret || !Buffer.isBuffer(rawBody) || typeof signature !== 'string') return false;
  const expected = `sha256=${crypto.createHmac('sha256', config.metaAppSecret).update(rawBody).digest('hex')}`;
  return safeEqual(signature, expected);
}

app.get('/health', (_req, res) => res.json({
  ok: true,
  service: 'pyincc-meta-webhook',
  commit: (process.env.RENDER_GIT_COMMIT || 'local').slice(0, 7),
}));
app.get('/privacy', (_req, res) => res.type('html').send(
  '<!doctype html><html lang="vi"><head><meta charset="utf-8"><title>Chính sách Quyền riêng tư — PyinccCRM</title></head>' +
  '<body style="font-family:sans-serif;max-width:720px;margin:32px auto;padding:0 16px;line-height:1.6;">' +
  '<h1>Chính sách Quyền riêng tư — PyinccCRM</h1>' +
  '<p>PyinccCRM thu thập và xử lý tin nhắn Fanpage, hình ảnh khách hàng gửi để tư vấn, và thông tin quản trị viên Fanpage do chủ tiệm cấp quyền nhằm mục đích chăm sóc khách hàng, đặt lịch hẹn và hỗ trợ tư vấn thẩm mỹ.</p>' +
  '<h2>Các bên thứ ba xử lý dữ liệu</h2>' +
  '<ul>' +
  '<li><strong>Supabase:</strong> lưu trữ cơ sở dữ liệu hội thoại, lịch hẹn và tệp ảnh khách hàng trong bucket riêng tư (truy cập qua đường dẫn ký có thời hạn).</li>' +
  '<li><strong>Google Gemini API:</strong> tiếp nhận ảnh khách hàng (đã xóa siêu dữ liệu EXIF) thông qua Supabase Edge Function để phân tích dáng mặt, tông da và gợi ý mẫu tư vấn cho nhân viên.</li>' +
  '<li><strong>Meta Platforms:</strong> nhận và gửi tin nhắn Messenger khi chủ tiệm kết nối Fanpage.</li>' +
  '</ul>' +
  '<p><strong>Thời gian lưu trữ &amp; Xóa dữ liệu:</strong> Dữ liệu được lưu trong thời gian tiệm sử dụng dịch vụ hoặc đến khi có yêu cầu xóa. Xem hướng dẫn xóa dữ liệu tại <a href="/data-deletion">/data-deletion</a> hoặc liên hệ <strong>phanhungkg03@gmail.com</strong>.</p></body></html>'
));
app.get('/terms', (_req, res) => res.type('html').send(
  '<!doctype html><html lang="vi"><head><meta charset="utf-8"><title>Điều khoản Dịch vụ — PyinccCRM</title></head>' +
  '<body style="font-family:sans-serif;max-width:720px;margin:32px auto;padding:0 16px;line-height:1.6;">' +
  '<h1>Điều khoản Dịch vụ — PyinccCRM</h1>' +
  '<p>PyinccCRM là công cụ hỗ trợ chủ tiệm và nhân viên quản lý hội thoại Messenger, lịch hẹn và mô phỏng mẫu tư vấn. Chủ tiệm chịu trách nhiệm kiểm duyệt mọi nội dung trước khi gửi tới khách hàng.</p>' +
  '<p>Liên hệ: phanhungkg03@gmail.com</p></body></html>'
));
app.get('/data-deletion', asyncHandler(async (req, res) => {
  const rawCode = typeof req.query.code === 'string' ? req.query.code.trim() : '';
  const safeCode = /^[a-zA-Z0-9_-]{1,64}$/.test(rawCode) ? rawCode : '';
  let statusBanner = '';
  if (safeCode && supabase) {
    const { data: row } = await supabase.from('data_deletion_requests')
      .select('code, status, created_at')
      .eq('code', safeCode)
      .maybeSingle();
    if (row) {
      statusBanner = `<p style="padding:12px;background:#e8f5e9;border-radius:8px;color:#1b5e20;"><strong>Mã xác nhận ${row.code}:</strong> Trạng thái <code>${row.status}</code> (ghi nhận lúc ${row.created_at}). Toàn bộ liên kết Fanpage, token đã mã hóa và liên kết Facebook của tài khoản này đã được gỡ bỏ.</p>`;
    } else {
      statusBanner = `<p style="padding:12px;background:#fff3e0;border-radius:8px;color:#e65100;"><strong>Mã xác nhận ${safeCode}:</strong> Không tìm thấy yêu cầu tương ứng trong hệ thống.</p>`;
    }
  }
  return res.type('html').send(
    '<!doctype html><html lang="vi"><head><meta charset="utf-8"><title>Hướng dẫn Xóa Dữ liệu — PyinccCRM</title></head>' +
    '<body style="font-family:sans-serif;max-width:720px;margin:32px auto;padding:0 16px;line-height:1.6;">' +
    '<h1>Hướng dẫn Xóa Dữ liệu Người dùng — PyinccCRM</h1>' +
    statusBanner +
    '<p>Để thu hồi quyền và xóa toàn bộ dữ liệu liên kết Fanpage:</p>' +
    '<ol><li>Vào Cài đặt Facebook → Tiện ích tích hợp cho doanh nghiệp (Business Integrations) → chọn <strong>PyinccCRM</strong> → bấm <strong>Gỡ</strong>. Hệ thống sẽ tự động nhận tín hiệu thu hồi và xóa toàn bộ Page Token, liên kết Fanpage và gỡ liên kết Facebook khỏi tài khoản thành viên.</li>' +
    '<li>Hoặc gửi email yêu cầu xóa toàn bộ dữ liệu hội thoại về <strong>phanhungkg03@gmail.com</strong>, yêu cầu sẽ được xử lý trong vòng 48 giờ.</li></ol></body></html>'
  );
}));
app.get('/internal/status', requireInternalApiKey, (_req, res) =>
  res.json({ ok: true, configured: missingConfig.length === 0 }));
app.get('/internal/webhook-status', requireInternalApiKey, (_req, res) =>
  res.json({ ...webhookDiagnostics }));

// Returns 501 Not Implemented until an image generation model is configured (Section 1 & Section 12)
app.post('/api/tryon/generate', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), asyncHandler(async (req, res) => {
  const imageBase64 = String(req.body?.image_base64 || req.body?.imageBase64 || '').trim();
  if (!imageBase64) return res.status(400).json({ error: 'image_base64 is required' });
  return res.status(501).json({
    error: 'NOT_IMPLEMENTED',
    message: 'Chưa có model ghép ảnh trên môi trường này.',
  });
}));

app.get('/memberships', requireAuth, requireRole('owner'), asyncHandler(async (req, res) => {
  const { data, error } = await supabase.from('memberships')
    .select('id, org_id, user_id, invited_email, invited_fb_user_id, role, status, created_at')
    .eq('org_id', req.orgId).order('created_at', { ascending: false });
  if (error) return res.status(500).json({ error: 'Failed to load memberships' });
  return res.json({ memberships: data || [] });
}));

app.post('/memberships/invite', authWriteLimiter, requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const invitedEmail = typeof req.body?.email === 'string' && req.body.email.trim()
    ? req.body.email.trim().toLowerCase()
    : null;
  const invitedFbUserId = typeof req.body?.fbUserId === 'string' && req.body.fbUserId.trim()
    ? req.body.fbUserId.trim()
    : null;
  if (!invitedEmail && !invitedFbUserId) return res.status(400).json({ error: 'email or fbUserId is required to invite staff' });

  if (invitedEmail) {
    const { data: dupEmail } = await supabase.from('memberships')
      .select('id')
      .eq('org_id', req.orgId)
      .eq('invited_email', invitedEmail)
      .eq('status', 'pending')
      .maybeSingle();
    if (dupEmail) return res.status(409).json({ error: 'INVITATION_ALREADY_EXISTS' });
  }
  if (invitedFbUserId) {
    const { data: dupFb } = await supabase.from('memberships')
      .select('id')
      .eq('org_id', req.orgId)
      .eq('invited_fb_user_id', invitedFbUserId)
      .eq('status', 'pending')
      .maybeSingle();
    if (dupFb) return res.status(409).json({ error: 'INVITATION_ALREADY_EXISTS' });
  }

  const { data, error } = await supabase.from('memberships').insert({
    org_id: req.orgId, invited_email: invitedEmail, invited_fb_user_id: invitedFbUserId,
    role: 'staff', status: 'pending',
  }).select('id, org_id, invited_email, invited_fb_user_id, role, status, created_at').single();
  if (error) {
    if (error.code === '23505') {
      return res.status(409).json({ error: 'INVITATION_ALREADY_EXISTS' });
    }
    return res.status(500).json({ error: 'Failed to create staff invitation' });
  }
  return res.json({ success: true, invitation: data });
}));

app.post('/auth/facebook/exchange-token', authWriteLimiter, requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  if (!config.metaAppSecret || !config.metaAppId) return res.status(503).json({ error: 'Service Unavailable' });
  const userAccessToken = req.body?.accessToken || req.body?.userAccessToken || req.body?.user_access_token;
  if (typeof userAccessToken !== 'string' || !userAccessToken.trim()) return res.status(400).json({ error: 'accessToken is required' });
  try {
    const verified = await verifyFacebookUserToken(userAccessToken.trim());
    const pages = await exchangeUserTokenAndSavePages(userAccessToken.trim(), req.orgId, verified.userId);
    return res.json({
      success: true,
      org_id: req.orgId,
      role: req.userRole,
      pages: pages.map((p) => ({
        id: p.page_id,
        name: p.page_name,
        page_id: p.page_id,
        page_name: p.page_name,
      })),
    });
  } catch (error) {
    if (error.code === 'PAGE_ALREADY_BOUND_TO_ANOTHER_ORG') {
      return res.status(409).json({ error: 'PAGE_ALREADY_BOUND_TO_ANOTHER_ORG' });
    }
    if (error.code === 'INVALID_FACEBOOK_TOKEN') {
      return res.status(401).json({ error: 'INVALID_FACEBOOK_TOKEN', message: 'Token Facebook không hợp lệ hoặc đã hết hạn.' });
    }
    console.error(JSON.stringify({ event: 'exchange_token_failed', message: error.message }));
    return res.status(502).json({ error: 'META_UPSTREAM_ERROR' });
  }
}));

async function purgeFacebookUserData(fbUserId) {
  const { error: pagesErr } = await supabase.from('connected_pages').delete().eq('connected_by_fb_user_id', fbUserId);
  if (pagesErr) throw new Error(`connected_pages_delete_failed: ${pagesErr.message}`);
  // Only unlink Facebook identity on memberships; never delete membership rows on Facebook app removal.
  const { error: memErr } = await supabase.from('memberships')
    .update({ invited_fb_user_id: null, updated_at: new Date().toISOString() })
    .eq('invited_fb_user_id', fbUserId);
  if (memErr) throw new Error(`memberships_unlink_failed: ${memErr.message}`);
}

app.post('/auth/facebook/deauthorize', express.urlencoded({ extended: false }), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  if (!config.metaAppSecret || !supabase) return res.status(503).json({ error: 'Service Unavailable' });
  const parsed = verifyFacebookSignedRequest(req.body?.signed_request);
  if (!parsed?.user_id) return res.status(403).json({ error: 'Forbidden' });
  await purgeFacebookUserData(String(parsed.user_id));
  return res.json({ success: true });
}));

app.post('/auth/facebook/data-deletion', express.urlencoded({ extended: false }), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  if (!config.metaAppSecret || !supabase) return res.status(503).json({ error: 'Service Unavailable' });
  const parsed = verifyFacebookSignedRequest(req.body?.signed_request);
  if (!parsed?.user_id) return res.status(403).json({ error: 'Forbidden' });
  const fbUserId = String(parsed.user_id);
  try {
    await purgeFacebookUserData(fbUserId);
  } catch (err) {
    console.error(JSON.stringify({ event: 'data_deletion_failed', message: err.message }));
    return res.status(500).json({ error: 'DATA_DELETION_FAILED' });
  }
  const confirmationCode = crypto.createHash('sha256')
    .update(`${fbUserId}:${Date.now()}:${crypto.randomBytes(8).toString('hex')}`)
    .digest('hex')
    .slice(0, 16);
  const { error: reqErr } = await supabase.from('data_deletion_requests').insert({
    code: confirmationCode,
    fb_user_id: fbUserId,
    status: 'completed',
    created_at: new Date().toISOString(),
  });
  if (reqErr) {
    console.error(JSON.stringify({ event: 'data_deletion_log_failed', message: reqErr.message }));
    return res.status(500).json({ error: 'DATA_DELETION_LOG_FAILED' });
  }
  const statusUrl = `${config.publicBaseUrl.replace(/\/+$/, '')}/data-deletion?code=${confirmationCode}`;
  return res.json({ url: statusUrl, confirmation_code: confirmationCode });
}));

// App uses native Facebook Login SDK (/auth/facebook/exchange-token); web OAuth callback is intentionally disabled
app.get('/auth/facebook/callback', (_req, res) => {
  return res.status(410).json({
    error: 'WEB_OAUTH_FLOW_GONE',
    message: 'Ứng dụng sử dụng Facebook Login SDK trực tiếp trên thiết bị.',
  });
});

app.get('/connected-pages', requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data, error } = await supabase.from('connected_pages').select('page_id, page_name, updated_at')
    .eq('org_id', req.orgId).order('updated_at', { ascending: false });
  if (error) return res.status(500).json({ error: 'Failed to load connected pages' });
  return res.json({ pages: data || [] });
}));

async function verifyFacebookUserToken(inputToken) {
  let response;
  try {
    response = await axios.get(`https://graph.facebook.com/${config.graphApiVersion}/debug_token`, {
      params: { input_token: inputToken, access_token: `${config.metaAppId}|${config.metaAppSecret}` }, timeout: 15000,
    });
  } catch (error) {
    const status = error.response?.status;
    if (status === 400 || status === 401 || status === 403) {
      const invalidErr = new Error('Facebook token rejected by debug_token');
      invalidErr.code = 'INVALID_FACEBOOK_TOKEN';
      throw invalidErr;
    }
    throw error;
  }
  const tokenData = response.data?.data;
  if (!tokenData || tokenData.is_valid !== true || String(tokenData.app_id) !== String(config.metaAppId) || !tokenData.user_id) {
    const invalidErr = new Error('Facebook token failed debug_token validation');
    invalidErr.code = 'INVALID_FACEBOOK_TOKEN';
    throw invalidErr;
  }
  return { userId: String(tokenData.user_id), appId: String(tokenData.app_id) };
}

function verifyFacebookSignedRequest(signedRequest) {
  if (typeof signedRequest !== 'string' || !signedRequest.includes('.')) return null;
  const [signature, payload] = signedRequest.split('.', 2);
  if (!signature || !payload || !config.metaAppSecret) return null;
  const expected = crypto.createHmac('sha256', config.metaAppSecret).update(payload).digest('base64url');
  if (!safeEqual(signature, expected)) return null;
  try { return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); } catch { return null; }
}

async function exchangeUserTokenAndSavePages(userAccessToken, orgId, fbUserId) {
  let tokenToUse = userAccessToken;
  if (config.metaAppId && config.metaAppSecret) {
    try {
      const longRes = await axios.get(`https://graph.facebook.com/${config.graphApiVersion}/oauth/access_token`, {
        params: { grant_type: 'fb_exchange_token', client_id: config.metaAppId,
          client_secret: config.metaAppSecret, fb_exchange_token: userAccessToken }, timeout: 15000,
      });
      if (longRes.data?.access_token) tokenToUse = longRes.data.access_token;
    } catch (error) { console.warn(JSON.stringify({ event: 'long_lived_exchange_skipped', message: error.message })); }
  }
  const appSecretProof = crypto.createHmac('sha256', config.metaAppSecret).update(tokenToUse).digest('hex');
  const accountsRes = await axios.get(`https://graph.facebook.com/${config.graphApiVersion}/me/accounts`, {
    params: { fields: 'id,name,access_token,category', access_token: tokenToUse, appsecret_proof: appSecretProof }, timeout: 15000,
  });
  const savedPages = [];
  for (const page of (Array.isArray(accountsRes.data?.data) ? accountsRes.data.data : [])) {
    if (!page.id || !page.access_token) continue;
    const pageIdStr = String(page.id);

    // Prevent overwriting org_id if this Page is already bound to a different organization
    const { data: existingPage } = await supabase.from('connected_pages')
      .select('org_id').eq('page_id', pageIdStr).maybeSingle();
    if (existingPage?.org_id && String(existingPage.org_id) !== String(orgId)) {
      const conflictErr = new Error('Page is already bound to another organization');
      conflictErr.code = 'PAGE_ALREADY_BOUND_TO_ANOTHER_ORG';
      throw conflictErr;
    }

    try {
      const proof = crypto.createHmac('sha256', config.metaAppSecret).update(page.access_token).digest('hex');
      await axios.post(`https://graph.facebook.com/${config.graphApiVersion}/${page.id}/subscribed_apps`, null, {
        params: { subscribed_fields: 'messages,messaging_postbacks,messaging_handovers',
          access_token: page.access_token, appsecret_proof: proof }, timeout: 15000,
      });
    } catch (error) {
      console.warn(JSON.stringify({ event: 'page_webhook_subscribe_warning', pageId: page.id, message: error.message }));
    }
    const row = { org_id: orgId, page_id: pageIdStr, page_name: String(page.name || `Page ${page.id}`),
      page_access_token: encryptPageToken(page.access_token), connected_by_fb_user_id: fbUserId || null,
      updated_at: new Date().toISOString() };
    const { error } = await supabase.from('connected_pages').upsert(row, { onConflict: 'page_id' });
    if (error) throw new Error(`Could not persist connected page: ${error.message}`);
    savedPages.push({ page_id: row.page_id, page_name: row.page_name });
  }
  return savedPages;
}

async function resolvePageCredentialsForOrg(orgId, requiredPageId) {
  const cleanPageId = String(requiredPageId || '').trim();
  if (!orgId || !cleanPageId) return null;
  const { data } = await supabase.from('connected_pages')
    .select('page_id, page_access_token')
    .eq('org_id', orgId)
    .eq('page_id', cleanPageId)
    .maybeSingle();
  if (data?.page_access_token) {
    return { pageId: data.page_id, pageAccessToken: decryptPageToken(data.page_access_token) };
  }
  return null;
}

app.get('/settings', requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data, error } = await supabase.from('salon_settings').select('on_duty, consultation_script, updated_at')
    .eq('org_id', req.orgId).maybeSingle();
  if (error) return res.status(500).json({ error: 'Failed to load settings' });
  return res.json({ onDuty: data ? Boolean(data.on_duty) : true,
    consultationScript: data ? String(data.consultation_script || '') : '' });
}));

app.put('/settings', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '32kb' }), asyncHandler(async (req, res) => {
  if (typeof req.body?.consultationScript === 'string' && req.userRole !== 'owner') return res.status(403).json({ error: 'FORBIDDEN_ROLE' });
  const onDuty = typeof req.body?.onDuty === 'boolean' ? req.body.onDuty : true;
  const payload = { key: `org:${req.orgId}`, org_id: req.orgId, on_duty: onDuty, updated_at: new Date().toISOString() };
  if (req.userRole === 'owner' && typeof req.body?.consultationScript === 'string') payload.consultation_script = req.body.consultationScript.trim();
  const { error } = await supabase.from('salon_settings').upsert(payload, { onConflict: 'key' });
  if (error) return res.status(500).json({ error: 'Failed to save settings' });
  return res.json({ success: true, onDuty });
}));

app.get('/bookings', requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data, error } = await supabase.from('bookings').select('*').eq('org_id', req.orgId)
    .order('scheduled_at', { ascending: true }).limit(50);
  if (error) return res.status(500).json({ error: 'Failed to fetch bookings' });
  return res.json({ bookings: data || [] });
}));

// Normalizes HH:mm or ISO timestamp explicitly to Vietnam timezone (+07:00)
function parseVietnamScheduledAt(timeSlot) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(String(timeSlot || '').trim());
  if (match) {
    const hh = String(Math.min(Math.max(Number(match[1]), 0), 23)).padStart(2, '0');
    const mm = String(Math.min(Math.max(Number(match[2]), 0), 59)).padStart(2, '0');
    const vnNow = new Date(Date.now() + 7 * 3600 * 1000);
    const yyyy = vnNow.getUTCFullYear();
    const mo = String(vnNow.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(vnNow.getUTCDate()).padStart(2, '0');
    return new Date(`${yyyy}-${mo}-${dd}T${hh}:${mm}:00+07:00`).toISOString();
  }
  if (timeSlot && !Number.isNaN(Date.parse(timeSlot))) {
    return new Date(timeSlot).toISOString();
  }
  return new Date().toISOString();
}

app.post('/bookings', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const customerName = String(req.body?.customerName || req.body?.customer_name || '').trim();
  const customerPhone = String(req.body?.customerPhone || req.body?.customer_phone || '').trim();
  const serviceName = String(req.body?.serviceName || req.body?.service_name || '').trim();
  const timeSlot = String(req.body?.time || req.body?.scheduled_at || '').trim();
  if (!customerName || !serviceName) return res.status(400).json({ error: 'customerName and serviceName are required' });

  const scheduledIso = parseVietnamScheduledAt(timeSlot);

  // Prevent double-booking the same slot in the same organization
  const { data: conflict } = await supabase.from('bookings')
    .select('id')
    .eq('org_id', req.orgId)
    .eq('scheduled_at', scheduledIso)
    .in('status', ['pending', 'confirmed'])
    .maybeSingle();

  if (conflict) {
    return res.status(409).json({ error: 'BOOKING_SLOT_CONFLICT' });
  }

  const { data, error } = await supabase.from('bookings').insert({ org_id: req.orgId,
    customer_name: customerName, customer_phone: customerPhone, service_name: serviceName,
    scheduled_at: scheduledIso, status: 'confirmed' }).select('*').single();
  if (error) {
    if (error.code === '23505') {
      return res.status(409).json({ error: 'BOOKING_SLOT_CONFLICT' });
    }
    return res.status(500).json({ error: 'Failed to create booking' });
  }
  return res.json({ success: true, booking: data });
}));

app.post('/messages/:id/approve', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const messageRowId = String(req.params.id || '').trim();
  const draftReply = String(req.body?.text || req.body?.draftReply || '').trim();
  if (!messageRowId || !draftReply) return res.status(400).json({ error: 'message id and text are required' });
  if (draftReply.length > 2000) return res.status(400).json({ error: 'text must be 2000 characters or fewer' });
  const approvedAt = new Date().toISOString();
  const { data, error } = await supabase.from('conversation_messages').update({ draft_reply: draftReply,
    approval_status: 'approved', approved_by: req.authUser.id, approved_at: approvedAt })
    .eq('id', messageRowId).eq('org_id', req.orgId)
    .in('approval_status', ['pending', 'approved'])
    .select('id, org_id, customer_psid, draft_reply, approval_status, approved_by, approved_at').single();
  if (error || !data) return res.status(404).json({ error: 'Message record not found in your organization' });
  return res.json({ success: true, approval: data });
}));

function mapMetaSendError(error) {
  const metaErr = error?.response?.data?.error;
  const code = Number(metaErr?.code);
  const subcode = Number(metaErr?.error_subcode);
  if (code === 10 || subcode === 2018278) {
    return {
      status: 422,
      body: {
        error: 'OUTSIDE_24H_WINDOW',
        message: 'Đã quá khung 24 giờ kể từ tin nhắn cuối của khách. Cần chờ khách nhắn lại hoặc dùng Message Tag hợp lệ.',
      },
    };
  }
  return { status: 502, body: { error: 'META_SEND_FAILED' } };
}

app.post('/send-message', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const messageRecordId = String(req.body?.messageRecordId || req.body?.message_record_id || '').trim();
  const requestedPageId = String(req.body?.pageId || req.body?.page_id || '').trim();
  if (!messageRecordId) return res.status(400).json({ error: 'messageRecordId is required; approve the message first' });

  const { data: msg, error: fetchErr } = await supabase.from('conversation_messages')
    .select('id, org_id, page_id, customer_psid, draft_reply, approval_status, approved_by, approved_at')
    .eq('id', messageRecordId).eq('org_id', req.orgId).single();
  if (fetchErr || !msg) return res.status(404).json({ error: 'Message record not found in your organization' });
  if (msg.approval_status === 'sending' || msg.approval_status === 'sent') {
    return res.status(409).json({ error: 'ALREADY_SENT_OR_SENDING' });
  }
  if (msg.approval_status !== 'approved' || !msg.approved_by || !msg.approved_at || !msg.draft_reply) {
    return res.status(403).json({ error: 'NOT_APPROVED' });
  }
  const msgPageId = String(msg.page_id || '').trim();
  if (!msgPageId) {
    return res.status(422).json({ error: 'MISSING_PAGE_CONTEXT' });
  }
  if (requestedPageId && requestedPageId !== msgPageId) {
    return res.status(422).json({ error: 'PAGE_MISMATCH' });
  }

  const page = await resolvePageCredentialsForOrg(req.orgId, msgPageId);
  if (!page) return res.status(503).json({ error: 'Chưa có Fanpage nào được kết nối cho tiệm của bạn.' });

  // Atomic lock: claim row by setting approval_status = 'sending' only if still 'approved'
  const { data: claimed } = await supabase.from('conversation_messages')
    .update({ approval_status: 'sending' })
    .eq('id', msg.id)
    .eq('org_id', req.orgId)
    .eq('approval_status', 'approved')
    .select('id')
    .maybeSingle();
  if (!claimed) return res.status(409).json({ error: 'ALREADY_SENT_OR_SENDING' });

  try {
    const response = await axios.post(`https://graph.facebook.com/${config.graphApiVersion}/${page.pageId}/messages`, {
      recipient: { id: String(msg.customer_psid).trim() }, messaging_type: 'RESPONSE', message: { text: String(msg.draft_reply).trim() },
    }, { headers: { Authorization: `Bearer ${page.pageAccessToken}` }, timeout: 15000 });
    await supabase.from('conversation_messages').update({ approval_status: 'sent' }).eq('id', msg.id).eq('org_id', req.orgId);
    await supabase.from('conversation_messages').upsert({ org_id: req.orgId, page_id: page.pageId, channel: 'facebook',
      customer_psid: String(msg.customer_psid).trim(), sender: 'staff', message_type: 'text',
      message_text: String(msg.draft_reply).trim(), message_id: response.data?.message_id || null,
      is_from_customer: false, approval_status: 'sent', approved_by: msg.approved_by,
      approved_at: msg.approved_at, created_at: new Date().toISOString() },
      { onConflict: 'message_id', ignoreDuplicates: true });
    return res.json({ success: true, data: response.data });
  } catch (error) {
    await supabase.from('conversation_messages').update({ approval_status: 'approved' }).eq('id', msg.id).eq('org_id', req.orgId);
    console.error(JSON.stringify({ event: 'send_message_failed', status: error.response?.status, code: error.response?.data?.error?.code }));
    const mapped = mapMetaSendError(error);
    return res.status(mapped.status).json(mapped.body);
  }
}));

app.post('/tryon-drafts', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), asyncHandler(async (req, res) => {
  const recipientId = String(req.body?.recipientId || req.body?.recipient_id || '').trim();
  const pageId = String(req.body?.pageId || req.body?.page_id || '').trim();
  const imageBase64 = String(req.body?.imageBase64 || req.body?.image_base64 || '').trim();
  const caption = String(req.body?.caption || '').trim();
  if (!imageBase64) return res.status(400).json({ error: 'imageBase64 is required' });
  let buffer;
  try { buffer = Buffer.from(imageBase64, 'base64'); } catch { return res.status(400).json({ error: 'Invalid base64 image' }); }
  if (!buffer.length || buffer.length > 15 * 1024 * 1024) return res.status(400).json({ error: 'Image size must be under 15 MB' });
  const storagePath = `tryon/${req.orgId}/${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await uploadWithRetry(storagePath, buffer, 'image/jpeg');
  if (uploadError) return res.status(502).json({ error: `Upload Try-On image failed: ${uploadError.message}` });
  const createdAt = new Date().toISOString();
  const { data: media, error } = await supabase.from('customer_media').insert({ org_id: req.orgId,
    source_channel: 'mobile', source_message_id: storagePath, storage_url: null, storage_path: storagePath,
    file_name: storagePath, mime_type: 'image/jpeg', file_size: buffer.length,
    recipient_psid: recipientId || null, page_id: pageId || null, caption: caption || null,
    created_by: req.authUser.id, approval_status: 'pending',
    approved_by: null, approved_at: null, uploaded_at: createdAt })
    .select('id, org_id, storage_path, page_id, created_by, approval_status, approved_by, approved_at').single();
  if (error || !media) return res.status(500).json({ error: 'Failed to persist Try-On draft media record' });
  return res.json({ success: true, media });
}));

app.post('/tryon-drafts/:id/approve', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const mediaRecordId = String(req.params.id || '').trim();
  if (!mediaRecordId) return res.status(400).json({ error: 'media id is required' });

  const { data: existing, error: lookupErr } = await supabase.from('customer_media')
    .select('id, created_by, approval_status')
    .eq('id', mediaRecordId)
    .eq('org_id', req.orgId)
    .maybeSingle();
  if (lookupErr || !existing) {
    return res.status(404).json({ error: 'Pending Try-On draft not found in your organization' });
  }
  if (existing.approval_status !== 'pending') {
    return res.status(409).json({ error: 'DRAFT_NOT_PENDING' });
  }
  // Prevent staff from approving their own draft; owners may self-approve for 1-person salons (documented in README).
  if (req.userRole !== 'owner' && existing.created_by && String(existing.created_by) === String(req.authUser.id)) {
    return res.status(403).json({ error: 'SELF_APPROVAL_NOT_ALLOWED' });
  }

  const captionOverride = typeof req.body?.caption === 'string' ? req.body.caption.trim() : undefined;
  const approvedAt = new Date().toISOString();
  const updatePayload = {
    approval_status: 'approved',
    approved_by: req.authUser.id,
    approved_at: approvedAt,
  };
  if (captionOverride !== undefined) updatePayload.caption = captionOverride || null;
  let updateQuery = supabase.from('customer_media')
    .update(updatePayload)
    .eq('id', mediaRecordId)
    .eq('org_id', req.orgId)
    .eq('approval_status', 'pending');
  if (req.userRole !== 'owner') {
    updateQuery = updateQuery.neq('created_by', req.authUser.id);
  }
  const { data: media, error } = await updateQuery
    .select('id, org_id, storage_path, recipient_psid, page_id, caption, created_by, approval_status, approved_by, approved_at')
    .maybeSingle();
  if (error || !media) return res.status(409).json({ error: 'DRAFT_NOT_PENDING' });
  return res.json({ success: true, media });
}));

app.post('/send-tryon-image', writeLimiter, requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const mediaRecordId = String(req.body?.mediaRecordId || req.body?.media_record_id || '').trim();
  if (!mediaRecordId) return res.status(400).json({ error: 'mediaRecordId is required' });
  const { data: media, error } = await supabase.from('customer_media')
    .select('id, org_id, storage_path, recipient_psid, page_id, caption, approval_status, approved_by, approved_at')
    .eq('id', mediaRecordId).eq('org_id', req.orgId).single();
  if (error || !media) return res.status(404).json({ error: 'Try-On media record not found in your organization' });
  if (media.approval_status === 'sending' || media.approval_status === 'sent') {
    return res.status(409).json({ error: 'ALREADY_SENT_OR_SENDING' });
  }
  if (media.approval_status !== 'approved' || !media.approved_by || !media.approved_at || !media.storage_path) {
    return res.status(403).json({ error: 'NOT_APPROVED' });
  }

  const recipientId = String(media.recipient_psid || '').trim();
  if (!recipientId) {
    return res.status(422).json({ error: 'NO_RECIPIENT_OR_PAGE' });
  }
  const storedPageId = String(media.page_id || '').trim();
  const bodyPageId = String(req.body?.pageId || req.body?.page_id || '').trim();
  if (storedPageId && bodyPageId && storedPageId !== bodyPageId) {
    return res.status(422).json({ error: 'PAGE_MISMATCH' });
  }
  const targetPageId = storedPageId || bodyPageId;
  if (!targetPageId) {
    return res.status(422).json({ error: 'MISSING_PAGE_CONTEXT' });
  }

  const page = await resolvePageCredentialsForOrg(req.orgId, targetPageId);
  if (!page) {
    return res.status(422).json({ error: 'NO_RECIPIENT_OR_PAGE' });
  }

  const { data: claimed } = await supabase.from('customer_media')
    .update({ approval_status: 'sending' })
    .eq('id', media.id)
    .eq('org_id', req.orgId)
    .eq('approval_status', 'approved')
    .select('id')
    .maybeSingle();
  if (!claimed) return res.status(409).json({ error: 'ALREADY_SENT_OR_SENDING' });

  const signedUrlTtlSeconds = 3600;
  try {
    const signedUrl = await createSignedUrl(media.storage_path, signedUrlTtlSeconds);
    console.info(JSON.stringify({
      event: 'send_tryon_dispatch',
      mediaId: media.id,
      pageId: page.pageId,
      signedUrlTtlSeconds,
    }));
    await axios.post(`https://graph.facebook.com/${config.graphApiVersion}/${page.pageId}/messages`, {
      recipient: { id: recipientId }, messaging_type: 'RESPONSE',
      message: { attachment: { type: 'image', payload: { url: signedUrl, is_reusable: false } } },
    }, { headers: { Authorization: `Bearer ${page.pageAccessToken}` }, timeout: 20000 });
    if (media.caption) await axios.post(`https://graph.facebook.com/${config.graphApiVersion}/${page.pageId}/messages`, {
      recipient: { id: recipientId }, messaging_type: 'RESPONSE', message: { text: String(media.caption).trim() },
    }, { headers: { Authorization: `Bearer ${page.pageAccessToken}` }, timeout: 15000 });
    await supabase.from('customer_media').update({ approval_status: 'sent' }).eq('id', media.id).eq('org_id', req.orgId);
    return res.json({ success: true, signedUrl, deliveredToMessenger: true });
  } catch (error) {
    await supabase.from('customer_media').update({ approval_status: 'approved' }).eq('id', media.id).eq('org_id', req.orgId);
    console.error(JSON.stringify({
      event: 'send_tryon_failed',
      mediaId: media.id,
      pageId: page.pageId,
      signedUrlTtlSeconds,
      status: error.response?.status,
      code: error.response?.data?.error?.code,
    }));
    const mapped = mapMetaSendError(error);
    return res.status(mapped.status).json(mapped.body);
  }
}));

const HANDOFF_DAILY_AI_CAP = 50;
const ANALYSIS_SCHEMA = {
  type: 'OBJECT',
  properties: {
    summary: { type: 'STRING' },
    risk: { type: 'STRING', enum: ['low', 'medium', 'high'] },
    face_detected: { type: 'BOOLEAN' },
    recommended_item_id: { type: 'STRING' },
    draft_reply: { type: 'STRING' },
  },
  required: ['summary', 'risk', 'draft_reply'],
};

const HANDOFF_PROMPT = [
  'Bạn là trợ lý phân tích nội bộ cho chủ tiệm thẩm mỹ/phun xăm.',
  '- Tóm tắt ngắn gọn nhu cầu khách (summary) và đánh giá mức độ rủi ro ca làm (risk: low, medium, high — ca sửa mày trổ xanh/đỏ, sẹo, cơ địa nhạy cảm là high).',
  '- Nếu có ảnh: xác định face_detected (true/false) và chọn recommended_item_id phù hợp nhất trong DANH MỤC (hoặc để trống nếu không phù hợp).',
  '- Soạn draft_reply lịch sự, tự nhiên để chủ tiệm kiểm duyệt trước khi gửi. KHÔNG tự bịa giá ngoài danh mục, KHÔNG cam kết 100% hay đảm bảo tuyệt đối.',
].join('\n');

function detectImageMime(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) return 'image/png';
  if (
    buf[0] === 0x52 && buf[1] === 0x49 && buf[2] === 0x46 && buf[3] === 0x46 &&
    buf[8] === 0x57 && buf[9] === 0x45 && buf[10] === 0x42 && buf[11] === 0x50
  ) return 'image/webp';
  return null;
}

async function loadCatalog(orgId) {
  const { data } = await supabase.from('catalog_items')
    .select('id, name, category, price')
    .eq('org_id', orgId);
  return Array.isArray(data) ? data : [];
}

async function dailyAiCount(orgId) {
  const vnNow = new Date(Date.now() + 7 * 3600 * 1000);
  const yyyy = vnNow.getUTCFullYear();
  const mo = String(vnNow.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(vnNow.getUTCDate()).padStart(2, '0');
  const startOfVnDayIso = new Date(`${yyyy}-${mo}-${dd}T00:00:00+07:00`).toISOString();
  const { count } = await supabase.from('handoff_cases')
    .select('id', { count: 'exact', head: true })
    .eq('org_id', orgId)
    .gte('created_at', startOfVnDayIso)
    .in('status', ['analyzing', 'pending_review', 'approved', 'sending', 'sent', 'rejected']);
  return count || 0;
}

async function analyzeCase({ orgId, text, imageBase64, mime, catalog }) {
  const geminiKey = String(process.env.GEMINI_API_KEY || '').trim();
  if (!geminiKey) {
    throw Object.assign(new Error('GEMINI_NOT_CONFIGURED'), { code: 'GEMINI_NOT_CONFIGURED' });
  }
  const cap = await dailyAiCount(orgId);
  if (cap >= HANDOFF_DAILY_AI_CAP) {
    throw Object.assign(new Error('AI_DAILY_CAP'), { code: 'AI_DAILY_CAP' });
  }
  const parts = [{
    text: `${HANDOFF_PROMPT}\nDANH MỤC: ${JSON.stringify(catalog)}\nKHÁCH NÓI: ${text || '(không có)'}`,
  }];
  if (imageBase64 && mime) {
    parts.push({ inline_data: { mime_type: mime, data: imageBase64 } });
  }
  const { data } = await axios.post(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
    {
      contents: [{ parts }],
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: ANALYSIS_SCHEMA,
        temperature: 0.2,
      },
    },
    { headers: { 'x-goog-api-key': geminiKey }, timeout: 30000 },
  );
  const rawText = data?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
  const out = JSON.parse(rawText);
  if (!catalog.some((c) => String(c.id) === String(out.recommended_item_id))) {
    out.recommended_item_id = null;
  }
  return out;
}

app.get('/handoff-cases', requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 30, 1), 100);
  const rawStatus = String(req.query.status || '').trim();
  const allowedStatuses = new Set(['new', 'analyzing', 'pending_review', 'approved', 'sending', 'sent', 'rejected', 'failed']);
  const statusList = rawStatus
    ? rawStatus.split(',').map((s) => s.trim()).filter((s) => allowedStatuses.has(s))
    : [];

  let query = supabase.from('handoff_cases')
    .select('id, org_id, source, message_id, page_id, psid, customer_text, image_path, status, analysis, draft_reply, created_by, approved_by, approved_at, created_at')
    .eq('org_id', req.orgId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (statusList.length === 1) {
    query = query.eq('status', statusList[0]);
  } else if (statusList.length > 1) {
    query = query.in('status', statusList);
  }
  const { data, error } = await query;
  if (error) {
    console.error(JSON.stringify({ event: 'fetch_handoff_cases_failed', message: error.message }));
    return res.status(500).json({ error: 'Failed to fetch handoff cases' });
  }
  const cases = await Promise.all((data || []).map(async (row) => {
    let signedImageUrl = null;
    if (row.image_path) {
      try { signedImageUrl = await createSignedUrl(row.image_path, 3600); } catch (_) { /* ignore */ }
    }
    return { ...row, image_url: signedImageUrl };
  }));
  return res.json({ cases });
}));

app.post('/handoff-cases/capture', writeLimiter, requireAuth, requireRole('owner', 'staff'),
  express.json({ limit: '15mb' }), asyncHandler(async (req, res) => {
    const imageBase64 = String(req.body?.image_base64 || '').trim();
    const customerText = typeof req.body?.customer_text === 'string' ? req.body.customer_text.trim() : null;
    if (!imageBase64) return res.status(400).json({ error: 'IMAGE_REQUIRED' });
    const buf = Buffer.from(imageBase64, 'base64');
    if (!buf.length || buf.length > 15 * 1024 * 1024) return res.status(413).json({ error: 'IMAGE_TOO_LARGE' });
    const mime = detectImageMime(buf);
    if (!mime) return res.status(415).json({ error: 'UNSUPPORTED_IMAGE_TYPE' });
    const ext = mime === 'image/png' ? 'png' : (mime === 'image/webp' ? 'webp' : 'jpg');
    const storagePath = `owner/${req.orgId}/${crypto.randomUUID()}.${ext}`;
    const { error: upErr } = await uploadWithRetry(storagePath, buf, mime);
    if (upErr) return res.status(502).json({ error: 'UPLOAD_FAILED' });
    const catalog = await loadCatalog(req.orgId);
    const { data: row, error: insertErr } = await supabase.from('handoff_cases').insert({
      org_id: req.orgId,
      source: 'owner_capture',
      customer_text: customerText,
      image_path: storagePath,
      created_by: req.authUser.id,
      status: 'analyzing',
    }).select('id').single();
    if (insertErr || !row) return res.status(500).json({ error: 'CASE_CREATE_FAILED' });

    try {
      const analysis = await analyzeCase({ orgId: req.orgId, text: customerText, imageBase64, mime, catalog });
      await supabase.from('handoff_cases').update({
        analysis,
        draft_reply: analysis.draft_reply || null,
        status: 'pending_review',
      }).eq('id', row.id).eq('org_id', req.orgId);
      return res.json({ id: row.id, status: 'pending_review', analysis });
    } catch (err) {
      await supabase.from('handoff_cases').update({ status: 'failed' }).eq('id', row.id).eq('org_id', req.orgId);
      const status = err.code === 'AI_DAILY_CAP' ? 429 : (err.code === 'GEMINI_NOT_CONFIGURED' ? 503 : 502);
      return res.status(status).json({ error: err.code || 'AI_FAILED' });
    }
  }));

app.post('/handoff-cases/:id/analyze', writeLimiter, requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data: row } = await supabase.from('handoff_cases').select('*')
    .eq('id', req.params.id).eq('org_id', req.orgId).maybeSingle();
  if (!row) return res.status(404).json({ error: 'NOT_FOUND' });
  if (row.status !== 'new' && row.status !== 'failed') {
    return res.status(409).json({ error: 'ALREADY_ANALYZED' });
  }
  await supabase.from('handoff_cases').update({ status: 'analyzing' }).eq('id', row.id).eq('org_id', req.orgId);
  try {
    let imageBase64 = null;
    let mime = null;
    if (row.image_path) {
      const { data: blob, error: dlErr } = await supabase.storage.from(config.storageBucket).download(row.image_path);
      if (!dlErr && blob) {
        const buf = Buffer.from(await blob.arrayBuffer());
        mime = detectImageMime(buf);
        if (mime) imageBase64 = buf.toString('base64');
      }
    }
    const catalog = await loadCatalog(req.orgId);
    const analysis = await analyzeCase({ orgId: req.orgId, text: row.customer_text, imageBase64, mime, catalog });
    await supabase.from('handoff_cases').update({
      analysis,
      draft_reply: analysis.draft_reply || null,
      status: 'pending_review',
    }).eq('id', row.id).eq('org_id', req.orgId);
    return res.json({ id: row.id, status: 'pending_review', analysis });
  } catch (err) {
    await supabase.from('handoff_cases').update({ status: 'failed' }).eq('id', row.id).eq('org_id', req.orgId);
    const status = err.code === 'AI_DAILY_CAP' ? 429 : (err.code === 'GEMINI_NOT_CONFIGURED' ? 503 : 502);
    return res.status(status).json({ error: err.code || 'AI_FAILED' });
  }
}));

app.post('/handoff-cases/:id/approve', writeLimiter, requireAuth, requireRole('owner', 'staff'),
  express.json({ limit: '8kb' }), asyncHandler(async (req, res) => {
    const text = String(req.body?.draft_reply || '').trim();
    if (!text || text.length > 2000) return res.status(400).json({ error: 'TEXT_INVALID' });
    const { data, error } = await supabase.from('handoff_cases').update({
      draft_reply: text,
      status: 'approved',
      approved_by: req.authUser.id,
      approved_at: new Date().toISOString(),
    })
      .eq('id', req.params.id)
      .eq('org_id', req.orgId)
      .eq('status', 'pending_review')
      .select('id, status')
      .maybeSingle();
    if (error || !data) return res.status(404).json({ error: 'NOT_PENDING' });
    return res.json({ success: true, id: data.id, status: data.status });
  }));

app.post('/handoff-cases/:id/reject', writeLimiter, requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data, error } = await supabase.from('handoff_cases').update({ status: 'rejected' })
    .eq('id', req.params.id)
    .eq('org_id', req.orgId)
    .in('status', ['new', 'pending_review', 'approved'])
    .select('id, status')
    .maybeSingle();
  if (error || !data) return res.status(404).json({ error: 'NOT_REJECTABLE' });
  return res.json({ success: true, id: data.id, status: data.status });
}));

app.post('/handoff-cases/:id/send', writeLimiter, requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const { data: c } = await supabase.from('handoff_cases').select('*')
    .eq('id', req.params.id).eq('org_id', req.orgId).maybeSingle();
  if (!c) return res.status(404).json({ error: 'NOT_FOUND' });
  if (c.status === 'sending' || c.status === 'sent') return res.status(409).json({ error: 'ALREADY_SENDING' });
  if (c.status !== 'approved' || !c.approved_by || !c.approved_at || !c.draft_reply) {
    return res.status(403).json({ error: 'NOT_APPROVED' });
  }
  if (!c.psid || !c.page_id) return res.status(422).json({ error: 'NO_RECIPIENT' });
  const page = await resolvePageCredentialsForOrg(req.orgId, c.page_id);
  if (!page) return res.status(503).json({ error: 'NO_PAGE' });
  const { data: claimed } = await supabase.from('handoff_cases').update({ status: 'sending' })
    .eq('id', c.id).eq('org_id', req.orgId).eq('status', 'approved').select('id').maybeSingle();
  if (!claimed) return res.status(409).json({ error: 'ALREADY_SENDING' });
  try {
    await axios.post(`https://graph.facebook.com/${config.graphApiVersion}/${page.pageId}/messages`, {
      recipient: { id: c.psid }, messaging_type: 'RESPONSE', message: { text: c.draft_reply },
    }, { headers: { Authorization: `Bearer ${page.pageAccessToken}` }, timeout: 15000 });
    await supabase.from('handoff_cases').update({ status: 'sent' }).eq('id', c.id).eq('org_id', req.orgId);
    return res.json({ success: true });
  } catch (err) {
    await supabase.from('handoff_cases').update({ status: 'approved' }).eq('id', c.id).eq('org_id', req.orgId);
    const mapped = mapMetaSendError(err);
    return res.status(mapped.status).json(mapped.body);
  }
}));

app.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];
  if (mode === 'subscribe' && config.verifyToken && typeof token === 'string' && safeEqual(token, config.verifyToken) && typeof challenge === 'string') {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

app.get('/messages', requireAuth, requireRole('owner', 'staff'), asyncHandler(async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 30, 1), 100);
  const { data, error } = await supabase.from('conversation_messages').select('*').eq('org_id', req.orgId)
    .order('created_at', { ascending: false }).limit(limit);
  if (error) {
    console.error(JSON.stringify({ event: 'fetch_messages_failed', message: error.message }));
    return res.status(500).json({ error: 'Failed to fetch messages' });
  }
  const rows = await Promise.all((data || []).map(async (row) => {
    let freshImageUrl = null;
    if (row.storage_path) {
      try {
        freshImageUrl = await createSignedUrl(row.storage_path, 3600);
      } catch (signErr) {
        console.warn(JSON.stringify({ event: 'sign_message_image_failed', message: signErr.message }));
      }
    }
    return {
      ...row,
      image_url: freshImageUrl,
      attachment_url: undefined,
      storage_url: undefined,
    };
  }));
  return res.json({ messages: rows });
}));

async function recordWebhookSignal({ eventId, eventType, senderPsid, messageId, messageType, messageText, rawPayload }) {
  if (!supabase) return;
  const { error } = await supabase.from('webhook_events').upsert({
    event_id: eventId,
    event_type: eventType,
    sender_psid: senderPsid || null,
    message_id: messageId || null,
    message_type: messageType || null,
    message_text: messageText || null,
    raw_payload: rawPayload,
    received_at: new Date().toISOString(),
  }, { onConflict: 'event_id', ignoreDuplicates: true });
  if (error) throw new Error(`Could not persist webhook signal: ${error.message}`);
}

function classifyWebhookEvent(event) {
  if (event.message) return event.message.is_echo ? 'facebook_message_echo' : 'facebook_message_inbound';
  if (event.pass_thread_control) return 'messaging_handover_pass';
  if (event.take_thread_control) return 'messaging_handover_take';
  if (event.request_thread_control) return 'messaging_handover_request';
  if (event.postback) return 'messaging_postback';
  if (event.delivery) return 'messaging_delivery';
  if (event.read) return 'messaging_read';
  if (event.standby) return 'messaging_standby';
  return 'messaging_other';
}

app.post('/webhook', express.raw({ type: 'application/json', limit: '10mb' }), asyncHandler(async (req, res) => {
  if (!config.metaAppSecret || !supabase) return res.status(503).send('Service Unavailable');
  const rawBody = req.body;
  if (!Buffer.isBuffer(rawBody) || rawBody.length === 0) return res.status(400).send('Missing body');
  if (!verifyMetaSignature(rawBody, req.get('x-hub-signature-256'))) {
    console.warn(JSON.stringify({ event: 'webhook_signature_rejected' }));
    return res.status(403).send('Forbidden');
  }

  let payload;
  try { payload = JSON.parse(rawBody.toString('utf8')); }
  catch { return res.status(400).send('Invalid JSON'); }
  if (payload.object !== 'page') return res.status(404).send('Unsupported webhook object');

  try {
    for (const entry of (Array.isArray(payload.entry) ? payload.entry : [])) {
      const pageId = entry.id ? String(entry.id) : null;
      const orgId = await resolveOrgIdByPageId(pageId);
      if (!orgId) {
        console.warn(JSON.stringify({ event: 'webhook_unmapped_page_ignored', pageId }));
        continue;
      }

      for (const event of (Array.isArray(entry.messaging) ? entry.messaging : [])) {
        const eventType = classifyWebhookEvent(event);
        webhookDiagnostics.received += 1;
        webhookDiagnostics.lastReceivedAt = new Date().toISOString();
        webhookDiagnostics.lastPageId = pageId;
        webhookDiagnostics.lastKinds = [eventType];

        if (event.pass_thread_control) {
          const senderId = String(event.sender?.id || '').trim();
          if (senderId && pageId) {
            await supabase.from('handover_threads').upsert({
              org_id: orgId,
              page_id: pageId,
              psid: senderId,
              active: true,
              updated_at: new Date().toISOString(),
            }, { onConflict: 'page_id,psid' });
          }
          const signalId = eventIdForSignal(pageId, event);
          await recordWebhookSignal({ eventId: signalId, eventType,
            senderPsid: senderId || event.recipient?.id,
            rawPayload: { pageId, event } });
          continue;
        }

        if (event.message) {
          const uploadedPath = await handleFacebookMessage(orgId, pageId, event, event.message);
          if (!event.message.is_echo && pageId) {
            const senderId = String(event.sender?.id || '').trim();
            if (senderId) {
              const { data: th } = await supabase.from('handover_threads')
                .select('org_id')
                .eq('page_id', pageId)
                .eq('psid', senderId)
                .eq('active', true)
                .maybeSingle();
              if (th) {
                await supabase.from('handoff_cases').upsert({
                  org_id: th.org_id,
                  source: 'business_ai_handover',
                  message_id: event.message.mid || eventIdForSignal(pageId, event),
                  page_id: pageId,
                  psid: senderId,
                  customer_text: typeof event.message.text === 'string' ? event.message.text : null,
                  image_path: uploadedPath || null,
                  status: 'new',
                }, { onConflict: 'message_id', ignoreDuplicates: true });
              }
            }
          }
        } else {
          const signalId = eventIdForSignal(pageId, event);
          await recordWebhookSignal({ eventId: signalId, eventType,
            senderPsid: event.sender?.id || event.recipient?.id,
            rawPayload: { pageId, event } });
        }
      }

      // Handle Meta Handover Protocol standby channel events
      for (const standbyEvent of (Array.isArray(entry.standby) ? entry.standby : [])) {
        const eventType = 'messaging_standby';
        webhookDiagnostics.received += 1;
        webhookDiagnostics.lastReceivedAt = new Date().toISOString();
        webhookDiagnostics.lastPageId = pageId;
        webhookDiagnostics.lastKinds = [eventType];
        const signalId = eventIdForSignal(pageId, standbyEvent);
        await recordWebhookSignal({
          eventId: signalId,
          eventType,
          senderPsid: standbyEvent.sender?.id || standbyEvent.recipient?.id,
          messageId: standbyEvent.message?.mid || null,
          messageText: typeof standbyEvent.message?.text === 'string' ? standbyEvent.message.text : null,
          rawPayload: { pageId, standby: standbyEvent },
        });
      }

      for (const change of (Array.isArray(entry.changes) ? entry.changes : [])) {
        const value = change.value || {};
        for (const message of (Array.isArray(value.messages) ? value.messages : [])) {
          const event = { sender: value, message };
          const eventType = classifyWebhookEvent(event);
          webhookDiagnostics.received += 1;
          webhookDiagnostics.lastReceivedAt = new Date().toISOString();
          webhookDiagnostics.lastPageId = pageId;
          webhookDiagnostics.lastKinds = [eventType];
          await handleFacebookMessage(orgId, pageId, event, message);
        }
      }
    }
  } catch (error) {
    console.error(JSON.stringify({ event: 'webhook_processing_failed', message: error.message }));
    return res.status(500).send('Processing failed');
  }
  return res.status(200).send('EVENT_RECEIVED');
}));

function eventIdForSignal(pageId, event) {
  const eventTime = event.timestamp || '';
  const raw = JSON.stringify(event);
  return event.mid || event.message?.mid || crypto.createHash('sha256')
    .update(`${pageId || ''}:${eventTime}:${raw}`).digest('hex');
}

async function resolveOrgIdByPageId(pageId) {
  if (!pageId || !supabase) return null;
  const { data } = await supabase.from('connected_pages').select('org_id').eq('page_id', pageId).maybeSingle();
  return data?.org_id || null;
}

async function handleFacebookMessage(orgId, pageId, event, message) {
  const isEcho = message.is_echo === true;
  const senderPsid = String(isEcho
    ? (event.recipient?.id || message.to?.id || event.sender?.id || '')
    : (event.sender?.id || message.from?.id || '')).trim();
  const messageId = message.mid || message.id || null;
  const attachment = Array.isArray(message.attachments) ? message.attachments[0] : null;
  const messageText = typeof message.text === 'string' ? message.text
    : (typeof message.text?.body === 'string' ? message.text.body : null);
  const imageUrl = attachment?.type === 'image' && typeof attachment.payload?.url === 'string'
    ? attachment.payload.url : null;
  const eventType = isEcho ? 'facebook_message_echo' : 'facebook_message_inbound';
  const eventId = messageId || eventIdForSignal(pageId, event);

  await recordWebhookSignal({ eventId, eventType, senderPsid, messageId,
    messageType: attachment?.type || 'text', messageText, rawPayload: { pageId, event, message } });
  if (!orgId) {
    console.warn(JSON.stringify({ event: 'webhook_message_unmapped_page', pageId, eventType }));
    return;
  }

  let uploaded = null;
  if (!isEcho && imageUrl) uploaded = await uploadImageToSupabase(orgId, imageUrl, messageId || crypto.randomUUID());
  const { error } = await supabase.from('conversation_messages').upsert({
    org_id: orgId,
    page_id: pageId || null,
    channel: 'facebook',
    customer_psid: senderPsid || null,
    sender: isEcho ? 'system' : 'customer',
    message_type: attachment?.type || 'text',
    message_text: messageText,
    image_url: null,
    storage_path: uploaded?.path || null,
    message_id: messageId,
    attachment_type: attachment?.type || null,
    attachment_url: null,
    is_from_customer: !isEcho,
    approval_status: isEcho ? 'sent' : 'pending',
    created_at: new Date().toISOString(),
  }, { onConflict: 'message_id', ignoreDuplicates: true });
  if (error) throw new Error(`Could not persist conversation message: ${error.message}`);

  if (uploaded) {
    const { error: mediaError } = await supabase.from('customer_media').upsert({
      org_id: orgId, page_id: pageId || null, recipient_psid: senderPsid || null,
      source_channel: 'facebook', source_message_id: messageId,
      source_url: null, storage_url: null, storage_path: uploaded.path,
      file_name: uploaded.path, mime_type: uploaded.mimeType, file_size: uploaded.size,
      approval_status: 'pending', uploaded_at: new Date().toISOString(),
    }, { onConflict: 'source_message_id', ignoreDuplicates: true });
    if (mediaError) throw new Error(`Could not persist customer media: ${mediaError.message}`);
  }
  return uploaded?.path || null;
}

async function uploadImageToSupabase(orgId, remoteUrl, messageId) {
  const safeOrgId = String(orgId || '').replace(/[^a-zA-Z0-9_-]/g, '');
  if (!safeOrgId) throw new Error('Organization ID is required for image upload');
  let parsedUrl;
  try { parsedUrl = new URL(remoteUrl); } catch { throw new Error('Invalid image URL'); }
  const allowed = parsedUrl.protocol === 'https:' &&
    (parsedUrl.hostname === 'fbcdn.net' || parsedUrl.hostname.endsWith('.fbcdn.net') ||
      parsedUrl.hostname === 'fbsbx.com' || parsedUrl.hostname.endsWith('.fbsbx.com'));
  if (!allowed) throw new Error('Image URL host is not an allowed Facebook CDN host');
  const response = await axios.get(parsedUrl.toString(), { responseType: 'arraybuffer', timeout: 20000,
    maxRedirects: 0, maxContentLength: 15 * 1024 * 1024, maxBodyLength: 15 * 1024 * 1024,
    validateStatus: (status) => status >= 200 && status < 300 });
  const mimeType = String(response.headers['content-type'] || '').split(';')[0].toLowerCase();
  const extensions = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  if (!extensions[mimeType]) throw new Error('Unsupported image content type');
  const buffer = Buffer.from(response.data);
  if (!buffer.length || buffer.length > 15 * 1024 * 1024) throw new Error('Image size is invalid');
  const safeId = crypto.createHash('sha256').update(String(messageId)).digest('hex');
  const path = `facebook/${safeOrgId}/${safeId}.${extensions[mimeType]}`;
  const { error } = await uploadWithRetry(path, buffer, mimeType);
  if (error) throw new Error(`Supabase Storage upload failed: ${error.message}`);
  return { path, mimeType, size: buffer.length };
}

async function createSignedUrl(path, expiresInSeconds = 3600) {
  if (!supabase) throw new Error('Supabase client is not initialized');
  const { data, error } = await supabase.storage.from(config.storageBucket).createSignedUrl(path, expiresInSeconds);
  if (error || !data?.signedUrl) throw new Error(`Could not create signed URL: ${error?.message || 'unknown error'}`);
  return data.signedUrl;
}

async function uploadWithRetry(path, buffer, mimeType, maxRetries = 3) {
  let lastError;
  for (let attempt = 0; attempt < maxRetries; attempt += 1) {
    const { error } = await supabase.storage.from(config.storageBucket).upload(path, buffer, {
      contentType: mimeType, upsert: true, cacheControl: '3600',
    });
    if (!error) return { error: null };
    lastError = error;
    if (attempt < maxRetries - 1) await new Promise((resolve) => setTimeout(resolve, 500 * (2 ** attempt)));
  }
  return { error: lastError };
}

app.use((err, _req, res, _next) => {
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'BAD_JSON' });
  }
  console.error(JSON.stringify({ event: 'unhandled_route_error', message: err?.message || 'unknown' }));
  return res.status(500).json({ error: 'SERVER_ERROR' });
});

if (require.main === module) {
  app.listen(port, () => console.log(JSON.stringify({ event: 'server_started', service: 'pyincc-meta-webhook', port })));
}

module.exports = {
  app,
  purgeFacebookUserData,
  resolvePageCredentialsForOrg,
  uploadImageToSupabase,
  verifyFacebookSignedRequest,
};
