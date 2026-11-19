-- Idempotent P0/P1 Hardening Migration
-- 1. Add storage_path & page_id to conversation_messages (avoid persisting expiring signed URLs; reply via originating page)
-- 2. Add data_deletion_requests table for Meta Data Deletion status lookup (/data-deletion?code=...)
-- 3. Add atomic unique partial index bookings_active_slot to prevent double-booking race conditions

alter table public.conversation_messages
  add column if not exists storage_path text,
  add column if not exists page_id text;

create table if not exists public.data_deletion_requests (
  code text primary key,
  fb_user_id text not null,
  status text not null default 'completed',
  created_at timestamptz default now()
);

alter table public.data_deletion_requests enable row level security;

create unique index if not exists bookings_active_slot
  on public.bookings (org_id, scheduled_at)
  where status in ('pending', 'confirmed');
