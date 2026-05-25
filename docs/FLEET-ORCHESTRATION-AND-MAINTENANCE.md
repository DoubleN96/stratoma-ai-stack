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

## 5. Gotchas learned in production

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
