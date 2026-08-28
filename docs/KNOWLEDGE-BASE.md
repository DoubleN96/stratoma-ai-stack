# Knowledge Base — self-hosted Outline, one instance for every client

The wiki layer of the stack. Open source, self-hosted, and — the part that matters here — it
has a real REST API, so your agents can read and write it instead of a human copy-pasting into
a chat.

Replaces paid tools like Slite/Notion for internal documentation, meeting records and SOPs.

---

## Architecture decision: one instance, not one per client

Outline community edition is **not multi-tenant**: one deployment is one workspace, one URL.
The obvious move is one instance per client. Do not do that. You end up with N deployments to
patch, N backups to verify, and N domains to visit.

Instead: **a single instance on your own domain** (`kb.example.com`), where each client is a
**private Collection** plus a **Group**:

| | one instance (this) | one per client |
|---|---|---|
| Domains to maintain | 1 | N |
| Upgrades / backups | 1 | N |
| Agent indexing | one API, sees everything | N tokens, N endpoints |
| Client sees own branding | no | yes |
| Isolation | permissions | infrastructure |

The trade-off is real and you should say it out loud: isolation rests on permissions being set
correctly, and everyone lives under your brand. A client who demands their own domain gets a
separate instance as the **exception**, not the default.

**The rule that keeps isolation honest:** a client Collection is created *private from the
start* and shared with exactly one Group. Never "create it open and restrict it later" — for
the minutes it stays open, every other client can read it.

---

## Deploy

```yaml
# docker-compose.yml
services:
  outline:
    image: outlinewiki/outline:latest
    env_file: .env
    depends_on: [postgres, redis]
    ports: ["3000:3000"]
    restart: unless-stopped

  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: outline
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: outline
    volumes: [postgres-data:/var/lib/postgresql/data]
    restart: unless-stopped

  redis:
    image: redis:7
    restart: unless-stopped

volumes:
  postgres-data:
```

```bash
# .env — generate the secrets, never reuse them across installs
SECRET_KEY=$(openssl rand -hex 32)
UTILS_SECRET=$(openssl rand -hex 32)
URL=https://kb.example.com
DATABASE_URL=postgres://outline:${POSTGRES_PASSWORD}@postgres:5432/outline
REDIS_URL=redis://redis:6379
FILE_STORAGE=local
```

Then point the reverse proxy at port 3000 and the DNS record at the server
(see [TRACKING-AND-ANALYTICS.md](TRACKING-AND-ANALYTICS.md) §1 for the Cloudflare record and the
grey-cloud certificate gotcha).

Two things that bite on first run:

- **`URL` must be the final public URL before first boot.** Outline builds absolute links from
  it; changing it later leaves broken links in existing documents.
- **Run the database migration** (`yarn db:migrate` in the image, or the one-shot `migrate`
  service) before the app serves traffic, or it starts against an empty schema and fails.

Login is SSO — Google or generic OIDC. There is no local password auth, by design.

---

## Onboarding a client, in order

1. **Group** — Settings → Groups → create `client-acme`.
2. **Collection** — new collection `Acme`, visibility **private**, shared with `client-acme`.
3. **Members** — invite the client's people, add them to that group only.
4. **Verify with a second account** that a member of another group cannot see the collection.
   Do this once per client. Assuming it worked is how leaks happen.

---

## The AI layer — why this is worth self-hosting

Outline has no built-in RAG. That gap is the opportunity: your agents already exist, and
Outline hands them a clean API.

```bash
# search across everything the token can see
curl -sS -X POST https://kb.example.com/api/documents.search \
  -H "Authorization: Bearer $OUTLINE_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"query": "onboarding process", "limit": 5}'

# write a document — meeting notes, a generated report, an SOP
curl -sS -X POST https://kb.example.com/api/documents.create \
  -H "Authorization: Bearer $OUTLINE_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Weekly review","text":"## Agenda\n...","collectionId":"...","publish":true}'
```

