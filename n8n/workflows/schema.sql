-- Supabase tables the shipped n8n exports read and write.
--
-- Reconstructed from the exports themselves (every `/rest/v1/<table>` call in
-- n8n/workflows/*.json), not dumped from a live database — so treat it as the
-- starting point it is, and widen the types if your data needs it. Without
-- these tables PostgREST answers 404 and every approval workflow fails on its
-- first Supabase node.
--
-- Run it against the stack's Postgres:
--   docker compose exec -T supabase-db psql -U postgres -d postgres < n8n/workflows/schema.sql

-- ── telegram_pending ────────────────────────────────────────────────────────
-- One row per AI-proposed WhatsApp reply awaiting the operator's /ok.
-- Keyed by the Telegram message id so a reply-to in the chat finds its context.
create table if not exists public.telegram_pending (
    id                bigint generated always as identity primary key,
    telegram_msg_id   bigint      not null unique,
    contact_id        text        not null,
    conv_id           text,
    lead_name         text,
    historial         jsonb       not null default '[]'::jsonb,
    proposed_response text,
    created_at        timestamptz not null default now()
);

-- ── email_pending_approvals ─────────────────────────────────────────────────
-- One row per inbound email the monitor workflows classified. The approve /
-- reject webhooks look the row up by `id`, so the insert must be sent with
-- `Prefer: return=representation` for n8n to read the new id back.
create table if not exists public.email_pending_approvals (
    id                uuid        primary key default gen_random_uuid(),
    email_id          text,
    thread_id         text,
    from_email        text,
    from_name         text,
    subject           text,
    body_snippet      text,
    to_account        text,
    category          text,
    -- the n8n credential id to reply with; each monitor workflow writes its own
    gmail_credential  text,
    proposed_response text,
    status            text        not null default 'pending',
    created_at        timestamptz not null default now()
);

-- ── knowledge_gaps ──────────────────────────────────────────────────────────
-- Questions the AI could not answer. The weekly self-improvement workflow
-- reads `resolved = false` ordered by created_at, then flips them.
create table if not exists public.knowledge_gaps (
    id          bigint generated always as identity primary key,
    question    text        not null,
    ai_response text,
    gap_type    text,
    contact_id  text,
    resolved    boolean     not null default false,
    resolved_at timestamptz,
    created_at  timestamptz not null default now()
);

create index if not exists knowledge_gaps_unresolved_idx
    on public.knowledge_gaps (created_at desc)
    where resolved = false;

-- ── ai_memory ───────────────────────────────────────────────────────────────
-- Rolling conversation memory, one row per CRM contact. The upsert uses
-- `?on_conflict=ghl_contact_id`, so that column must carry a unique constraint.
create table if not exists public.ai_memory (
    id              bigint generated always as identity primary key,
    ghl_contact_id  text        not null unique,
    messages        jsonb       not null default '[]'::jsonb,
    updated_at      timestamptz not null default now()
);

-- ── Grants ──────────────────────────────────────────────────────────────────
-- The workflows call PostgREST with the service_role JWT. That role exists in
-- the supabase/postgres image; guarded so this file still runs on stock
-- Postgres, where you grant to whatever role your JWT maps to instead.
do $$
begin
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        grant usage on schema public to service_role;
        grant all on public.telegram_pending, public.email_pending_approvals,
                      public.knowledge_gaps, public.ai_memory to service_role;
        grant usage, select on all sequences in schema public to service_role;
    end if;
end
$$;

-- Tell PostgREST to pick the new tables up without a restart.
notify pgrst, 'reload schema';
