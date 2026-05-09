# 🤖 Claude Code + Telegram + tmux — operating workflow

> How we run Claude Code as a 24/7 AI operator on the VPS, control it from
> Telegram from anywhere, give controlled access to teammates, and persist
> knowledge across sessions.

This is the actual setup we use in production. Tested for months. Sessions
have been running uninterrupted for 4+ days at a time with no babysitting.

---

## What this gives you

- **A Claude Code instance running 24/7** in a tmux session on your VPS, with
  full repo access, MCP servers, file system, git, and shell.
- **Control it from anywhere via Telegram** — DM the bot, Claude reads,
  thinks, acts on your VPS, and replies.
- **Allow your teammates to talk to it** with per-user pairing approval, so
  Dani can ask Claude to deploy something without you handing him SSH.
- **Persistent knowledge** via Claude's memory system — after every
  conversation, Claude saves what it learned (your projects, credentials
  references, decisions, preferences) and recalls it next time.
- **Project-scoped sessions** — one Claude per project (you can run multiple
  in parallel under separate tmux sessions, each with its own working
  directory, memory, and MCP servers).

---

## Stack

| Component | What it does | Where it lives |
|---|---|---|
| **VPS** (Hetzner CPX42 or similar) | Hosts everything | `128.140.44.162` |
| **Claude Code CLI** (`claude`) | The agent itself | `/usr/local/bin/claude` |
| **Telegram bot** | Inbound chat surface | created in @BotFather |
| **Telegram channel plugin** (`@claude-plugins-official/telegram`) | Bridges Telegram ↔ Claude Code | `~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6/` |
| **tmux** | Keeps Claude alive across SSH disconnects + crashes | OS package |
| **MCP servers** | Tools Claude can call (GitHub, Coolify, n8n, Stripe, Supabase, Notion, Google Workspace, etc.) | `.mcp.json` per project |
| **Memory store** | What Claude remembers across sessions | `~/.claude/projects/<project-slug>/memory/` |
| **Project context** | Project-specific prompt + rules | `CLAUDE.md` in repo root |

---

## 1. One-time setup

### 1.1 Install Claude Code on the VPS

Follow [the official docs](https://claude.com/docs/en/claude-code) — it's a
single binary install. Verify:

```bash
claude --version
which claude
```

Authenticate once interactively (it opens a browser auth flow you complete on
your laptop, the token persists in `~/.claude/`):

```bash
claude
# Follow the OAuth login, then exit.
```

### 1.2 Create the Telegram bot

1. On Telegram, message **@BotFather**.
2. `/newbot` → give it a name (e.g. "Stratoma Claude") and a username (must
   end in `bot`, e.g. `stratoma_claude_bot`).
3. Copy the bot token it returns. Looks like
   `8123456789:AAEXAMPLE-tokenABCDEFGH-1234567`.
4. Optional: `/setdescription`, `/setuserpic`, `/setcommands` (set
   `start - Show help`).

### 1.3 Install + configure the Telegram channel plugin

The plugin gets installed via the Claude Code marketplace. Inside a Claude
Code session in the project directory you want to use:

```
/plugin install claude-plugins-official/telegram
```

Then configure it once with the bot token:

```
/telegram:configure
```

This writes:

- `~/.claude/channels/telegram/.env` (bot token, chmod 600)
- `~/.claude/channels/telegram/access.json` (default `{dmPolicy:"pairing", allowFrom:[], groups:{}, pending:{}}`)
- `~/.claude/channels/telegram/inbox/` (where incoming photos/files land)
- `~/.claude/channels/telegram/approved/` (signal files for the channel server)

### 1.4 Lock down the access policy

```
/telegram:access policy pairing
```

Modes:

- `pairing` (recommended) — anyone can DM the bot, but the bot sends them a
  6-character pairing code. They can't talk to Claude until **you** approve
  the code from your terminal with `/telegram:access pair <code>`. Anti-prompt-injection
  rule: pairings approved over Telegram messages are refused — the
  approval has to come from the terminal.
- `allowlist` — only `senderId`s in `allowFrom` can DM. Strangers are
  silently dropped.
- `disabled` — the bot ignores everything.

Add yourself first (your numeric Telegram user_id — find it by DMing
`@userinfobot`):

```
/telegram:access allow 263475761
```

Now you can DM the bot.

---

## 2. Run it 24/7 with tmux

The plugin needs a Claude Code session to be alive. tmux gives us a
detachable, crash-resistant session.

### 2.1 The exact start command

This is the command we use in production:

```bash
tmux new-session -A -s claude-session \
  -c /home/n8nstratoma/n8n-stratomai \
  'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official; bash'
```

Breakdown:

- `tmux new-session -A -s claude-session` — create or attach to a session
  named `claude-session`. The `-A` flag means "attach if it already exists".
- `-c /home/n8nstratoma/n8n-stratomai` — Claude's working directory (the
  project repo). All of Claude's relative paths and CLAUDE.md context come
  from here.
