#!/bin/bash
source .env 2>/dev/null || true

PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
N8N_URL="${N8N_URL:-http://localhost:5678}"
SUPABASE_URL_LOCAL="${SUPABASE_URL:-http://localhost:8000}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Stratoma Stack Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check() {
  local name=$1
  local url=$2
  if curl -sf "$url" > /dev/null 2>&1; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name ($url)"
  fi
}

check "Paperclip"  "$PAPERCLIP_URL/health"
check "n8n"        "$N8N_URL/healthz"
check "Supabase"   "$SUPABASE_URL_LOCAL/rest/v1/"

echo ""
docker-compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true
