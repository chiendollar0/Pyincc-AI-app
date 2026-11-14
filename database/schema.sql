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
  tag text check (tag in ('urgent','hard_case','tried_sample','normal')) default 'normal',
  ai_summary text,
  assigned_user_id uuid references users(id),
  updated_at timestamptz default now()
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