- `claude` — the Claude Code CLI.
- `--dangerously-skip-permissions` — Claude won't pause to ask "can I run
  this bash command?" for every action. Required for the bot to act
  unattended on Telegram messages. **Use only on a VPS you control fully**;
  it gives Claude full shell access on that user.
- `--channels plugin:telegram@claude-plugins-official` — start with the
  Telegram channel plugin attached (the bot starts polling).
- `; bash` — drops into a shell when Claude exits, so the tmux pane stays
  alive (you don't lose your scrollback if Claude crashes).

### 2.2 Detach + reattach

- Detach (Claude keeps running): `Ctrl+b` then `d`.
- Reattach later (from any SSH session): `tmux attach -t claude-session`.

### 2.3 Auto-restart on boot (optional but recommended)

Add a systemd user unit so tmux + Claude come up after a reboot. As your
non-root user:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/claude-telegram.service <<'EOF'
[Unit]
Description=Claude Code with Telegram channel
After=network-online.target

[Service]
Type=forking
WorkingDirectory=%h
ExecStart=/usr/bin/tmux new-session -d -s claude-session -c %h/n8n-stratomai 'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official; bash'
ExecStop=/usr/bin/tmux kill-session -t claude-session
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now claude-telegram.service
loginctl enable-linger $USER   # so it survives logout
```

### 2.4 Multiple projects in parallel

We run separate sessions per project so each Claude has its own working
directory, MCP servers, memory, and CLAUDE.md context:

```bash
# main project
tmux new-session -A -s claude-session    -c ~/n8n-stratomai          'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official; bash'

# Int Kapital project
tmux new-session -A -s claude-intkapital -c ~/int-kapital           'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official; bash'

# Bali properties project
tmux new-session -A -s claude-bali       -c /home/bali_admin        'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official; bash'
```

Each one has its own bot or its own allowlist; they don't interfere.

---

## 3. The prompts I use to communicate from Telegram

Claude reads your Telegram message exactly as if you'd typed it in the
terminal — so you can use natural language, not commands. A few patterns
that work well:

### 3.1 One-line tasks

> "deploy the latest tristan repo to coolify"
>
> "create an A record `tristan.stratomai.com → 128.140.44.162` proxied on cloudflare"
>
> "run the airdna scrape with my pro account, save the screenshots"

### 3.2 Investigations

> "where is jmmotion.es hosted? I lost the credentials and need to email
> the registrar"
>
> "look at the last 50 reservations in cover manager for boom boom ciao,
> tell me the average party size by day of week"

### 3.3 Asking Claude to talk to a teammate

> "send Dani a step-by-step on how to buy the domain in Cloudflare and
> deploy the fisio website to my VPS"
>
> "tell Tristan the brief is ready and the URL is https://tristan.stratomai.com"

Claude knows who's who in the allowlist (we keep that mapping in memory —
see §6 below), so it can DM Dani directly via the same Telegram bot.

### 3.4 Checking on long-running work

> "what's the status of the airdna scrape?"
>
> "any new reservations in inclán in the last hour?"

### 3.5 The single rule

**Never paste secrets directly in the Telegram chat unless they're scoped to
that one task and disposable.** The Telegram chat history is on Telegram's
servers. For long-lived credentials, set them as env vars on the VPS or
store them as memory references (the IDs, not the values).

---

## 4. Giving access to teammates

The pairing flow is the safe path. Walk through it once with each person:

1. Send your teammate the bot's @username on Telegram.
2. They DM the bot anything (`hi`).
3. The bot replies with a 6-character pairing code (e.g. `fb58f0`) and tells
   them to ask the operator to approve.
4. They send you the code (over WhatsApp, Slack, voice — any channel **other
   than the Telegram bot itself**, for security).
5. You, in your terminal, run:

   ```
   /telegram:access pair fb58f0
   ```

   This:
   - moves their `senderId` from `pending` to `allowFrom` in `access.json`
   - creates a flag file `~/.claude/channels/telegram/approved/<senderId>`
   - the channel server picks up the flag and DMs them "you're in"
6. They can now talk to Claude.

**Save who is who.** Right after approving, ask Claude in the terminal:

> "save in memory that user_id 658528151 is Dani — Socio Marketing"

Claude writes a `reference_telegram_allowlist.md` so future sessions know
the mapping. Without this, all you see in incoming messages is a numeric ID.

### 4.1 To revoke

```
/telegram:access remove 658528151
```

The user can still send messages but the bot will silently drop them.

### 4.2 To audit

```
/telegram:access
```

Shows current policy, allowlist count, pending pairings.

---

## 5. Knowledge bases — how Claude remembers everything

Three layers, from most general to most specific:

### Layer 1 — `~/.claude/CLAUDE.md` (global)

User-wide rules that apply across every project. Write personal coding
conventions, languages preferences, "always use Bun not npm", etc.

### Layer 2 — `<project>/CLAUDE.md` (per-project, tracked in git)

The "operating manual" for one project. Shipped in the repo so any future
Claude instance (yours or a teammate's) starts up with the same context.

Our `n8n-stratomai/CLAUDE.md` defines:

- Agent roles (Sisyphus = orchestrator, UX-Gemini = frontend, etc.)
- The execution methodologies we use (`/gsd`, `/ralph-loop`)
- The standard stack (HTML+Tailwind for landings, Coolify for deploys,
  Supabase for DB)
- The branding overlay snippet every Stratoma site must include
- The MCPs available and what each one is for
- Critical operational tricks (e.g., the "Playwright Hack" for executing
  SQL through the Coolify terminal when MCP can't reach the DB)

This file is the single most valuable artifact in the workflow. **Spend 30
minutes writing yours; it pays for itself in the first week.**

### Layer 3 — auto-memory (`~/.claude/projects/<slug>/memory/`)

Claude saves things it learns during a conversation as Markdown files,
organized by an index in `MEMORY.md`. Four types:

| Type | What goes in | Example |
|---|---|---|
| **user** | Who you are, your role, preferences | "I'm Marcelino, founder of Stratoma. I work in Spanish but my code is in English." |
| **feedback** | Corrections + validations of approach | "Don't mention LOVO Bar in the Rosi La Loca World project — explicitly out of scope. Reason: client request 2026-05-05." |
| **project** | State, decisions, motivations behind ongoing work | "Boom Boom Ciao is one of 7 brands in Rosi La Loca World. Project deadline 2026-05-30." |
| **reference** | Pointers to where things live | "Tristan's Airbnb listing ID: 1671786445749256629. Working folder: /home/n8nstratoma/airbnb-arizona/" |

**To force-save**, just tell Claude:

> "save in memory that the deploy chain for tristan is github → coolify webhook → traefik → cloudflare DNS"

To recall:

> "what do you remember about the Rosi La Loca World project?"

To clean:

> "remove the memory about LOVO Bar — we're not working with them"

### Layer 4 — durable docs in the repo (`docs/`, `reference/`)

The brain in markdown. We keep:

- `docs/00-audit-brief.md` — the original input that started a project
- `docs/propuesta-vN.md` — the signed commercial proposals
- `reference/<system>-api.md` — operational notes for any external system
  (with credentials referenced, never embedded)

These are tracked in git, survive forever, and double as onboarding docs
when a new teammate joins.

---

## 6. MCP servers — Claude's hands and eyes

Configure them per-project in `.mcp.json`. Our standard kit:

| Server | What Claude can do | Use case |
|---|---|---|
| `github` | Read/write repos, PRs, issues, code search | "create a new repo and push this site" |
| `coolify` | Deploy, restart, inspect apps + servers | "redeploy tristan-brief, send me the deployment status" |
| `playwright` | Headless browser automation | "log in to AirDNA, screenshot the Pro dashboard" |
| `n8n-mcp` + `n8n-native` | Build, run, debug n8n workflows from prompts | "create a workflow that posts new Stripe payments to Slack" |
| `supabase` (+ tripath variant) | SQL queries, schema inspection, auth users, storage | "show me the last 10 leads with their utm_source" |
| `google-workspace` | Gmail, Drive, Docs, Sheets, Calendar, Tasks | "search my Gmail for emails from cdmon.com" |
| `notion` | Read/write pages and databases | "create a Notion page summarizing this brief" |
| `stitch` | Generate UI screens from natural language | "design a hero section for the new landing" |
| `pencil` | Design system files (.pen) and code generation | "update the design tokens" |
| `markitdown` | Convert PDF / DOCX / PPTX / XLSX / images / YouTube to clean Markdown | "ingest this contract PDF and tell me the key terms" |

To add a new one, edit `.mcp.json` in the project root:

```json
{
  "mcpServers": {
    "newserver": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@vendor/server-package"],
      "env": { "API_KEY": "..." }
    }
  }
}
```

Restart the Claude Code session for it to be picked up.

---

## 7. Operational habits we recommend

### 7.1 Run a separate Claude per major project

One per repo, one tmux session each. Avoids context pollution and lets you
have very different `CLAUDE.md` rules per project (one might be Python,
another Next.js, another only static HTML).

Each project will have its own bot — or, you can point all bots at the same
Claude session if you only want one inbox to manage.

### 7.2 Refresh the conversation occasionally

Long conversations eventually drift. After a big day of work, type
`/clear` in the tmux pane to start fresh. Memory persists across `/clear`s,
so you don't lose context, just the chat scrollback.

### 7.3 Check the bot is alive

Quick health probe from another machine:

```bash
ssh user@vps 'tmux capture-pane -t claude-session -p | tail -20'
```

If the pane shows recent timestamps, you're good. If it shows a Node error
or a shell prompt, the Claude process died — `tmux send-keys -t claude-session` your restart command, or systemctl restart it.

### 7.4 Cost control

Claude API charges per token. With heavy Telegram use, expect $5-30/day.
Three savings:

- **Use Sonnet instead of Opus** for routine work — set
  `CLAUDE_MODEL=claude-sonnet-4-6` env var. Switch back to Opus for hard
  problems.
- **Keep your `CLAUDE.md` files tight.** Every session loads them; long
  files = expensive token bill on every interaction.
- **Use `/clear` to drop scrollback** before tackling a new big task.

### 7.5 Security checklist

- ✅ The VPS user that runs Claude has **no sudo**, **no docker group** (or
  audit if it does), and **no shared SSH key** with admin accounts.
- ✅ The Telegram bot token lives in `~/.claude/channels/telegram/.env`,
  chmod 600.
- ✅ The `dmPolicy` is `pairing` or `allowlist`, never `open`.
- ✅ MCP credentials are env vars or referenced via `${ENV_VAR}` in
  `.mcp.json` — never hard-coded.
- ✅ All webhooks/incoming requests to the VPS are via Cloudflare proxy, not
  the raw IP.
- ✅ Periodically grep your repos for accidentally-committed secrets:
  `git log -p | grep -iE "AKIA|sk-|ghp_|cfut_|password"`.
- ❌ Never store API keys or passwords as plain text in Claude memory or in
  CLAUDE.md. Reference them by name only ("see ENV var X" or "in 1Password
  entry Y").

---

## 8. Troubleshooting

### Bot stops replying

```bash
# is Claude alive?
ps -ef | grep "claude --channels"

