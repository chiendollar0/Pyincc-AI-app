# PYINCC Meta Webhook

Node.js service for receiving Meta webhook events, validating Meta signatures, storing customer messages/media in Supabase, and sending staff-approved Messenger replies.

## Local run

```bash
cp .env.example .env
npm install
npm start
```

Set the environment variables from `.env.example` in Render. Do not commit `.env` or expose `SUPABASE_SERVICE_ROLE_KEY` or `PAGE_ACCESS_TOKEN` to Flutter.

Required Supabase setup:

1. Run `database/schema.sql` on a new project, or run `database/migrations/20261116_meta_webhook.sql` on a project that already has the base schema.
2. Create the `customer-media` Storage bucket. Customer photos are sensitive: prefer a private bucket and serve authorized access through signed URLs. If using the current public-URL implementation, understand that anyone with a URL may view the image.
3. Set `DEFAULT_ORG_ID` to the organization UUID used by the app.
4. Enable Realtime for `conversation_messages`; the migration adds the table to `supabase_realtime` when available.

## Meta configuration

Configure the callback URL as `https://<your-domain>/webhook`, set the same `VERIFY_TOKEN` in Render and Meta, and subscribe to the Page messaging events. Meta's GET verification handshake returns the challenge only when the token matches. POST payloads are accepted only when `x-hub-signature-256` matches the HMAC-SHA256 signature calculated from the original raw request body and `META_APP_SECRET`.

## API

- `GET /health` — health check.
- `GET /webhook?hub.mode=subscribe&hub.verify_token=...&hub.challenge=...` — Meta subscription verification.
- `POST /webhook` — signed Meta events.
- `GET /messages?limit=30` — requires `x-api-key`; returns recent rows from `conversation_messages` for the Flutter inbox.
- `POST /send-message` — requires `x-api-key`; accepts `{ "recipientId": "PSID", "text": "..." }` (also accepts `recipient_id`). Call only after a staff member approves the response. The Page token and API key must remain server-side.

Example send request:

```bash
curl -X POST 'https://<your-domain>/send-message' \
  -H 'Content-Type: application/json' \
  -H 'x-api-key: <API_KEY>' \
  -d '{"recipientId":"<CUSTOMER_PSID>","text":"Xin chào!"}'
```

`webhook_events.event_id` and `conversation_messages.message_id` are used for idempotent processing of Meta retries. Photos are downloaded only from HTTPS Facebook CDN hosts, validated as supported image types, limited to 15 MB, and uploaded under deterministic paths.
