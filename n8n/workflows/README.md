# n8n Workflows — Stratoma AI Stack

This directory contains 12 exported n8n workflow JSON files, organized by project and category. Client-specific exports (e.g. real meeting-recording integrations) are kept private and documented here as methodology only.

---

## Before you import — read this

**1. These workflows call metered LLM APIs. The agent does not; this layer does.**
The Claude Code agent that operates the stack runs on your Claude subscription and bills nothing
per token. That is a claim about the *agent*, and it does not extend to these exports. **5 of the
12** call a paid third-party model API and will not run without a key you pay for:

| Workflow | Provider | How it is wired |
|---|---|---|
| `Project-A-Monitor-Email-Comercial-Telegram-Approval.json` | OpenRouter · Google Gemini | n8n credentials `openRouterApi`, `googlePalmApi` |
| `Project-A-IA-WhatsApp-Respuesta.json` | OpenRouter · Google Gemini | n8n credentials `openRouterApi`, `googlePalmApi` |
| `Project-A-IA-Auto-Mejora-Conocimiento.json` | Google Gemini | n8n credential `googlePalmApi` (`gemini-flash-latest`) |
| `Project-A-Bot-Correcciones-Telegram.json` | OpenRouter | direct HTTP POST, `Bearer YOUR_OPENROUTER_API_KEY` |
| `Project-A-Monitor-Email-IA-Telegram-Approval.json` | OpenRouter | direct HTTP POST, `Bearer YOUR_OPENROUTER_API_KEY` |

Nothing forces you to keep them on those providers — they are ordinary HTTP and LLM nodes — but
out of the box, importing these is opting into per-token billing.

**2. Create the Supabase tables first.** The exports make 31 PostgREST calls against four tables
that this repo does not create for you: `telegram_pending`, `email_pending_approvals`,
`knowledge_gaps`, `ai_memory`. Import without them and every approval flow 404s on its first
Supabase node. [`schema.sql`](schema.sql) in this directory creates all four — it is reconstructed
from these exports rather than dumped from a live database, so read it before you run it.

