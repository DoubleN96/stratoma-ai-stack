#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Stratoma AI Stack — Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Load env
if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example to .env first."
  exit 1
fi
source .env

# Check required vars
required_vars=(N8N_ENCRYPTION_KEY SUPABASE_JWT_SECRET)
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

if [ -z "$SUPABASE_ANON_KEY" ] || [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
  echo "ERROR: SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are not set in .env."
  echo "       Generate them from SUPABASE_JWT_SECRET:"
  echo "       https://supabase.com/docs/guides/self-hosting#api-keys"
  exit 1
fi

# Kong is bind-mounted at ./supabase/kong.yml. If the file is missing, Docker
# silently creates a DIRECTORY there and Kong crash-loops with no useful error —
# so refuse to start rather than hand back a half-booted stack. There is no
# committed template; see the "Known rough edge" section of the README.
if [ -d supabase/kong.yml ]; then
  echo "ERROR: supabase/kong.yml is a DIRECTORY. Docker created it on an earlier run."
  echo "       Remove it (rmdir supabase/kong.yml) and write the file. See README."
  exit 1
fi
if [ ! -f supabase/kong.yml ]; then
  echo "ERROR: supabase/kong.yml is missing. Supabase's REST and Auth endpoints are"
  echo "       reached through Kong, and Kong will not start without it."
  echo "       This repo ships no template on purpose — see the README section"
  echo "       'Known rough edge' for what to put in it and why."
  echo ""
  echo "       To bring up n8n only in the meantime:"
  echo "         docker-compose up -d --build n8n"
  exit 1
fi

echo "Starting services..."
docker-compose up -d --build

echo "Waiting for n8n..."
for _ in $(seq 1 60); do
  if curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
    echo " OK"
    break
  fi
  echo -n "."
  sleep 3
done
if ! curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
  echo ""
  echo "ERROR: n8n did not become healthy in 3 minutes. Check: docker-compose logs n8n"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Containers started. n8n answered its health check."
echo ""
echo "  n8n:       http://localhost:5678   (verified above)"
echo "  Supabase:  http://localhost:8000   (NOT verified by this script)"
echo ""
echo "  Next: ./scripts/health-check.sh    <- this one probes Supabase too"
echo "        then install Claude Code on the host — docs/SETUP-FROM-SCRATCH.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
