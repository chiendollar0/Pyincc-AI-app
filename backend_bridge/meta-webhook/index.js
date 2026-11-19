const express = require('express');
const crypto = require('crypto');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const app = express();
app.disable('x-powered-by');
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
  defaultOrgId: process.env.DEFAULT_ORG_ID || null,
  pageId: process.env.PAGE_ID || null,
  pageAccessToken: process.env.PAGE_ACCESS_TOKEN || null,
  graphApiVersion: process.env.META_GRAPH_API_VERSION || 'v21.0',
  storageBucket: process.env.SUPABASE_STORAGE_BUCKET || 'customer-media',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || 'https://pyincccrm.bothelper.vn',
};

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
      statusBanner = `<p style="padding:12px;background:#e8f5e9;border-radius:8px;color:#1b5e20;"><strong>Mã xác nhận ${row.code}:</strong> Trạng thái <code>${row.status}</code> (ghi nhận lúc ${row.created_at}). Toàn bộ liên kết Fanpage, token đã mã hóa và thông tin lời mời Facebook của tài khoản này đã được xóa.</p>`;
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
    '<ol><li>Vào Cài đặt Facebook → Tiện ích tích hợp cho doanh nghiệp (Business Integrations) → chọn <strong>PyinccCRM</strong> → bấm <strong>Gỡ</strong>. Hệ thống sẽ tự động nhận tín hiệu thu hồi và xóa toàn bộ Page Token, liên kết Fanpage và thông tin thành viên Facebook.</li>' +
    '<li>Hoặc gửi email yêu cầu xóa toàn bộ dữ liệu hội thoại về <strong>phanhungkg03@gmail.com</strong>, yêu cầu sẽ được xử lý trong vòng 48 giờ.</li></ol></body></html>'
  );
}));
app.get('/internal/status', requireInternalApiKey, (_req, res) =>
  res.json({ ok: true, configured: missingConfig.length === 0 }));
app.get('/internal/webhook-status', requireInternalApiKey, (_req, res) =>
  res.json({ ...webhookDiagnostics }));

// Returns 501 Not Implemented until an image generation model is configured (Section 1 & Section 12)
app.post('/api/tryon/generate', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), asyncHandler(async (req, res) => {
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

app.post('/memberships/invite', requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const invitedEmail = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : null;
  const invitedFbUserId = typeof req.body?.fbUserId === 'string' ? req.body.fbUserId.trim() : null;
  if (!invitedEmail && !invitedFbUserId) return res.status(400).json({ error: 'email or fbUserId is required to invite staff' });
  const { data, error } = await supabase.from('memberships').insert({
    org_id: req.orgId, invited_email: invitedEmail, invited_fb_user_id: invitedFbUserId,
    role: 'staff', status: 'pending',
  }).select('id, org_id, invited_email, invited_fb_user_id, role, status, created_at').single();
  if (error) return res.status(500).json({ error: 'Failed to create staff invitation' });
  return res.json({ success: true, invitation: data });
}));

