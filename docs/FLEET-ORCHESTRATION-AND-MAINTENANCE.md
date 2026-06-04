# Fleet Orchestration & Self-Maintenance

> How a fleet of Claude Code sessions (one "mother" orchestrator + several
> project "children") stays alive, reachable, and self-updating — controlled
> end-to-end from Telegram. This complements
> [MULTI-CLAUDE-MOTHER-AND-CHILDREN.md](./MULTI-CLAUDE-MOTHER-AND-CHILDREN.md)
> and [CLAUDE-CODE-TELEGRAM-WORKFLOW.md](./CLAUDE-CODE-TELEGRAM-WORKFLOW.md).

All names, IPs, IDs and tokens below are placeholders. Put real values only in
a private repo or an untracked secrets file.

---

## 1. The fleet

Each project runs its own Claude Code session as its own UNIX user, isolated by
permissions, each connected to its **own** Telegram bot via the
`plugin:telegram@claude-plugins-official` channel.

| Session | UNIX user | tmux | Telegram bot | Notes |
|---------|-----------|------|--------------|-------|
| mother (orchestrator) | `op` | `claude-session` | `@MotherBot` | coordinates everything; **not** auto-restarted (no backstop) |
| child-a | `proj_a` | `claude` | `@ProjectABot` | |
| child-b | `proj_b` | `claude-b` | `@ProjectBBot` | home is non-standard → see cred path override |
| child-c | `proj_c` | `child_c` | `@ProjectCBot` | needs `bun` on PATH for its Telegram plugin |
| child-remote | `op_remote` | `claude-remote` | `@RemoteBot` | lives on a second VPS; `dmPolicy: pairing` |

Isolation is by UNIX permissions; the operator holds a single shared sudo
password kept **only** in an untracked `secrets.env` (chmod 600), never in git.

---

## 2. The orchestrator identity (bot ↔ bot is impossible)

