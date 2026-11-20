-- Idempotent migration: Unified handoff_cases & handover_threads architecture
-- Supports Input A (Business AI Handover) & Input B (Owner Capture at Salon)
-- with a single human-approved output pipeline and RLS tenant isolation.

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

create index if not exists idx_handoff_cases_org_created
  on public.handoff_cases (org_id, created_at desc);

create table if not exists public.handover_threads (
  org_id uuid not null references public.organizations(id) on delete cascade,
  page_id text not null,
  psid text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (page_id, psid)
);

alter table public.handoff_cases enable row level security;
alter table public.handover_threads enable row level security;

drop policy if exists "org_isolate_handoff_cases" on public.handoff_cases;
create policy "org_isolate_handoff_cases"
  on public.handoff_cases for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));

drop policy if exists "org_isolate_handover_threads" on public.handover_threads;
create policy "org_isolate_handover_threads"
  on public.handover_threads for all
  to authenticated
  using (org_id in (select public.user_org_ids()))
  with check (org_id in (select public.user_org_ids()));
