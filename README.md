# Stratoma AI Stack

Complete AI operations infrastructure for agencies. One-command deployment of:

- **Paperclip** — AI agent platform (agents work autonomously on tasks)
- **n8n** — Workflow automation (email, CRM, webhooks)
- **Supabase** — Self-hosted database + auth
- **OpenClaw** — WhatsApp & Telegram bot gateway
- **ruflo** — AI agent orchestration (swarms, memory, tools)
- **Coolify** — Deployment & management UI (optional)

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

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Stratoma AI Stack                  │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐   │
│  │Paperclip │  │   n8n    │  │    Supabase    │   │
│  │ :3100    │  │  :5678   │  │    :8000       │   │
│  │          │  │          │  │                │   │
│  │ Agents   │  │Workflows │  │  DB + Auth +   │   │
│  │ Skills   │  │ Webhooks │  │  Storage       │   │
│  │ Issues   │  │  APIs    │  │                │   │
│  └────┬─────┘  └────┬─────┘  └───────┬────────┘   │
│       │              │                │             │
│  ┌────▼──────────────▼────────────────▼────────┐   │
│  │              OpenClaw :18789                 │   │
│  │     WhatsApp + Telegram Gateway              │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  MCPs available to all agents:                      │
│  ruflo | n8n-mcp | github | coolify | supabase      │
└─────────────────────────────────────────────────────┘
```

## Services & Ports

| Service | Port | URL |
|---------|------|-----|
| Paperclip | 3100 | https://paperclip.yourdomain.com |
| n8n | 5678 | https://n8n.yourdomain.com |
| Supabase Kong | 8000 | https://db.yourdomain.com |
| OpenClaw | 18789 | Internal only |
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
