#!/usr/bin/env bash
# Install the GTM container snippet into a web repo — the ONLY tracking script that
# belongs in application code. Everything else is configured inside GTM.
# See docs/TRACKING-AND-ANALYTICS.md
set -euo pipefail

REPO=""; GTM_ID=""

usage() {
  cat <<'EOF'
Usage: setup-tracking.sh --repo <path> --gtm-id GTM-XXXXXXX

Detects the framework and injects the Google Tag Manager container:
  Next.js App Router  -> app/layout.tsx via @next/third-parties/google
  Nuxt 3              -> prints the nuxt.config.ts snippet to add
  plain HTML          -> every *.html found at the repo root

Also appends NEXT_PUBLIC_GTM_ID to .env.example. Idempotent: refuses to run
if the repo already references a GTM container.

Docs: docs/TRACKING-AND-ANALYTICS.md
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="${2:?--repo needs a path}"; shift 2 ;;
    --gtm-id)  GTM_ID="${2:?--gtm-id needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$REPO" ] && [ -n "$GTM_ID" ] || { usage >&2; exit 2; }
[ -d "$REPO" ] || { echo "not a directory: $REPO" >&2; exit 1; }
# Container ids are GTM- followed by uppercase alphanumerics. Catch typos here,
# not three weeks later when someone asks why there is no data.
echo "$GTM_ID" | grep -qE '^GTM-[A-Z0-9]+$' || {
  echo "invalid container id: $GTM_ID (expected GTM-XXXXXXX)" >&2; exit 1; }

cd "$REPO"

if grep -rqE 'GTM-[A-Z0-9]+|GoogleTagManager|googletagmanager\.com' \
     --include='*.tsx' --include='*.ts' --include='*.vue' --include='*.html' . 2>/dev/null; then
  echo "This repo already references GTM. Nothing to do." >&2
  echo "Manage tags in the GTM UI or with scripts/gtm_provision.py." >&2
  exit 0
fi

inject_next() {
  local layout="$1"
  # Import goes after the last existing import so it survives 'use client' banners.
  local last_import
  last_import=$(grep -n '^import ' "$layout" | tail -1 | cut -d: -f1)
  [ -n "$last_import" ] || { echo "no imports found in $layout — inject manually" >&2; return 1; }

  # The component goes AFTER </body>, which is where Next's own docs put it.
  awk -v n="$last_import" -v gtm="$GTM_ID" '
    NR == n { print; print "import { GoogleTagManager } from '\''@next/third-parties/google'\''"; next }
    { print }
    /<\/body>/ && !done { print "      <GoogleTagManager gtmId={process.env.NEXT_PUBLIC_GTM_ID ?? \"" gtm "\"} />"; done = 1 }
  ' "$layout" > "$layout.tmp" && mv "$layout.tmp" "$layout"

  grep -q 'GoogleTagManager' "$layout" || { echo "injection failed in $layout" >&2; return 1; }
  echo "  -> $layout"
  echo "  !  run: npm install @next/third-parties"
}

inject_html() {
  # Done in Python, not sed: the GTM snippet contains '||' and '/', which collide
  # with every convenient sed delimiter.
  GTM_ID="$GTM_ID" python3 - "$1" <<'PY'
import os, re, sys

path, gtm = sys.argv[1], os.environ["GTM_ID"]
html = open(path, encoding="utf-8").read()

head = (
    "<!-- Google Tag Manager -->\n"
    "<script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':"
    "new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],"
    "j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;"
    "j.src='https://www.googletagmanager.com/gtm.js?id='+i+dl;"
    "f.parentNode.insertBefore(j,f);})"
    f"(window,document,'script','dataLayer','{gtm}');</script>\n"
)
body = (
    "\n<!-- Google Tag Manager (noscript) -->\n"
    f'<noscript><iframe src="https://www.googletagmanager.com/ns.html?id={gtm}"\n'
    'height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>'
)

if "</head>" not in html:
    sys.exit(f"{path}: no </head> — inject manually")
html = html.replace("</head>", head + "</head>", 1)
html = re.sub(r"(<body[^>]*>)", lambda m: m.group(1) + body, html, count=1)

open(path, "w", encoding="utf-8").write(html)
PY
  echo "  -> $1"
}

echo "Installing container $GTM_ID into $REPO"

if   [ -f app/layout.tsx ];     then inject_next app/layout.tsx
elif [ -f src/app/layout.tsx ]; then inject_next src/app/layout.tsx
elif [ -f nuxt.config.ts ];     then
  echo "  !  Nuxt detected. Add to nuxt.config.ts under app.head.script:" >&2
  echo "     { src: 'https://www.googletagmanager.com/gtm.js?id=${GTM_ID}', async: true }" >&2
else
  found=0
  for f in *.html; do [ -e "$f" ] || continue; inject_html "$f"; found=1; done
  [ "$found" = 1 ] || { echo "no supported entry point found (app/layout.tsx, nuxt.config.ts, *.html)" >&2; exit 1; }
fi

touch .env.example
grep -q '^NEXT_PUBLIC_GTM_ID' .env.example || {
  printf '\n# Google Tag Manager container (public by design — never put tokens in NEXT_PUBLIC_*)\nNEXT_PUBLIC_GTM_ID=%s\n' "$GTM_ID" >> .env.example
  echo "  -> .env.example"
}

cat <<EOF

Done. Next:
  1. set NEXT_PUBLIC_GTM_ID=$GTM_ID in the deployment platform's env vars
  2. deploy, then verify:  curl -s https://YOUR-DOMAIN | grep -o 'GTM-[A-Z0-9]*'
  3. configure tags:       python3 scripts/gtm_provision.py --help
EOF
