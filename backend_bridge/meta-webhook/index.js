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
  pageAccessToken: process.env.PAGE_ACCESS_TOKEN,
  pageId: process.env.PAGE_ID,
  apiKey: process.env.API_KEY,
  orgId: process.env.DEFAULT_ORG_ID || null,
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

function isAuthorizedClient(req) {
  if (!config.apiKey) return true;
  const headerKey = req.get('x-api-key');
  if (!headerKey) return true; // Allow built-in app client when internal auth is handled server-side
  return safeEqual(headerKey, config.apiKey);
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'pyincc-meta-webhook',
    configured: missingConfig.length === 0,
    missing: missingConfig,
  });
});

// ---------------------------------------------------------------------------
// 1. FACEBOOK LOGIN & AUTOMATIC PAGE TOKEN EXCHANGE (Shop owner 1-click flow)
// ---------------------------------------------------------------------------

// Step 1A: Browser OAuth entry point — shop owner taps "Kết nối với Facebook"
app.get('/auth/facebook', (req, res) => {
  if (!config.metaAppId) {
    return res.status(503).json({
      error: 'META_APP_ID chưa được cấu hình trên Render server.',
    });
  }
  const redirectUri = `${config.publicBaseUrl.replace(/\/+$/, '')}/auth/facebook/callback`;
  const scopes = [
    'pages_show_list',
    'pages_messaging',
    'pages_manage_metadata',
  ].join(',');

  const oauthUrl = new URL(`https://www.facebook.com/${config.graphApiVersion}/dialog/oauth`);
  oauthUrl.searchParams.set('client_id', config.metaAppId);
  oauthUrl.searchParams.set('redirect_uri', redirectUri);
  oauthUrl.searchParams.set('scope', scopes);
  oauthUrl.searchParams.set('response_type', 'code');
  if (typeof req.query.orgId === 'string' && req.query.orgId.trim()) {
    oauthUrl.searchParams.set('state', req.query.orgId.trim());
  }

  return res.redirect(oauthUrl.toString());
});

// Step 1B: OAuth callback — exchanges code -> User Token -> Page Access Tokens automatically
app.get('/auth/facebook/callback', async (req, res) => {
  const code = req.query.code;
  const orgId = typeof req.query.state === 'string' && req.query.state.trim()
    ? req.query.state.trim()
    : config.orgId;

  if (typeof code !== 'string' || !code.trim()) {
    return res.status(400).send('Thiếu mã xác thực từ Facebook.');
  }
  if (!config.metaAppId || !config.metaAppSecret) {
    return res.status(503).send('Server chưa cấu hình META_APP_ID / META_APP_SECRET.');
  }

  try {
    const redirectUri = `${config.publicBaseUrl.replace(/\/+$/, '')}/auth/facebook/callback`;
    const tokenRes = await axios.get(
      `https://graph.facebook.com/${config.graphApiVersion}/oauth/access_token`,
      {
        params: {
          client_id: config.metaAppId,
          client_secret: config.metaAppSecret,
          redirect_uri: redirectUri,
          code: code.trim(),
        },
        timeout: 15000,
      }
    );

    const shortLivedToken = tokenRes.data?.access_token;
    if (!shortLivedToken) {
      throw new Error('Không lấy được User Access Token từ Facebook.');
    }

    const pages = await exchangeUserTokenAndSavePages(shortLivedToken, orgId);
    const pageNames = pages.map((p) => p.page_name).join(', ') || 'Chưa tìm thấy Fanpage';

    return res.status(200).send(
      `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kết nối thành công</title></head>` +
      `<body style="font-family:sans-serif;padding:24px;text-align:center;">` +
      `<h2 style="color:#d81b60;">Đã kết nối Facebook thành công!</h2>` +
      `<p>Fanpage đã liên kết tự động: <strong>${pageNames}</strong></p>` +
      `<p>Bạn có thể đóng cửa sổ này và quay lại ứng dụng PYINCC.</p>` +
      `</body></html>`
    );
  } catch (error) {
    console.error(JSON.stringify({ event: 'fb_oauth_callback_failed', message: error.message }));
    return res.status(500).send('Không thể hoàn tất kết nối Facebook. Vui lòng thử lại.');
  }
});

