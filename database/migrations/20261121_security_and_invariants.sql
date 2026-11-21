-- Idempotent forward-only migration: Security hardening & DB-enforced concurrency invariants
-- 1. Deduplicate any legacy duplicate pending invitations safely (without modifying old migration files).
-- 2. Restrict public.audit_logs direct RLS reads strictly to active owners (not staff).
-- 3. Enforce last-active-owner invariant transactionally on public.memberships via advisory lock trigger.

with ranked_email as (
  select id, row_number() over (partition by org_id, invited_email order by created_at asc, id asc) as rn
  from public.memberships
  where status = 'pending' and invited_email is not null
)
delete from public.memberships where id in (select id from ranked_email where rn > 1);

with ranked_fb as (
  select id, row_number() over (partition by org_id, invited_fb_user_id order by created_at asc, id asc) as rn
  from public.memberships
  where status = 'pending' and invited_fb_user_id is not null
)
delete from public.memberships where id in (select id from ranked_fb where rn > 1);

create unique index if not exists memberships_pending_email_uidx
  on public.memberships (org_id, invited_email)
  where status = 'pending' and invited_email is not null;

create unique index if not exists memberships_pending_fb_uidx
  on public.memberships (org_id, invited_fb_user_id)
  where status = 'pending' and invited_fb_user_id is not null;

-- Single-owner model (v1): restrict both user_org_ids() and user_owner_org_ids() strictly to active owners
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
    and role = 'owner'
    and status = 'active';
$$;

create or replace function public.user_owner_org_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select org_id
  from public.memberships
  where user_id = auth.uid()
    and role = 'owner'
    and status = 'active';
$$;

alter table public.audit_logs enable row level security;

drop policy if exists "org_isolate_audit_logs" on public.audit_logs;
create policy "org_isolate_audit_logs"
  on public.audit_logs for select
  to authenticated
  using (org_id in (select public.user_owner_org_ids()));

create or replace function public.prevent_zero_active_owners()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  remaining_owners integer;
begin
  if OLD.role = 'owner' and OLD.status = 'active' then
    if TG_OP = 'DELETE' and not exists (select 1 from public.organizations where id = OLD.org_id) then
      return OLD;
    end if;
    if TG_OP = 'DELETE' or NEW.role <> 'owner' or NEW.status <> 'active' then
      -- Serialize concurrent demotion/revocation attempts within the same organization
      perform pg_advisory_xact_lock(hashtext(OLD.org_id::text));
      select count(*) into remaining_owners
      from public.memberships
      where org_id = OLD.org_id
        and role = 'owner'
        and status = 'active'
        and id <> OLD.id;
      if remaining_owners = 0 then
        raise exception 'LAST_OWNER_PROTECTED' using errcode = 'P0001';
      end if;
    end if;
  end if;
  if TG_OP = 'DELETE' then
    return OLD;
  end if;
  return NEW;
end;
$$;

drop trigger if exists memberships_prevent_zero_active_owners on public.memberships;
create trigger memberships_prevent_zero_active_owners
  before update or delete on public.memberships
  for each row
  execute function public.prevent_zero_active_owners();
