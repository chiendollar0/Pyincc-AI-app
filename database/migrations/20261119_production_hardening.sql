-- Idempotent Production Hardening Migration
-- 1. Ensure data_deletion_requests exists with unique code primary key + RLS
-- 2. Add created_by (author) and page_id (originating Facebook Page) to customer_media
-- 3. Add partial unique indexes to prevent duplicate pending invitations per organization

create table if not exists public.data_deletion_requests (
  code text primary key,
  fb_user_id text not null,
  status text not null default 'completed',
  created_at timestamptz not null default now()
);

alter table public.data_deletion_requests enable row level security;

alter table public.customer_media
  add column if not exists created_by uuid,
  add column if not exists page_id text;

create unique index if not exists memberships_pending_email_uidx
  on public.memberships (org_id, invited_email)
  where status = 'pending' and invited_email is not null;

create unique index if not exists memberships_pending_fb_uidx
  on public.memberships (org_id, invited_fb_user_id)
  where status = 'pending' and invited_fb_user_id is not null;
