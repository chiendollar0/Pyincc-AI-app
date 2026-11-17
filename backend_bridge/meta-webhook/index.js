const express = require('express');
const crypto = require('crypto');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const port = Number(process.env.PORT) || 3000;
const config = {
  supabaseUrl: process.env.SUPABASE_URL || 'https://ihufvqrxdswgbagzhydb.supabase.co',
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  metaAppId: process.env.META_APP_ID,
  metaAppSecret: process.env.META_APP_SECRET,
  verifyToken: process.env.VERIFY_TOKEN,
  apiKey: process.env.API_KEY,
  graphApiVersion: process.env.META_GRAPH_API_VERSION || 'v19.0',
  storageBucket: process.env.SUPABASE_STORAGE_BUCKET || 'customer-media',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || 'https://pyincc-ai-app.onrender.com',
};

const requiredConfig = [
  ['SUPABASE_URL', config.supabaseUrl],
  ['SUPABASE_SERVICE_ROLE_KEY', config.supabaseServiceRoleKey],
  ['META_APP_SECRET', config.metaAppSecret],
  ['VERIFY_TOKEN', config.verifyToken],
];
const missingConfig = requiredConfig.filter(([, value]) => !value).map(([name]) => name);
if (missingConfig.length) {
  console.warn(JSON.stringify({
    event: 'missing_env_vars',
    missing: missingConfig,
  }));
}

const supabase = config.supabaseUrl && config.supabaseServiceRoleKey
  ? createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })
  : null;

// ---------------------------------------------------------------------------
// AES-256-GCM ENCRYPTION FOR PAGE ACCESS TOKENS AT REST
// ---------------------------------------------------------------------------

function getEncryptionKey() {
  if (!config.metaAppSecret) {
    throw new Error('Missing META_APP_SECRET for token encryption');
  }
  return crypto.createHash('sha256').update(`pyincc-page-token-key:${config.metaAppSecret}`).digest();
}

function encryptPageToken(plainToken) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(String(plainToken), 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return `enc:v1:${iv.toString('base64')}:${authTag.toString('base64')}:${encrypted.toString('base64')}`;
}

