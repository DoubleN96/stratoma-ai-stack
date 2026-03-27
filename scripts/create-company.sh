#!/bin/bash
# Usage: ./scripts/create-company.sh "Company Name" "project-slug"

set -e
source .env

COMPANY_NAME="${1:-My Company}"
PROJECT_SLUG="${2:-company-develop}"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
ADMIN_API_KEY="${PAPERCLIP_ADMIN_API_KEY}"

if [ -z "$ADMIN_API_KEY" ]; then
  echo "ERROR: Set PAPERCLIP_ADMIN_API_KEY in .env"
  exit 1
fi

echo "Creating company: $COMPANY_NAME"

# 1. Create company
COMPANY=$(curl -sf -X POST "$PAPERCLIP_URL/api/companies" \
  -H "Authorization: Bearer $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$COMPANY_NAME\"}")

COMPANY_ID=$(echo $COMPANY | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.id)")
echo "Company ID: $COMPANY_ID"

# 2. Create project directory
mkdir -p "projects/$PROJECT_SLUG"
cp paperclip/stratoma-default/.mcp.json "projects/$PROJECT_SLUG/.mcp.json"
echo "Project dir: projects/$PROJECT_SLUG"

# 3. Create default agents
AGENTS=(
  '{"name":"CEO","role":"ceo","adapterType":"claude_local"}'
  '{"name":"Engineer","role":"engineer","adapterType":"claude_local"}'
  '{"name":"Sales Manager","role":"general","adapterType":"claude_local"}'
  '{"name":"Marketing","role":"general","adapterType":"claude_local"}'
)

for agent_data in "${AGENTS[@]}"; do
  AGENT_NAME=$(echo $agent_data | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.name)")
  curl -sf -X POST "$PAPERCLIP_URL/api/companies/$COMPANY_ID/agents" \
    -H "Authorization: Bearer $ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$agent_data" > /dev/null
  echo "  Agent created: $AGENT_NAME"
done

# 4. Install n8n skills
N8N_SKILLS=(
  "czlonkowski/n8n-skills/n8n-workflow-patterns"
  "czlonkowski/n8n-skills/n8n-mcp-tools-expert"
  "czlonkowski/n8n-skills/n8n-node-configuration"
  "czlonkowski/n8n-skills/n8n-code-javascript"
)

for skill_path in "${N8N_SKILLS[@]}"; do
  skill_name=$(basename $skill_path)
  curl -sf -X POST "$PAPERCLIP_URL/api/companies/$COMPANY_ID/skills" \
    -H "Authorization: Bearer $ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$skill_name\", \"source\": \"skills_sh\", \"sourceLocator\": \"https://skills.sh/$skill_path\"}" > /dev/null
  echo "  Skill installed: $skill_name"
done

echo ""
echo "Company '$COMPANY_NAME' ready!"
echo "  ID: $COMPANY_ID"
echo "  Paperclip: $PAPERCLIP_URL"
