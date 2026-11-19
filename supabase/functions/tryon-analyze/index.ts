// Supabase Edge Function: tryon-analyze
import { createClient } from 'npm:@supabase/supabase-js@2';

const GEMINI_MODEL = 'gemini-2.5-flash';
const MAX_DECODED_BYTES = 1500 * 1024;

const SCHEMA = {
  type: 'OBJECT',
  properties: {
    face_detected: { type: 'BOOLEAN' },
    face_shape: { type: 'STRING' },
    skin_tone: { type: 'STRING' },
    observations: { type: 'STRING' },
    recommended_item_id: { type: 'STRING' },
    consultation_note: { type: 'STRING' },
  },
  required: ['face_detected'],
};

const PROMPT = `Bạn là trợ lý quan sát ảnh cho nhân viên thẩm mỹ.
- Trước hết xác định ảnh có khuôn mặt người rõ ràng không. Nếu không, trả face_detected=false và để các trường khác rỗng.
- Nếu có: mô tả khách quan dáng mặt, tông da, và tình trạng chân mày/môi quan sát được.
- Chọn recommended_item_id trong danh sách mẫu được cung cấp, hoặc để rỗng nếu không phù hợp.
- KHÔNG nêu giá, KHÔNG hứa kết quả, KHÔNG dùng từ "đảm bảo", "100%", "chắc chắn".
- consultation_note là gợi ý ngắn để nhân viên tham khảo, không phải lời chốt với khách.`;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function detectMime(bytes: Uint8Array): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d &&
    bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    bytes.length >= 12 && bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 &&
    bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return 'image/webp';
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'METHOD_NOT_ALLOWED' });

  const auth = req.headers.get('Authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(auth.trim());
  const token = match?.[1]?.trim() ?? '';
  if (!token) return json(401, { error: 'AUTH_REQUIRED' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) return json(503, { error: 'SERVICE_UNAVAILABLE' });

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userData.user) return json(401, { error: 'AUTH_INVALID' });

  let payload: { image_base64?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: 'BAD_JSON' });
  }
  const imageBase64 = payload?.image_base64;
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return json(400, { error: 'MISSING_IMAGE' });
  }
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(imageBase64)) {
    return json(400, { error: 'INVALID_IMAGE_ENCODING' });
  }
  const approxDecoded = Math.floor((imageBase64.length * 3) / 4) -
    (imageBase64.endsWith('==') ? 2 : imageBase64.endsWith('=') ? 1 : 0);
  if (approxDecoded > MAX_DECODED_BYTES) return json(413, { error: 'IMAGE_TOO_LARGE' });

  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(imageBase64), (character) => character.charCodeAt(0));
  } catch {
    return json(400, { error: 'INVALID_IMAGE_ENCODING' });
  }
  if (!bytes.length) return json(400, { error: 'MISSING_IMAGE' });
  const mime = detectMime(bytes);
  if (!mime) return json(415, { error: 'UNSUPPORTED_IMAGE_TYPE' });

  // catalog_items has no `active` column in this repository's schema. RLS scopes
  // this query to the authenticated user's organization.
  const { data: items, error: catalogError } = await supabase
    .from('catalog_items')
    .select('id, name, category');
  if (catalogError) {
    console.error(JSON.stringify({ event: 'catalog_query_failed', code: catalogError.code }));
    return json(500, { error: 'SERVER_ERROR' });
  }

  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!geminiKey) return json(503, { error: 'SERVICE_UNAVAILABLE' });

  let geminiResponse: Response;
  try {
    geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiKey },
        body: JSON.stringify({
          contents: [{
            parts: [
              { text: `${PROMPT}\nDanh mục mẫu: ${JSON.stringify(items ?? [])}` },
              { inline_data: { mime_type: mime, data: imageBase64 } },
            ],
          }],
          generationConfig: {
            responseMimeType: 'application/json',
            responseSchema: SCHEMA,
            temperature: 0.2,
          },
        }),
      },
    );
  } catch {
    return json(502, { error: 'AI_UPSTREAM_ERROR' });
  }

  if (!geminiResponse.ok) {
    console.error(JSON.stringify({ event: 'gemini_error', status: geminiResponse.status }));
    return json(502, { error: 'AI_UPSTREAM_ERROR' });
  }

  let result: Record<string, unknown>;
  try {
    const output = await geminiResponse.json();
    const text = output?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
    const parsed: unknown = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return json(502, { error: 'AI_BAD_OUTPUT' });
    }
    result = parsed as Record<string, unknown>;
  } catch {
    return json(502, { error: 'AI_BAD_OUTPUT' });
  }

  const validIds = new Set((items ?? []).map((item: { id: string }) => String(item.id)));
  if (
    result.recommended_item_id &&
    !validIds.has(String(result.recommended_item_id))
  ) {
    result.recommended_item_id = '';
  }
  if (result.face_detected !== true) {
    return json(200, { analysis: { face_detected: false } });
  }

  return json(200, { analysis: result });
});