function decryptPageToken(storedValue) {
  const raw = String(storedValue || '');
  if (!raw.startsWith('enc:v1:')) {
    return raw;
  }
  const parts = raw.split(':');
  if (parts.length !== 5) {
    throw new Error('Invalid encrypted page token format');
  }
  const iv = Buffer.from(parts[2], 'base64');
  const authTag = Buffer.from(parts[3], 'base64');
  const ciphertext = Buffer.from(parts[4], 'base64');
  const decipher = crypto.createDecipheriv('aes-256-gcm', getEncryptionKey(), iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

// ---------------------------------------------------------------------------
// JWT AUTHENTICATION + MULTI-TENANT MEMBERSHIP & ROLE RESOLUTION
// ---------------------------------------------------------------------------

function hasValidJwtFormat(token) {
  const parts = String(token).split('.');
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) return false;
  try {
    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (!header || typeof header !== 'object' || !header.alg) return false;
    if (!payload || typeof payload !== 'object' || typeof payload.sub !== 'string') return false;
    if (typeof payload.exp === 'number' && payload.exp * 1000 <= Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}

// Resolves or activates the user's membership (org_id + role) from database
async function resolveOrActivateMembership(user) {
  // 1. Check existing active membership for user_id
  const { data: activeRow } = await supabase
    .from('memberships')
    .select('id, org_id, role, status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle();

  if (activeRow && activeRow.org_id && activeRow.role) {
    return activeRow;
  }

  // 2. Check pending invitation matching user's email or Facebook provider_id
  const email = typeof user.email === 'string' ? user.email.trim().toLowerCase() : '';
  const fbUserId = String(user.user_metadata?.provider_id || user.user_metadata?.sub || '').trim();

  let pendingRow = null;
  if (email) {
    const { data } = await supabase
      .from('memberships')
      .select('id, org_id, role, status')
      .eq('invited_email', email)
      .eq('status', 'pending')
      .maybeSingle();
    if (data) pendingRow = data;
  }
  if (!pendingRow && fbUserId) {
    const { data } = await supabase
      .from('memberships')
      .select('id, org_id, role, status')
      .eq('invited_fb_user_id', fbUserId)
      .eq('status', 'pending')
      .maybeSingle();
    if (data) pendingRow = data;
  }

  if (pendingRow) {
    const { data: activated } = await supabase
      .from('memberships')
      .update({
        user_id: user.id,
        status: 'active',
        updated_at: new Date().toISOString(),
      })
      .eq('id', pendingRow.id)
      .select('id, org_id, role, status')
      .single();
    if (activated) return activated;
  }

  // 3. Bootstrap first owner ONLY if no organization exists yet in the database
  const { count } = await supabase
    .from('organizations')
    .select('id', { count: 'exact', head: true });

  if (count === 0) {
    const { data: newOrg } = await supabase
      .from('organizations')
      .insert({ name: 'PYINCC Salon' })
      .select('id')
      .single();

    if (newOrg?.id) {
      const { data: ownerMembership } = await supabase
        .from('memberships')
        .insert({
          org_id: newOrg.id,
          user_id: user.id,
          invited_email: email || null,
          invited_fb_user_id: fbUserId || null,
          role: 'owner',
          status: 'active',
        })
        .select('id, org_id, role, status')
        .single();
      return ownerMembership || null;
    }
  }

  return null;
}

// Middleware 1: Verify Supabase User JWT and load org_id + role from memberships table
async function requireAuth(req, res, next) {
  if (!supabase) {
    console.warn(JSON.stringify({ event: 'auth_unavailable', reason: 'missing_supabase_config' }));
    return res.status(503).json({ error: 'Service Unavailable' });
  }

  const authHeader = req.get('authorization') || '';
  const bearerMatch = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
  const bearerToken = bearerMatch ? bearerMatch[1].trim() : '';

  if (!bearerToken || !hasValidJwtFormat(bearerToken)) {
    console.warn(JSON.stringify({ event: 'auth_rejected', reason: 'missing_or_malformed_jwt' }));
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const { data, error } = await supabase.auth.getUser(bearerToken);
    if (error || !data?.user) {
      console.warn(JSON.stringify({ event: 'auth_rejected', reason: 'invalid_or_expired_jwt' }));
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const membership = await resolveOrActivateMembership(data.user);
    if (!membership || !membership.org_id || !membership.role) {
      console.warn(JSON.stringify({ event: 'membership_rejected', userId: data.user.id }));
      return res.status(403).json({ error: 'Forbidden' });
    }

    req.authUser = data.user;
    req.orgId = membership.org_id;
    req.userRole = membership.role; // 'owner' | 'staff'
    return next();
  } catch {
    console.warn(JSON.stringify({ event: 'auth_rejected', reason: 'jwt_verification_exception' }));
    return res.status(401).json({ error: 'Unauthorized' });
  }
}

// Middleware 2: Enforce role ('owner' or 'staff') from memberships table
function requireRole(...allowedRoles) {
  return (req, res, next) => {
    if (!req.userRole || !allowedRoles.includes(req.userRole)) {
      return res.status(403).json({ error: 'Forbidden' });
    }
    return next();
  };
}

// Middleware 3: Require internal server-to-server x-api-key header matching API_KEY
function requireInternalApiKey(req, res, next) {
  const headerKey = req.get('x-api-key');
  if (config.apiKey && typeof headerKey === 'string' && safeEqual(headerKey, config.apiKey)) {
    return next();
  }
  console.warn(JSON.stringify({ event: 'internal_auth_rejected' }));
  return res.status(401).json({ error: 'Unauthorized' });
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'pyincc-meta-webhook',
  });
});

app.get('/internal/status', requireInternalApiKey, (_req, res) => {
  res.json({
    ok: true,
    configured: missingConfig.length === 0,
  });
});

app.post('/api/tryon/generate', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), async (req, res) => {
  const imageBase64 = String(req.body?.image_base64 || req.body?.imageBase64 || '').trim();
  if (!imageBase64) {
    return res.status(400).json({ error: 'image_base64 is required' });
  }

  try {
    const buffer = Buffer.from(imageBase64, 'base64');
    if (!buffer.length) {
      return res.status(400).json({ error: 'image_base64 is empty' });
    }

    // Fallback for local/demo usage when the actual AI image generation service is not configured.
    // This keeps the app working without a 404 and still returns a valid preview payload.
    return res.json({
      success: true,
      result_base64: imageBase64,
      fallback: true,
      note: 'Preview route is available; actual Gemini/AI generation is not configured on this deployment.',
    });
  } catch (error) {
    return res.status(400).json({ error: 'Invalid image_base64 payload' });
  }
});

// ---------------------------------------------------------------------------
// 1. STAFF INVITATIONS & MEMBERSHIP MANAGEMENT (Owner only)
// ---------------------------------------------------------------------------

app.get('/memberships', requireAuth, requireRole('owner'), async (req, res) => {
  const { data, error } = await supabase
    .from('memberships')
    .select('id, org_id, user_id, invited_email, invited_fb_user_id, role, status, created_at')
    .eq('org_id', req.orgId)
    .order('created_at', { ascending: false });

  if (error) {
    return res.status(500).json({ error: 'Failed to load memberships' });
  }
  return res.json({ memberships: data || [] });
});

app.post('/memberships/invite', requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), async (req, res) => {
  const invitedEmail = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : null;
  const invitedFbUserId = typeof req.body?.fbUserId === 'string' ? req.body.fbUserId.trim() : null;

  if (!invitedEmail && !invitedFbUserId) {
    return res.status(400).json({ error: 'email or fbUserId is required to invite staff' });
  }

  // Invited members are strictly assigned 'staff' role by server
  const { data, error } = await supabase
    .from('memberships')
    .insert({
      org_id: req.orgId,
      invited_email: invitedEmail,
      invited_fb_user_id: invitedFbUserId,
      role: 'staff',
      status: 'pending',
    })
    .select('id, org_id, invited_email, invited_fb_user_id, role, status, created_at')
    .single();

  if (error) {
    return res.status(500).json({ error: 'Failed to create staff invitation' });
  }
  return res.json({ success: true, invitation: data });
});

