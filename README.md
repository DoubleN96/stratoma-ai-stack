# Stratoma AI Stack

> ## 👋 Never set up a server or an AI agent before? Start here.
>
> **Full beginner tutorial (zero experience needed) → [docs/SETUP-FROM-SCRATCH.md](docs/SETUP-FROM-SCRATCH.md)**
> Every command, copy-paste, from *buying a server* to *texting your own AI agent that runs it for you*.
>
> **The 10 steps at a glance:**
> 1. Buy a server (Hetzner) + get root access
> 2. Connect to it over SSH
> 3. Install Claude Code (Node + one npm command)
> 4. Log in to your account
> 5. Run it inside `tmux` (survives disconnects)
> 6. Install the official Telegram plugin
> 7. Create your Telegram bot with BotFather
> 8. Control the server from your phone ✅
> 9. Add MCP tools + skills (the agent's hands & playbooks)
> 10. Add Cloudflare DNS + the API tokens that make the agent your "brain"
>
> Already comfortable with Linux/Docker? Skip to **[Quick Start](#quick-start)** below.

---

Complete AI operations infrastructure for agencies. One-command deployment of:

- **Paperclip** — AI agent platform (agents work autonomously on tasks)
- **n8n** — Workflow automation (email, CRM, webhooks)
- **Supabase** — Self-hosted database + auth
- **OpenClaw** — WhatsApp & Telegram bot gateway
- **ruflo** — AI agent orchestration (swarms, memory, tools)
- **Coolify** — Deployment & management UI (optional)

**External SaaS integrations (no self-hosting needed):**
- **GoHighLevel (GHL)** — CRM central + pipeline comercial
- **Gmail / Google Workspace** — Mailing transaccional y comercial
- **WhatsApp vía GHL AppLevel** — Comunicación bidireccional directa con leads/clientes
- **WhatsApp Meta API Oficial** — Comunicaciones masivas (campañas, broadcasts)

---

> ## 🤖 The operating layer: Claude Code via Telegram
>
> Once the stack is up, this is **how we actually run it day-to-day** — a
> single Claude Code instance in a tmux session on the VPS, controlled from
> Telegram by the operator and approved teammates. Knowledge bases, MCP
> servers, deploys, scrapes, and customer comms all happen from your phone.
>
> **→ [docs/CLAUDE-CODE-TELEGRAM-WORKFLOW.md](docs/CLAUDE-CODE-TELEGRAM-WORKFLOW.md)** — full setup, the exact start command, tmux + systemd, pairing flow for teammates, memory layers, MCP catalog, troubleshooting.
>
> **🚀 Brand new? Start here → [docs/SETUP-FROM-SCRATCH.md](docs/SETUP-FROM-SCRATCH.md)** — the complete zero-to-running tutorial: buy a Hetzner server, SSH in, install Claude Code, log in, wire the official Telegram plugin + a BotFather bot, control the box from your phone, then add MCP tools + skills and the Cloudflare/API tokens that make the agent your orchestration brain.

> ## 🪆 Going further: multiple Claudes orchestrated by a "mother"
>
> Once you have more than one client project, you split Claude across UNIX
> users (one per project) and let a **mother Claude** read each child's
> screen, message them via `tmux send-keys`, and aggregate everything into a
> daily journal on a single web panel. Call transcripts
> flow into the same panel.
>
> **→ [docs/MULTI-CLAUDE-MOTHER-AND-CHILDREN.md](docs/MULTI-CLAUDE-MOTHER-AND-CHILDREN.md)** — the full architecture: per-user isolation, cross-tmux orchestration, Supabase journal schema, on-demand refresh button, Fathom webhook + cron pull, panel cron list, how to add a new project.
>
> **→ [docs/FLEET-ORCHESTRATION-AND-MAINTENANCE.md](docs/FLEET-ORCHESTRATION-AND-MAINTENANCE.md)** — keeping the fleet alive and self-updating: the orchestrator user-account pattern (bot↔bot is impossible), allowlist hot-reload + pairing, and a 3-layer cron loop (hourly liveness/revive, 8-hourly end-to-end round-trip, weekly resume-restart for auto-updates). Plus production gotchas (bun PATH, tmux send-keys, pm2 venv).

## Quick Start

### Prerequisites
- Docker + Docker Compose
- A domain (or use sslip.io for testing)
- API keys (see `.env.example`)

### Deploy

```bash
git clone https://github.com/DoubleN96/stratoma-ai-stack
cd stratoma-ai-stack
cp .env.example .env
# Edit .env with your values
./scripts/setup.sh
docker-compose up -d
```

### Post-install

```bash
# Create your first company + agents
./scripts/create-company.sh "My Client" "client-develop"

# Health check
./scripts/health-check.sh
```

## Recommended VPS: Hetzner CPX42

This entire stack runs in production on a **Hetzner CPX42** — best price/performance ratio for AI workloads.

| Spec | Value |
|------|-------|
| vCPU | 8 cores |
| RAM | 16 GB |
| Disk | 320 GB SSD |
| Bandwidth | 20 TB/month |
| Price | €19.49/mo (€0.031/h) |
| Location | EU (Nuremberg / Helsinki / Falkenstein) |

**→ [Get €20 free credit on Hetzner](https://console.hetzner.com/refer?pk_content=lbEMCsnlJ2EP)**

Why Hetzner:
- Cheapest EU cloud with enterprise-grade SSD
- Snapshots + backups built-in via Coolify
- Low latency from Spain/EU (vs AWS/GCP)
- CPX42 handles: Paperclip + n8n + Supabase + OpenClaw + all containers simultaneously

> Minimum recommended: **CPX31** (4 vCPU / 8 GB / 160 GB — ~€11/mo) for lighter setups.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      Stratoma AI Stack                            │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐                │
│  │Paperclip │  │   n8n    │  │    Supabase    │                │
│  │ :3100    │  │  :5678   │  │    :8000       │                │
│  │ Agents   │  │Workflows │  │  DB + Auth     │                │
│  │ Skills   │  │ Webhooks │  │  Storage       │                │
│  └────┬─────┘  └────┬─────┘  └───────┬────────┘                │
│       │              │                │                          │
│  ┌────▼──────────────▼────────────────▼────────┐                │
│  │              OpenClaw :18789                 │                │
│  │   Telegram Gateway (bots personales/equipo)  │                │
│  └──────────────────────────────────────────────┘                │
│                                                                  │
│  MCPs disponibles para todos los agentes:                        │
│  ruflo | n8n-mcp | github | coolify | supabase                   │
└──────────────────────────────────────────────────────────────────┘

          ↕ Integraciones externas (SaaS)

┌──────────────────────────────────────────────────────────────────┐
│                    Comunicaciones & CRM                           │
│                                                                  │
│  ┌─────────────────────┐   ┌──────────────────────────────────┐ │
│  │  GoHighLevel (GHL)  │   │      Gmail / Google Workspace    │ │
│  │                     │   │                                  │ │
│  │  · CRM & Pipeline   │   │  · Email comercial (mailing)     │ │
│  │  · Contactos        │   │  · Email transaccional           │ │
│  │  · Automatizaciones │   │  · Calendarios y Drive           │ │
│  │  · Seguimiento      │   │  · Integración via GWS CLI       │ │
│  └──────────┬──────────┘   └──────────────────────────────────┘ │
│             │                                                    │
│    ┌────────┴──────────────────────────┐                        │
│    │         WhatsApp (dos canales)     │                        │
│    │                                   │                        │
│    │  ┌────────────────────────────┐   │                        │
│    │  │  AppLevel vía GHL          │   │                        │
│    │  │  · Comunicación DIRECTA    │   │                        │
│    │  │  · Bidireccional 1:1       │   │                        │
│    │  │  · Respuestas IA en tiempo │   │                        │
│    │  │    real (n8n + OpenClaw)   │   │                        │
│    │  └────────────────────────────┘   │                        │
│    │                                   │                        │
│    │  ┌────────────────────────────┐   │                        │
│    │  │  Meta API Oficial          │   │                        │
│    │  │  · Comunicaciones MASIVAS  │   │                        │
│    │  │  · Campañas & broadcasts   │   │                        │
│    │  │  · Templates aprobados     │   │                        │
│    │  │  · Alta deliverability     │   │                        │
│    │  └────────────────────────────┘   │                        │
│    └───────────────────────────────────┘                        │
└──────────────────────────────────────────────────────────────────┘
```

## Canales de Comunicación

| Canal | Plataforma | Uso | Dirección |
|-------|-----------|-----|-----------| 
| Email comercial | Gmail / GWS | Comunicación con leads y clientes | Bidireccional |
| Email masivo | Gmail + n8n | Campañas, newsletters | Saliente |
| WhatsApp directo | GHL AppLevel | Conversaciones 1:1 con leads | Bidireccional |
| WhatsApp masivo | Meta API Oficial | Broadcasts, campañas, notificaciones | Saliente |
| Telegram | OpenClaw | Notificaciones internas del equipo | Bidireccional |

### WhatsApp: dos canales, dos propósitos

**AppLevel vía GHL** — para conversaciones directas:
- Conectado al CRM (GHL): historial de conversación por contacto
- Los agentes de Paperclip pueden leer y responder vía n8n
- Ideal para: seguimiento de leads, responder dudas, cerrar ventas

**Meta API Oficial** — para comunicaciones masivas:
- Templates aprobados por Meta (alta tasa de entrega)
- Broadcasts a listas segmentadas desde GHL
- Ideal para: campañas de nurturing, recordatorios, lanzamientos

## Services & Ports (self-hosted)

| Servicio | Puerto | URL |
|---------|------|-----|
| Paperclip | 3100 | https://paperclip.yourdomain.com |
| n8n | 5678 | https://n8n.yourdomain.com |
| Supabase Kong | 8000 | https://db.yourdomain.com |
| OpenClaw | 18789 | Interno |
| Supabase Studio | 3000 | https://studio.yourdomain.com |

## Adding a New Client

```bash
./scripts/create-company.sh "Client Name" "client-slug"
```

This will:
1. Create the company in Paperclip
2. Create default agents (CEO, Engineer, Sales, Marketing)
3. Install standard skills (n8n, ruflo, GWS, etc.)
4. Create the client project directory with MCP config

## MCP Configuration

Every agent gets access to these MCPs by default (via `/paperclip/stratoma-default/.mcp.json`):

- **ruflo** — 60+ AI orchestration tools
- **n8n-mcp** — Create/edit n8n workflows
- **github** — Repository management
- **coolify** — Deploy applications
- **supabase** — Database operations

## n8n Workflows incluidos

Ver [`n8n/workflows/`](n8n/workflows/) — 16 workflows listos para importar:

### Sample vertical: coliving / property management
- Monitor commercial email + AI categorization + Telegram approval
- CRM → AI agent bridge in real time
- AI replies on WhatsApp (via CRM provider)
- Telegram correction bot
- Inbound listings scraping
- Bookings + marketplace email automation
- Automatic check-in

### Sample vertical: real estate investments
- Call transcript provider → CRM sync
- Error workflow for the technical team

### Generic
- Template error handler (reusable for any client)

## Contributing

Issues and PRs are welcome! Some ideas for improvements:

- [ ] ARM64 / Apple Silicon support for local dev
- [ ] Kubernetes / Helm chart version
- [ ] One-click deploy button for Coolify / Railway / Render
- [ ] More workflow templates (real estate, e-commerce, SaaS)
- [ ] OpenClaw config wizard (interactive setup)
- [ ] Monitoring stack (Grafana + Prometheus)
- [ ] Backup automation scripts

Open an issue to share your setup, report bugs, or suggest features.

## License

MIT

## Skills & agents (opinionated defaults)

The stack ships with a reproducible set of Paperclip skills and a default agent roster.

- **`paperclip/skills/catalog.yaml`** — external skills pulled from GitHub + [skills.sh](https://skills.sh). Covers Google Workspace, n8n, marketing/SEO, Next.js, Supabase, Anthropic doc/pdf tooling, and Paperclip meta-skills.
- **`paperclip/agents/roster.yaml`** — 9 agents (CEO, Engineer, Marketing/SEO, Sales Manager, Sales Rep, Lead Qualifier, Follow-up, CRM Updater, Admin). Each agent is pre-wired to a sensible subset of skills for its role.

### Bootstrapping a new company

```bash
cp .env.example .env
# Fill in PAPERCLIP_ADMIN_API_KEY + other vars
./scripts/setup.sh                               # docker-compose up
./scripts/create-company.sh "Client Name" "client-slug"
# Creates company → installs skills from catalog.yaml → seeds 9 agents from roster.yaml
```

Requires `yq`, `jq`, `curl` on the host.

### Customising

- Add new skills: append to `paperclip/skills/catalog.yaml` and re-run `./scripts/install-skills.sh <company_id>`.
- Add/remove agents: edit `paperclip/agents/roster.yaml` and re-run the relevant section of `create-company.sh`.
- Per-company AGENTS.md instructions (credential blocks, runbooks, tone) are uploaded separately via `PUT /api/agents/{id}/instructions-bundle/file`.
