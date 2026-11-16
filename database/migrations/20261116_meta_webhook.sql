-- Run after database/schema.sql on an existing Supabase project.
-- These columns/indexes support the Meta webhook implementation and idempotent delivery.

alter table public.webhook_events
  add column if not exists event_id text;

create unique index if not exists webhook_events_event_id_uidx
  on public.webhook_events (event_id)
  where event_id is not null;

alter table public.conversation_messages
  add column if not exists message_id text,
  add column if not exists attachment_type text,
  add column if not exists attachment_url text,
  add column if not exists is_from_customer boolean not null default true;

create unique index if not exists conversation_messages_message_id_uidx
  on public.conversation_messages (message_id)
  where message_id is not null;

alter table public.customer_media
  add column if not exists storage_path text,
  add column if not exists file_size integer;

create unique index if not exists customer_media_source_message_id_uidx
  on public.customer_media (source_message_id)
  where source_message_id is not null;

-- Enable Supabase Realtime for inbox updates. Safe to run repeatedly.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_messages'
  ) then
    alter publication supabase_realtime add table public.conversation_messages;
  end if;
end $$;