// ---------------------------------------------------------------------------
// 2. FACEBOOK LOGIN, DEBUG_TOKEN VERIFICATION & ENCRYPTED PAGE TOKEN STORAGE
// ---------------------------------------------------------------------------

app.post('/auth/facebook/exchange-token', requireAuth, requireRole('owner'), express.json({ limit: '16kb' }), async (req, res) => {
  if (!config.metaAppSecret || !config.metaAppId) {
    return res.status(503).json({ error: 'Service Unavailable' });
  }

  const userAccessToken = req.body?.accessToken || req.body?.userAccessToken || req.body?.user_access_token;
  if (typeof userAccessToken !== 'string' || !userAccessToken.trim()) {
    return res.status(400).json({ error: 'accessToken is required' });
  }

  try {
    // Verify with Facebook /debug_token that the token belongs to this META_APP_ID and is valid
    const verifiedTokenInfo = await verifyFacebookUserToken(userAccessToken.trim());

    // Exchange for long-lived token and save encrypted Page tokens bound to req.orgId (from membership)
    const pages = await exchangeUserTokenAndSavePages(
      userAccessToken.trim(),
      req.orgId,
      verifiedTokenInfo.userId
    );

    return res.json({
      success: true,
      org_id: req.orgId,
      role: req.userRole,
      pages: pages.map((p) => ({
        page_id: p.page_id,
        page_name: p.page_name,
      })),
    });
  } catch (error) {
    console.error(JSON.stringify({ event: 'exchange_token_failed', message: error.message }));
    return res.status(401).json({ error: 'Unauthorized' });
  }
});

// Facebook Deauthorize Callback — revokes stored Page tokens when owner removes the app on Facebook
app.post('/auth/facebook/deauthorize', express.urlencoded({ extended: false }), express.json({ limit: '16kb' }), async (req, res) => {
  if (!config.metaAppSecret || !supabase) {
    return res.status(503).json({ error: 'Service Unavailable' });
  }

  const signedRequest = req.body?.signed_request;
  const parsed = verifyFacebookSignedRequest(signedRequest);
  if (!parsed || !parsed.user_id) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  await supabase
    .from('connected_pages')
    .delete()
    .eq('connected_by_fb_user_id', String(parsed.user_id));

  return res.json({ success: true });
});

app.get('/connected-pages', requireAuth, requireRole('owner', 'staff'), async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('connected_pages')
      .select('page_id, page_name, updated_at')
      .eq('org_id', req.orgId)
      .order('updated_at', { ascending: false });

    if (error) {
      return res.status(500).json({ error: 'Failed to load connected pages' });
    }
    return res.json({ pages: data || [] });
  } catch {
    return res.status(500).json({ error: 'Failed to load connected pages' });
  }
});

async function verifyFacebookUserToken(inputToken) {
  const appAccessToken = `${config.metaAppId}|${config.metaAppSecret}`;
  const debugRes = await axios.get(
    `https://graph.facebook.com/${config.graphApiVersion}/debug_token`,
    {
      params: {
        input_token: inputToken,
        access_token: appAccessToken,
      },
      timeout: 15000,
    }
  );

  const tokenData = debugRes.data?.data;
  if (
    !tokenData ||
    tokenData.is_valid !== true ||
    String(tokenData.app_id) !== String(config.metaAppId) ||
    !tokenData.user_id
  ) {
    throw new Error('Facebook token failed debug_token validation');
  }

  return {
    userId: String(tokenData.user_id),
    appId: String(tokenData.app_id),
  };
}

