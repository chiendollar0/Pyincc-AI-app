create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz default now()
);

create table users (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete cascade,
  name text not null,
  role text check (role in ('owner','sale','technician')) not null,
  zalo_id text,
  on_duty boolean default false
);

create table shifts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade,
  shift_type text check (shift_type in ('morning','afternoon','evening')) not null,
  shift_date date not null
);

create table catalog_items (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete cascade,
  category text check (category in ('eyebrow','lip')) not null,
  name text not null,
  price numeric,
  image_url text
);

create table conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete cascade,
  channel text check (channel in ('facebook','zalo')) not null,
  customer_name text,
  customer_psid text,
  tag text check (tag in ('urgent','hard_case','tried_sample','normal')) default 'normal',
  ai_summary text,
  assigned_user_id uuid references users(id),
  updated_at timestamptz default now()
);

create table conversation_messages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete cascade,
  channel text check (channel in ('facebook','zalo')) not null default 'facebook',
  customer_psid text,
  sender text check (sender in ('customer','staff','system')) default 'customer',
  message_type text check (message_type in ('text','image','file','audio','video')) default 'text',
  message_text text,
  image_url text,
  created_at timestamptz default now()
);

create table customer_media (
  id uuid primary key default gen_random_uuid(),
  source_channel text check (source_channel in ('facebook','zalo','mobile')) default 'facebook',
  source_message_id text,
  source_url text,
  storage_url text,
  file_name text,
  mime_type text,
  uploaded_at timestamptz default now()
);

create table webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  sender_psid text,
  message_id text,
  message_type text,
  message_text text,
  image_url text,
  raw_payload jsonb,
  received_at timestamptz default now()
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references organizations(id) on delete cascade,
  customer_name text not null,
  customer_phone text,
  service_name text,
  technician_id uuid references users(id),
  scheduled_at timestamptz not null,
  status text check (status in ('pending','confirmed','done','cancelled')) default 'pending'
);

create index idx_conversation_messages_customer_psid on conversation_messages(customer_psid);
create index idx_conversation_messages_created_at on conversation_messages(created_at);
create index idx_customer_media_source_message_id on customer_media(source_message_id);
create index idx_webhook_events_received_at on webhook_events(received_at);

alter table conversations
  alter column updated_at set default now();

create or replace function touch_conversation_updated_at()
returns trigger as $$
begin
  update conversations
  set updated_at = now()
  where id = NEW.org_id;
  return NEW;
end;
$$ language plpgsql;

create trigger conversation_updated_at_trigger
  after insert or update on conversation_messages
  for each row
  execute function touch_conversation_updated_at();
