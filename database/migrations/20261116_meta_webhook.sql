-- Run after database/schema.sql on an existing Supabase project.
-- These columns/indexes support the Meta webhook implementation and idempotent delivery.

alter table public.webhook_events
  add column if not exists event_id text;

drop index if exists public.webhook_events_event_id_uidx;
create unique index if not exists webhook_events_event_id_uidx
  on public.webhook_events (event_id);

alter table public.conversation_messages
  add column if not exists message_id text,
  add column if not exists attachment_type text,
  add column if not exists attachment_url text,
  add column if not exists is_from_customer boolean not null default true,
  add column if not exists draft_reply text,
  add column if not exists approval_status text not null default 'pending' check (approval_status in ('pending','approved','sent')),
  add column if not exists approved_by uuid,
  add column if not exists approved_at timestamptz;

drop index if exists public.conversation_messages_message_id_uidx;
create unique index if not exists conversation_messages_message_id_uidx
  on public.conversation_messages (message_id);

alter table public.customer_media
  add column if not exists storage_path text,
  add column if not exists file_size integer,
  add column if not exists recipient_psid text,
  add column if not exists caption text,
  add column if not exists approval_status text not null default 'pending' check (approval_status in ('pending','approved','sent')),
  add column if not exists approved_by uuid,
  add column if not exists approved_at timestamptz;

drop index if exists public.customer_media_source_message_id_uidx;
create unique index if not exists customer_media_source_message_id_uidx
  on public.customer_media (source_message_id);

create table if not exists public.connected_pages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  page_id text not null unique,
  page_name text not null,
  page_access_token text not null,
  connected_by_fb_user_id text,
  connected_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.salon_settings (
  key text primary key,
  org_id uuid references public.organizations(id) on delete cascade,
  on_duty boolean not null default true,
  consultation_script text not null default '',
  updated_at timestamptz default now()
);

create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid,
  invited_email text,
  invited_fb_user_id text,
  role text not null check (role in ('owner','staff')),
  status text not null default 'pending' check (status in ('pending','active','revoked')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create unique index if not exists memberships_org_user_uidx
  on public.memberships (org_id, user_id)
  where user_id is not null;

alter table public.customer_media
  add column if not exists org_id uuid references public.organizations(id) on delete cascade;

create or replace function public.touch_conversation_updated_at()
returns trigger as $$
begin
  update public.conversations
  set updated_at = now()
  where customer_psid = NEW.customer_psid
    and channel = NEW.channel
    and (org_id = NEW.org_id or NEW.org_id is null);
  return NEW;
end;
$$ language plpgsql;

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
