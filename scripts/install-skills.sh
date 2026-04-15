#!/bin/bash
# Install external skills (github + skills.sh) into a Paperclip company.
# Usage: ./scripts/install-skills.sh <company_id> [path/to/catalog.yaml]
#
# Requires: yq, curl, jq, and PAPERCLIP_ADMIN_API_KEY in .env

set -e
source .env

COMPANY_ID="${1:?Company ID required}"
CATALOG="${2:-paperclip/skills/catalog.yaml}"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"

if [ -z "$PAPERCLIP_ADMIN_API_KEY" ]; then
  echo "ERROR: PAPERCLIP_ADMIN_API_KEY not set in .env"
  exit 1
fi

if ! command -v yq &> /dev/null; then
  echo "ERROR: yq required (https://github.com/mikefarah/yq)"
  exit 1
fi

echo "Installing skills from $CATALOG into company $COMPANY_ID..."

count=$(yq '.skills | length' "$CATALOG")
for i in $(seq 0 $((count - 1))); do
  slug=$(yq ".skills[$i].slug" "$CATALOG")
  source=$(yq ".skills[$i].source" "$CATALOG")
  locator=$(yq ".skills[$i].locator" "$CATALOG")

  # Skip local_path skills (Paperclip bundles these itself)
  if [ "$source" = "local_path" ]; then
    echo "  - $slug (local, skipping)"
    continue
  fi

  echo -n "  + $slug ($source)... "
  response=$(curl -sf -X POST "$PAPERCLIP_URL/api/companies/$COMPANY_ID/skills" \
    -H "Authorization: Bearer $PAPERCLIP_ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$slug\",\"source\":\"$source\",\"sourceLocator\":\"$locator\"}" 2>&1) && echo "OK" || echo "FAIL: $response"
done

echo ""
echo "Skills installed. Verify in: $PAPERCLIP_URL/companies/$COMPANY_ID/skills"
