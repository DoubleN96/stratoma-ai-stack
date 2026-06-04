# From Zero to a Telegram-Controlled AI Server — Step by Step

> A complete, copy-paste walkthrough: buy a fresh cloud server, install Claude
> Code on it, log in, control it from your phone over Telegram, then give it
> MCP tools + skills and the API tokens it needs to act as the "brain" that
> drives all your other tools.
>
> **All values below are placeholders.** Put real IPs, tokens and IDs only in an
> untracked secrets file or a private repo — never in git. See
> [FLEET-ORCHESTRATION-AND-MAINTENANCE.md](./FLEET-ORCHESTRATION-AND-MAINTENANCE.md)
> for running many of these sessions as a fleet.

---

## 0. What you'll end up with

A Linux server you never have to open a terminal for again: you talk to it from
Telegram, it runs commands, edits code, deploys apps, and calls external APIs
(GitHub, hosting, LLMs, Google, etc.) on your behalf.

Roughly 20–30 minutes from nothing to "I texted my server and it replied."

---

## 1. Buy the server (Hetzner)

1. Create an account at **<https://console.hetzner.com/refer?pk_content=lbEMCsnlJ2EP>** (this referral link gives you **€20 free credit** to get started).
2. **New Project → Add Server.**
   - Location: closest to you.
   - Image: **Ubuntu 24.04**.
   - Type: a shared-vCPU instance is fine to start (e.g. 2 vCPU / 4 GB). You can
     resize later.
   - **Authentication:** add your SSH public key now if you have one (recommended).
     If you don't, Hetzner emails you a **root password**.
3. Create it and copy the server's **public IP** (e.g. `203.0.113.10`).

> No SSH key? Either let Hetzner set a root password, or use the **Rescue** tab /
> the web **Console** in the Hetzner panel to log in and set one with `passwd`.

---

## 2. Connect to it

From your computer's terminal:

```bash
ssh root@203.0.113.10        # use your server's real IP
```

Accept the host fingerprint, enter the password (or it logs in via your key).
You're now on the server.

(Optional but recommended) create a non-root user and keep one session per
project under its own user — see the fleet doc.

---

## 3. Install Claude Code

Install Node.js (v18+), then Claude Code:

```bash
# Node via nvm (clean, no sudo headaches)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
. ~/.nvm/nvm.sh
nvm install --lts

# Claude Code
npm install -g @anthropic-ai/claude-code

claude --version    # confirm it's installed
```

> If `npm -g` hits permission errors, set a user prefix:
> `npm config set prefix ~/.npm-global` and add `~/.npm-global/bin` to your PATH.

---

## 4. Log in

Run `claude` once and authenticate:

```bash
claude
```

- **Claude subscription (recommended):** choose "Claude account with
  subscription", open the printed URL in your browser, approve, paste the code
  back. For an unattended/long-lived login use `claude setup-token` (a 1-year
  token you can export as `CLAUDE_CODE_OAUTH_TOKEN`).
- Alternatives: the same machine can also host other CLIs (e.g. a Codex CLI or a
  Gemini CLI) logged into their own accounts — the pattern is identical.

> Headless tip: the login URL redirects to `localhost`. If you're on a remote
> box, just copy the final redirect URL from the browser and paste it back into
> the prompt — no tunnel needed.

---

## 5. Run it inside tmux (so it survives disconnects)

```bash
sudo apt-get update && sudo apt-get install -y tmux
tmux new -s claude          # start a persistent session
# inside tmux:
claude
# detach with: Ctrl-b then d   ·   reattach later with: tmux attach -t claude
```

This keeps the agent alive after you close your laptop.

---

## 6. Install the official Telegram plugin

The Telegram channel lets you talk to this session from your phone. Its bridge
runs on **bun**, so install bun first:

```bash
npm install -g bun      # provides `bun` on PATH (used by the plugin bridge)
```

Then enable the plugin for the session. In `~/.claude/settings.json`:

```json
{
  "enabledPlugins": { "telegram@claude-plugins-official": true }
}
```

> **Critical:** without this `enabledPlugins` entry the session will say
> *"Listening for channel messages"* but never start the bridge — the bot stays
> silent.

---

## 7. Create your Telegram bot (BotFather)

1. In Telegram, open **@BotFather** → `/newbot` → give it a name → give it a
   username ending in `bot`.
2. BotFather returns a **bot token** like `123456789:AA...`. Keep it secret.
3. Configure the channel on the server:

