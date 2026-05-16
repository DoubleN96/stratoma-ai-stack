# 🤖 Multi-Claude — Mother + Children + Daily Journal + Fathom

> One **mother Claude** orchestrates several **child Claudes**, each running
> as a separate UNIX user (or on a different VPS), all sharing the same
> Telegram bot. Every day they self-report into a Supabase journal that
> renders in a public web panel. Fathom calls (transcripts) flow into the
> same panel via webhook + cron pull.

This is the operating model we use across Stratoma AI projects. It scales
from 1 to N projects with no per-project babysitting, and gives you a single
URL (`panel.stratomai.com`) where you see what each Claude did today and
which client calls happened.

---

## Why this exists

Single-Claude works fine until you have multiple clients with different:
- working directories
- MCP servers (each project has its own GHL, Notion, Coolify scope)
- conversation history (don't mix Tripath context with Neverland context)
- credentials (one client must NOT see another's secrets)
- humans on Telegram (Sam ↔ Bali ops, Dani ↔ Neverland ops, you ↔ everything)

Running one Claude per project gives clean isolation. The mother Claude
sits on top to coordinate, summarize, and react when something needs
cross-project attention.

---

## Architecture

```
┌────────────────────── 1× Telegram bot ──────────────────────┐
│                                                              │
│   Operator (you) + approved teammates (Sam, Dani, etc.)     │
│                                                              │
└──┬──────────────────┬──────────────────┬──────────────────┬──┘
   │                  │                  │                  │
   ▼                  ▼                  ▼                  ▼
┌────────┐      ┌────────────┐    ┌───────────┐    ┌────────────────┐
│ MOTHER │      │ CHILD #1   │    │ CHILD #2  │    │ CHILD #N       │
│        │      │ bali_admin │    │ intkapital│    │ claudeuser     │
│ UNIX:  │      │            │    │           │    │ (Tripath VPS)  │
│ main   │      │ Unreal +   │    │ Neverland │    │ Tripath        │
│        │      │ Venaso     │    │           │    │                │
│ tmux:  │      │ tmux:      │    │ tmux:     │    │ tmux:          │
│ claude-│      │ claude     │    │ intkapital│    │ claude-tripath │
│ session│      │            │    │           │    │                │
└───┬────┘      └─────┬──────┘    └─────┬─────┘    └────────┬───────┘
    │                 │                  │                   │
    │   (mother can read & control children via su / SSH)    │
    │                                                        │
    └──────────────────► Supabase (panel.stratomai.com) ◄────┘
                              │
                              │  panel_agent_sessions
                              │  panel_daily_reports
                              │  panel_fathom_calls
                              │  panel_poll_triggers
                              ▼
                    panel.stratomai.com  (Next.js · live read)
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

### Example layout (this stack)

| User | Project focus | tmux session name | Home |
|---|---|---|---|
| `n8nstratoma` (UID 1000) | Mother — orchestration, cross-project | `claude-session` | `/home/n8nstratoma` |
| `bali_admin` (UID 1001) | Unreal Studio Bali + Venaso (Sam ops) | `claude` | `/home/bali_admin` |
| `intkapital` (UID 1002) | Int Kapital / Neverland (Dani ops) | `intkapital` | `/home/n8nstratoma/int-kapital` |
| `claudeuser` (remote VPS) | Tripath (real estate ops) | `claude-tripath` | `/home/claudeuser` (on 46.224.16.135) |

---

## Layer 2 — Mother reaches children

### Read a child's screen (no interruption)

```bash
sudo -u bali_admin tmux capture-pane -t claude -p -S -100
```

For the remote VPS:

```bash
sshpass -p 'ROOT_PWD' ssh root@46.224.16.135 \
  "tmux capture-pane -t claude-tripath -p -S -100"
```

### Send a prompt into a child's input

```bash
sudo -u bali_admin tmux send-keys -t claude 'tu prompt aquí' Enter
# Then ALSO send a second Enter — Claude Code treats multi-line input as
# a paste buffer and only commits on the second Enter:
sleep 0.5
sudo -u bali_admin tmux send-keys -t claude Enter
```

### Spawn a fresh child session

The remote Tripath VPS has a helper script `/root/.local/bin/claude-tripath`
that does the "attach if exists, else create" dance:

```bash
#!/bin/bash
SESSION_NAME="claude-tripath"
WORK_DIR="/home/claudeuser/tripath-develop"
RUN_USER="claudeuser"

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

Each project copies and tweaks this script for its own `WORK_DIR` and
`RUN_USER`. Result: every Claude is **persistent** — survives crashes,
SSH disconnects, and reboots (with a systemd unit; see
`CLAUDE-CODE-TELEGRAM-WORKFLOW.md`).

---

## Layer 3 — Daily journal (Supabase + Next.js)

Every night at **22:00 Madrid**, the mother runs `daily_journal_poll.py`:

1. Generates a self-summary by scanning her own `.jsonl` session log.
2. For each child: `tmux send-keys` a prompt that asks the child to:
   - write a 4-6 bullet markdown summary of what was done today, and
   - `INSERT INTO public.panel_daily_reports ...` it directly into Supabase.
3. 30 minutes later, a fallback run inserts a `source='system'` placeholder
   for any child that didn't reply.

The panel at `panel.stratomai.com/diario` shows a timeline grouped by
date and session.

### Database schema (TL;DR)

```sql
create table public.panel_agent_sessions (
  slug             text unique not null,    -- 'n8nstratoma', 'bali-admin', etc.
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

The `/diario` page has a **"🔄 Generar reporte ahora"** button:

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

Total clic-to-fresh-data: 30-90 seconds.

---

## Layer 4 — Fathom integration

Each client brand has its own Fathom workspace (call transcripts). We
ingest in two ways for redundancy:

### A) Realtime webhook (instant)

`/api/fathom-webhook/[project]` accepts Fathom's POST, verifies HMAC with
the per-workspace secret, then upserts into `panel_fathom_calls`.

Per-project routing:

| URL | Workspace | Secret env var |
|---|---|---|
| `/api/fathom-webhook/neverland` | invest@neverlandlombok.com | `FATHOM_WEBHOOK_SECRET_NEVERLAND` |
| `/api/fathom-webhook/unreal-bali` | unrealstudio@gmail.com (shared with Venaso) | `FATHOM_WEBHOOK_SECRET_UNREAL` |

When the Unreal workspace posts, the endpoint auto-classifies each call as
**Venaso** or **Unreal Studio Bali** by:

1. Title contains "venaso" → Venaso
2. Any attendee/host email under `@venasobali.com.au` or `@venaso.com.au` → Venaso
3. Known Venaso users (Marcelino, Sergio, Andreas, Sam) → Venaso
4. Otherwise → Unreal Studio Bali

You configure the URLs once in Fathom's UI (https://fathom.video/api_clients).

### B) Cron pull (safety net + backfill)

`fathom_pull.py` runs three times a day (03:00, 11:00, 19:00 Madrid) against
the Fathom API and upserts everything new. This catches webhooks that were
missed or that arrived before the webhook URL was configured.

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

`panel.stratomai.com/calls` renders the timeline grouped by project.

---

## Layer 5 — Web panel (Next.js + pg)

The panel is a standalone Next.js app (`DoubleN96/panel-stratomai`) that
reads directly from Postgres via the `pg` package.

### Important: the Coolify Supabase stack has no PostgREST

The `/rest/v1` Kong route returns `503 "name resolution failed"` because
the upstream PostgREST container is missing from the standard Coolify
Supabase compose. We bypass it entirely:

```
panel-stratomai container
   ├─ docker network: coolify (default Coolify net)
   └─ docker network: wckks4gsg8owkososoo8sosg (Supabase stack net)
       │
       └─ resolves "supabase-db" → port 5432 → pg client connects with
          PG_HOST / PG_USER (=postgres) / PG_PASSWORD / PG_DATABASE
```

Because Coolify uses `build_pack=dockerfile` and ignores the
`docker-compose.yaml` network spec, we install a per-minute cron that
re-attaches the panel container to the Supabase network after every rebuild:

```bash
# /home/n8nstratoma/claude-proxy/ensure_panel_network.sh (excerpt)
PANEL=$(sudo docker ps --format '{{.Names}}' | grep '^xgoocs8wcsw' | head -1)
sudo docker inspect "$PANEL" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
  | grep -q 'wckks4gsg8owkososoo8sosg' \
  || { sudo docker network connect wckks4gsg8owkososoo8sosg "$PANEL"; sudo docker restart "$PANEL"; }
```

### Routes

| Route | What it shows | Source |
|---|---|---|
| `/` | Dashboard — live GHL data per project (contacts, pipeline, calendars, agents) | GHL API |
| `/diario` | Cross-session daily journal timeline | Supabase `panel_daily_reports` |
| `/calls` | Fathom call transcripts grouped by project | Supabase `panel_fathom_calls` |
| `/api/refresh-journal` (POST) | Enqueue a manual journal poll | Inserts into `panel_poll_triggers` |
| `/api/fathom-webhook/[project]` (POST) | Receive Fathom transcripts | HMAC verify, upsert call |

---

## Cron schedule

All on the mother's VPS (`128.140.44.162` as user `n8nstratoma`):

| Schedule | Script | Purpose |
|---|---|---|
| `* * * * *` | `process_journal_triggers.py` | Pick up panel button presses (≤60s latency) |
| `* * * * *` | `ensure_panel_network.sh` | Keep panel container attached to Supabase Docker network |
| `0 20 * * *` | `run_daily_journal.sh` | Nightly automatic poll at **22:00 Madrid** |
| `0 1,9,17 * * *` | `fathom_pull.py` | Pull Fathom meetings 3×/day (03:00, 11:00, 19:00 Madrid) |
| (host cron, optional) | `e2e_tests.py`, `health_check.py` | Existing site monitoring |

---

## Files in this stack

Under `/home/n8nstratoma/claude-proxy/`:

| File | Role |
|---|---|
| `daily_journal_poll.py` | Sends prompts to children, generates self report, writes reports |
| `process_journal_triggers.py` | Worker that polls `panel_poll_triggers` and runs `daily_journal_poll.py` |
| `ensure_panel_network.sh` | Reconnects panel container to Supabase network after rebuilds |
| `fathom_pull.py` | Pulls recent meetings from Fathom API, upserts into `panel_fathom_calls` |
| `run_daily_journal.sh` | Cron wrapper that warms sudo + runs the python script |

Under `DoubleN96/panel-stratomai`:

```
panel-stratomai/
├── app/
│   ├── page.tsx                              # Dashboard
│   ├── diario/page.tsx                       # Diario
│   ├── calls/page.tsx                        # Calls
│   └── api/
│       ├── refresh-journal/route.ts          # POST manual trigger
│       └── fathom-webhook/[project]/route.ts # POST Fathom webhook
├── components/
│   ├── Nav.tsx                               # Shared menu (Dashboard / Diario / Calls)
│   ├── RefreshJournalButton.tsx              # Client-side button
│   ├── CompanyDashboard.tsx                  # Dashboard card per project
│   └── Branding.tsx
├── lib/
│   ├── db.ts                                 # pg pool singleton
│   └── ghl.ts                                # GHL API helpers
└── supabase/migrations/                      # Schema versions
```

---

## How to add a new project to the stack

1. **Create the GHL location's PIT** (or whatever data source the project uses).
2. **Add it to the panel:**
   - `lib/ghl.ts` → push a new `LocationConfig` into `LOCATIONS`
   - Coolify env var: `GHL_PIT_<PROJECT>`
   - Supabase: `INSERT INTO panel_projects (slug, name, ghl_location_id, ...)`
3. **(Optional) Create a child Claude session:**
   - `sudo useradd -m <user>` on the VPS
   - Install Claude Code as that user; do the OAuth dance once
   - Create a `claude-<project>` launcher script (copy from claude-tripath)
   - `INSERT INTO panel_agent_sessions (slug, display_name, ...)`
4. **(Optional) Fathom:**
   - Get the workspace API key + webhook secret from `https://fathom.video/api_clients`
   - Add `FATHOM_WEBHOOK_SECRET_<PROJECT>` env var
   - Map the slug in `app/api/fathom-webhook/[project]/route.ts` (`secretEnvForProject`)
   - Configure the webhook URL in Fathom UI
   - Add the workspace to `fathom_pull.py` (`WORKSPACES` list)

---

## Common ops

### Force a journal poll right now
- UI: click "🔄 Generar reporte ahora" on `/diario`
- CLI: `cd /home/n8nstratoma/claude-proxy && .venv/bin/python daily_journal_poll.py`

### Check what a child is doing
```bash
sudo -u bali_admin tmux capture-pane -t claude -p -S -80
```

### Re-login a child whose OAuth expired
```bash
sudo -u bali_admin tmux attach -t claude
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
| Webhook-only Fathom ingestion | Misses calls when the webhook URL changes / is misconfigured |
| Pull-only Fathom ingestion | 8-hour staleness; webhooks are instant |
| n8n for orchestration | Adds another moving part. The cron + Python combo is auditable in plain text |

---

## Future work

- [ ] Search across Fathom transcripts (Postgres FTS on `summary_md` + `raw_payload->transcript`)
- [ ] Link Fathom calls to GHL contacts automatically (match by email)
- [ ] Slack-style mention notifications when a child reports something critical
- [ ] Replace `tmux send-keys` with a proper IPC channel (Unix sockets on shared `/tmp/`)
- [ ] Move from `pg` direct to a thin DAL once we add more tables
