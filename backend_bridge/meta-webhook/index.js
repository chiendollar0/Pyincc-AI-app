const express = require('express');
const crypto = require('crypto');
const axios = require('axios');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const port = Number(process.env.PORT) || 3000;

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const metaAppSecret = process.env.META_APP_SECRET;
const pageAccessToken = process.env.PAGE_ACCESS_TOKEN;
const pageId = process.env.PAGE_ID;
const apiKey = process.env.API_KEY;

const missing = [];
if (!supabaseUrl) missing.push('SUPABASE_URL');
if (!supabaseServiceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
if (!metaAppSecret) missing.push('META_APP_SECRET');
if (!pageAccessToken) missing.push('PAGE_ACCESS_TOKEN');
if (!pageId) missing.push('PAGE_ID');
if (!apiKey) missing.push('API_KEY');

if (missing.length) {
  console.warn(`⚠️ Missing environment variables: ${missing.join(', ')}`);
}

const supabase = createClient(supabaseUrl || 'https://example.supabase.co', supabaseServiceRoleKey || 'service-role-placeholder', {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
});

function verifyMetaSignature(rawBody, signature) {
  if (!metaAppSecret) return false;
  if (!signature || typeof signature !== 'string') return false;

  const expected = `sha256=${crypto.createHmac('sha256', metaAppSecret).update(rawBody).digest('hex')}`;

  if (expected.length !== signature.length) {
    return false;
  }

  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'pyincc-meta-webhook' });
});

app.post('/send-message', async (req, res) => {
  const providedKey = req.headers['x-api-key'] || req.headers['x-api-token'];
  if (!providedKey || providedKey !== apiKey) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { recipient_id, text } = req.body || {};
  if (!recipient_id || !text) {
    return res.status(400).json({ error: 'recipient_id and text are required' });
  }

  try {
    const response = await axios.post(
      `https://graph.facebook.com/v19.0/${pageId}/messages`,
      {
        messaging_product: 'facebook',
        recipient: { id: String(recipient_id) },
        message: {
          text: { body: String(text) },
        },
      },
      {
        headers: {
          Authorization: `Bearer ${pageAccessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    return res.json({ ok: true, data: response.data });
  } catch (error) {
    const message = error.response?.data || error.message;
    console.error('❌ Error sending message:', message);
    return res.status(500).json({ error: 'Failed to send message', details: message });
  }
});

app.use('/webhook', express.raw({ type: 'application/json', limit: '10mb' }));

app.post('/webhook', async (req, res) => {
  if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
    return res.status(400).send('Missing body');
  }

  const signature = req.headers['x-hub-signature-256'];
  if (!verifyMetaSignature(req.body, signature)) {
    return res.status(403).send('Forbidden');
  }

  let payload;
  try {
    payload = JSON.parse(req.body.toString('utf8'));
  } catch (error) {
    console.error('❌ Invalid JSON from Meta webhook:', error.message);
    return res.status(400).send('Invalid payload');
  }

  const entries = Array.isArray(payload.entry) ? payload.entry : [];

  for (const entry of entries) {
    const changes = Array.isArray(entry.changes) ? entry.changes : [];

    for (const change of changes) {
      const value = change.value || {};
      const messages = Array.isArray(value.messages) ? value.messages : [];

      for (const message of messages) {
        try {
          await handleFacebookMessage(value, message);
        } catch (error) {
          console.error('❌ Failed to process message:', error.message);
        }
      }
    }
  }

  return res.status(200).send('EVENT_RECEIVED');
});

async function handleFacebookMessage(value, message) {
  const customerPsid = message.from?.id || value.sender?.id || 'unknown';
  const messageText = message.text?.body || null;
  const attachment = Array.isArray(message.attachments) ? message.attachments[0] : null;
  const imageUrl = attachment?.type === 'image' && attachment.payload?.url ? attachment.payload.url : null;

  let finalImageUrl = null;
  if (imageUrl) {
    try {
      const uploadResult = await uploadImageToSupabase(imageUrl, String(message.mid || customerPsid));
      finalImageUrl = uploadResult.publicUrl;
    } catch (error) {
      console.error('❌ Unable to upload image to Supabase:', error.message);
    }
  }

  const eventPayload = {
    event_type: 'facebook_message',
    sender_psid: customerPsid,
    message_id: message.mid || null,
    message_type: attachment ? attachment.type : 'text',
    message_text: messageText || (imageUrl ? 'Image received' : null),
    image_url: finalImageUrl || imageUrl || null,
    raw_payload: value,
    received_at: new Date().toISOString(),
  };

  const { error: eventError } = await supabase.from('webhook_events').insert(eventPayload);
  if (eventError) {
    console.error('⚠️ webhook_events insert failed:', eventError.message);
  }

  const { error: messageError } = await supabase.from('conversation_messages').insert({
    org_id: process.env.DEFAULT_ORG_ID || null,
    channel: 'facebook',
    customer_psid: customerPsid,
    sender: 'customer',
    message_type: attachment ? attachment.type : 'text',
    message_text: messageText || null,
    image_url: finalImageUrl || imageUrl || null,
    created_at: new Date().toISOString(),
  });

  if (messageError) {
    console.error('⚠️ conversation_messages insert failed:', messageError.message);
  }

  if (imageUrl && finalImageUrl) {
    const { error: mediaError } = await supabase.from('customer_media').insert({
      source_channel: 'facebook',
      source_message_id: message.mid || null,
      source_url: imageUrl,
      storage_url: finalImageUrl,
      file_name: `facebook/${Date.now()}-${String(message.mid || customerPsid)}.jpg`,
      mime_type: 'image/jpeg',
      uploaded_at: new Date().toISOString(),
    });

    if (mediaError) {
      console.error('⚠️ customer_media insert failed:', mediaError.message);
    }
  }
}

async function uploadImageToSupabase(remoteUrl, messageId) {
  const response = await axios.get(remoteUrl, {
    responseType: 'arraybuffer',
    timeout: 20000,
    maxContentLength: 15 * 1024 * 1024,
    validateStatus: (status) => status >= 200 && status < 300,
  });

  const contentType = response.headers['content-type'] || 'image/jpeg';
  const buffer = Buffer.from(response.data);
  const extension = contentType.includes('png') ? 'png' : contentType.includes('webp') ? 'webp' : 'jpg';
  const fileName = `facebook/${Date.now()}-${messageId}.${extension}`;

  const { error } = await supabase.storage.from('customer-media').upload(fileName, buffer, {
    contentType,
    upsert: true,
    cacheControl: '3600',
  });

  if (error) {
    throw new Error(error.message);
  }

  const { data: publicUrlData } = supabase.storage.from('customer-media').getPublicUrl(fileName);
  return {
    path: fileName,
    publicUrl: publicUrlData?.publicUrl || null,
  };
}

app.listen(port, () => {
  console.log(`🚀 PYINCC Meta webhook is running on port ${port}`);
});