```bash
mkdir -p ~/.claude/channels/telegram
echo "TELEGRAM_BOT_TOKEN=123456789:AA-your-token" > ~/.claude/channels/telegram/.env

cat > ~/.claude/channels/telegram/access.json <<'JSON'
{
  "dmPolicy": "allowlist",
  "allowFrom": ["YOUR_TELEGRAM_USER_ID"],
  "groups": {},
  "pending": {}
}
JSON
```

Find `YOUR_TELEGRAM_USER_ID` by messaging **@userinfobot**. With
`dmPolicy: "pairing"` instead, the first DM creates a code you approve once with
`/telegram:access pair <code>`.

---

## 8. Launch and control it from Telegram

Start Claude with the channel enabled:

```bash
export PATH="$HOME/.bun/bin:$HOME/.npm-global/bin:$PATH"   # make sure bun is found
claude --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions
```

You should see **"Listening for channel messages…"** and a `bun … telegram …`
process running. Now text your bot from Telegram — it replies, runs commands,
and edits files on the server. ✅ You're controlling the box from your phone.

> Put steps 5–8 in a small `launch.sh` and auto-start it from `.bashrc` (inside
> tmux) so the agent comes back automatically after a reboot.

---

## 9. Add MCP tools and skills (the agent's hands and playbooks)

**MCP servers** give the agent tools (GitHub, your hosting panel, databases,
Google Workspace, web automation…). Declare them in a project `.mcp.json`:

```json
{
  "mcpServers": {
    "github":   { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"],
                  "env": { "GITHUB_TOKEN": "ghp_xxx" } },
    "hosting":  { "command": "npx", "args": ["-y", "your-hosting-mcp"],
                  "env": { "HOSTING_API_TOKEN": "xxx" } }
  }
}
```

Enable project MCP servers with `"enableAllProjectMcpServers": true` in
`.claude.json` (or approve them interactively).

**Skills** are reusable step-by-step playbooks. Pull a skills collection from its
repo (e.g. an "Everything Claude Code" style set) and install it under
`~/.claude/skills/`:

```bash
git clone https://github.com/<skills-repo> ~/skills-src
cp -r ~/skills-src/skills/* ~/.claude/skills/     # or run the repo's install script
```

The agent now lists them and uses them on demand. (Find the collection's web/repo
first, then vendor it into your own repo so the setup is reproducible.)

---

## 10. Cloudflare + the API tokens that make the agent the "brain"

To put a real domain on anything the agent deploys, use **Cloudflare** for DNS:

1. Add your domain to Cloudflare (change its nameservers at your registrar).
2. **DNS → Add record:** `A` record → your server IP (proxied = orange cloud for
   free HTTPS + CDN + protection).
3. **My Profile → API Tokens → Create Token →** template **"Edit zone DNS"**,
   scoped to your zone. Save the token.

Then collect an API token / key for **every** tool you want the agent to drive,
and feed them to the relevant MCP server or `.env`:

| Tool | Where to get the token |
|------|------------------------|
| Cloudflare | My Profile → API Tokens (Edit zone DNS) |
| GitHub | Settings → Developer settings → fine-grained PAT |
| Hosting panel (Coolify/etc.) | Panel → Settings → API tokens |
| LLM gateway (OpenRouter/etc.) | Provider dashboard → Keys |
| Google Workspace | Google Cloud → OAuth client / service account |
| Web automation, n8n, Notion… | each product's API/settings page |

Keep all of these in untracked `.env` / secrets files (chmod 600), referenced by
the MCP configs above. Once wired, the agent is the single **brain** that reads
your messages and orchestrates GitHub, hosting, DNS, LLMs and the rest — all from
a Telegram chat.

---

## Where to go next

- Run several of these as a coordinated fleet (one orchestrator + children),
  with health checks and self-healing → [FLEET-ORCHESTRATION-AND-MAINTENANCE.md](./FLEET-ORCHESTRATION-AND-MAINTENANCE.md).
- Mother/children model & cross-session control → [MULTI-CLAUDE-MOTHER-AND-CHILDREN.md](./MULTI-CLAUDE-MOTHER-AND-CHILDREN.md).
- Telegram control patterns in depth → [CLAUDE-CODE-TELEGRAM-WORKFLOW.md](./CLAUDE-CODE-TELEGRAM-WORKFLOW.md).
