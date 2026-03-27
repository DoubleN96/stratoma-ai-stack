# n8n Workflow Templates

Place exported n8n workflow JSON files here.

## Available Templates

- `email-monitor-telegram.json` — Monitor Gmail + send Telegram approval
- `fathom-ghl-sync.json` — Sync Fathom call recordings to GHL CRM
- `lead-qualifier.json` — Qualify incoming leads via AI

## Import

```bash
# Via n8n API
curl -X POST https://n8n.yourdomain.com/api/v1/workflows \
  -H "X-N8N-API-KEY: your_key" \
  -H "Content-Type: application/json" \
  -d @workflows/email-monitor-telegram.json
```
