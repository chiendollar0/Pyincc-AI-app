-- Idempotent migration: Audit logs for staff permissions & handoff case actions (Phase 3 - C1)
-- Enforces per-organization tenant isolation via RLS using public.user_org_ids().

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

alter table public.audit_logs enable row level security;

drop policy if exists "org_isolate_audit_logs" on public.audit_logs;
create policy "org_isolate_audit_logs"
  on public.audit_logs for select
  to authenticated
  using (org_id in (select public.user_org_ids()));