function verifyFacebookSignedRequest(signedRequest) {
  if (typeof signedRequest !== 'string' || !signedRequest.includes('.')) return null;
  const [encodedSig, payload] = signedRequest.split('.', 2);
  if (!encodedSig || !payload) return null;

  const expectedSig = crypto
    .createHmac('sha256', config.metaAppSecret)
    .update(payload)
    .digest('base64url');

  if (!safeEqual(encodedSig, expectedSig)) return null;

  try {
    return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

async function exchangeUserTokenAndSavePages(userAccessToken, orgId, fbUserId) {
  let tokenToUse = userAccessToken;

  if (config.metaAppId && config.metaAppSecret) {
    try {
      const longRes = await axios.get(
        `https://graph.facebook.com/${config.graphApiVersion}/oauth/access_token`,
        {
          params: {
            grant_type: 'fb_exchange_token',
            client_id: config.metaAppId,
            client_secret: config.metaAppSecret,
            fb_exchange_token: userAccessToken,
          },
          timeout: 15000,
        }
      );
      if (longRes.data?.access_token) {
        tokenToUse = longRes.data.access_token;
      }
    } catch (e) {
      console.warn(JSON.stringify({ event: 'long_lived_exchange_skipped', message: e.message }));
    }
  }

  const appSecretProof = crypto
    .createHmac('sha256', config.metaAppSecret)
    .update(tokenToUse)
    .digest('hex');

  const accountsRes = await axios.get(
    `https://graph.facebook.com/${config.graphApiVersion}/me/accounts`,
    {
      params: {
        fields: 'id,name,access_token,category',
        access_token: tokenToUse,
        appsecret_proof: appSecretProof,
      },
      timeout: 15000,
    }
  );

  const rawPages = Array.isArray(accountsRes.data?.data) ? accountsRes.data.data : [];
  const savedPages = [];

  for (const page of rawPages) {
    if (!page.id || !page.access_token) continue;

    try {
      const pageProof = crypto
        .createHmac('sha256', config.metaAppSecret)
        .update(page.access_token)
        .digest('hex');
      await axios.post(
        `https://graph.facebook.com/${config.graphApiVersion}/${page.id}/subscribed_apps`,
        null,
        {
          params: {
            subscribed_fields: 'messages,messaging_postbacks',
            access_token: page.access_token,
            appsecret_proof: pageProof,
          },
          timeout: 15000,
        }
      );
    } catch (subErr) {
      console.warn(JSON.stringify({
        event: 'page_webhook_subscribe_warning',
        pageId: page.id,
        message: subErr.message,
      }));
    }

    const encryptedToken = encryptPageToken(page.access_token);
    const row = {
      org_id: orgId,
      page_id: String(page.id),
      page_name: String(page.name || `Page ${page.id}`),
      page_access_token: encryptedToken,
      connected_by_fb_user_id: fbUserId || null,
      updated_at: new Date().toISOString(),
    };

    const { error } = await supabase
      .from('connected_pages')
      .upsert(row, { onConflict: 'page_id' });
    if (error) {
      throw new Error(`Could not persist connected page: ${error.message}`);
    }

    savedPages.push({ page_id: row.page_id, page_name: row.page_name });
  }

  return savedPages;
}

async function resolvePageCredentialsForOrg(orgId, requestedPageId) {
  let query = supabase
    .from('connected_pages')
    .select('page_id, page_access_token')
    .eq('org_id', orgId)
    .order('updated_at', { ascending: false })
    .limit(1);

  if (requestedPageId) {
    query = query.eq('page_id', requestedPageId);
  }

  const { data } = await query;
  if (Array.isArray(data) && data.length > 0 && data[0].page_access_token) {
    return {
      pageId: data[0].page_id,
      pageAccessToken: decryptPageToken(data[0].page_access_token),
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// 3. SALON SETTINGS & BOOKINGS (Scoped by req.orgId and Role)
// ---------------------------------------------------------------------------

app.get('/settings', requireAuth, requireRole('owner', 'staff'), async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('salon_settings')
      .select('on_duty, consultation_script, updated_at')
      .eq('org_id', req.orgId)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ error: 'Failed to load settings' });
    }

    return res.json({
      onDuty: data ? Boolean(data.on_duty) : true,
      consultationScript: data ? String(data.consultation_script || '') : '',
    });
  } catch {
    return res.status(500).json({ error: 'Failed to load settings' });
  }
});

// Only 'owner' can modify consultationScript; 'staff' or 'owner' can toggle onDuty
app.put('/settings', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '32kb' }), async (req, res) => {
  if (typeof req.body?.consultationScript === 'string' && req.userRole !== 'owner') {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const onDuty = typeof req.body?.onDuty === 'boolean' ? req.body.onDuty : true;
  const payload = {
    key: `org:${req.orgId}`,
    org_id: req.orgId,
    on_duty: onDuty,
    updated_at: new Date().toISOString(),
  };
  if (req.userRole === 'owner' && typeof req.body?.consultationScript === 'string') {
    payload.consultation_script = req.body.consultationScript.trim();
  }

  const { error } = await supabase
    .from('salon_settings')
    .upsert(payload, { onConflict: 'key' });

  if (error) {
    return res.status(500).json({ error: 'Failed to save settings' });
  }

  return res.json({
    success: true,
    onDuty,
  });
});

app.get('/bookings', requireAuth, requireRole('owner', 'staff'), async (req, res) => {
  const { data, error } = await supabase
    .from('bookings')
    .select('*')
    .eq('org_id', req.orgId)
    .order('scheduled_at', { ascending: true })
    .limit(50);

  if (error) {
    return res.status(500).json({ error: 'Failed to fetch bookings' });
  }

  return res.json({ bookings: data || [] });
});

