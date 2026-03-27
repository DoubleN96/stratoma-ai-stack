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
required_vars=(ANTHROPIC_API_KEY N8N_ENCRYPTION_KEY SUPABASE_JWT_SECRET)
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

# Generate JWT keys for Supabase if not set
if [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "Generating Supabase JWT keys..."
  JWT_SECRET="$SUPABASE_JWT_SECRET"
  # These would be generated via jwt.io or a script
  echo "WARN: Please generate SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY manually"
  echo "      Use: https://supabase.com/docs/guides/self-hosting#api-keys"
fi

echo "Starting services..."
docker-compose up -d --build

echo "Waiting for Paperclip to be healthy..."
until curl -sf http://localhost:3100/health > /dev/null 2>&1; do
  echo -n "."
  sleep 3
done
echo " OK"

echo "Waiting for n8n..."
until curl -sf http://localhost:5678/healthz > /dev/null 2>&1; do
  echo -n "."
  sleep 3
done
echo " OK"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setup complete!"
echo ""
echo "  Paperclip: http://localhost:3100"
echo "  n8n:       http://localhost:5678"
echo "  Supabase:  http://localhost:8000"
echo ""
echo "  Next: ./scripts/create-company.sh \"Client Name\" \"client-slug\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
