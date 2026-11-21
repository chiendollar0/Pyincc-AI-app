create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  specialty text,
  created_at timestamptz default now()
);

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  name text not null,
  role text check (role in ('owner','sale','technician')) not null,
  zalo_id text,
  on_duty boolean default false
);

create table if not exists public.shifts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  shift_type text check (shift_type in ('morning','afternoon','evening')) not null,
  shift_date date not null
);

create table if not exists public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  category text check (category in ('eyebrow','lip','other')) not null,
  group_label text not null default 'Khác',
  name text not null,
  description text,
  active boolean not null default true,
  price numeric,
  image_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  channel text check (channel in ('facebook','zalo')) not null,
  customer_name text,
  customer_psid text,
  tag text check (tag in ('urgent','hard_case','tried_sample','normal')) default 'normal',
  ai_summary text,
  assigned_user_id uuid references public.users(id),
  updated_at timestamptz default now()
);

create table if not exists public.conversation_messages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  channel text check (channel in ('facebook','zalo')) not null default 'facebook',
  customer_psid text,
  sender text check (sender in ('customer','staff','system')) default 'customer',
  message_type text check (message_type in ('text','image','file','audio','video')) default 'text',
  message_text text,
  image_url text,
  storage_path text,
  page_id text,
  message_id text,
  attachment_type text,
  attachment_url text,
  is_from_customer boolean not null default true,
  draft_reply text,
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','sending','sent')),
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz default now()
);

create table if not exists public.customer_media (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  source_channel text check (source_channel in ('facebook','zalo','mobile')) default 'facebook',
  source_message_id text,
  source_url text,
  storage_url text,
  storage_path text,
  file_name text,
  mime_type text,
  file_size integer,
  recipient_psid text,
  page_id text,
  caption text,
  created_by uuid,
  approval_status text not null default 'pending' check (approval_status in ('pending','approved','sending','sent')),
  approved_by uuid,
  approved_at timestamptz,
  uploaded_at timestamptz default now()
);

create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_id text,
  event_type text not null,
  sender_psid text,
  message_id text,
  message_type text,
  message_text text,
  image_url text,
  raw_payload jsonb,
  received_at timestamptz default now()
);

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

create unique index if not exists memberships_pending_email_uidx
  on public.memberships (org_id, invited_email)
  where status = 'pending' and invited_email is not null;

create unique index if not exists memberships_pending_fb_uidx
  on public.memberships (org_id, invited_fb_user_id)
  where status = 'pending' and invited_fb_user_id is not null;

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  customer_name text not null,
  customer_phone text,
  service_name text,
  technician_id uuid references public.users(id),
  scheduled_at timestamptz not null,
  service_date date,
  follow_up_due date,
  followup_done boolean not null default false,
  notes text,
  status text check (status in ('pending','confirmed','done','cancelled')) default 'pending'
);

create unique index if not exists bookings_active_slot
  on public.bookings (org_id, scheduled_at)
  where status in ('pending', 'confirmed');

create index if not exists idx_bookings_org_service_date
  on public.bookings (org_id, service_date)
  where followup_done = false and status <> 'cancelled';

create table if not exists public.onboarding_codes (
  code text primary key,
  org_name text not null,
  org_id uuid references public.organizations(id) on delete set null,
  claimed_by uuid,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.data_deletion_requests (
  code text primary key,
  fb_user_id text not null,
  status text not null default 'completed',
  created_at timestamptz default now()
);

create table if not exists public.handoff_cases (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  source text not null check (source in ('business_ai_handover','owner_capture')),
  message_id text unique,
  page_id text,
  psid text,
  customer_text text,
  image_path text,
  status text not null default 'new'
    check (status in ('new','analyzing','pending_review','approved','sending','sent','rejected','failed')),
  analysis jsonb,
  draft_reply text,
  created_by uuid,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_handoff_cases_org_status_created
  on public.handoff_cases (org_id, status, created_at desc);

create table if not exists public.handover_threads (
  org_id uuid not null references public.organizations(id) on delete cascade,
  page_id text not null,
  psid text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (page_id, psid)
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid,
  actor_role text,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_org_created
  on public.audit_logs (org_id, created_at desc);

create index if not exists idx_conversation_messages_customer_psid on public.conversation_messages(customer_psid);
create index if not exists idx_conversation_messages_created_at on public.conversation_messages(created_at);
create index if not exists idx_customer_media_source_message_id on public.customer_media(source_message_id);
create index if not exists idx_webhook_events_received_at on public.webhook_events(received_at);

create unique index if not exists webhook_events_event_id_uidx
  on public.webhook_events (event_id);

create unique index if not exists conversation_messages_message_id_uidx
  on public.conversation_messages (message_id);

create unique index if not exists customer_media_source_message_id_uidx
  on public.customer_media (source_message_id);

alter table public.conversations
  alter column updated_at set default now();

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