app.post('/bookings', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), async (req, res) => {
  const customerName = String(req.body?.customerName || req.body?.customer_name || '').trim();
  const customerPhone = String(req.body?.customerPhone || req.body?.customer_phone || '').trim();
  const serviceName = String(req.body?.serviceName || req.body?.service_name || '').trim();
  const timeSlot = String(req.body?.time || req.body?.scheduled_at || '').trim();

  if (!customerName || !serviceName) {
    return res.status(400).json({ error: 'customerName and serviceName are required' });
  }

  let scheduledIso = new Date().toISOString();
  const timeMatch = /^(\d{1,2}):(\d{2})$/.exec(timeSlot);
  if (timeMatch) {
    const now = new Date();
    now.setHours(Number(timeMatch[1]), Number(timeMatch[2]), 0, 0);
    scheduledIso = now.toISOString();
  } else if (timeSlot && !Number.isNaN(Date.parse(timeSlot))) {
    scheduledIso = new Date(timeSlot).toISOString();
  }

  const { data, error } = await supabase
    .from('bookings')
    .insert({
      org_id: req.orgId,
      customer_name: customerName,
      customer_phone: customerPhone,
      service_name: serviceName,
      scheduled_at: scheduledIso,
      status: 'confirmed',
    })
    .select('*')
    .single();

  if (error) {
    return res.status(500).json({ error: 'Failed to create booking' });
  }

  return res.json({ success: true, booking: data });
});

// ---------------------------------------------------------------------------
// 4. HUMAN-IN-THE-LOOP APPROVAL & MESSAGING (Scoped by req.orgId & Role)
// ---------------------------------------------------------------------------

app.post('/messages/:id/approve', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), async (req, res) => {
  const messageRowId = String(req.params.id || '').trim();
  const draftReply = String(req.body?.text || req.body?.draftReply || '').trim();

  if (!messageRowId || !draftReply) {
    return res.status(400).json({ error: 'message id and text are required' });
  }
  if (draftReply.length > 2000) {
    return res.status(400).json({ error: 'text must be 2000 characters or fewer' });
  }

  const approvedAt = new Date().toISOString();
  const { data, error } = await supabase
    .from('conversation_messages')
    .update({
      draft_reply: draftReply,
      approval_status: 'approved',
      approved_by: req.authUser.id,
      approved_at: approvedAt,
    })
    .eq('id', messageRowId)
    .eq('org_id', req.orgId)
    .select('id, org_id, customer_psid, draft_reply, approval_status, approved_by, approved_at')
    .single();

  if (error || !data) {
    return res.status(404).json({ error: 'Message record not found in your organization' });
  }

  return res.json({ success: true, approval: data });
});

app.post('/send-message', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), async (req, res) => {
  const messageRecordId = String(req.body?.messageRecordId || req.body?.message_record_id || '').trim();
  const requestedPageId = req.body?.pageId || req.body?.page_id;

  if (!messageRecordId) {
    return res.status(400).json({
      error: 'messageRecordId is required; approve the message via POST /messages/:id/approve first',
    });
  }

  const { data: msgRecord, error: fetchErr } = await supabase
    .from('conversation_messages')
    .select('id, org_id, customer_psid, draft_reply, approval_status, approved_by, approved_at')
    .eq('id', messageRecordId)
    .eq('org_id', req.orgId)
    .single();

  if (fetchErr || !msgRecord) {
    return res.status(404).json({ error: 'Message record not found in your organization' });
  }

  if (
    msgRecord.approval_status !== 'approved' ||
    !msgRecord.approved_by ||
    !msgRecord.approved_at ||
    !msgRecord.draft_reply
  ) {
    return res.status(403).json({
      error: 'Message has not been approved in database (missing approved status, approved_by, or approved_at)',
    });
  }

  const pageCreds = await resolvePageCredentialsForOrg(req.orgId, requestedPageId);
  if (!pageCreds) {
    return res.status(503).json({
      error: 'Chưa có Fanpage nào được kết nối cho tiệm của bạn.',
    });
  }

  try {
    const response = await axios.post(
      `https://graph.facebook.com/${config.graphApiVersion}/${pageCreds.pageId}/messages`,
      {
        recipient: { id: String(msgRecord.customer_psid).trim() },
        messaging_type: 'RESPONSE',
        message: { text: String(msgRecord.draft_reply).trim() },
      },
      {
        headers: { Authorization: `Bearer ${pageCreds.pageAccessToken}` },
        timeout: 15000,
      }
    );

    await supabase
      .from('conversation_messages')
      .update({ approval_status: 'sent' })
      .eq('id', msgRecord.id)
      .eq('org_id', req.orgId);

    const sentMessageId = response.data?.message_id || null;
    await supabase.from('conversation_messages').upsert({
      org_id: req.orgId,
      channel: 'facebook',
      customer_psid: String(msgRecord.customer_psid).trim(),
      sender: 'staff',
      message_type: 'text',
      message_text: String(msgRecord.draft_reply).trim(),
      message_id: sentMessageId,
      is_from_customer: false,
      approval_status: 'sent',
      approved_by: msgRecord.approved_by,
      approved_at: msgRecord.approved_at,
      created_at: new Date().toISOString(),
    }, { onConflict: 'message_id', ignoreDuplicates: true });

    return res.json({ success: true, data: response.data });
  } catch (error) {
    console.error(JSON.stringify({ event: 'send_message_failed', status: error.response?.status }));
    return res.status(502).json({ error: 'Failed to send message through Meta' });
  }
});

