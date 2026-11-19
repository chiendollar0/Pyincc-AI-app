-- Forward-only migration: Enable Row Level Security (RLS) across all tables
-- and allow 'sending' intermediate lock status on conversation_messages & customer_media.

alter table public.conversation_messages
  drop constraint if exists conversation_messages_approval_status_check;

alter table public.conversation_messages
  add constraint conversation_messages_approval_status_check
  check (approval_status in ('pending','approved','sending','sent'));

alter table public.customer_media
  drop constraint if exists customer_media_approval_status_check;

alter table public.customer_media
  add constraint customer_media_approval_status_check
  check (approval_status in ('pending','approved','sending','sent'));

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

-- Enable RLS on all tables (service_role bypasses RLS; anon has zero access; authenticated is scoped by org_id)
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