Two patterns worth building:

- **Ask over Telegram instead of browsing.** The bot searches the KB and answers with a link to
  the source document. People will use a chat they already have open; they will not open a wiki.
- **Write meetings back automatically.** Transcript in, structured summary out, filed in the
  right collection. The documentation stays current because nobody has to remember to write it.

**Token scope matters.** An API token inherits its creator's permissions. A token made by an
admin can read every client's collection — so a client-facing bot must authenticate as a user
who belongs to that client's group only. One token per bot, never the admin's.

---

## The client's own site reads the KB

This is the shape most businesses actually want: **the knowledge lives in one place, and their
public site is just a reader of it.** SOPs, process documentation and tutorials are written once
in the KB by the people who own the process, and the help centre, the onboarding tutorials and
the internal handbook all render from that same source. Same pattern as any product's docs site:
the content is not in the website repo.

What this buys you, and why it is worth the extra moving part:

- Non-technical staff update a process without a deploy, a PR, or asking you.
- One version of the truth. A tutorial cannot silently drift from the SOP it documents, because
  they are the same document.
- The AI gets clean markdown instead of scraped HTML — cheaper, and it stops quoting your cookie
  banner back at people.

### The proxy — the site's backend calls the KB, never the browser

The API token must stay on the server. A token in client-side JavaScript is a token anyone can
read, and it inherits its owner's permissions across every collection.

```ts
// app/api/kb/[slug]/route.ts — Next.js example
export const revalidate = 300  // cache 5 min: the KB is not a database under load

export async function GET(_req: Request, { params }: { params: { slug: string } }) {
  const res = await fetch('https://kb.example.com/api/documents.info', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OUTLINE_API_TOKEN}`,  // server-side only
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ id: params.slug }),
    next: { revalidate },
  })

  if (!res.ok) return new Response('Not found', { status: 404 })

  const { data } = await res.json()
  // Ship markdown, not Outline's internal shape — so a KB change never breaks the site.
  return Response.json({ title: data.title, markdown: data.text, updatedAt: data.updatedAt })
}
```

Two decisions that keep this stable:

- **Publish through a dedicated collection.** The site reads one collection (`Public Docs`),
  never the whole workspace. Then "draft in the KB" and "live on the site" stay different things:
  the internal collection is where work in progress lives, and moving a document into the public
  collection is the act of publishing.
- **Cache, and let it be stale for minutes.** A help centre that refetches per visitor turns your
  wiki into a dependency of your uptime. Five minutes of staleness is invisible to readers.

### Why this is the cheap way to feed the AI

The KB already stores documents as markdown, which is the format an LLM handles best per token.
Retrieval becomes: search → pull the two or three documents that matter → send those. No
scraping, no HTML stripping, no vector database until you genuinely need one.

```ts
// answer from the KB, with a token budget instead of "send everything"
const found = await kb('documents.search', { query: question, limit: 3 })
const context = found.data
  .map((r: any) => `# ${r.document.title}\n${r.document.text.slice(0, 4000)}`)
  .join('\n\n---\n\n')
// context -> the model prompt, with the source URLs kept for citations
```

Answer with the source link attached. "Here is the answer, and here is the SOP it came from" is
what makes people trust it — and when the answer is wrong, they fix the document, which makes the
next answer right. That feedback loop is the whole point of keeping the knowledge in one place.

Start here. Add embeddings only when search stops finding the right document — for a few hundred
SOPs, the built-in search plus a token budget is enough, and it is one less thing to keep in sync.

---

## Backups

Postgres holds everything (documents, permissions, history); the file storage volume holds
attachments. Both, daily, **on different infrastructure than the instance** — a backup on the
same server does not survive the failure it exists for.

```bash
docker compose exec -T postgres pg_dump -U outline outline | gzip > "kb-$(date +%F).sql.gz"
```

Restore-test it at least once. An untested backup is a hypothesis.