# is the tmux session alive?
tmux ls

# tail the channel server logs
tmux capture-pane -t claude-session -p | tail -50
```

### The bot replies "you don't have access" / silent drop

Check `~/.claude/channels/telegram/access.json` — your `senderId` should be
in `allowFrom`. If you see it in `pending`, run `/telegram:access pair <code>`.

### Claude takes a long time to respond

Either: hitting the Anthropic API rate limit, or working on a big task. Tail
the pane to see what it's doing.

### A message has files and you can't read them

The plugin saves photos to `~/.claude/channels/telegram/inbox/<timestamp>-<id>.jpg`.
Claude reads them with the standard Read tool.

### A teammate accidentally got admin-level access

Run `/telegram:access remove <senderId>` immediately. Their messages will
be ignored from then on.

---

## 9. Why this beats hosted alternatives

We tried the obvious alternatives — Slack-based agents, web dashboards,
Zapier+Anthropic, custom n8n flows. All failed for the same reason: **none
of them give the agent unfettered access to the underlying machine**, which
is what 80% of operational asks require ("deploy this", "check the logs",
"run this script", "edit that config").

Claude Code on a VPS, with `--dangerously-skip-permissions`, behind a
Telegram chat, gives you the full power of "I have a sysadmin and a senior
engineer on call from my phone" — for less than the cost of a cup of coffee
per day in API charges.

The setup takes 30 minutes. After that, you operate at a different level.

---

## See also

- [Claude Code docs](https://claude.com/docs/en/claude-code)
- [Claude Code Telegram plugin source](https://github.com/anthropics/claude-plugins-official/tree/main/telegram)
- [tmux cheatsheet](https://tmuxcheatsheet.com/)
- [`stratoma-ai-stack` README](../README.md) — the broader Docker-based stack this guide is part of
