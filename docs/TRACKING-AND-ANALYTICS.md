# Tracking & Analytics — one installable layer for every site

Cloudflare (DNS) → Google Tag Manager (the only tag layer) → GA4 + Search Console + Meta Pixel/CAPI.

The point of this document: **you set this up once, and every following site is the same five
steps**. No per-project improvisation, no scripts pasted into random components, no "who owns
this pixel again?" three months later.

---

## The rule that makes this maintainable

> **Exactly one script goes in the codebase: the GTM container snippet. Everything else is
> configured inside GTM.**

Analytics, ad pixels, heatmaps, chat widgets — all of it is added and removed in GTM, without a
code change and without a redeploy. A marketer can turn a pixel off at 2am without opening a PR.

Two consequences worth internalising:

- If a tag is hardcoded in the repo, it is a bug. Move it to GTM.
- If GTM is not on a page, that page has zero measurement. Put the snippet in the root layout,
  never in individual pages.

---

## 1. Cloudflare — DNS and the front door

Every domain sits behind Cloudflare. The agent manages records via API token, no dashboard
clicking.

Token scope (create at *My Profile → API Tokens → Create Token*):

| Permission | Scope | Why |
|---|---|---|
| Zone → DNS → Edit | the zone | create/update records |
| Zone → Zone → Read | the zone | resolve zone id |

```bash
# .env
CLOUDFLARE_API_TOKEN=...
CLOUDFLARE_ZONE_ID=...
```

```bash
# create/update an A record pointing a subdomain at the server
curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"app","content":"203.0.113.10","proxied":true}'
```

