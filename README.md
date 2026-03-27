# Stratoma AI Stack

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

### Tripath (coliving)
- Monitor Email Comercial + categorización IA + aprobación Telegram
- GHL → Paperclip bridge en tiempo real
- Respuestas IA por WhatsApp (AppLevel vía GHL)
- Bot correcciones Telegram
- Extraer llamadas Idealista
- Reservas + email marketplaces
- Check-in automático

### Int Kapital (inmobiliario)
- Fathom → GHL sync (transcripciones de llamadas)
- Workflow de errores para el equipo técnico

### Genérico
- Template error handler (reutilizable para cualquier cliente)
