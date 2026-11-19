-- Idempotent migration (safe to run repeatedly on an existing Supabase project):
-- 1. Ensures all required columns, indexes, and triggers exist without failing on existing tables
-- 2. Updates approval_status constraints to allow 'sending' atomic lock state
-- 3. Enables Row Level Security (RLS) across all 12 tables and defines tenant isolation policies

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
  add column if not exists approval_status text not null default 'pending',
  add column if not exists approved_by uuid,
  add column if not exists approved_at timestamptz;

alter table public.conversation_messages
  drop constraint if exists conversation_messages_approval_status_check;

alter table public.conversation_messages
  add constraint conversation_messages_approval_status_check
  check (approval_status in ('pending','approved','sending','sent'));

drop index if exists public.conversation_messages_message_id_uidx;
create unique index if not exists conversation_messages_message_id_uidx
  on public.conversation_messages (message_id);

alter table public.customer_media
  add column if not exists org_id uuid references public.organizations(id) on delete cascade,
  add column if not exists storage_path text,
  add column if not exists file_size integer,
  add column if not exists recipient_psid text,
  add column if not exists caption text,
  add column if not exists approval_status text not null default 'pending',
  add column if not exists approved_by uuid,
  add column if not exists approved_at timestamptz;

alter table public.customer_media
  drop constraint if exists customer_media_approval_status_check;

alter table public.customer_media
  add constraint customer_media_approval_status_check
  check (approval_status in ('pending','approved','sending','sent'));

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

drop trigger if exists conversation_updated_at_trigger on public.conversation_messages;
create trigger conversation_updated_at_trigger
  after insert or update on public.conversation_messages
  for each row
  execute function public.touch_conversation_updated_at();

-- Helper returning active org_ids for the current authenticated Supabase user
create or replace function public.user_org_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select org_id
  from public.memberships
  where user_id = auth.uid()
    and status = 'active';
$$;

-- Enable RLS on all 12 tables (service_role bypasses RLS; anon has zero access; authenticated is scoped by org_id)
alter table public.organizations enable row level security;
alter table public.users enable row level security;
alter table public.shifts enable row level security;
alter table public.catalog_items enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_messages enable row level security;
alter table public.customer_media enable row level security;
alter table public.webhook_events enable row level security;
alter table public.connected_pages enable row level security;
alter table public.salon_settings enable row level security;
alter table public.bookings enable row level security;
alter table public.memberships enable row level security;

-- Tenant-isolated policies for authenticated users
drop policy if exists "org_select_organizations" on public.organizations;
create policy "org_select_organizations"
  on public.organizations for select
  to authenticated
  using (id in (select public.user_org_ids()));

drop policy if exists "org_select_memberships" on public.memberships;
create policy "org_select_memberships"
  on public.memberships for select
  to authenticated
  using (org_id in (select public.user_org_ids()) or user_id = auth.uid());

drop policy if exists "org_isolate_users" on public.users;
create policy "org_isolate_users"
  on public.users for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_catalog_items" on public.catalog_items;
create policy "org_isolate_catalog_items"
  on public.catalog_items for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_conversations" on public.conversations;
create policy "org_isolate_conversations"
  on public.conversations for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_conversation_messages" on public.conversation_messages;
create policy "org_isolate_conversation_messages"
  on public.conversation_messages for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_customer_media" on public.customer_media;
create policy "org_isolate_customer_media"
  on public.customer_media for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_salon_settings" on public.salon_settings;
create policy "org_isolate_salon_settings"
  on public.salon_settings for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_bookings" on public.bookings;
create policy "org_isolate_bookings"
  on public.bookings for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

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
end;
$$;