**Gotcha that costs an afternoon:** if the server issues its own TLS certificates (Traefik or
Caddy with Let's Encrypt), the record must be created **grey-cloud** (`"proxied": false`) until
the certificate is issued, then switched to orange. An orange-cloud record intercepts the
HTTP-01 challenge and the certificate never arrives.

---

## 2. Google Tag Manager — the tag layer

### 2.1 Put the snippet in the site

`scripts/setup-tracking.sh` does this for you (Next.js App Router, Nuxt, or plain HTML):

```bash
./scripts/setup-tracking.sh --repo ../my-web --gtm-id GTM-XXXXXXX
```

It injects the container snippet into the root layout, adds the env placeholders to
`.env.example`, and refuses to run twice on the same repo.

For Next.js App Router it uses the official component, which loads GTM without blocking paint:

```tsx
// app/layout.tsx
import { GoogleTagManager } from '@next/third-parties/google'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
      <GoogleTagManager gtmId={process.env.NEXT_PUBLIC_GTM_ID!} />
    </html>
  )
}
```

### 2.2 Configure the container by API, not by hand

A single Google Cloud **service account** manages GTM and GA4 across *all* projects. One
account, granted per container — not one service account per client.

Setup, once per organisation:

1. Create a GCP project, enable **Tag Manager API v2** (`tagmanager.googleapis.com`) and
   **Google Analytics Admin API** (`analyticsadmin.googleapis.com`).
2. Create a service account, download the JSON key, store it `chmod 600` outside any repo.
3. Per project, grant that service account email:
   - **GTM** → container → Admin → User Management → **Publish**
   - **GA4** → property → Admin → Access Management → **Editor**

Step 3 is unavoidable and manual the first time: the API cannot grant itself access to a
container it is not already a member of. Everything after that is scripted:

```bash
export GTM_SA_KEY=/secure/path/service-account.json

# see what would change, without touching anything
python3 scripts/gtm_provision.py --account-id 1234567 --container-id 7654321 \
  --ga4-id G-XXXXXXXXXX --meta-pixel-id 000000000000 --dry-run

# apply, then publish a new container version
python3 scripts/gtm_provision.py --account-id 1234567 --container-id 7654321 \
  --ga4-id G-XXXXXXXXXX --meta-pixel-id 000000000000 --publish
```

The script is idempotent: it updates tags it already created instead of duplicating them.

---

## 3. GA4 — measure decisions, not vanity

Pageviews tell you nothing you can act on. Define the three or four events that mean money for
this specific site, and mark those as conversions.

Push them from the app into the data layer; GTM turns them into GA4 events:

```ts
// lib/track.ts — the only tracking helper the app needs
type Payload = Record<string, string | number | boolean>

export function track(event: string, payload: Payload = {}) {
  if (typeof window === 'undefined') return
  ;(window as any).dataLayer = (window as any).dataLayer || []
  ;(window as any).dataLayer.push({ event, ...payload })
}

// usage
track('lead_submitted', { form: 'contact', value: 1 })
```

Then in GTM: trigger *Custom Event = `lead_submitted`* → tag *GA4 Event*. In GA4, mark
`lead_submitted` as a conversion (Admin → Events → Mark as key event).

Naming convention, because inconsistency here is permanent: `snake_case`, verb in past tense,
one event per user intention (`lead_submitted`, `checkout_started`, `demo_booked`).

---

## 4. Search Console — the half everyone forgets

GA4 tells you what people did once they arrived. Search Console tells you whether they can find
you at all. Both, or you are guessing.

1. Add the property as a **Domain property** (verifies the whole domain, all subdomains, both
   protocols) — verification is a TXT record, so it goes through the same Cloudflare token:

```bash
curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"type":"TXT","name":"@","content":"google-site-verification=..."}'
```

2. Submit the sitemap (`/sitemap.xml`). If the framework does not generate one, generate one —
   an unsubmitted sitemap is the most common reason new pages sit unindexed for weeks.
3. Link Search Console to GA4 (GA4 Admin → Product links → Search Console). Free, and it puts
   query data next to behaviour data.

---

## 5. Meta Pixel + Conversions API

Browser-only pixel loses a large share of conversions to ad blockers, ITP and iOS. Run both:
the pixel in GTM, and server-side CAPI from your backend, sharing the same `event_id` so Meta
deduplicates them.

Pixel goes in GTM (the provisioning script creates it). CAPI goes in your API route:

```ts
// app/api/lead/route.ts
import { createHash } from 'crypto'

const sha256 = (v: string) => createHash('sha256').update(v.trim().toLowerCase()).digest('hex')

export async function POST(req: Request) {
  const { email, eventId } = await req.json()

  await fetch(
    `https://graph.facebook.com/v21.0/${process.env.META_PIXEL_ID}/events` +
      `?access_token=${process.env.META_CAPI_TOKEN}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        data: [
          {
            event_name: 'Lead',
            event_time: Math.floor(Date.now() / 1000),
            event_id: eventId,            // same id the browser pixel sends → dedup
            action_source: 'website',
            user_data: { em: [sha256(email)] },  // always hashed, never plaintext
          },
        ],
      }),
    },
  )

  return Response.json({ ok: true })
}
```

Non-negotiable: personal data (email, phone) is SHA-256 hashed before it leaves your server.
Sending it in the clear is both a Meta policy violation and a GDPR problem.

Verify in *Events Manager → Test Events* that browser and server events arrive **and
deduplicate** — two separate counts for one lead means your `event_id` is not shared.

---

## 6. Consent

In the EU, tags that write cookies must wait for consent. Use GTM's built-in **Consent Mode**:
set every tag's *Consent Settings* to require `analytics_storage` / `ad_storage`, and have the
banner update the consent state. Do not solve this by conditionally rendering the GTM snippet —
that breaks the whole point of having a tag layer.

---

## Repos and permissions — who touches what

| Surface | Owner | Granted to | Never |
|---|---|---|---|
| Production repo | tech lead | agent opens PRs only | direct pushes to `main` |
| Preview/staging repo | agent | agent deploys freely | pointing at production data |
| Cloudflare token | ops | agent (scoped to one zone) | account-wide tokens |
| GTM container | marketing + ops | service account (Publish) | shared human logins |
| GA4 property | ops | service account (Editor) | Admin for everyone |
| Meta CAPI token | ops | backend env var only | committed to a repo |

Two rules keep this honest:

- **No shared human accounts.** Access is granted per person or per service account, so it can be
  revoked for one without rotating everything for everyone.
- **Secrets live in the deployment platform's env vars**, never in the repo. The repo carries
  `.env.example` with empty keys, nothing else. `NEXT_PUBLIC_*` values are public by definition —
  IDs are fine there, tokens never are.

---

## Verify before you call it done

```bash
# 1. the container is actually on the page
curl -s https://example.com | grep -o 'GTM-[A-Z0-9]*'

# 2. events reach GA4 → GA4 Realtime, trigger the event yourself
# 3. pixel + CAPI deduplicate → Events Manager → Test Events
# 4. Search Console → Sitemaps → "Success", and URL Inspection on one real page
```

If you cannot see your own test event arrive, the tracking is not installed — regardless of what
the code says.
