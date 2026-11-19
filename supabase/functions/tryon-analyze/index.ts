// Supabase Edge Function: tryon-analyze
// Reads GEMINI_API_KEY from Supabase Edge Function Secrets (Deno.env.get('GEMINI_API_KEY'))
// Ref: https://supabase.com/docs/guides/functions/secrets

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

    if (supabaseUrl && supabaseAnonKey) {
      const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
      });
      const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
      if (authError || !user) {
        return new Response(
          JSON.stringify({ error: 'UNAUTHORIZED', message: 'Vui lòng đăng nhập để sử dụng AI phân tích.' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY');
    if (!geminiApiKey) {
      return new Response(
        JSON.stringify({ error: 'MISSING_GEMINI_API_KEY', message: 'Chưa cấu hình GEMINI_API_KEY trong Supabase Edge Function Secrets.' }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const body = await req.json();
    const imageBase64 = String(body?.image_base64 || '').trim();
    const catalog = Array.isArray(body?.catalog) ? body.catalog : [];

    if (!imageBase64) {
      return new Response(
        JSON.stringify({ error: 'BAD_REQUEST', message: 'Thiếu dữ liệu ảnh image_base64.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const catalogSummary = catalog
      .map((item: Record<string, unknown>) => `- id: ${item.id}, name: ${item.name}, category: ${item.category}`)
      .join('\n');

    const prompt = [
      'Bạn là chuyên gia tư vấn thẩm mỹ mày và môi cho tiệm Pyincc.',
      'Hãy quan sát ảnh khuôn mặt khách hàng và chọn 1 mẫu phù hợp nhất từ danh mục sau:',
      catalogSummary || '- id: brow_1, name: Mày sợi Hairstroke Nâu Tây, category: eyebrow',
      'Trả về đúng định dạng JSON (không bọc markdown) với các trường:',
      '{"face_shape": "...", "skin_tone": "...", "current_condition": "...", "recommended_item_id": "...", "consultation_script": "..."}',
    ].join('\n');

    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(geminiApiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: prompt },
                {
                  inline_data: {
                    mime_type: 'image/jpeg',
                    data: imageBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
          },
        }),
      },
    );

    if (!geminiRes.ok) {
      return new Response(
        JSON.stringify({ error: 'GEMINI_UPSTREAM_ERROR', status: geminiRes.status }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const geminiJson = await geminiRes.json();
    const rawText = geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text || '{}';
    const analysis = JSON.parse(rawText);

    return new Response(
      JSON.stringify({ analysis }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: 'SERVER_ERROR', message: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
