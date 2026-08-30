# Stratoma AI Stack

**Run a small agency from a chat app, on one VPS.** This repo is the stack *and* the operating
methodology: the Docker services, the playbooks, and — the part you only learn by running agents
in production for months — how to keep a fleet of them alive.

The agent lives in a `tmux` session on your server and you talk to it from Telegram. It deploys,
scrapes, writes workflows, answers customers, and runs the box. Everything here is derived from
what actually runs the operation.

> **On the shipped examples.** The `n8n/workflows/` exports are captured from production and were
> redacted by hand. That redaction is **not** verified by any automated check, so treat the exports
> as samples to read, not as scrubbed fixtures to reuse — and do not assume the same of your own
> exports. If you contribute workflow JSON, hand-write synthetic sample data rather than shipping
> captured traffic: names, addresses, bank details, listing IDs and tracking URLs all survive a
> naive find-and-replace, and encoded tokens survive it invisibly.

|  | |
|---|---|
| 🐣 **Never set up a server before?** | **[docs/SETUP-FROM-SCRATCH.md](docs/SETUP-FROM-SCRATCH.md)** — every command, copy-paste, from buying a server to texting an AI agent that runs it for you. |
| 🐳 **You know Docker?** | **[Quick Start](#quick-start)** below. |

Hosting is one small VPS (~€20/mo at the time of writing), plus the Claude subscription the agent
runs on. There is no `ANTHROPIC_API_KEY` anywhere in this repo — see
[Cost & security](#cost--security).

---

## 🎮 Showcase — built on this exact stack

**Pokémon Madrid** is a full Pokémon-style game set in
Madrid, **built almost entirely by AI from a prompt** (Claude Code · Opus + Gemini for the art),
and deployed on this stack: Hetzner + Coolify + self-hosted Supabase (account login & cloud saves).
The whole thing — code, art, audio, deploys, testing — was directed from **Telegram**, with a group
of friends sending photos and audio as context.

**→ [Get €20 free credit on Hetzner](https://hetzner.cloud/?ref=lbEMCsnlJ2EP)** and build your own.

---

## Documentation

| Doc | What it covers |
|-----|----------------|
| **[SETUP-FROM-SCRATCH](docs/SETUP-FROM-SCRATCH.md)** | Zero to a server you can text. Buy the VPS, SSH in, install Claude Code, `tmux`, the official Telegram plugin, a BotFather bot, then MCP tools, skills and DNS/API tokens. |
| **[CLAUDE-CODE-TELEGRAM-WORKFLOW](docs/CLAUDE-CODE-TELEGRAM-WORKFLOW.md)** | Day-to-day operating: the exact start command, tmux + systemd, the pairing flow for teammates, the four memory layers, the MCP catalog, security posture, troubleshooting. |
| **[MULTI-CLAUDE-MOTHER-AND-CHILDREN](docs/MULTI-CLAUDE-MOTHER-AND-CHILDREN.md)** | Many projects, one panel: per-UNIX-user isolation, cross-`tmux` orchestration, the Supabase journal schema, call-transcript ingestion, adding a new project. |
| **[FLEET-ORCHESTRATION-AND-MAINTENANCE](docs/FLEET-ORCHESTRATION-AND-MAINTENANCE.md)** | Keeping the fleet alive: the orchestrator user-account pattern, allowlist hot-reload, and the 3-layer cron loop (liveness, round-trip, restart). Plus production gotchas. |
| **[TRACKING-AND-ANALYTICS](docs/TRACKING-AND-ANALYTICS.md)** | One measurement layer per client site: DNS → one GTM container → GA4, Search Console, Meta Pixel/CAPI. Includes the grey-cloud gotcha that breaks Let's Encrypt. |
| **[KNOWLEDGE-BASE](docs/KNOWLEDGE-BASE.md)** | Self-hosted Outline as the docs layer: one instance, one private collection per client, and a REST API the agents read and write. |
| **[whatsapp/README](whatsapp/README.md)** | WhatsApp communities as funnel units — and the ban-risk section, stated plainly. |
| **[n8n/workflows/README](n8n/workflows/README.md)** | What each exported workflow does, and which ones are methodology-only. |

---

## The operating model

One agent per project, each under its own UNIX user, each with its own chat bot. A **mother**
session orchestrates them:

- **Reading a child** — `tmux capture-pane` shows you what it is doing without interrupting it.
- **Driving a child** — `tmux send-keys`, and you must send Enter **twice**: Claude Code treats
  multi-line input as a paste buffer and only commits on the second one.
- **Bot-to-bot is impossible** on Telegram, so the orchestrator drives a real *user* account
  (Telethon). That account can also script BotFather to mint bots for new projects, create
  channels, and run the round-trip health probe.
- **Three cron layers** keep it alive: hourly liveness + auto-revive, 8-hourly end-to-end
  round-trip (a real reply proves process + auth + channel, which a liveness check cannot), and a
  weekly restart to pick up auto-updates.
- **One long-lived token per account.** Minting a new `setup-token` appears to revoke the previous
  one, so exactly one session holds it and the rest run on the shared credential.

Detail in **[FLEET-ORCHESTRATION-AND-MAINTENANCE](docs/FLEET-ORCHESTRATION-AND-MAINTENANCE.md)**
and **[MULTI-CLAUDE-MOTHER-AND-CHILDREN](docs/MULTI-CLAUDE-MOTHER-AND-CHILDREN.md)**.

---

## Operational reliability

> The hard part is not starting agents. It is that a live process, a live bridge, and a *reachable*
> agent are three different things — and the failure modes below all look identical from outside:
> **process up, bot silent.** This table is the diagnosis layer we actually use.

| Symptom | What is really happening | Fix |
|---|---|---|
| Works after every restart, dies hours later, forever | A **Stop hook spawned a nested agent**. The child inherits `enabledPlugins`, boots its own chat bridge, and that bridge SIGTERMs the PID in the bridge PID file — the *parent's live bridge*. The child then exits and its own bridge dies on stdin EOF. Net: zero bridges, and dead MCP servers are never respawned. | No hook may spawn a nested `claude -p`. Audit every Stop/PostToolUse hook. Tell: a new multi-hundred-KB transcript file appears on **every turn**. |
| Bridge dead, session mid-task | Operators reach for the biggest hammer and burn hours of live context. | Recovery ladder, cheapest first: `/reload-plugins` in the live pane → restart the process → recreate the `tmux` session. Verify the session PID is *unchanged* to prove context survived. |
| Receives messages, composes the right answer in the pane, user gets nothing | Launched with the **resume/continue flag**, which can leave outbound routing unbound. The pane actively lies to you. | Make the canonical revive command flagless. If you must resume, probe with a round-trip and fall back to a clean relaunch automatically. **Note:** the recipes in [FLEET-ORCHESTRATION-AND-MAINTENANCE](docs/FLEET-ORCHESTRATION-AND-MAINTENANCE.md) (Layer 3 weekly restart, and restarting the mother) still launch with `--continue` and have no probe or fallback wired in — that doc has not caught up with this row. Add the round-trip probe yourself before relying on them. |
| Replies to one message in three; no errors anywhere | **Orphaned bridge reparented to init.** Two pollers on one token = 409 Conflict; updates go to whichever wins the race. Every heal cycle that kills the agent without its bridge tree adds another orphan. | Reap on every watchdog cycle: any bridge process with `PPID == 1` is wrong by definition — `kill -9` it (SIGTERM is ignored). |
| Alive, bridge up, reply tool works — still mute | Nothing in the platform *forces* the outbound tool call. On a short inbound ("ok", "ping") the model just emits text and ends the turn. | A **RULE #1** block at the top of every session's instruction file: the sender is reading a chat, not this terminal; the turn is not over until the reply tool has been called — including for one-word answers. |
| "Revived" entries for a session nobody saw crash | The **watchdog is the outage**. A loaded session takes ~90s to boot; a watchdog that samples once catches it mid-boot and kills it. | Grace period past full boot time, plus double confirmation — two identical readings 60s apart before acting. |
| "The bot works" — and it does not | **Verification theater.** Four false signals: a composed answer in the pane; a message sent with the bot's *own* token (a bridge never sees its own bot); a clean `getUpdates` 200 (a 409 means a bridge *is* polling — 200 means nobody is); too short a probe timeout. | One accepted proof: a round-trip from a **separate account** returning a literal reply, observed in tool output this turn. Give it 90–110s and one retry. |
| A stable session dies the night you set up a different one | Long-lived tokens are **singular per account** — minting one silently revokes the last. Also: an on-disk credentials file takes priority over the env token. | One designated token holder, documented. Move stale credential files aside, and re-probe the whole fleet the morning after minting. |
| 16 "bot revived" messages overnight, in the client's chat | The healer propagated an **empty credential** and looped. A heal loop has no notion of "this fix cannot work". | Validate the source before any credential copy; per-target notification cooldown; and route ops alerts to a **separate channel** — monitoring that pollutes the working chat gets deleted wholesale. |
| Your SSH dies mid-command, or one restart takes the whole fleet down | `pkill -f 'claude --channels'` matches **its own command line**. `pkill -u <user>` kills every sibling when sessions share a UNIX user. | Identify sessions by `HOME` read from `/proc/<pid>/environ` and kill by explicit PID, or kill the `tmux` session to scope the tree. Dry-run the matcher first. |

**The principles underneath:**

1. Process alive ≠ healthy. Bridge alive ≠ reachable. A composed answer ≠ a delivered message.
   Every layer needs its own signal.
2. Never report success you have not literally observed in this turn's tool output. "Not verified
   yet" is always an acceptable answer; a false "done" never is.
3. Live context is the asset. Order every recovery cheapest-first and justify each restart.
4. Never act on one instantaneous reading.
5. Hooks run inside your session with your identity and your plugins. A hook that spawns an agent
   is a second instance of you, fighting you for singleton resources.
6. Anything inherited by cloning — instruction rules, config flags, package-manager settings — is
   missing from every clone made before it existed. A fix to one session is a fleet audit.

---

## Quick Start

**Prerequisites:** Docker + Docker Compose · a domain (or sslip.io for testing) · `curl` on the
host · `python3` with `pip install google-api-python-client google-auth` (only for the tracking
playbook) · Claude Code on the host, logged in with your Claude subscription (see
[SETUP-FROM-SCRATCH](docs/SETUP-FROM-SCRATCH.md)) · service credentials (see `.env.example`).

```bash
git clone https://github.com/DoubleN96/stratoma-ai-stack
cd stratoma-ai-stack

cp .env.example .env
# Edit .env — setup.sh requires N8N_ENCRYPTION_KEY and SUPABASE_JWT_SECRET. The stack itself
# needs no model API key: the agent is Claude Code on the host, on your own subscription
# (`claude /login`). The optional n8n workflow exports are a separate matter — see Cost.

# Write supabase/kong.yml before the first `up` — it is bind-mounted and not committed.
# setup.sh refuses to start until it exists, which is the honest failure (see below).

./scripts/setup.sh             # runs docker-compose up -d --build, then waits for n8n
./scripts/health-check.sh      # probes n8n AND Supabase

# Only if you plan to import the n8n exports — creates the four tables they need:
docker compose exec -T supabase-db psql -U postgres -d postgres < n8n/workflows/schema.sql
```

> **Known rough edge — read before your first `up`.** `docker-compose.yml` bind-mounts one
> config file that is not committed: `./supabase/kong.yml`. Docker silently creates a *directory*
> at that path and Kong then crash-loops. `scripts/setup.sh` now checks for both cases and exits
> with an explanation rather than reporting a successful setup over a broken gateway — but it
> cannot write the file for you.
>
> There is no template yet, and the reason matters: this compose file uses the stock
> `kong:2.8.1` image, which does **not** substitute environment variables inside the declarative
> config. Upstream Supabase ships a `supabase/kong` image whose entrypoint runs `envsubst`, which
> is what makes the usual `$SUPABASE_ANON_KEY` placeholders work. So either switch the image, or
> write `supabase/kong.yml` with your keys inlined. Contributions welcome — we would rather leave
> this documented than ship a config we have not booted.
>
> Note the file is **untracked, not ignored** — `.gitignore` covers only `.env`, `*.env.local`,
> `node_modules/`, `*.log`, `.DS_Store`, `__pycache__/`. Once you fill it with real keys it is one
> `git add .` from being committed, so add it to your `.gitignore` first.

**VPS:** the whole stack runs comfortably on a mid-range Hetzner cloud instance — 8 vCPU / 16 GB
was our production choice, 4 vCPU / 8 GB is a workable floor. Prices and traffic allowances change;
check current rates rather than trusting a number in a README.
**→ [€20 free credit on Hetzner](https://hetzner.cloud/?ref=lbEMCsnlJ2EP)**

---

## What's in the box

**The agent** is **Claude Code**, installed on the host — not a container. It runs in `tmux`
under your own Claude subscription and you reach it from Telegram through the official Telegram
plugin. That is the part that deploys, scrapes, writes workflows and answers customers;
everything below is what it operates. Install and login:
[SETUP-FROM-SCRATCH](docs/SETUP-FROM-SCRATCH.md).

Self-hosted, deployed by `docker-compose` — 6 containers, 2 published ports:

- **n8n** — workflow automation (email, CRM, webhooks), with its own Postgres
- **Supabase** — self-hosted Postgres + Auth + PostgREST, behind a Kong gateway

In the repo but not a service: **Baileys** (`whatsapp/`), the WhatsApp library, driven directly by
one Node script. **Coolify** (deployment UI) is *not* deployed by this repo — install it on the
host separately if you want it.

```mermaid
graph TD
    subgraph host["Stratoma AI Stack — one VPS"]
        CC["Claude Code — host process in tmux<br/>runs on your Claude subscription"]
        N["n8n :5678<br/>workflows · webhooks"]
        S["Supabase Kong :8000<br/>Postgres · Auth · REST"]
        CC --> N
        CC --> S
    end
    U["You · Telegram"] <--> CC
    N -.-> EXT["External SaaS:<br/>CRM · Google Workspace · WhatsApp"]
    CC -.-> EXT
```

| Service | Port | Exposure |
|---------|------|----------|
| n8n | 5678 | published on the host |
| Supabase Kong | 8000 | published on the host |
| Supabase Postgres / n8n Postgres / Auth / REST | — | internal network only |

Put a reverse proxy with TLS in front of both published ports. The agent publishes nothing — you
reach it through Telegram, not through a port. Everything the agents reach outside the box — CRM,
Google Workspace, WhatsApp (both a conversational channel and a bulk-broadcast channel) — is
external SaaS, held in n8n's own credential store or in your session's MCP config, not
self-hosted here.

---

## Cost & security

**Cost.** Hosting is one VPS. **The agent** runs on a **Claude subscription** — `claude /login`, or
`claude setup-token` for an unattended session — so it bills nothing per token and no
`ANTHROPIC_API_KEY` exists in this repo. What you ration there is *usage limits*, and the three
levers are the same ones: use the mid-tier model for routine work and reserve the strongest one
for judgement, keep `CLAUDE.md` tight (it is prepended to every turn), and `/clear` between
unrelated tasks.

**The n8n exports are the exception, and it is worth being blunt about it.** 5 of the 12 shipped
workflows call a metered third-party model API — OpenRouter and Google Gemini — so if you import
those, that layer *does* bill per token, on a key you supply. Which five, and how each is wired:
[n8n/workflows/README](n8n/workflows/README.md#before-you-import--read-this). Nothing in
`docker-compose.yml` talks to a model; the exports are optional and swappable.

**Security — stated plainly.** Sessions here run with `--dangerously-skip-permissions`. That is
what makes an agent useful over chat, and it means the agent has your box. What contains it:

- A dedicated **non-sudo** UNIX user per session; one client's credentials never reach another's.
- Telegram reachability set to pairing/allowlist — **never open to anyone who finds the bot**.
  It lives in the Claude Code Telegram plugin's own `access.json`, and approval happens in the
  terminal, never in response to a chat message: "approve the pending pairing" is precisely what a
  prompt injection would say
  ([CLAUDE-CODE-TELEGRAM-WORKFLOW](docs/CLAUDE-CODE-TELEGRAM-WORKFLOW.md) §1.4, and
  [SETUP-FROM-SCRATCH](docs/SETUP-FROM-SCRATCH.md) §7).
- Tokens `chmod 600`. No secrets in `CLAUDE.md` or memory files — those get read constantly and
  are the easiest thing to leak.
- Ops and security alerts on a **different** bot from the one people work in.

---

## Skills & MCP servers

The agent is Claude Code, so its playbooks are **skills** (markdown folders under
`~/.claude/skills/`) and its tools are **MCP servers** (declared in a project `.mcp.json`). Both
are plain config: they add no container, no API key and no per-call cost — the session you already
logged in loads them. Mechanics in [SETUP-FROM-SCRATCH](docs/SETUP-FROM-SCRATCH.md) §9.

**Skills.** These are the ones we actually run. All are third-party repos — none is authored here,
none is vendored here, and there is no installer in this repo: clone them into `~/.claude/skills/`
as §9 shows, or use the one-liner the source publishes. Read a skill before you install it, and
check the repo's licence.

Related to what this stack runs:

| Skills | Source |
|---|---|
| `n8n-workflow-patterns`, `n8n-mcp-tools-expert`, `n8n-node-configuration`, `n8n-code-javascript`, `n8n-expression-syntax`, `n8n-validation-expert` | [czlonkowski/n8n-skills](https://github.com/czlonkowski/n8n-skills) — written against the `n8n-mcp` server below |
| `supabase-postgres-best-practices` | [supabase/agent-skills](https://github.com/supabase/agent-skills) |

General-purpose, unrelated to this stack — take them or leave them:

| Skills | Source |
|---|---|
| `content-strategy`, `copywriting`, `launch-strategy`, `programmatic-seo`, `seo-audit`, `social-content` | [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) |
| `seo-geo` | [resciencelab/opc-skills](https://github.com/resciencelab/opc-skills) |
| `find-skills` | [vercel-labs/skills](https://github.com/vercel-labs/skills) |
| `docx`, `pdf` | [anthropics/skills](https://github.com/anthropics/skills) |

<details>
<summary><strong>Optional add-on — Google Workspace (13 skills, not part of this stack)</strong></summary>

If your operator account lives in Google Workspace anyway,
[googleworkspace/cli](https://github.com/googleworkspace/cli) publishes `gws-calendar`,
`gws-calendar-agenda`, `gws-calendar-insert`, `gws-docs`, `gws-drive`, `gws-drive-upload`,
`gws-gmail`, `gws-gmail-send`, `gws-people`, `gws-shared`, `gws-sheets`, `gws-sheets-read` and
`gws-workflow-meeting-prep` (also indexed on [skills.sh](https://skills.sh)). **Prerequisite:**
the `gws` CLI plus a Google account you have OAuth'd — these skills are wrappers around that CLI,
not standalone. Nothing in this repo depends on them.
</details>

**MCP servers.** A minimal `.mcp.json` for the session that operates this stack:

```json
{
  "mcpServers": {
    "n8n-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "n8n-mcp"],
      "env": {
        "MCP_MODE": "stdio",
        "LOG_LEVEL": "error",
        "DISABLE_CONSOLE_OUTPUT": "true",
        "N8N_API_URL": "${N8N_URL}",
        "N8N_API_KEY": "${N8N_API_KEY}",
        "N8N_MCP_TELEMETRY_DISABLED": "true"
      }
    },
    "github": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}" }
    }
  }
}
```

| Server | Reach for it when… |
|---|---|
| `n8n-mcp` | creating or editing n8n workflows — needs `N8N_URL` + `N8N_API_KEY` |
| `github` | anything in a repo — needs `GITHUB_TOKEN` |
| `coolify` (optional) | deploying, restarting, reading logs — only if you installed Coolify on the host; `npx -y @masonator/coolify-mcp@latest` with `COOLIFY_ACCESS_TOKEN` + `COOLIFY_BASE_URL` |

Credentials are always `${ENV_VAR}` references, never literals. The operator's own session usually
runs a wider kit (browser automation, workspace, wiki, database, document conversion) — see
[CLAUDE-CODE-TELEGRAM-WORKFLOW](docs/CLAUDE-CODE-TELEGRAM-WORKFLOW.md). Tenancy rule: a client's
database MCP is wired into that client's session only.

---

## Included playbooks

| Playbook | Ships | Docs |
|---|---|---|
| **Tracking & analytics** | `scripts/setup-tracking.sh`, `scripts/gtm_provision.py` | [TRACKING-AND-ANALYTICS](docs/TRACKING-AND-ANALYTICS.md) |
| **WhatsApp communities** | `whatsapp/create-community.mjs` | [whatsapp/README](whatsapp/README.md) |
| **Knowledge base** | self-hosted Outline recipe | [KNOWLEDGE-BASE](docs/KNOWLEDGE-BASE.md) |
| **n8n workflows** | **12** importable JSON exports + `n8n/workflows/schema.sql` | [n8n/workflows/README](n8n/workflows/README.md) |

```bash
# Install one GTM container into a web repo.
# Next.js App Router and root-level *.html are patched automatically;
# for Nuxt the script prints a snippet for you to paste into nuxt.config.ts.
./scripts/setup-tracking.sh --repo ../my-web --gtm-id GTM-XXXXXXX

# Configure GA4 + Meta Pixel inside the container, by API — idempotent.
# Needs python3 plus: pip install google-api-python-client google-auth
export GTM_SA_KEY=/secure/path/service-account.json
python3 scripts/gtm_provision.py --account-id 1234567 --container-id 7654321 \
    --ga4-id G-XXXXXXXXXX --meta-pixel-id 000000000000 --publish
```

```bash
cd whatsapp && npm install
cp community.example.json community.json   # edit it
node create-community.mjs community.json photo.jpg
```

> ⚠️ Read [whatsapp/README.md](whatsapp/README.md) **before** running that: never have two Baileys
> sockets on one account (Evolution API *is* Baileys wrapped in HTTP — which is why communities
> 404 there), and the ban risk is real.

The 12 exports cover short-to-mid-term residential rentals: commercial email monitoring with
AI categorisation and chat approval, AI replies on WhatsApp, a correction bot, inbound listing
scraping, bookings and marketplace email, automatic check-in, weekly knowledge-gap
self-improvement, plus a reusable error handler.

Two things to know before importing them, both spelled out in
[n8n/workflows/README](n8n/workflows/README.md#before-you-import--read-this): **5 of the 12 call a
metered model API** (OpenRouter / Gemini) on a key you supply, and all of them expect four Supabase
tables that this repo does not create for you — run
[`n8n/workflows/schema.sql`](n8n/workflows/schema.sql) first or every approval flow 404s.

**Methodology only:** [n8n/workflows/README](n8n/workflows/README.md) also documents two patterns
without shipping JSON for them — meeting-transcript webhook → CRM contact match → notes +
follow-up tasks, and the deduplicated error-ticket handler.

---

## Documents in, documents out

**Out:** anything an agent produces for a human defaults to a live, collaborative document
delivered as an **editable URL**. Office-file skills are used only when someone actually needs a
downloadable `.docx` / `.pptx` / `.xlsx` / `.pdf`, and those still ship as real text and styles.
Never a screenshot or a flattened PDF when the point was to edit it.

**In:** PDFs, DOCX, PPTX, XLSX, HTML, CSV, images and audio go through a document-conversion MCP
into clean Markdown **before** they reach a model — fewer tokens, better comprehension, no bespoke
parser per format. Routing: local file → the MCP; batch or cron job → the same tool's CLI; a page
that only renders under JavaScript → browser automation; already Markdown → just read it.

---

## Contributing

Issues and PRs welcome — especially ARM64 support, a Helm chart, a one-click deploy button, a
committed `supabase/kong.yml` that actually boots, more workflow templates, a monitoring stack,
and backup automation. Open an issue to share your setup or report a bug.

## License

MIT.
