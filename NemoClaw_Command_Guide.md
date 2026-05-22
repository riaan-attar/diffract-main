# NemoClaw Advanced Setup — Command Guide

**Companion to: "NemoClaw: Connect Telegram, Set Up Policies & Install Your First Skills"**
**FuturMinds | March 2026 | NemoClaw v0.1.0 | OpenClaw 2026.3.11**

---

## Prerequisites

- NemoClaw sandbox running (from Part 1 setup video)
- Access to host terminal (outside sandbox)
- Access to OpenClaw dashboard (http://127.0.0.1:18789 or your domain)

---

## 1. Network Policies

### Find Your Policy Files

```bash
# Save the path as a shortcut (run this first in every session)
NEMOCLAW_POLICIES="$(npm root -g)/nemoclaw/nemoclaw-blueprint/policies"

# View the main policy file
cat $NEMOCLAW_POLICIES/openclaw-sandbox.yaml

# View available presets
ls $NEMOCLAW_POLICIES/presets/
# Output: discord.yaml  docker.yaml  huggingface.yaml  jira.yaml
#         npm.yaml  outlook.yaml  pypi.yaml  slack.yaml  telegram.yaml
```



### Open the TUI (Real-Time Monitor)

```bash
# Run on the HOST (not inside sandbox)
openshell term
```

| Key | Action |
|-----|--------|
| Tab | Switch panels (Gateways / Providers / Sandboxes) |
| j / k | Navigate up/down |
| Enter | Select / drill into detail view |
| r | View network rules (inside sandbox view) |
| a | Approve pending request (session-only) |
| x | Reject pending request |
| A | Approve all pending |
| q | Quit |

> **IMPORTANT:** TUI approvals are session-only. They persist while the sandbox runs but reset on restart. Use policy file edits for permanent changes.

### Add a New Endpoint (Permanent)

**Step 1:** Open the policy file:
```bash
nano $NEMOCLAW_POLICIES/openclaw-sandbox.yaml
```

**Step 2:** Add entry at the bottom of `network_policies:` section. Example — weather service:

```yaml
  weather:
    name: weather
    endpoints:
      - host: wttr.in
        port: 80
      - host: wttr.in
        port: 443
        protocol: rest
        tls: terminate
        enforcement: enforce
        rules:
          - allow: { method: GET, path: "/**" }
    binaries:
      - { path: /usr/bin/curl }
```
linkedin:
    name: linkedin
    endpoints:
      - host: linkedin.com
        port: 80
      - host: linkedin.com
        port: 443
        protocol: rest
        tls: terminate
        enforcement: enforce
        rules:
          - allow: { method: GET, path: "/**" }
    binaries:
      - { path: /usr/bin/curl }

**Step 3:** Apply (immediate, persists across reboots):
```bash
openshell policy set --policy $NEMOCLAW_POLICIES/openclaw-sandbox.yaml agent
```

> **WARNING:** `openshell policy set` REPLACES the entire policy. Always edit the full file, not a partial one.

### Add Telegram (If Not in Your Default Policy)

The easiest way is to use the interactive preset:

```bash
# Interactive menu — select "telegram" when prompted
nemoclaw nemoclaw-sandbox policy-add

# Verify it was added
nemoclaw nemoclaw-sandbox policy-list
```

Presets are also available for: discord, slack, docker, huggingface, jira, npm, outlook, pypi

---

## 2. Connect Telegram

### Create a Bot

1. Open Telegram → message `@BotFather` (verify blue checkmark)
2. Send `/newbot`
3. Choose a name and username (must end in `bot`)
4. Copy the token

### Start the Bridge (on HOST)

In a separate terminal from your sandbox connection:

```bash
export TELEGRAM_BOT_TOKEN="8376185430:AAGnQMVCJlKJZxho47CkwZmAU0dQHziFULw"
nemoclaw start
```

Make permanent:
```bash
echo 'export TELEGRAM_BOT_TOKEN="8376185430:AAGnQMVCJlKJZxho47CkwZmAU0dQHziFULw"' >> ~/.bashrc
```

export ALLOWED_CHAT_IDS="7871236037"
echo 'export ALLOWED_CHAT_IDS="7871236037"' >> ~/.bashrc
nemoclaw start


> **NOTE:** `nemoclaw start` runs auxiliary services (Telegram bridge + cloudflared tunnel). Separate from `nemoclaw nemoclaw-sandbox connect`. Both run simultaneously.

### Lock Down Access (Dashboard UI)

1. Get your Telegram user ID: message `@userinfobot` on Telegram — it replies with your numeric ID
   - Or use: https://web.telegram.org/k/#@userinfobot
2. Open Dashboard → Settings → Config
3. Add in the channels section:

```json5
channels: {
  telegram: {
    enabled: true,
    dmPolicy: 'allowlist',
    allowFrom: [
      '7871236037',
    ],
    groupPolicy: 'allowlist',
    streaming: 'partial',
  },
},
```

Replace `YOUR_NUMERIC_ID` with the number from userinfobot.

- `dmPolicy: 'allowlist'` — only listed IDs can DM the bot
- `groupPolicy: 'allowlist'` — only listed groups can interact
- `streaming: 'partial'` — bot sends response as it generates (feels more natural)

### VPS Users — Fix Config Rewrite Bug

In Dashboard → Settings → Config:
- Set `channels.telegram.configWrites` to `false`

### Other Channels — Same Pattern

1. Create credentials on the platform
2. Add endpoint to policy (or use `nemoclaw nemoclaw-sandbox policy-add` for presets)
3. Configure token in Dashboard → Settings → Config

Available presets: discord, slack, telegram, docker, huggingface, jira, npm, outlook, pypi

---

## 3. Skills & Plugins

### Check Available Skills (Inside Sandbox)

```bash
openclaw skills list          # all skills + status
openclaw skills check         # ready vs missing requirements
openclaw skills info <name>   # details on a specific skill
```

### Install Skills Safely (From HOST)

Skills cannot be installed from inside the sandbox — the network policy blocks it. This is by design. Install on the host, review, then copy in.

**Step 1:** Install ClawHub CLI on the host:
```bash
npm install -g clawhub
```

**Step 2:** Download a skill:
```bash
clawhub install <skill-name>
```

**Step 3:** Review the skill BEFORE putting it in the sandbox:
```bash
cat /root/skills/<skill-name>/SKILL.md
```

**Step 4:** Copy into the sandbox (two-step through the k3s cluster):
```bash
# Into Docker container first
docker cp /root/skills/<skill-name> openshell-cluster-nemoclaw:/tmp/<skill-name>

# Then into the sandbox
docker exec openshell-cluster-nemoclaw kubectl cp \
  /tmp/<skill-name> \
  openshell/nemoclaw-sandbox:/sandbox/.openclaw-data/skills/<skill-name>
```

**Batch copy all skills:**
```bash
for skill in /root/skills/*/; do
  name=$(basename "$skill")
  docker cp "$skill" openshell-cluster-nemoclaw:/tmp/$name
  docker exec openshell-cluster-nemoclaw kubectl exec \
    -n openshell nemoclaw-sandbox -- rm -rf /sandbox/.openclaw-data/skills/$name
  docker exec openshell-cluster-nemoclaw kubectl cp \
    /tmp/$name openshell/nemoclaw-sandbox:/sandbox/.openclaw-data/skills/$name
done
```

> **TIP:** After copying, type `/new` in the dashboard chat to start a fresh session so the agent picks up the new skills.

### Plugins (Inside Sandbox)

Plugins install through the `openclaw` binary which IS allowed by the network policy:

```bash
openclaw plugins list
openclaw plugins install <package-name>
openclaw plugins enable <name>
openclaw plugins disable <name>
openclaw plugins update
openclaw plugins uninstall <name>
openclaw plugins info <name>
```

### Key File Locations for Skills

| What | Where |
|------|-------|
| Skills on host | `/root/skills/` |
| Skills in sandbox | `/sandbox/.openclaw-data/skills/` |

---

## 4. Switching AI Models

One model at a time. No automatic fallback. Switch manually from the host — takes seconds, no restart.

```bash
# Register a new provider (one-time)
openshell provider create --name anthropic \
  --type anthropic \
  --credential ANTHROPIC_API_KEY=sk-ant-your-key

# Switch to Anthropic Claude
openshell inference set --provider anthropic \
  --model claude-sonnet-4-20250514 --no-verify

# Switch back to NVIDIA Nemotron
openshell inference set --provider nvidia-nim \
  --model nvidia/nemotron-3-super-120b-a12b

# Check what's active
openshell inference get
```

> Anthropic (`api.anthropic.com`) is already in the baseline policy. If adding OpenAI, add `api.openai.com` to the policy file first.

---

## 5. Privacy Router — What It Actually Does

**Protects:** API keys and credentials
**Does NOT protect:** Message content (names, emails, PII)

How it works:
1. Agent sends request to `inference.local` (virtual endpoint inside sandbox)
2. OpenShell intercepts, strips agent's placeholder API key
3. Injects real API key from gateway storage, rewrites model to configured one
4. Forwards to actual provider (NVIDIA, Anthropic, etc.)

Your real API keys never enter the sandbox. Content-level PII filtering (replacing "John Smith" with `[PERSON_1]`) is NOT built in as of March 2026.

---

## 6. Monitoring & Logs

```bash
# TUI — real-time network monitor (run on HOST)
openshell term

# Sandbox logs — live agent activity
nemoclaw nemoclaw-sandbox logs --follow

# Sandbox status
nemoclaw nemoclaw-sandbox status

# Current inference provider
openshell inference get
```

---

## 7. Security — NemoClaw vs Vanilla OpenClaw

| Protection | Vanilla OpenClaw | NemoClaw |
|---|---|---|
| File access | No restrictions | `/sandbox` + `/tmp` only |
| Network access | No restrictions | Deny-by-default policy |
| API key exposure | Keys in agent's environment | Keys in gateway, never in sandbox |
| Visibility | No audit trail | TUI + logs + policy revision history |
| Policy enforcement | Application-level (bypassable) | OS-level (Landlock + seccomp) |

> **Known gap:** Telegram and Discord policy entries don't restrict which programs (`binaries`) can use them. A malicious skill could exfiltrate data through these already-approved endpoints.

---

## 8. Commands to AVOID

| Command | Why |
|---|---|
| `openclaw configure` | Known bug — can wipe workspace, sessions, API keys. Use Dashboard UI or `openclaw config set` instead |
| `nemoclaw onboard` (to change policy) | Recreates sandbox from scratch, losing all state. Use `openshell policy set` instead |
| `openshell gateway destroy` | Deletes ALL state — policies, providers, sandbox. Only use if starting completely fresh |

---

## 9. Key File Locations

| What | Where |
|---|---|
| Policy file | `$(npm root -g)/nemoclaw/nemoclaw-blueprint/policies/openclaw-sandbox.yaml` |
| Policy presets | `$(npm root -g)/nemoclaw/nemoclaw-blueprint/policies/presets/` |
| Skills (host) | `/root/skills/` |
| Skills (sandbox) | `/sandbox/.openclaw-data/skills/` |
| OpenClaw config (sandbox) | `/sandbox/.openclaw/openclaw.json` |
| NemoClaw credentials (host) | `~/.nemoclaw/credentials.json` |
| Agent data (sandbox) | `~/.openclaw/agents/<id>/` |

---

*Guide by Future Minds | Join our free Skool community for more guides and templates*
*NemoClaw v0.1.0 | OpenClaw 2026.3.11 | March 2026*


sudo tee /etc/caddy/Caddyfile > /dev/null << 'CADDYEOF'
srv1534809.hstgr.cloud {
    reverse_proxy 127.0.0.1:18789 {
        header_up Host 127.0.0.1:18789
        header_up Origin http://127.0.0.1:18789
    }
}
CADDYEOF
