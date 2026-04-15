#!/bin/bash
# Bootstrap a new Paperclip company with the default agent roster + skill catalog.
# Usage: ./scripts/create-company.sh "Company Name" "project-slug"

set -e
source .env

COMPANY_NAME="${1:-My Company}"
PROJECT_SLUG="${2:-company-develop}"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
ADMIN_API_KEY="${PAPERCLIP_ADMIN_API_KEY}"
ROSTER="${ROSTER:-paperclip/agents/roster.yaml}"
CATALOG="${CATALOG:-paperclip/skills/catalog.yaml}"

if [ -z "$ADMIN_API_KEY" ]; then
  echo "ERROR: PAPERCLIP_ADMIN_API_KEY must be set in .env"
  exit 1
fi

for tool in yq jq curl; do
  command -v "$tool" &> /dev/null || { echo "ERROR: $tool required"; exit 1; }
done

echo "━━━ Creating company: $COMPANY_NAME ━━━"

# 1. Create company
COMPANY=$(curl -sf -X POST "$PAPERCLIP_URL/api/companies" \
  -H "Authorization: Bearer $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$COMPANY_NAME\"}")
COMPANY_ID=$(echo "$COMPANY" | jq -r '.id')
echo "  Company ID: $COMPANY_ID"

# 2. Project directory with shared MCP config
mkdir -p "projects/$PROJECT_SLUG"
cp paperclip/stratoma-default/.mcp.json "projects/$PROJECT_SLUG/.mcp.json"
echo "  Project dir: projects/$PROJECT_SLUG"

# 3. Install skills from catalog (github + skills.sh)
echo ""
echo "━━━ Installing skills from $CATALOG ━━━"
./scripts/install-skills.sh "$COMPANY_ID" "$CATALOG"

# 4. Create agents from roster
echo ""
echo "━━━ Creating agents from $ROSTER ━━━"
agent_count=$(yq '.agents | length' "$ROSTER")
for i in $(seq 0 $((agent_count - 1))); do
  name=$(yq ".agents[$i].name" "$ROSTER")
  role=$(yq ".agents[$i].role" "$ROSTER")
  adapter=$(yq ".agents[$i].adapter_type" "$ROSTER")
  skills_json=$(yq -o=json ".agents[$i].skills" "$ROSTER" | jq -c 'map("company/'$COMPANY_ID'/" + .)')

  echo -n "  + $name ($role)... "
  agent_response=$(curl -sf -X POST "$PAPERCLIP_URL/api/companies/$COMPANY_ID/agents" \
    -H "Authorization: Bearer $ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg n "$name" --arg r "$role" --arg a "$adapter" --argjson s "$skills_json" \
      '{name:$n, role:$r, adapterType:$a, adapterConfig:{paperclipSkillSync:{desiredSkills:$s}}}')")
  agent_id=$(echo "$agent_response" | jq -r '.id // "ERROR"')
  echo "$agent_id"
done

echo ""
echo "━━━ Done ━━━"
echo "  Company: $COMPANY_NAME"
echo "  ID:      $COMPANY_ID"
echo "  URL:     $PAPERCLIP_URL/companies/$COMPANY_ID"
echo ""
echo "Next steps:"
echo "  - Upload AGENTS.md per agent (credentials block, runbooks)"
echo "  - Wire channels (Telegram/WhatsApp) via OpenClaw"
