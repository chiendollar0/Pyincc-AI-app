-- Idempotent migration: Onboarding codes, price-free catalog descriptions, and 7-day booking follow-up reminders
-- 1. public.onboarding_codes: one-time setup code for a salon owner to claim/create their organization
-- 2. public.catalog_items: add description & updated_at (price remains optional/nullable and unused by v1 API)
-- 3. public.bookings: add service_date, followup_done, notes for 7-day post-service reminders (owner-only, no auto-messaging)

create table if not exists public.onboarding_codes (
  code text primary key,
  org_name text not null,
  org_id uuid references public.organizations(id) on delete set null,
  claimed_by uuid,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.onboarding_codes enable row level security;

alter table public.catalog_items
  add column if not exists description text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.catalog_items
  drop constraint if exists catalog_items_category_check;

alter table public.catalog_items
  add constraint catalog_items_category_check
  check (category in ('eyebrow', 'lip', 'other'));

alter table public.bookings
  add column if not exists service_date date,
  add column if not exists followup_done boolean not null default false,
  add column if not exists notes text;

create index if not exists idx_bookings_org_service_date
  on public.bookings (org_id, service_date)
  where followup_done = false and status <> 'cancelled';
