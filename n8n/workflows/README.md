# n8n Workflows — Stratoma AI Stack

This directory contains 16 exported n8n workflow JSON files, organized by project and category.

---

## Tripath Coliving

### Email Automation

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Tripath-Monitor-Email-Comercial-Telegram-Approval.json` | Tripath — Monitor Email Comercial + Telegram Approval | Polls Gmail (user@yourclient.com) every minute for unread emails, uses an LLM (Gemini/OpenRouter) to classify as comercial or operativa, saves to Supabase, sends a Telegram notification for human approval, creates a Paperclip task, and marks the email as read. |
| `Tripath-Monitor-Email-IA-Telegram-Approval.json` | Tripath — Monitor Email + IA + Telegram Approval | Polls Gmail (user@yourclient.com), detects developer vs. regular emails, fetches available rooms from the Tripath API, generates an AI reply via OpenRouter (Gemini), saves pending approval to Supabase, and sends a Telegram message with Approve/Reject inline buttons. (Archived — superseded by Comercial version.) |
| `Tripath-Email-Aprobar-Rechazar-Telegram.json` | Tripath — Email Aprobar Rechazar Telegram | Webhook-based handler for the Approve/Reject buttons sent in Telegram. On approval: retrieves the pending record from Supabase, sends the Gmail reply, labels it, and updates status. On rejection: marks the record as rejected and notifies Telegram. |

### WhatsApp & Lead Management

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Tripath-IA-WhatsApp-Respuesta.json` | Tripath — IA WhatsApp Respuesta | Monitors incoming WhatsApp messages via GHL webhook, fetches conversation history and available rooms, generates an AI response (Gemini/GPT), saves it as a pending approval in Supabase, and sends a Telegram message with the proposed reply for human review. |
| `Tripath-Aprobar-Respuesta-IA.json` | Tripath — Aprobar Respuesta IA | Webhook handler (approve/reject) for WhatsApp AI responses. On approval: sends the message via GHL WhatsApp API and notifies Telegram. On rejection: notifies Telegram with a rejection status. |
| `Tripath-Bot-Correcciones-Telegram.json` | Tripath — Bot Correcciones Telegram | Telegram bot webhook that lets the operator correct AI-proposed WhatsApp responses. Replies to a proposal with a correction text → AI regenerates the proposal; replies with `/ok` → sends the message to the lead via GHL WhatsApp and removes the pending record from Supabase. |
| `Tripath-GHL-Paperclip-Bridge-Tiempo-Real.json` | Tripath — GHL → Paperclip Bridge (Tiempo Real) | Real-time bridge from GoHighLevel to Paperclip. On an inbound lead message: creates a new Paperclip issue assigned to the Lead Qualifier agent; on a subsequent message for an existing lead: adds a comment to the existing issue. Deduplication via contactId. |

### Lead Extraction

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Tripath-Extraer-Llamadas-Idealista-Teléfono-Habitación.json` | Tripath — Extraer Llamadas Idealista (Teléfono + Habitación) | Polls Gmail for Idealista call-notification emails (via label filter), extracts phone number, call status, room reference, and ad code using regex, deduplicates against Supabase, creates a GHL contact + adds it to a pipeline, and optionally triggers a WhatsApp message. |

### Knowledge & AI Self-Improvement

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Tripath-IA-Auto-Mejora-Conocimiento.json` | Tripath — IA Auto-Mejora Conocimiento | Weekly scheduled workflow (every Monday 09:00). Reads unresolved knowledge gaps from Supabase, groups them by topic using a Gemini AI agent, appends structured answers to a Google Doc knowledge base, marks gaps as resolved, and sends a Telegram summary. |

### Email Reply (Room Inquiries)

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Contestar-Mails-Habitaciones-Tripath-v2-high-level.json` | Contestar Mails Habitaciones Tripath v2 high level | High-level flow for replying to room-inquiry emails. Fetches available rooms, builds an AI-generated personalized reply via LLM, saves to Supabase for approval, and sends Telegram notification with approve/reject options. |

### Bookings & Check-In

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Extraer-Reservas-y-Mandar-Correo-Marketplaces.json` | Extraer Reservas y Mandar Correo Marketplaces | Extracts new booking records from marketplace sources (Airbnb, Booking, etc.) and sends personalized confirmation or welcome emails to guests. |
| `Enviar-instrucciones-de-Check-In-al-Recibir-Comprobante-de-R.json` | Enviar instrucciones de Check In al Recibir Comprobante de Reserva | Google Sheets trigger (Booking Receipt tab). When a new booking comprobante row is added, extracts check-in date and contact info, then sends WhatsApp and/or email check-in instructions to the tenant. |

---

## Int Kapital

### Fathom Meeting Sync

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Neverland-Lombok-Sync-Fathom-meeting-summaries-and-action-it.json` | Neverland Lombok - Sync Fathom meeting summaries and action items with GoHighLevel contacts | Fathom webhook triggered when a meeting ends. Extracts external attendees, matches them to GHL contacts by email, adds a brief summary + recording link as an internal conversation comment, writes detailed meeting notes to the contact record, and converts action items into GHL tasks due in 7 days. |
| `Casa-Caoba-Sync-Fathom-meeting-summaries-and-action-items-wi.json` | Casa Caoba - Sync Fathom meeting summaries and action items with GoHighLevel contacts | Same flow as Neverland Lombok but configured for the Casa Caoba project with its own GHL location ID and calendar setup. |

### Error Handling

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Int-Kapital-Workflow-de-errores-Pepe.json` | Int Kapital - Workflow de errores (Pepe) | Error-handler workflow for Int Kapital n8n workflows. On error trigger: searches Paperclip (Int Kapital company) for an existing open task for the same workflow. If none exists, creates a new high-priority task assigned to Pepe. If one exists, adds a comment with the new error execution details (deduplication). |

---

## Generic / Shared

| File | Workflow Name | Description |
|------|--------------|-------------|
| `Workflow-de-errores.json` | Workflow de errores | Generic error-handler for all Tripath n8n workflows. On error trigger: sends an email to developer@yourclient.com, and simultaneously checks Paperclip for an existing open error task. Creates a new task if none exists, or adds a comment to the existing one (deduplication via workflow name matching). |

---

## Notes

- All workflows use credentials stored in the n8n instance (not included in these exports for security).
- Supabase backend: `https://db.yourclient.com` (Tripath) and `https://paperclip.yourdomain.com` (Paperclip task manager).
- Telegram notifications go to chat ID `YOUR_TELEGRAM_CHAT_ID`.
- AI models used: Google Gemini Flash, OpenRouter (fallback).