app.post('/tryon-drafts', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '15mb' }), async (req, res) => {
  const recipientId = String(req.body?.recipientId || req.body?.recipient_id || '').trim();
  const imageBase64 = String(req.body?.imageBase64 || req.body?.image_base64 || '').trim();
  const caption = String(req.body?.caption || '').trim();

  if (!imageBase64) {
    return res.status(400).json({ error: 'imageBase64 is required' });
  }

  let buffer;
  try {
    buffer = Buffer.from(imageBase64, 'base64');
  } catch {
    return res.status(400).json({ error: 'Invalid base64 image' });
  }
  if (!buffer.length || buffer.length > 15 * 1024 * 1024) {
    return res.status(400).json({ error: 'Image size must be under 15 MB' });
  }

  const storagePath = `tryon/${req.orgId}/${crypto.randomUUID()}.jpg`;
  const { error: uploadError } = await uploadWithRetry(storagePath, buffer, 'image/jpeg');
  if (uploadError) {
    return res.status(502).json({ error: `Upload Try-On image failed: ${uploadError.message}` });
  }

  const approvedAt = new Date().toISOString();
  const { data: mediaRecord, error: insertError } = await supabase
    .from('customer_media')
    .insert({
      org_id: req.orgId,
      source_channel: 'mobile',
      source_message_id: storagePath,
      storage_path: storagePath,
      file_name: storagePath,
      mime_type: 'image/jpeg',
      file_size: buffer.length,
      recipient_psid: recipientId || null,
      caption: caption || null,
      approval_status: 'approved',
      approved_by: req.authUser.id,
      approved_at: approvedAt,
      uploaded_at: approvedAt,
    })
    .select('id, org_id, storage_path, approval_status, approved_by, approved_at')
    .single();

  if (insertError || !mediaRecord) {
    return res.status(500).json({ error: 'Failed to persist approved Try-On media record' });
  }

  return res.json({ success: true, media: mediaRecord });
});

app.post('/send-tryon-image', requireAuth, requireRole('owner', 'staff'), express.json({ limit: '16kb' }), async (req, res) => {
  const mediaRecordId = String(req.body?.mediaRecordId || req.body?.media_record_id || '').trim();
  if (!mediaRecordId) {
    return res.status(400).json({
      error: 'mediaRecordId is required; create & approve the Try-On draft via POST /tryon-drafts first',
    });
  }

  const { data: mediaRow, error: fetchErr } = await supabase
    .from('customer_media')
    .select('id, org_id, storage_path, recipient_psid, caption, approval_status, approved_by, approved_at')
    .eq('id', mediaRecordId)
    .eq('org_id', req.orgId)
    .single();

  if (fetchErr || !mediaRow) {
    return res.status(404).json({ error: 'Try-On media record not found in your organization' });
  }

  if (
    mediaRow.approval_status !== 'approved' ||
    !mediaRow.approved_by ||
    !mediaRow.approved_at ||
    !mediaRow.storage_path
  ) {
    return res.status(403).json({
      error: 'Try-On image has not been approved in database (missing approved status, approved_by, or approved_at)',
    });
  }

  const signedUrl = await createSignedUrl(mediaRow.storage_path, 3600);
  const recipientId = String(mediaRow.recipient_psid || '').trim();
  const caption = String(mediaRow.caption || '').trim();
  const pageCreds = await resolvePageCredentialsForOrg(req.orgId, req.body?.pageId);

  if (recipientId && pageCreds) {
    try {
      await axios.post(
        `https://graph.facebook.com/${config.graphApiVersion}/${pageCreds.pageId}/messages`,
        {
          recipient: { id: recipientId },
          messaging_type: 'RESPONSE',
          message: {
            attachment: {
              type: 'image',
              payload: { url: signedUrl, is_reusable: false },
            },
          },
        },
        {
          headers: { Authorization: `Bearer ${pageCreds.pageAccessToken}` },
          timeout: 20000,
        }
      );

      if (caption) {
        await axios.post(
          `https://graph.facebook.com/${config.graphApiVersion}/${pageCreds.pageId}/messages`,
          {
            recipient: { id: recipientId },
            messaging_type: 'RESPONSE',
            message: { text: caption },
          },
          {
            headers: { Authorization: `Bearer ${pageCreds.pageAccessToken}` },
            timeout: 15000,
          }
        );
      }
    } catch (err) {
      console.error(JSON.stringify({ event: 'send_tryon_messenger_failed', status: err.response?.status }));
      return res.status(502).json({ error: 'Không gửi được ảnh qua Messenger cho khách.' });
    }
  }

  await supabase
    .from('customer_media')
    .update({ approval_status: 'sent' })
    .eq('id', mediaRow.id)
    .eq('org_id', req.orgId);

  return res.json({
    success: true,
    signedUrl,
    deliveredToMessenger: Boolean(recipientId && pageCreds),
  });
});

