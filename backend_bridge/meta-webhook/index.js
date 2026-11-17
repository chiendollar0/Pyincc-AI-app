const express = require('express');
const crypto = require('crypto');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const port = Number(process.env.PORT) || 3000;
const config = {
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  metaAppSecret: process.env.META_APP_SECRET,
  verifyToken: process.env.VERIFY_TOKEN,
  pageAccessToken: process.env.PAGE_ACCESS_TOKEN,
  pageId: process.env.PAGE_ID,
  apiKey: process.env.API_KEY,
  orgId: process.env.DEFAULT_ORG_ID || null,
  graphApiVersion: process.env.META_GRAPH_API_VERSION || 'v19.0',
  storageBucket: process.env.SUPABASE_STORAGE_BUCKET || 'customer-media',
};

const requiredConfig = [
  ['SUPABASE_URL', config.supabaseUrl],
  ['SUPABASE_SERVICE_ROLE_KEY', config.supabaseServiceRoleKey],
  ['META_APP_SECRET', config.metaAppSecret],
  ['VERIFY_TOKEN', config.verifyToken],
  ['PAGE_ACCESS_TOKEN', config.pageAccessToken],
  ['PAGE_ID', config.pageId],
  ['API_KEY', config.apiKey],
];
const missingConfig = requiredConfig.filter(([, value]) => !value).map(([name]) => name);
if (missingConfig.length) {
  throw new Error(`Missing required environment variables: ${missingConfig.join(', ')}`);
}

const supabase = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'pyincc-meta-webhook' });
});

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

// Fetch recent inbox messages for the Flutter app (requires x-api-key).
app.get('/messages', async (req, res) => {
  if (!safeEqual(req.get('x-api-key'), config.apiKey)) {
    return res.status(401).json({ error: 'Unauthorized' });
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

// Parse only this endpoint as JSON; Meta signature verification uses the exact raw bytes.
app.post('/send-message', express.json({ limit: '16kb' }), async (req, res) => {
  if (!safeEqual(req.get('x-api-key'), config.apiKey)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const recipientId = req.body?.recipientId || req.body?.recipient_id;
  const text = req.body?.text;
  if (typeof recipientId !== 'string' || !recipientId.trim() || typeof text !== 'string' || !text.trim()) {
    return res.status(400).json({ error: 'recipientId and text are required' });
  }
  if (text.length > 2000) {
    return res.status(400).json({ error: 'text must be 2000 characters or fewer' });
  }

  try {
    const response = await axios.post(
      `https://graph.facebook.com/${config.graphApiVersion}/${config.pageId}/messages`,
      {
        recipient: { id: recipientId.trim() },
        messaging_type: 'RESPONSE',
        message: { text: text.trim() },
      },
      {
        headers: { Authorization: `Bearer ${config.pageAccessToken}` },
        timeout: 15000,
      }
    );

    const sentMessageId = response.data?.message_id || null;
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

    return res.json({ success: true, data: response.data });
  } catch (error) {
    console.error(JSON.stringify({ event: 'send_message_failed', status: error.response?.status }));
    return res.status(502).json({ error: 'Failed to send message through Meta' });
  }
});

app.post('/webhook', express.raw({ type: 'application/json', limit: '10mb' }), async (req, res) => {
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
    // Messenger sends entry.messaging; changes.value.messages covers other Meta products.
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

  // event_id and message_id are unique in the migration. Ignore duplicate webhook deliveries.
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
      source_url: null, // Facebook CDN URLs expire; retain only our durable storage URL/path.
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