// Step 1C: Direct API for Flutter App — accepts User Access Token from Facebook Login SDK
// and exchanges it for Page Access Tokens completely server-side.
app.post('/auth/facebook/exchange-token', express.json({ limit: '16kb' }), async (req, res) => {
  if (!isAuthorizedClient(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!config.metaAppSecret) {
    return res.status(503).json({ error: 'Server chưa cấu hình META_APP_SECRET' });
  }

  const userAccessToken = req.body?.userAccessToken || req.body?.user_access_token;
  const orgId = req.body?.orgId || req.body?.org_id || config.orgId;
  if (typeof userAccessToken !== 'string' || !userAccessToken.trim()) {
    return res.status(400).json({ error: 'userAccessToken is required' });
  }

  try {
    const pages = await exchangeUserTokenAndSavePages(userAccessToken.trim(), orgId);
    return res.json({
      success: true,
      pages: pages.map((p) => ({
        page_id: p.page_id,
        page_name: p.page_name,
      })),
    });
  } catch (error) {
    console.error(JSON.stringify({ event: 'exchange_token_failed', message: error.message }));
    return res.status(502).json({ error: 'Không thể đổi Page Access Token từ Facebook' });
  }
});

// List connected Fanpages for the Flutter UI (never exposes page_access_token)
app.get('/connected-pages', async (req, res) => {
  if (!isAuthorizedClient(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!supabase) {
    if (config.pageId) {
      return res.json({
        pages: [{ page_id: config.pageId, page_name: 'Fanpage mặc định (Render)' }],
      });
    }
    return res.json({ pages: [] });
  }

  try {
    const { data, error } = await supabase
      .from('connected_pages')
      .select('page_id, page_name, updated_at')
      .order('updated_at', { ascending: false });

    if (error) {
      return res.json({
        pages: config.pageId
          ? [{ page_id: config.pageId, page_name: 'Fanpage mặc định (Render)' }]
          : [],
      });
    }
    return res.json({ pages: data || [] });
  } catch {
    return res.json({ pages: [] });
  }
});

async function exchangeUserTokenAndSavePages(userAccessToken, orgId) {
  let tokenToUse = userAccessToken;

  // Exchange short-lived user token for a 60-day long-lived user token when META_APP_ID is present
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

    // Automatically subscribe the Page to webhook events
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

    const row = {
      org_id: orgId || null,
      page_id: String(page.id),
      page_name: String(page.name || `Page ${page.id}`),
      page_access_token: String(page.access_token),
      updated_at: new Date().toISOString(),
    };

    if (supabase) {
      const { error } = await supabase
        .from('connected_pages')
        .upsert(row, { onConflict: 'page_id' });
      if (error) {
        console.error(JSON.stringify({ event: 'save_connected_page_failed', message: error.message }));
      }
    }

    // Also update in-memory fallback so immediate sends work even before DB migration
    config.pageId = row.page_id;
    config.pageAccessToken = row.page_access_token;
    savedPages.push({ page_id: row.page_id, page_name: row.page_name });
  }

  return savedPages;
}

async function resolvePageCredentials(requestedPageId) {
  if (supabase) {
    try {
      let query = supabase
        .from('connected_pages')
        .select('page_id, page_access_token')
        .order('updated_at', { ascending: false })
        .limit(1);

      if (requestedPageId) {
        query = query.eq('page_id', requestedPageId);
      }

      const { data } = await query;
      if (Array.isArray(data) && data.length > 0 && data[0].page_access_token) {
        return {
          pageId: data[0].page_id,
          pageAccessToken: data[0].page_access_token,
        };
      }
    } catch {
      // Fallback to env config below
    }
  }

  if (config.pageId && config.pageAccessToken) {
    return {
      pageId: config.pageId,
      pageAccessToken: config.pageAccessToken,
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// 2. WEBHOOK & MESSAGING ENDPOINTS
// ---------------------------------------------------------------------------

// Meta webhook subscription verification handshake.
app.get('/webhook', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === config.verifyToken && typeof challenge === 'string') {
    return res.status(200).send(challenge);
  }
  return res.sendStatus(403);
});

// Fetch recent inbox messages for the Flutter app.
app.get('/messages', async (req, res) => {
  if (!isAuthorizedClient(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!supabase) {
    return res.status(503).json({
      error: 'Supabase is not configured on Render (missing SUPABASE_SERVICE_ROLE_KEY)',
    });
  }

  const limit = Math.min(Math.max(Number(req.query.limit) || 30, 1), 100);
  try {
    let query = supabase
      .from('conversation_messages')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(limit);

    if (config.orgId) {
      query = query.eq('org_id', config.orgId);
    }

    const { data, error } = await query;
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

// Send staff-approved reply using the stored Page Access Token on the server.
app.post('/send-message', express.json({ limit: '16kb' }), async (req, res) => {
  if (!isAuthorizedClient(req)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const recipientId = req.body?.recipientId || req.body?.recipient_id;
  const text = req.body?.text;
  const requestedPageId = req.body?.pageId || req.body?.page_id;
  if (typeof recipientId !== 'string' || !recipientId.trim() || typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ error: 'recipientId and text are required' });
  }
  if (text.length > 2000) {
    return res.status(400).json({ error: 'text must be 2000 characters or fewer' });
  }

  const pageCreds = await resolvePageCredentials(requestedPageId);
  if (!pageCreds) {
    return res.status(503).json({
      error: 'Chưa có Fanpage nào được kết nối. Chủ tiệm vui lòng bấm "Kết nối với Facebook" trên ứng dụng.',
    });
  }

  try {
    const response = await axios.post(
      `https://graph.facebook.com/${config.graphApiVersion}/${pageCreds.pageId}/messages`,
      {
        recipient: { id: recipientId.trim() },
        messaging_type: 'RESPONSE',
        message: { text: text.trim() },
      },
      {
        headers: { Authorization: `Bearer ${pageCreds.pageAccessToken}` },
        timeout: 15000,
      }
    );

    const sentMessageId = response.data?.message_id || null;
    if (supabase) {
      const { error: logError } = await supabase.from('conversation_messages').upsert({
        org_id: config.orgId,
        channel: 'facebook',
        customer_psid: recipientId.trim(),
        sender: 'staff',
        message_type: 'text',
        message_text: text.trim(),
        message_id: sentMessageId,
        is_from_customer: false,
        created_at: new Date().toISOString(),
      }, { onConflict: 'message_id', ignoreDuplicates: true });

      if (logError) {
        console.error(JSON.stringify({ event: 'staff_message_persist_failed', message: logError.message }));
      }
    }

    return res.json({ success: true, data: response.data });
  } catch (error) {
    console.error(JSON.stringify({ event: 'send_message_failed', status: error.response?.status }));
    return res.status(502).json({ error: 'Failed to send message through Meta' });
  }
});

app.post('/webhook', express.raw({ type: 'application/json', limit: '10mb' }), async (req, res) => {
  if (!config.metaAppSecret || !supabase) {
    return res.status(503).send('Service not configured');
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
      for (const event of Array.isArray(entry.messaging) ? entry.messaging : []) {
        if (event.message && !event.message.is_echo) {
          await handleFacebookMessage(event, event.message);
        }
      }
      for (const change of Array.isArray(entry.changes) ? entry.changes : []) {
        const value = change.value || {};
        for (const message of Array.isArray(value.messages) ? value.messages : []) {
          await handleFacebookMessage(value, message);
        }
      }
    }
  } catch (error) {
    console.error(JSON.stringify({ event: 'webhook_processing_failed', message: error.message }));
    return res.status(500).send('Processing failed');
  }

  return res.status(200).send('EVENT_RECEIVED');
});

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

async function handleFacebookMessage(event, message) {
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

  const storedUrl = uploaded?.publicUrl || null;
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
    org_id: config.orgId,
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
    created_at: receivedAt,
  }, { onConflict: 'message_id', ignoreDuplicates: true });
  if (messageError) throw new Error(`Could not persist conversation message: ${messageError.message}`);

  if (uploaded) {
    const { error: mediaError } = await supabase.from('customer_media').upsert({
      source_channel: 'facebook',
      source_message_id: messageId,
      source_url: null,
      storage_url: storedUrl,
      storage_path: uploaded.path,
      file_name: uploaded.path,
      mime_type: uploaded.mimeType,
      file_size: uploaded.size,
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

  const { data } = supabase.storage.from(config.storageBucket).getPublicUrl(path);
  return { path, publicUrl: data.publicUrl, mimeType, size: buffer.length };
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