// ---------------------------------------------------------------------------
// 5. WEBHOOK & INBOX FETCH ENDPOINTS (Scoped by org_id)
// ---------------------------------------------------------------------------

app.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === config.verifyToken && typeof challenge === 'string') {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

app.get('/messages', requireAuth, requireRole('owner', 'staff'), async (req, res) => {
  const limit = Math.min(Math.max(Number(req.query.limit) || 30, 1), 100);
  try {
    const { data, error } = await supabase
      .from('conversation_messages')
      .select('*')
      .eq('org_id', req.orgId)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) {
      console.error(JSON.stringify({ event: 'fetch_messages_failed', message: error.message }));
      return res.status(500).json({ error: 'Failed to fetch messages' });
    }

    return res.json({ messages: data || [] });
  } catch (error) {
    console.error(JSON.stringify({ event: 'fetch_messages_exception', message: error.message }));
    return res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

app.post('/webhook', express.raw({ type: 'application/json', limit: '10mb' }), async (req, res) => {
  if (!config.metaAppSecret || !supabase) {
    console.warn(JSON.stringify({ event: 'webhook_unavailable', reason: 'missing_required_secrets' }));
    return res.status(503).send('Service Unavailable');
  }
  const rawBody = req.body;
  if (!Buffer.isBuffer(rawBody) || rawBody.length === 0) {
    return res.status(400).send('Missing body');
  }
  if (!verifyMetaSignature(rawBody, req.get('x-hub-signature-256'))) {
    return res.status(403).send('Forbidden');
  }

  let payload;
  try {
    payload = JSON.parse(rawBody.toString('utf8'));
  } catch {
    return res.status(400).send('Invalid JSON');
  }

  try {
    for (const entry of Array.isArray(payload.entry) ? payload.entry : []) {
      const pageId = entry.id ? String(entry.id) : null;
      const orgId = await resolveOrgIdByPageId(pageId);

      for (const event of Array.isArray(entry.messaging) ? entry.messaging : []) {
        if (event.message && !event.message.is_echo) {
          await handleFacebookMessage(orgId, event, event.message);
        }
      }
      for (const change of Array.isArray(entry.changes) ? entry.changes : []) {
        const value = change.value || {};
        for (const message of Array.isArray(value.messages) ? value.messages : []) {
          await handleFacebookMessage(orgId, value, message);
        }
      }
    }
  } catch (error) {
    console.error(JSON.stringify({ event: 'webhook_processing_failed', message: error.message }));
    return res.status(500).send('Processing failed');
  }

  return res.status(200).send('EVENT_RECEIVED');
});

async function resolveOrgIdByPageId(pageId) {
  if (!pageId || !supabase) return null;
  const { data } = await supabase
    .from('connected_pages')
    .select('org_id')
    .eq('page_id', pageId)
    .maybeSingle();
  return data?.org_id || null;
}

function safeEqual(received, expected) {
  if (typeof received !== 'string' || typeof expected !== 'string') return false;
  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);
  return receivedBuffer.length === expectedBuffer.length && crypto.timingSafeEqual(receivedBuffer, expectedBuffer);
}

function verifyMetaSignature(rawBody, signature) {
  if (typeof signature !== 'string') return false;
  const expected = `sha256=${crypto.createHmac('sha256', config.metaAppSecret).update(rawBody).digest('hex')}`;
  return safeEqual(signature, expected);
}

async function handleFacebookMessage(orgId, event, message) {
  const messageId = message.mid || message.id || null;
  const senderPsid = message.from?.id || event.sender?.id || 'unknown';
  const attachment = Array.isArray(message.attachments) ? message.attachments[0] : null;
  const messageText = typeof message.text === 'string'
    ? message.text
    : (typeof message.text?.body === 'string' ? message.text.body : null);
  const imageUrl = attachment?.type === 'image' && typeof attachment.payload?.url === 'string'
    ? attachment.payload.url
    : null;

  let uploaded = null;
  if (imageUrl) {
    uploaded = await uploadImageToSupabase(imageUrl, messageId || crypto.randomUUID());
  }

  const storedUrl = uploaded?.signedUrl || null;
  const eventId = messageId || crypto.createHash('sha256').update(JSON.stringify(message)).digest('hex');
  const receivedAt = new Date().toISOString();

  const { error: eventError } = await supabase.from('webhook_events').upsert({
    event_id: eventId,
    event_type: 'facebook_message',
    sender_psid: senderPsid,
    message_id: messageId,
    message_type: attachment?.type || 'text',
    message_text: messageText,
    image_url: storedUrl,
    raw_payload: message,
    received_at: receivedAt,
  }, { onConflict: 'event_id', ignoreDuplicates: true });
  if (eventError) throw new Error(`Could not persist webhook event: ${eventError.message}`);

  const { error: messageError } = await supabase.from('conversation_messages').upsert({
    org_id: orgId,
    channel: 'facebook',
    customer_psid: senderPsid,
    sender: 'customer',
    message_type: attachment?.type || 'text',
    message_text: messageText,
    image_url: storedUrl,
    message_id: messageId,
    attachment_type: attachment?.type || null,
    attachment_url: storedUrl,
    is_from_customer: true,
    approval_status: 'pending',
    created_at: receivedAt,
  }, { onConflict: 'message_id', ignoreDuplicates: true });
  if (messageError) throw new Error(`Could not persist conversation message: ${messageError.message}`);

  if (uploaded) {
    const { error: mediaError } = await supabase.from('customer_media').upsert({
      org_id: orgId,
      source_channel: 'facebook',
      source_message_id: messageId,
      source_url: null,
      storage_url: storedUrl,
      storage_path: uploaded.path,
      file_name: uploaded.path,
      mime_type: uploaded.mimeType,
      file_size: uploaded.size,
      approval_status: 'pending',
      uploaded_at: receivedAt,
    }, { onConflict: 'source_message_id', ignoreDuplicates: true });
    if (mediaError) throw new Error(`Could not persist customer media: ${mediaError.message}`);
  }
}

async function uploadImageToSupabase(remoteUrl, messageId) {
  let parsedUrl;
  try {
    parsedUrl = new URL(remoteUrl);
  } catch {
    throw new Error('Invalid image URL');
  }
  const hostAllowed = parsedUrl.protocol === 'https:' &&
    (parsedUrl.hostname === 'fbcdn.net' || parsedUrl.hostname.endsWith('.fbcdn.net') ||
      parsedUrl.hostname === 'fbsbx.com' || parsedUrl.hostname.endsWith('.fbsbx.com'));
  if (!hostAllowed) throw new Error('Image URL host is not an allowed Facebook CDN host');

  const response = await axios.get(parsedUrl.toString(), {
    responseType: 'arraybuffer',
    timeout: 20000,
    maxContentLength: 15 * 1024 * 1024,
    maxBodyLength: 15 * 1024 * 1024,
    validateStatus: (status) => status >= 200 && status < 300,
  });
  const mimeType = String(response.headers['content-type'] || '').split(';')[0].toLowerCase();
  const extensions = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  if (!extensions[mimeType]) throw new Error('Unsupported image content type');
  const buffer = Buffer.from(response.data);
  if (!buffer.length || buffer.length > 15 * 1024 * 1024) throw new Error('Image size is invalid');

  const safeId = crypto.createHash('sha256').update(String(messageId)).digest('hex');
  const path = `facebook/${safeId}.${extensions[mimeType]}`;
  const { error } = await uploadWithRetry(path, buffer, mimeType);
  if (error) throw new Error(`Supabase Storage upload failed: ${error.message}`);

  const signedUrl = await createSignedUrl(path, 3600);
  return { path, signedUrl, mimeType, size: buffer.length };
}

async function createSignedUrl(path, expiresInSeconds = 3600) {
  if (!supabase) {
    throw new Error('Supabase client is not initialized');
  }
  const { data, error } = await supabase.storage
    .from(config.storageBucket)
    .createSignedUrl(path, expiresInSeconds);

  if (error || !data?.signedUrl) {
    throw new Error(`Could not create signed URL for ${path}: ${error?.message || 'unknown error'}`);
  }
  return data.signedUrl;
}

async function uploadWithRetry(path, buffer, mimeType, maxRetries = 3) {
  let lastError;
  for (let attempt = 0; attempt < maxRetries; attempt += 1) {
    const { error } = await supabase.storage.from(config.storageBucket).upload(path, buffer, {
      contentType: mimeType,
      upsert: true,
      cacheControl: '3600',
    });
    if (!error) return { error: null };
    lastError = error;
    if (attempt < maxRetries - 1) await new Promise((resolve) => setTimeout(resolve, 500 * (2 ** attempt)));
  }
  return { error: lastError };
}

app.listen(port, () => {
  console.log(JSON.stringify({ event: 'server_started', service: 'pyincc-meta-webhook', port }));
});
