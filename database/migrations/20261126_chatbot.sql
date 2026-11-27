-- Forward-only idempotent migration: Phase 0 chatbot foundation
-- Creates/extends kb_entries, conversations, and reply_drafts with owner-only RLS.
-- Strictly additive (no destructive statements); safe on databases where public.conversations exists.

create table if not exists public.kb_entries (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  category text not null check (category in ('hours', 'address', 'service', 'booking', 'policy', 'faq')),
  title text not null,
  content text not null,
  keywords text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists kb_entries_org_category_idx
  on public.kb_entries (org_id, category, active);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  channel text not null default 'facebook' check (channel in ('facebook', 'zalo')),
  page_id text,
  customer_name text,
  customer_psid text,
  tag text default 'normal' check (tag in ('urgent', 'hard_case', 'tried_sample', 'normal')),
  ai_summary text,
  status text not null default 'open' check (status in ('open', 'pending_review', 'escalated', 'closed')),
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  last_message_preview text,
  unread_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.conversations add column if not exists page_id text;
alter table public.conversations add column if not exists status text not null default 'open';
alter table public.conversations add column if not exists last_inbound_at timestamptz;
alter table public.conversations add column if not exists last_outbound_at timestamptz;
alter table public.conversations add column if not exists last_message_preview text;
alter table public.conversations add column if not exists unread_count integer not null default 0;
alter table public.conversations add column if not exists created_at timestamptz not null default now();

create unique index if not exists conversations_org_page_psid_uidx
  on public.conversations (org_id, page_id, customer_psid)
  where page_id is not null and customer_psid is not null;

create index if not exists conversations_org_updated_idx
  on public.conversations (org_id, updated_at desc);

create table if not exists public.reply_drafts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  inbound_message_id text,
  source text not null default 'ai' check (source in ('faq', 'ai', 'fixed_no_price', 'consent_request', 'escalate', 'owner')),
  action text not null default 'reply' check (action in ('reply', 'ask_consent', 'escalate')),
  risk text not null default 'low' check (risk in ('low', 'medium', 'high')),
  draft_text text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'sending', 'sent', 'rejected', 'failed')),
  approved_by uuid,
  approved_at timestamptz,
  sent_at timestamptz,
  meta_message_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reply_drafts_org_status_idx
  on public.reply_drafts (org_id, status, created_at desc);

create index if not exists reply_drafts_conversation_idx
  on public.reply_drafts (conversation_id, created_at desc);

alter table public.kb_entries enable row level security;
alter table public.conversations enable row level security;
alter table public.reply_drafts enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'kb_entries' and policyname = 'org_isolate_kb_entries'
  ) then
    create policy "org_isolate_kb_entries"
      on public.kb_entries for all
      to authenticated
      using (org_id in (select public.user_owner_org_ids()))
      with check (org_id in (select public.user_owner_org_ids()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'conversations' and policyname = 'org_isolate_conversations_owner'
  ) then
    create policy "org_isolate_conversations_owner"
      on public.conversations for all
      to authenticated
      using (org_id in (select public.user_owner_org_ids()))
      with check (org_id in (select public.user_owner_org_ids()));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'reply_drafts' and policyname = 'org_isolate_reply_drafts'
  ) then
    create policy "org_isolate_reply_drafts"
      on public.reply_drafts for all
      to authenticated
      using (org_id in (select public.user_owner_org_ids()))
      with check (org_id in (select public.user_owner_org_ids()));
  end if;
end $$;