app.post('/auth/facebook/exchange-token', requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
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
  const { error: memErr } = await supabase.from('memberships').delete().eq('invited_fb_user_id', fbUserId);
  if (memErr) throw new Error(`memberships_delete_failed: ${memErr.message}`);
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

async function resolvePageCredentialsForOrg(orgId, requestedPageId) {
  let query = supabase.from('connected_pages').select('page_id, page_access_token')
    .eq('org_id', orgId).order('updated_at', { ascending: false }).limit(1);
  if (requestedPageId) query = query.eq('page_id', requestedPageId);
  const { data } = await query;
  if (Array.isArray(data) && data.length && data[0].page_access_token) {
    return { pageId: data[0].page_id, pageAccessToken: decryptPageToken(data[0].page_access_token) };
  }
  if (config.pageId && config.pageAccessToken && config.defaultOrgId && String(orgId) === String(config.defaultOrgId)) {
    return { pageId: config.pageId, pageAccessToken: config.pageAccessToken };
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

app.put('/settings', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '32kb' }), asyncHandler(async (req, res) => {
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

app.post('/bookings', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
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

app.post('/messages/:id/approve', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const messageRowId = String(req.params.id || '').trim();
  const draftReply = String(req.body?.text || req.body?.draftReply || '').trim();
  if (!messageRowId || !draftReply) return res.status(400).json({ error: 'message id and text are required' });
  if (draftReply.length > 2000) return res.status(400).json({ error: 'text must be 2000 characters or fewer' });
  const approvedAt = new Date().toISOString();
  const { data, error } = await supabase.from('conversation_messages').update({ draft_reply: draftReply,
    approval_status: 'approved', approved_by: req.authUser.id, approved_at: approvedAt })
    .eq('id', messageRowId).eq('org_id', req.orgId)
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

app.post('/send-message', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const messageRecordId = String(req.body?.messageRecordId || req.body?.message_record_id || '').trim();
  const requestedPageId = req.body?.pageId || req.body?.page_id;
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

  const page = await resolvePageCredentialsForOrg(req.orgId, requestedPageId || msg.page_id);
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

app.post('/tryon-drafts', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), asyncHandler(async (req, res) => {
  const recipientId = String(req.body?.recipientId || req.body?.recipient_id || '').trim();
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
    recipient_psid: recipientId || null, caption: caption || null, approval_status: 'pending',
    approved_by: null, approved_at: null, uploaded_at: createdAt })
    .select('id, org_id, storage_path, approval_status, approved_by, approved_at').single();
  if (error || !media) return res.status(500).json({ error: 'Failed to persist Try-On draft media record' });
  return res.json({ success: true, media });
}));

app.post('/tryon-drafts/:id/approve', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const mediaRecordId = String(req.params.id || '').trim();
  if (!mediaRecordId) return res.status(400).json({ error: 'media id is required' });
  const captionOverride = typeof req.body?.caption === 'string' ? req.body.caption.trim() : undefined;
  const approvedAt = new Date().toISOString();
  const updatePayload = {
    approval_status: 'approved',
    approved_by: req.authUser.id,
    approved_at: approvedAt,
  };
  if (captionOverride !== undefined) updatePayload.caption = captionOverride || null;
  const { data: media, error } = await supabase.from('customer_media')
    .update(updatePayload)
    .eq('id', mediaRecordId)
    .eq('org_id', req.orgId)
    .eq('approval_status', 'pending')
    .select('id, org_id, storage_path, recipient_psid, caption, approval_status, approved_by, approved_at')
    .maybeSingle();
  if (error || !media) return res.status(404).json({ error: 'Pending Try-On draft not found in your organization' });
  return res.json({ success: true, media });
}));

app.post('/send-tryon-image', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), asyncHandler(async (req, res) => {
  const mediaRecordId = String(req.body?.mediaRecordId || req.body?.media_record_id || '').trim();
  if (!mediaRecordId) return res.status(400).json({ error: 'mediaRecordId is required' });
  const { data: media, error } = await supabase.from('customer_media')
    .select('id, org_id, storage_path, recipient_psid, caption, approval_status, approved_by, approved_at')
    .eq('id', mediaRecordId).eq('org_id', req.orgId).single();
  if (error || !media) return res.status(404).json({ error: 'Try-On media record not found in your organization' });
  if (media.approval_status === 'sending' || media.approval_status === 'sent') {
    return res.status(409).json({ error: 'ALREADY_SENT_OR_SENDING' });
  }
  if (media.approval_status !== 'approved' || !media.approved_by || !media.approved_at || !media.storage_path) {
    return res.status(403).json({ error: 'NOT_APPROVED' });
  }

  const recipientId = String(media.recipient_psid || '').trim();
  const page = await resolvePageCredentialsForOrg(req.orgId, req.body?.pageId);
  if (!recipientId || !page) {
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

  try {
    const signedUrl = await createSignedUrl(media.storage_path, 3600);
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
    console.error(JSON.stringify({ event: 'send_tryon_failed', status: error.response?.status, code: error.response?.data?.error?.code }));
    const mapped = mapMetaSendError(error);
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

        if (event.message) {
          await handleFacebookMessage(orgId, pageId, event, event.message);
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
  if (!isEcho && imageUrl) uploaded = await uploadImageToSupabase(imageUrl, messageId || crypto.randomUUID());
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
      org_id: orgId, source_channel: 'facebook', source_message_id: messageId,
      source_url: null, storage_url: null, storage_path: uploaded.path,
      file_name: uploaded.path, mime_type: uploaded.mimeType, file_size: uploaded.size,
      approval_status: 'pending', uploaded_at: new Date().toISOString(),
    }, { onConflict: 'source_message_id', ignoreDuplicates: true });
    if (mediaError) throw new Error(`Could not persist customer media: ${mediaError.message}`);
  }
}

async function uploadImageToSupabase(remoteUrl, messageId) {
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
  const path = `facebook/${safeId}.${extensions[mimeType]}`;
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

app.listen(port, () => console.log(JSON.stringify({ event: 'server_started', service: 'pyincc-meta-webhook', port })));
