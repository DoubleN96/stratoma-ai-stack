# 🤖 Multi-Claude — Mother + Children + Daily Journal + Calls

> One **mother Claude** orchestrates several **child Claudes**, each running
> as a separate UNIX user (or on a different VPS), all sharing the same
> Telegram bot. Every day they self-report into a Supabase journal that
> renders in a web panel. Call transcripts (Fathom or similar) flow into
> the same panel via webhook + cron pull.

This is the operating model we use across the agency's projects. It scales
from 1 to N projects with no per-project babysitting, and gives you a single
URL where you see what each Claude did today and which client calls
happened.

> ℹ️ Examples below use **Project A**, **Project B**, **Project C** as
> generic stand-ins for real client brands. Adapt UNIX user names,
> URLs, location IDs, and email domains to your own setup.

---

## Why this exists

Single-Claude works fine until you have multiple clients with different:
- working directories
- MCP servers (each project has its own CRM, Notion, Coolify scope)
- conversation history (don't mix Project A context with Project B context)
- credentials (one client must NOT see another's secrets)
- humans on Telegram (one operator per project, you on top of all)

Running one Claude per project gives clean isolation. The mother Claude
sits on top to coordinate, summarize, and react when something needs
cross-project attention.

---

## Architecture

```
┌────────────────────── 1× Telegram bot ──────────────────────┐
│                                                              │
│   Operator (you) + approved teammates                       │
│                                                              │
└──┬──────────────────┬──────────────────┬──────────────────┬──┘
   │                  │                  │                  │
   ▼                  ▼                  ▼                  ▼
┌────────┐      ┌────────────┐    ┌───────────┐    ┌────────────────┐
│ MOTHER │      │ CHILD #A   │    │ CHILD #B  │    │ CHILD #C       │
│        │      │ client_a   │    │ client_b  │    │ client_c       │
│ UNIX:  │      │            │    │           │    │ (remote VPS)   │
│ main   │      │ Project A  │    │ Project B │    │ Project C      │
│        │      │            │    │           │    │                │
│ tmux:  │      │ tmux:      │    │ tmux:     │    │ tmux:          │
│ claude │      │ claude     │    │ claude    │    │ claude-c       │
└───┬────┘      └─────┬──────┘    └─────┬─────┘    └────────┬───────┘
    │                 │                  │                   │
    │   (mother can read & control children via su / SSH)    │
    │                                                        │
    └──────────────────► Supabase (panel app) ◄──────────────┘
                              │
                              │  panel_agent_sessions
                              │  panel_daily_reports
                              │  panel_fathom_calls
                              │  panel_poll_triggers
                              ▼
                       panel (Next.js · live read)
                       / · /diario · /calls
```

---

## Layer 1 — UNIX users as isolation boundary

Each project Claude runs as its own UNIX user on the same VPS (or on a
dedicated VPS for heavier projects). Each user has its own:

| Resource | Why isolated |
|---|---|
| `/home/<user>/` | own working dirs, no cross-project file leaks |
| `~/.claude/` | own credentials.json (OAuth token), own memory |
| `~/.mcp.json` | own MCP server set per project |
| `/tmp/tmux-<uid>/` | own tmux socket (perms 0700) |
| `claude --channels plugin:telegram@...` | own bot connection, own allowlist |

The mother Claude (operator user) holds the sudo password and the SSH key
to remote VPSes, so she can `su - <child>` to inspect or message a child
session.

### Example layout (illustrative)

| User | Project focus | tmux session name | Home |
|---|---|---|---|
| `mother` (UID 1000) | Orchestration, cross-project | `claude-session` | `/home/mother` |
| `client_a` (UID 1001) | Project A — investments brand | `claude` | `/home/client_a` |
| `client_b` (UID 1002) | Project B — overseas RE + sub-brand | `claude` | `/home/client_b` |
| `client_c` (remote VPS) | Project C — property management | `claude-c` | `/home/client_c` (remote IP) |

---

## Layer 2 — Mother reaches children

### Read a child's screen (no interruption)

```bash
sudo -u client_a tmux capture-pane -t claude -p -S -100
```

For a remote VPS:

```bash
sshpass -p '<REMOTE_ROOT_PWD>' ssh root@<REMOTE_VPS_IP> \
  "tmux capture-pane -t claude-c -p -S -100"
```

### Send a prompt into a child's input

```bash
sudo -u client_a tmux send-keys -t claude 'your prompt here' Enter
# Then ALSO send a second Enter — Claude Code treats multi-line input as
# a paste buffer and only commits on the second Enter:
sleep 0.5
sudo -u client_a tmux send-keys -t claude Enter
```

### Spawn a fresh child session

Each project gets a small helper script (e.g. `/root/.local/bin/claude-<project>`)
that does the "attach if exists, else create" dance:

```bash
#!/bin/bash
SESSION_NAME="claude-<project>"
WORK_DIR="/home/<user>/<project-folder>"
RUN_USER="<user>"

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  exec tmux attach -t "$SESSION_NAME"
fi

tmux kill-session -t "$SESSION_NAME" 2>/dev/null
tmux new-session -d -s "$SESSION_NAME" \
  sudo -u "$RUN_USER" bash --norc --noprofile -i
tmux send-keys -t "$SESSION_NAME" \
  "cd $WORK_DIR && claude --dangerously-skip-permissions" Enter
exec tmux attach -t "$SESSION_NAME"
```

Result: every Claude is **persistent** — survives crashes, SSH disconnects,
and reboots (combine with a systemd unit; see
`CLAUDE-CODE-TELEGRAM-WORKFLOW.md`).

---

## Layer 3 — Daily journal (Supabase + Next.js)

Every night at **22:00 local time**, the mother runs `daily_journal_poll.py`:

1. Generates a self-summary by scanning her own `.jsonl` session log.
2. For each child: `tmux send-keys` a prompt that asks the child to:
   - write a 4-6 bullet markdown summary of what was done today, and
   - `INSERT INTO public.panel_daily_reports ...` it directly into Supabase.
3. 30 minutes later, a fallback run inserts a `source='system'` placeholder
   for any child that didn't reply.

The `/diario` page on the panel shows a timeline grouped by date and session.

### Database schema (TL;DR)

```sql
create table public.panel_agent_sessions (
  slug             text unique not null,    -- 'mother', 'client_a', etc.
  display_name     text not null,
  vps_host         text not null,
  unix_user        text not null,
  tmux_session     text,
  telegram_chat_id text,
  focus_projects   text[] not null default '{}',
  is_active        boolean not null default true
);

create table public.panel_daily_reports (
  id            bigint generated always as identity primary key,
  report_date   date not null,
  session_slug  text not null references public.panel_agent_sessions(slug),
  project_slugs text[] not null default '{}',
  summary_md    text not null,
  source        text not null default 'self',  -- 'self' or 'system'
  created_at    timestamptz not null default now(),
  unique (session_slug, report_date)
);
```

### On-demand refresh from the panel

The `/diario` page has a **"🔄 Generate report now"** button:

```
Browser
  ↓ POST /api/refresh-journal
Next.js API (Supabase service_role)
  ↓ INSERT into panel_poll_triggers (status='pending')
Supabase
  ↓ host cron every minute
process_journal_triggers.py
  ↓ executes daily_journal_poll.py
Children sessions  (via tmux send-keys + SSH)
  ↓ each writes its row in panel_daily_reports
/diario reflects new rows on next 60s revalidate
```

Total click-to-fresh-data: 30-90 seconds.

---

## Layer 4 — Calls integration (Fathom example)

Each client brand has its own call-transcript workspace (e.g. Fathom). We
ingest in two ways for redundancy:

### A) Realtime webhook (instant)

`/api/fathom-webhook/[project]` accepts the provider's POST, verifies HMAC
with the per-workspace secret, then upserts into `panel_fathom_calls`.

Per-project routing:

| URL | Workspace | Secret env var |
|---|---|---|
| `/api/fathom-webhook/project_a` | brand A's Fathom workspace | `FATHOM_WEBHOOK_SECRET_PROJECT_A` |
| `/api/fathom-webhook/project_b` | brand B's Fathom workspace (shared with sub-brand B1) | `FATHOM_WEBHOOK_SECRET_PROJECT_B` |

When workspace B posts, the endpoint auto-classifies each call as the
**main brand** or **sub-brand B1** by:

1. Title contains the sub-brand name → sub-brand
2. Any attendee/host email under sub-brand's domain → sub-brand
3. Known sub-brand users (configurable list) → sub-brand
4. Otherwise → main brand

You configure the URLs once in your Fathom UI (or equivalent provider's UI).

### B) Cron pull (safety net + backfill)

`fathom_pull.py` runs three times a day (e.g. 03:00, 11:00, 19:00 local) against
the provider's API and upserts everything new. This catches webhooks that were
missed or that arrived before the URL was configured.

Fathom example:

```bash
# Fathom API base
GET https://api.fathom.ai/external/v1/meetings?limit=25
Header: X-Api-Key: <api_key>          # NOT Bearer
```

Returns `{items: [...], next_cursor: "..."}` with full call metadata:
title, started_at, duration, attendees, summary, action_items, share_url.

### Schema

```sql
create table public.panel_fathom_calls (
  id                bigint generated always as identity primary key,
  fathom_call_id    text unique,
  project_slug      text references public.panel_projects(slug),
  title             text,
  call_started_at   timestamptz,
  duration_seconds  int,
  recording_url     text,
  share_url         text,
  transcript_url    text,
  summary_md        text,
  action_items      jsonb,
  attendees         jsonb,
  host_email        text,
  highlights        jsonb,
  raw_payload       jsonb,
  received_at       timestamptz not null default now()
);
```

The `/calls` page renders the timeline grouped by project.

---

## Layer 5 — Web panel (Next.js + pg)

The panel is a standalone Next.js app that reads directly from Postgres
via the `pg` package.

### Important: the Coolify Supabase stack has no PostgREST

The `/rest/v1` Kong route returns `503 "name resolution failed"` because
the upstream PostgREST container is missing from the standard Coolify
Supabase compose. We bypass it entirely:

```
panel container
   ├─ docker network: coolify (default Coolify net)
   └─ docker network: <supabase-stack-id> (Supabase stack net)
       │
       └─ resolves "supabase-db" → port 5432 → pg client connects with
          PG_HOST / PG_USER (=postgres) / PG_PASSWORD / PG_DATABASE
```

Because Coolify uses `build_pack=dockerfile` and ignores the
`docker-compose.yaml` network spec, we install a per-minute cron that
re-attaches the panel container to the Supabase network after every rebuild:

```bash
# ensure_panel_network.sh (excerpt)
PANEL=$(sudo docker ps --format '{{.Names}}' | grep '^<panel-container-prefix>' | head -1)
sudo docker inspect "$PANEL" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
  | grep -q '<supabase-stack-id>' \
  || { sudo docker network connect <supabase-stack-id> "$PANEL"; sudo docker restart "$PANEL"; }
```

### Routes

| Route | What it shows | Source |
|---|---|---|
| `/` | Dashboard — live CRM data per project (contacts, pipeline, calendars, agents) | CRM API (e.g. GHL) |
| `/diario` | Cross-session daily journal timeline | Supabase `panel_daily_reports` |
| `/calls` | Call transcripts grouped by project | Supabase `panel_fathom_calls` |
| `/api/refresh-journal` (POST) | Enqueue a manual journal poll | Inserts into `panel_poll_triggers` |
| `/api/fathom-webhook/[project]` (POST) | Receive call transcripts | HMAC verify, upsert call |

---

## Cron schedule

All on the mother's VPS:

| Schedule | Script | Purpose |
|---|---|---|
| `* * * * *` | `process_journal_triggers.py` | Pick up panel button presses (≤60s latency) |
| `* * * * *` | `ensure_panel_network.sh` | Keep panel container attached to Supabase Docker network |
| `0 20 * * *` | `run_daily_journal.sh` | Nightly automatic poll (22:00 local) |
| `0 1,9,17 * * *` | `fathom_pull.py` | Pull Fathom meetings 3×/day (03:00, 11:00, 19:00 local) |

---

## Files in this stack

Under a working dir on the mother (e.g. `/home/mother/claude-proxy/`):

| File | Role |
|---|---|
| `daily_journal_poll.py` | Sends prompts to children, generates self report, writes reports |
| `process_journal_triggers.py` | Worker that polls `panel_poll_triggers` and runs `daily_journal_poll.py` |
| `ensure_panel_network.sh` | Reconnects panel container to Supabase network after rebuilds |
| `fathom_pull.py` | Pulls recent meetings from Fathom API, upserts into `panel_fathom_calls` |
| `run_daily_journal.sh` | Cron wrapper that warms sudo + runs the python script |

Under the panel repo:

```
panel/
├── app/
│   ├── page.tsx                              # Dashboard
│   ├── diario/page.tsx                       # Daily journal
│   ├── calls/page.tsx                        # Calls
│   └── api/
│       ├── refresh-journal/route.ts          # POST manual trigger
│       └── fathom-webhook/[project]/route.ts # POST call webhook
├── components/
│   ├── Nav.tsx                               # Shared menu (Dashboard / Diario / Calls)
│   ├── RefreshJournalButton.tsx              # Client-side button
│   ├── CompanyDashboard.tsx                  # Dashboard card per project
│   └── Branding.tsx
├── lib/
│   ├── db.ts                                 # pg pool singleton
│   └── ghl.ts                                # CRM API helpers
└── supabase/migrations/                      # Schema versions
```

---

## How to add a new project to the stack

1. **Create the CRM source's API token** (or whatever data source the project uses).
2. **Add it to the panel:**
   - Push a new project entry into the CRM `LOCATIONS` array
   - Coolify env var: `CRM_TOKEN_<PROJECT>`
   - Supabase: `INSERT INTO panel_projects (slug, name, ...)`
3. **(Optional) Create a child Claude session:**
   - `sudo useradd -m <user>` on the VPS
   - Install Claude Code as that user; do the OAuth dance once
   - Create a `claude-<project>` launcher script (copy the template above)
   - `INSERT INTO panel_agent_sessions (slug, display_name, ...)`
4. **(Optional) Calls:**
   - Get the workspace API key + webhook secret from the provider
   - Add `FATHOM_WEBHOOK_SECRET_<PROJECT>` env var
   - Map the slug in `app/api/fathom-webhook/[project]/route.ts`
   - Configure the webhook URL in the provider's UI
   - Add the workspace to `fathom_pull.py` (`WORKSPACES` list)

---

## Common ops

### Force a journal poll right now
- UI: click "🔄 Generate report now" on `/diario`
- CLI: `cd /home/mother/claude-proxy && .venv/bin/python daily_journal_poll.py`

### Check what a child is doing
```bash
sudo -u client_a tmux capture-pane -t claude -p -S -80
```

### Re-login a child whose OAuth expired
```bash
sudo -u client_a tmux attach -t claude
# Inside: /login   (paste OAuth code from browser)
```

### Add yourself to a different child's allowlist
- Open the corresponding `~/.claude/channels/telegram/access.json` as that user
- Use `/telegram:access pair <code>` from a terminal session running as that user

---

## Why this design beats alternatives

| Alternative | Why we don't do that |
|---|---|
| One Claude with many MCP servers | Context grows fast, MCP namespace collisions, no per-project memory |
| One Claude per project but no central panel | No cross-project visibility, no morning standup |
| Slack/Discord instead of Telegram | Telegram bots are 30s to wire, the plugin already exists, push reliability is excellent |
| Webhook-only call ingestion | Misses calls when the webhook URL changes / is misconfigured |
| Pull-only call ingestion | 8-hour staleness; webhooks are instant |
| n8n for orchestration | Adds another moving part. The cron + Python combo is auditable in plain text |

---

## Future work

- [ ] Search across call transcripts (Postgres FTS on `summary_md` + `raw_payload->transcript`)
- [ ] Link calls to CRM contacts automatically (match by email)
- [ ] Slack-style mention notifications when a child reports something critical
- [ ] Replace `tmux send-keys` with a proper IPC channel (Unix sockets on shared `/tmp/`)
- [ ] Move from `pg` direct to a thin DAL once we add more tables