A Telegram **bot cannot send messages to another bot.** To let the mother test
or talk to each child's channel autonomously, the orchestrator uses a Telegram
**user account** (not a bot), driven via [Telethon](https://github.com/LonamiWebs/Telethon):

```python
from telethon import TelegramClient
from telethon.sessions import StringSession
client = TelegramClient(StringSession(SESSION_STRING), API_ID, API_HASH)
await client.send_message("ProjectABot", "ping")   # a USER messaging a bot — allowed
```

- One-time login (`api_id`/`api_hash` from my.telegram.org + an OTP) produces a
  portable **string session**, stored 0600 outside any repo.
- The orchestrator's numeric user-id must be added to each child's
  `~/.claude/channels/telegram/access.json` `allowFrom` list. **This list is
  hot-reloaded** — no session restart required.
- For `dmPolicy: "pairing"` channels, the first DM triggers a pairing code; the
  operator approves it once (`/telegram:access pair <code>`).

### 2a. Obtaining `api_id` / `api_hash` and producing the string session

The Telethon client above needs three secrets: `api_id`, `api_hash` (identify the
*application*), and a **string session** (identifies the logged-in *account*).
One-time setup:

1. **Create the Telegram application** at <https://my.telegram.org> →
   *API development tools* (full reference:
   <https://core.telegram.org/api/obtaining_api_id>):
   - Log in with the **phone number of the user account** that will be the
     orchestrator (a real account, not a bot).
   - Fill *App title* and *Short name* (anything, e.g. `fleet-orchestrator`).
     Platform: *Other*. Leave URL blank.
   - Submit → you get **`api_id`** (a number) and **`api_hash`** (a 32-char hex
     string). One app per account is enough; reuse it everywhere.
2. **Generate the string session** once, interactively, then store it (never the
   raw `api_hash`/OTP) for unattended use:

   ```python
   # login_once.py  — run interactively ONE time
   from telethon.sync import TelegramClient
   from telethon.sessions import StringSession
   api_id, api_hash = 123456, "your32charhexhash"
   with TelegramClient(StringSession(), api_id, api_hash) as c:
       # prompts for phone, the OTP Telegram sends, and 2FA password if enabled
       print(c.session.save())   # ← copy this long string
   ```

   Run it, enter the phone + OTP (+ 2FA if set). It prints the portable session
   string.
3. **Store secrets `0600` outside any repo** (e.g. `~/.config/tg-userbot/.env`):

   ```bash
   TG_API_ID=123456
   TG_API_HASH=your32charhexhash
   TG_SESSION=1Bv...long-string-session...
   ```

   The unattended monitor then loads these and never needs an OTP again:
   `TelegramClient(StringSession(TG_SESSION), TG_API_ID, TG_API_HASH)`.

> Gotchas: the OTP arrives **inside Telegram** (Saved Messages / the login
> prompt), not by SMS, when you're already logged in elsewhere. If the account
> has 2FA, Telethon also asks for that password. A string session is bearer
> access to the whole account — treat it like a root credential; rotate by
> running `client.log_out()` and regenerating.

> Security: children correctly treat an unknown sender that asks them to
> "identify yourself" as a possible prompt injection and refuse. To make a child
> *respond* to the orchestrator, declare the orchestrator's user-id as a trusted
> internal identity in that session's `CLAUDE.md` (loaded on next start).

---

## 3. Three layers of self-maintenance

### Layer 1 — hourly liveness + auto-revive (cron)
A script checks each session every hour: tmux exists? a `claude` process is
running? does the last screen show a fatal auth state
(`Please run /login`, `OAuth error`)? On failure it backs up the user's
credentials, copies the mother's credentials over (all sessions share one
Claude subscription), relaunches, and alerts Telegram. The mother is **omitted**
(if it is down nothing else runs anyway).

```cron
0 * * * * /path/session_health_check.py >> /var/log/session-health.log 2>&1
```

> Recurring `401 / Please run /login` on a child is usually **OAuth token
> rotation** between sessions sharing one account: when one refreshes, the
> others' refresh token can be invalidated. Copying the mother's credentials is
> the pragmatic mitigation; the durable fix is independent auth per session.

### Layer 2 — 8-hourly end-to-end round-trip (cron)
The mother pings every child's bot from the orchestrator **user account** and
checks for a reply. A reply proves process + auth + channel all work — a real
"does it actually work" test that liveness checks miss. Report-only (revival is
owned by Layer 1, to avoid double-revive races).

```cron
0 */8 * * * /path/health_check.sh >> /var/log/health-check.log 2>&1
```

### Layer 3 — weekly resume-restart (cron)
Once a week, each **child** is closed and reopened with `--continue` so the
conversation is preserved and Claude Code auto-updates on launch:

```bash
tmux kill-session -t "$SESS"
# child-c needs bun on PATH for its Telegram plugin to load:
export PATH="$HOME/.bun/bin:$PATH"
tmux new-session -d -s "$SESS" -c "$WORKDIR" \
  'claude --continue --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions'
```

```cron
20 5 * * 0 /path/weekly_restart.sh >> /var/log/weekly-restart.log 2>&1
```

Scheduled off the top of the hour so it never collides with Layer 1.

---

## 4. Restarting the orchestrator itself

**Restart the mother manually.** Unlike the children (Layers 1–3), the mother
has no automated restart, and self-restart is intentionally avoided: a session
cannot reliably tear down and relaunch itself mid-turn, so an in-session
"detached helper" approach proved fragile in practice (race conditions between
the tmux kill, the stale process, and the relaunch led to failed reopens).

The dependable path is to relaunch it yourself from a separate shell (SSH /
terminal), resuming the conversation so no context is lost:

```bash
cd /path/to/orchestrator-workdir
claude --continue --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions
```

If you want this automated, drive it from **outside** the session — e.g. a host
cron job or a small supervisor process that owns the tmux session — never from
inside the mother itself.

---

## 5. The orchestrator user account as an action layer

Because it is a real Telegram *user* (not a bot), the orchestrator account can do
things the Bot API forbids — which is what lets the fleet spin up a new project's
Telegram presence end to end, autonomously:

- **Create a bot** by scripting a conversation with `@BotFather`
  (`/newbot` → name → username → capture the returned token). The fleet can
  provision a brand-new project bot with no human in BotFather.
- **Create a broadcast channel or group**, set its title, and **post** to it
  (e.g. publish a project's output feed) via the same account.
- **Resolve a phone number to a user-id**, invite a specific person, or **DM a
  user directly** (onboarding message, a login link). User→user is allowed; a bot
  cannot initiate a chat with a stranger.
- **Poll each child bot for replies** — the round-trip test in §3 Layer 2.

All of this runs through one Telethon string-session, stored 0600 outside git.
Treat that credential as high-value: it can act as the human.

---

## 6. Onboarding a new project session

To add a new isolated session + bot to the fleet (same host, separate `$HOME`):

1. **Bot** — create it via the orchestrator + BotFather (§5).
2. **Plugin** — copy a working session's `.claude/plugins` tree into the new
   `$HOME`, rewriting the old home path → the new one in *every* plugin file
   (install records embed absolute paths).
3. **Channel config** — `~/.claude/channels/telegram/.env` = the new bot token;
   `access.json` = `dmPolicy: allowlist` + the operator and orchestrator user-ids.
4. **Enable the plugin (critical, easy to miss)** — the session's `settings.json`
   MUST contain `"enabledPlugins": { "telegram@claude-plugins-official": true }`.
   Without it the session prints *"Listening for channel messages"* but never
   spawns the bridge subprocess, so the bot stays silent. Pin the model here too
   (`"model": "<model-id>"`).
5. **Auth = one shared subscription, no rotation war** — instead of copying the
   mother's rotating OAuth credentials (the cause of the §3 `401` problem), mint a
   long-lived token once (`claude setup-token`) and write it into the session's
   `.credentials.json` as the `accessToken` with a far-future `expiresAt`. Every
   session uses the same subscription, but nothing refreshes/rotates, so no
   session can invalidate another. This also gives full *subscription* mode — the
   Telegram bridge only spawns under a real login, not a bare API-key env var.
6. **Launch** in tmux with `bun` on PATH; accept the trust + bypass-permissions
   prompts once (or pre-seed them in `.claude.json`).
7. **Verify** the bridge process exists *and* the bot returns a real reply, then
   add the bot to the §3 health-check lists.

---

## 7. Gotchas learned in production

- **`bun` not on PATH** → a plugin launched via `bun run` (e.g. the Telegram
  plugin) silently fails to connect. Symptom: the session receives nothing / has
  no reply tool. Fix: export `~/.bun/bin` onto PATH before launching `claude`.
- **`tmux send-keys` submission**: send the text, capture-pane to confirm it
  landed, then send `Enter` as a *separate* call. Do not use `-l` (triggers
  bracketed paste → Enter becomes a newline, not submit).
- **pm2 + Python services**: point pm2 at a launcher that uses the project's
  `.venv`; running a Flask app with bare `python3` (no venv) crash-loops on
  `ModuleNotFoundError`.
- **Non-interactive `su - user -c`** does not source `.bashrc`, so PATH-derived
  tools (bun, uv) are missing — a frequent false-negative when probing a child's
  MCP servers from outside its live session.