**3. Every credential and endpoint is a placeholder.** `YOUR_OPENROUTER_API_KEY`,
`YOUR_SUPABASE_JWT_TOKEN`, `YOUR_TELEGRAM_BOT_TOKEN`, `YOUR_TELEGRAM_CHAT_ID`,
`YOUR_GHL_API_KEY`, `YOUR_N8N_GMAIL_CREDENTIAL_ID*`, `db.yourclient.com`, `n8n.yourdomain.com`.
Search for `YOUR_` and `yourclient` after importing; anything you miss fails at runtime, not at
import. The correction prompt in `Project-A-Bot-Correcciones-Telegram.json` ("Preparar Prompt
Correccion") is likewise a **generic rewrite** — the production prompt was client copy and was
removed, so the shipped one is a working skeleton to replace, not a tuned prompt.

---

## Project A (Coliving)

### Email Automation

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Project-A-Monitor-Email-Comercial-Telegram-Approval.json` | Project A — Monitor Email Comercial + Telegram Approval | Polls Gmail (user@yourclient.com) every minute for unread emails, uses an LLM (Gemini/OpenRouter) to classify as comercial or operativa, saves to Supabase, sends a Telegram notification for human approval, and marks the email as read. |
| `Project-A-Monitor-Email-IA-Telegram-Approval.json` | Project A — Monitor Email + IA + Telegram Approval | Polls Gmail (user@yourclient.com), detects developer vs. regular emails, fetches available rooms from the Project A API, generates an AI reply via OpenRouter (Gemini), saves pending approval to Supabase, and sends a Telegram message with Approve/Reject inline buttons. (Archived — superseded by Comercial version.) |
| `Project-A-Email-Aprobar-Rechazar-Telegram.json` | Project A — Email Aprobar Rechazar Telegram | Webhook-based handler for the Approve/Reject buttons sent in Telegram. On approval: retrieves the pending record from Supabase, sends the Gmail reply, labels it, and updates status. On rejection: marks the record as rejected and notifies Telegram. |

### WhatsApp & Lead Management

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Project-A-IA-WhatsApp-Respuesta.json` | Project A — IA WhatsApp Respuesta | Monitors incoming WhatsApp messages via GHL webhook, fetches conversation history and available rooms, generates an AI response (Gemini/GPT), saves it as a pending approval in Supabase, and sends a Telegram message with the proposed reply for human review. |
| `Project-A-Aprobar-Respuesta-IA.json` | Project A — Aprobar Respuesta IA | Webhook handler (approve/reject) for WhatsApp AI responses. On approval: sends the message via GHL WhatsApp API and notifies Telegram. On rejection: notifies Telegram with a rejection status. |
| `Project-A-Bot-Correcciones-Telegram.json` | Project A — Bot Correcciones Telegram | Telegram bot webhook that lets the operator correct AI-proposed WhatsApp responses. Replies to a proposal with a correction text → AI regenerates the proposal; replies with `/ok` → sends the message to the lead via GHL WhatsApp and removes the pending record from Supabase. |

### Lead Extraction

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Project-A-Extraer-Llamadas-Idealista-Teléfono-Habitación.json` | Project A — Extraer Llamadas Idealista (Teléfono + Habitación) | Polls Gmail for Idealista call-notification emails (via label filter), extracts phone number, call status, room reference, and ad code using regex, deduplicates against Supabase, creates a GHL contact + adds it to a pipeline, and optionally triggers a WhatsApp message. |

### Knowledge & AI Self-Improvement

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Project-A-IA-Auto-Mejora-Conocimiento.json` | Project A — IA Auto-Mejora Conocimiento | Weekly scheduled workflow (every Monday 09:00). Reads unresolved knowledge gaps from Supabase, groups them by topic using a Gemini AI agent, appends structured answers to a Google Doc knowledge base, marks gaps as resolved, and sends a Telegram summary. |

### Email Reply (Room Inquiries)

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Contestar-Mails-Habitaciones-Project-A-v2-high-level.json` | Contestar Mails Habitaciones Project A v2 high level | High-level flow for replying to room-inquiry emails. Fetches available rooms, builds an AI-generated personalized reply via LLM, saves to Supabase for approval, and sends Telegram notification with approve/reject options. |

### Bookings & Check-In

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Extraer-Reservas-y-Mandar-Correo-Marketplaces.json` | Extraer Reservas y Mandar Correo Marketplaces | Extracts new booking records from marketplace sources (Airbnb, Booking, etc.) and sends personalized confirmation or welcome emails to guests. |
| `Enviar-instrucciones-de-Check-In-al-Recibir-Comprobante-de-R.json` | Enviar instrucciones de Check In al Recibir Comprobante de Reserva | Google Sheets trigger (Booking Receipt tab). When a new booking comprobante row is added, extracts check-in date and contact info, then sends WhatsApp and/or email check-in instructions to the tenant. |

---

## Project B (Investment / Real Estate)

> Methodology only. The actual exports are client-specific (they embed real
> meeting-recording links, contact data, and per-tenant GHL location IDs) and
> are kept in a private repo.

### Fathom Meeting Sync

A Fathom webhook fires when a meeting ends. The workflow extracts external
attendees, matches them to GoHighLevel contacts by email, posts a brief summary
plus the recording link as an internal conversation comment, writes detailed
meeting notes onto the contact record, and converts action items into GHL tasks
due in 7 days. Multiple variants exist — one per sub-brand — each with its own
GHL location ID and calendar configuration.

### Error Handling

An error-trigger workflow watches the project's other n8n workflows. On failure
it looks up whether an open ticket already exists for that workflow (dedup key:
the workflow name); if none exists it opens a new high-priority one; if one does,
it appends the new error-execution details as a comment. The tracker is whatever
you already use — the reusable part is the dedup key, not the product.

---

## Generic / Shared

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Workflow-de-errores.json` | Workflow de errores | Generic error-handler for all Project A n8n workflows. On error trigger: sends an email to developer@yourclient.com. Two nodes, nothing else. (The original export also opened and deduplicated a ticket in an external task manager that is no longer part of this stack; those nodes were removed rather than left pointing at a service you do not run — the dedup pattern itself is written up under Project B → Error Handling.) |

---

## Notes

- All workflows use credentials stored in the n8n instance (not included in these exports for security).
- Supabase backend: `https://db.yourclient.com` (Project A) — a placeholder host; point it at your own.
- Telegram notifications go to chat ID `YOUR_TELEGRAM_CHAT_ID`.
- AI models used: Google Gemini Flash, OpenRouter (fallback) — both metered, see
  [Before you import](#before-you-import--read-this).
- Tables required: see [`schema.sql`](schema.sql).
