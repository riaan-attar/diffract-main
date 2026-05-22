Setup Guide · March 2026

**NemoClaw on Hostinger VPS**

*A non-technical guide — from zero to running AI agent with Claude*

nemoclaw v0.1.0 · OpenClaw 2026.3.11 · Ubuntu 24.04

# **01  Before you start**

You need four things before running any commands:

| What | Where to get it | Notes |
| :---- | :---- | :---- |
| Hostinger VPS | hPanel → VPS | Ubuntu 24.04, minimum 4 cores / 8 GB RAM / 50 GB disk. KVM2 plan works well. |
| NVIDIA API key | build.nvidia.com | Free tier available. Starts with nvapi-. Used for the wizard only. |
| Anthropic API key | console.anthropic.com | Starts with sk-ant-. This powers Claude inside OpenClaw. |
| SSH access | hPanel → Terminal, or any SSH client | All commands run as root on the VPS. |

# **02  Open the firewall in Hostinger hPanel**

Hostinger drops all incoming traffic by default. Add two rules before anything else.

| 1 | Go to firewall settings |
| :---: | :---- |

In hPanel, select your VPS → click Security → click Firewall → select your server → click Manage.

| 2 | Add port 80 rule |
| :---: | :---- |

Click Add rule: Action \= Accept · Protocol \= TCP · Port \= 80 · Source \= Any. Click Add rule.

| 3 | Add port 443 rule |
| :---: | :---- |

Repeat with Port \= 443\. Everything else stays the same.

|   | That's all. Do not open any other ports. OpenClaw runs on port 18789 inside the VPS — it never needs to be exposed directly. Caddy handles HTTPS → port 18789 internally. |
| :---- | :---- |

# **03  Install NemoClaw**

Three commands — run them in order. Each one builds on the last.

| A | Update system and install Docker |
| :---: | :---- |

| apt update && apt upgrade \-y && \\ |
| :---- |
| curl \-fsSL https://get.docker.com | sh && \\ |
| systemctl enable docker && systemctl start docker && \\ |
| usermod \-aG docker $USER && newgrp docker |
|   |

| B | Fix Docker cgroup setting and install OpenShell |
| :---: | :---- |

Ubuntu 24.04 uses cgroup v2 which requires a Docker config fix. This also installs the OpenShell CLI.

| echo '{"default-cgroupns-mode": "host"}' \> /etc/docker/daemon.json && \\ |
| :---- |
| systemctl restart docker && \\ |
| curl \-LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh && \\ |
| source \~/.bashrc |
|   |

| C | Install NemoClaw |
| :---: | :---- |

Node.js is handled automatically — you don't need to install it separately. The first two lines ensure nvm is loaded before the script runs.

| export NVM\_DIR="$HOME/.nvm" && \\ |
| :---- |
| \[ \-s "$NVM\_DIR/nvm.sh" \] && \\. "$NVM\_DIR/nvm.sh" ; \\ |
| curl \-fsSL https://nvidia.com/nemoclaw.sh | bash |
|   |

|   | This takes 5–10 minutes. The wizard launches automatically at the end and will ask for your sandbox name, NVIDIA key, and channel policies. See Section 04 for exactly what to enter. |
| :---- | :---- |

| D | Fix PATH so commands work in future sessions |
| :---: | :---- |

After install, nemoclaw and openshell may not be found in new terminal sessions. Run this once to fix it permanently:

| echo 'export NVM\_DIR="$HOME/.nvm"' \>\> \~/.bashrc && \\ |
| :---- |
| echo '\[ \-s "$NVM\_DIR/nvm.sh" \] && \\. "$NVM\_DIR/nvm.sh"' \>\> \~/.bashrc && \\ |
| echo 'export PATH="$PATH:$HOME/.local/bin"' \>\> \~/.bashrc && \\ |
| source \~/.bashrc |
|   |

|   | Why this is needed: nemoclaw is installed via nvm and openshell installs to \~/.local/bin. Neither is in the default PATH until you add them. |
| :---- | :---- |

# **04  Complete the setup wizard**

The install script from Step C launches the wizard automatically. If it doesn't — or if you need to re-run it — start it manually:

| nemoclaw onboard |
| :---- |
|   |

The wizard runs through 7 stages and asks for your input at three points:

| 1 | Sandbox name |
| :---: | :---- |

The wizard shows:

| Sandbox name (lowercase, numbers, hyphens) \[my-assistant\]: |
| :---- |
|   |

Type nemoclaw-sandbox and press Enter. If it says "already exists — Recreate? \[y/N\]", press N to keep the existing one.

|   | The wizard may skip this prompt and auto-accept the default name. Check what name appears in the final summary — that is your sandbox name. This guide uses nemoclaw-sandbox throughout. |
| :---- | :---- |

| 2 | NVIDIA API key |
| :---: | :---- |

The wizard shows:

| NVIDIA API Key: |
| :---- |
|   |

Paste your nvapi-... key and press Enter.

| 3 | Policy presets |
| :---: | :---- |

Near the end the wizard asks:

| Apply suggested presets (pypi, npm)? \[Y/n/list\]: |
| :---- |
|   |

Type list and press Enter, then type slack,telegram and press Enter.

|   | If the policy step fails with "sandbox not found" — this is a known bug in OpenShell 0.0.10. Press N to skip. Once the wizard finishes, apply policies manually: openshell policy set nemoclaw-sandbox \--policy \- \--wait \<\< 'EOF' network\_policies:   telegram:     name: telegram     endpoints:       \- host: api.telegram.org         port: 443   slack:     name: slack     endpoints:       \- host: slack.com         port: 443       \- host: api.slack.com         port: 443 EOF |
| :---- | :---- |

| 4 | Wait for the summary and connect |
| :---: | :---- |

When the wizard finishes you'll see a summary. Now connect to start the OpenClaw gateway and port forward:

| nemoclaw nemoclaw-sandbox connect |
| :---- |
|   |

Wait for the sandbox prompt (sandbox@nemoclaw-sandbox). This means OpenClaw is running and the port forward on 127.0.0.1:18789 is active. Keep this session running and open a new terminal for remaining steps.

# **05  Find and save your gateway token**

The gateway token is your password to log into the chat interface. Get it reliably by connecting to the sandbox and reading the config file:

| RUN ON VPS HOST — PRINTS YOUR TOKEN |
| :---- |
| nemoclaw nemoclaw-sandbox connect |
| python3 \-c "import json; d=json.load(open('/sandbox/.openclaw/openclaw.json')); print('TOKEN:', d\['gateway'\]\['auth'\]\['token'\])" |
| exit |
|  |
|   |

|   | Copy everything after TOKEN: and save it in a notes app or password manager. Lost your token? Just run the command above again — it never changes unless you reinstall. |
| :---- | :---- |

# **06  Set up Caddy for HTTPS access**

Caddy gives you a clean https:// address with an auto-renewing SSL certificate. No port numbers in your URL, nothing to manage manually.

| 1 | Install Caddy |
| :---: | :---- |

| curl \-1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg \--dearmor \-o /usr/share/keyrings/caddy-stable-archive-keyring.gpg |  |  |  |
| :---- | :---- | :---- | ----- |
| curl \-1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list |  |  |  |
| apt update && apt install caddy \-y |  |  |  |
|   |  |  |  |
|  |   | Run this on the VPS host — not inside the sandbox. If your prompt shows sandbox@nemoclaw-sandbox, type exit first. |  |

| 2 | Find your Hostinger subdomain |
| :---: | :---- |

In hPanel, go to your VPS Overview page. Your subdomain looks like srv1234567.hstgr.cloud. Copy it — you need it in the next step.

| 3 | Write the Caddy config and start it |
| :---: | :---- |

Replace YOUR-SUBDOMAIN.hstgr.cloud with your actual subdomain, then run both commands:

| COMMAND 1 — WRITE CONFIG (REPLACE THE SUBDOMAIN) |
| :---- |
|  sudo tee /etc/caddy/Caddyfile \> /dev/null \<\< 'CADDYEOF' srv1534809.hstgr.cloud {     reverse\_proxy 127.0.0.1:18789 {         header\_up Host 127.0.0.1:18789         header\_up Origin http://127.0.0.1:18789     } } CADDYEOF  |
|   |

| COMMAND 2 — START CADDY |
| :---- |
| systemctl restart caddy && systemctl enable caddy |
|   |

|   | Your URL is now: https://YOUR-SUBDOMAIN.hstgr.cloud The first load takes 15–30 seconds while Caddy gets the SSL certificate from Let's Encrypt. After that it loads instantly. The certificate renews automatically every 90 days. |
| :---- | :---- |

# **07  Access the chat interface**

| 1 | Verify the sandbox and port forward are running |
| :---: | :---- |

Before opening the browser, confirm the gateway is active:

| ss \-tlnp | grep 18789 |
| :---- |
| openshell forward list |
|   |

Port 18789 should show as listening and the forward status should be running. If it shows dead or nothing appears, run:

| nemoclaw nemoclaw-sandbox connect |
| :---- |
|   |

Wait for the sandbox prompt to appear. The forward starts automatically. You only need to run this once — it keeps running even after you exit the terminal session.

| 2 | Open the chat interface |
| :---: | :---- |

Open your browser and go to:

| Your URL https://YOUR-SUBDOMAIN.hstgr.cloud |
| :---: |

You'll see the OpenClaw login screen. Enter the gateway token you saved in Section 05\.

# **08  Add your API keys securely**

OpenShell manages API keys as providers — named credential bundles stored on the VPS host and injected into sandboxes at runtime. Keys never touch the sandbox filesystem. OpenClaw sends all inference requests through inference.local, a special endpoint where OpenShell's privacy router strips sandbox-side credentials, injects the real key from the host, and forwards to the actual API.

|   | Why inference.local? If OpenClaw called api.anthropic.com directly, it would need your key stored inside the sandbox. With inference.local, the key stays on the host — the sandbox never sees it. |
| :---- | :---- |

| 1 | Create OpenShell providers on the VPS host |
| :---: | :---- |

Run on the VPS host — not inside the sandbox. Replace the key values with your real keys.

| ANTHROPIC / CLAUDE |
| :---- |
| export ANTHROPIC\_API\_KEY="sk-ant-YOUR-KEY-HERE" |
| openshell provider create \--name anthropic-prod \--type anthropic \--from-existing |
|   |

| OPENAI (SKIP IF NOT USING OPENAI) |
| :---- |
| export OPENAI\_API\_KEY="sk-proj-YOUR-KEY-HERE" |
| openshell provider create \--name openai-prod \--type openai \--from-existing |
|   |

| openshell provider list |
| :---- |
|   |

| 2 | Point inference.local at Anthropic |
| ----- | :---- |
| openshell inference set \--provider openai-prod \--model gpt-4.1 \--no-verify |  |
|   |  |

| openshell inference get |
| :---- |
|   |

| 3 | Add providers to OpenClaw config inside the sandbox |
| :---: | :---- |

OpenShell routes keys securely via inference.local, but OpenClaw also needs to know about the providers in its own config. Run this script outside the sandbox:

| \# Load PATH export PATH="$PATH:$HOME/.local/bin" export NVM\_DIR="$HOME/.nvm" && \\. "$NVM\_DIR/nvm.sh" \# Fix ownership so sandbox user can write openshell doctor exec \-- kubectl exec \-n openshell nemoclaw-sandbox \-- chown sandbox:sandbox /sandbox/.openclaw/openclaw.json \# Connect and run the script nemoclaw nemoclaw-sandbox connect |
| :---- |
|   |

Then, inside the sandbox:

| ADD ANTHROPIC (CLAUDE) AND OPENAI PROVIDERS |
| :---- |
| openclaw config set models.providers.openai '{"baseUrl":"https://inference.local/v1","apiKey":"unused","api":"openai-completions","models":\[{"id":"gpt-4.1","name":"GPT-4.1"},{"id":"gpt-4o","name":"GPT-4o"}\]}' \# Anthropic provider openclaw config set models.providers.anthropic '{"baseUrl":"https://inference.local/v1","apiKey":"unused","api":"anthropic-messages","models":\[{"id":"claude-sonnet-4-6","name":"Claude Sonnet 4.6"},{"id":"claude-opus-4-6","name":"Claude Opus 4.6"}\]}' \# Set default model (this one already worked) openclaw config set agents.defaults.model.primary "openai/gpt-4.1"  |

| 4 | Restart the OpenClaw gateway to apply changes |
| :---: | :---- |

Still inside the sandbox, stop and restart the OpenClaw gateway:

| openclaw gateway stop |
| :---- |
| openclaw gateway |
|   |

Then exit the sandbox:

| exit |
| :---- |
|   |

In the chat UI, go to Settings → Models — you should now see Anthropic and OpenAI listed as providers. GPT-4.1 will be the default.

|   | Switching between Claude and OpenAI — run the appropriate command on the VPS host: Switch to Claude:  openshell inference set \--provider anthropic-prod \--model claude-sonnet-4-6 Switch to OpenAI:  openshell inference set \--provider openai-prod \--model gpt-4.1 \--no-verify No sandbox restart needed. Takes effect in seconds. Why both providers show type "openai": OpenShell uses openai as the generic type for any OpenAI-compatible API. It does not mean both are the same provider. |
| :---- | :---- |

# **09  Quick command cheatsheet**

All commands run on the VPS host — not inside the sandbox.

| Command | What it does |
| :---- | :---- |
| nemoclaw nemoclaw-sandbox connect | Start or reconnect the sandbox and gateway |
| nemoclaw nemoclaw-sandbox status | Check if the sandbox is healthy |
| nemoclaw nemoclaw-sandbox logs \--follow | Watch live activity logs |
| openshell sandbox list | List all sandboxes and their state |
| openshell inference get | Check which provider and model is active |
| openshell inference set \--provider anthropic-prod \--model claude-sonnet-4-6 | Switch to Claude |
| openshell inference set \--provider openai-prod \--model gpt-4.1 \--no-verify | Switch to OpenAI |
| openshell term | Open the security monitor — approve or deny network requests |
| systemctl status caddy | Check Caddy is running |
| systemctl restart caddy | Restart Caddy if the URL stops responding |
| nemoclaw onboard | Re-run the full setup wizard |
| openshell forward start 18789 agent \--background | if url isnt working  |
| nano $NEMOCLAW\_POLICIES/openclaw-sandbox.yaml  | to change policies  |
| openshell policy set \--policy $NEMOCLAW\_POLICIES/openclaw-sandbox.yaml agent | apply policy throughout  |
| nemoclaw nemoclaw connect |  |
| python3 \-c "import json; d=json.load(open('/sandbox/.openclaw/openclaw.json')); print('TOKEN:', d\['gateway'\]\['auth'\]\['token'\])" |  |
| exit |  |

|   | Retrieve your token anytime — run these inside the sandbox: nemoclaw nemoclaw-sandbox connect python3 \-c "import json; d=json.load(open('/sandbox/.openclaw/openclaw.json')); print(d\['gateway'\]\['auth'\]\['token'\])" exit |
| :---- | :---- |

|   | WARNING — Do not run this unless you want to start completely over:   nemoclaw nemoclaw-sandbox destroy This permanently deletes the sandbox and all its data. You will need to run nemoclaw onboard to rebuild from scratch. |
| :---- | :---- |

**\# NemoClaw Advanced Setup — Command Guide**

**\*\*Companion to: "NemoClaw: Connect Telegram, Set Up Policies & Install Your First Skills"\*\***

**\*\*FuturMinds | March 2026 | NemoClaw v0.1.0 | OpenClaw 2026.3.11\*\***

\---

**\#\# Prerequisites**

\- NemoClaw sandbox running (from Part 1 setup video)

\- Access to host terminal (outside sandbox)

\- Access to OpenClaw dashboard (http://127.0.0.1:18789 or your domain)

\---

**\#\# 1\. Network Policies**

**\#\#\# Find Your Policy Files**

\`\`\`bash

\# Save the path as a shortcut (run this first in every session)

NEMOCLAW\_POLICIES\="$(npm root \-g)/nemoclaw/nemoclaw-blueprint/policies"

\# View the main policy file

cat $NEMOCLAW\_POLICIES/openclaw-sandbox.yaml

\# View available presets

ls $NEMOCLAW\_POLICIES/presets/

\# Output: discord.yaml  docker.yaml  huggingface.yaml  jira.yaml

\#         npm.yaml  outlook.yaml  pypi.yaml  slack.yaml  telegram.yaml

\`\`\`

**\#\#\# Open the TUI (Real-Time Monitor)**

\`\`\`bash

\# Run on the HOST (not inside sandbox)

openshell term

\`\`\`

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

\> **\*\*IMPORTANT:\*\*** TUI approvals are session-only. They persist while the sandbox runs but reset on restart. Use policy file edits for permanent changes.

**\#\#\# Add a New Endpoint (Permanent)**

**\*\*Step 1:\*\*** Open the policy file:

\`\`\`bash

nano $NEMOCLAW\_POLICIES/openclaw-sandbox.yaml

\`\`\`

**\*\*Step 2:\*\*** Add entry at the bottom of \`network\_policies:\` section. Example — weather service:

\`\`\`yaml

 weather:

   name: weather

   endpoints:

     \- host: wttr.in

       port: 80

     \- host: wttr.in

       port: 443

       protocol: rest

       tls: terminate

       enforcement: enforce

       rules:

         \- allow: { method: GET, path: "/\*\*" }

   binaries:

     \- { path: /usr/bin/curl }

**\*\*Step 3:\*\*** Apply (immediate, persists across reboots):

\`\`\`bash

openshell policy set \--policy $NEMOCLAW\_POLICIES/openclaw-sandbox.yaml agent

\`\`\`

\> **\*\*WARNING:\*\*** \`openshell policy set\` REPLACES the entire policy. Always edit the full file, not a partial one.

**\#\#\# Add Telegram (If Not in Your Default Policy)**

The easiest way is to use the interactive preset:

\`\`\`bash

\# Interactive menu — select "telegram" when prompted

nemoclaw nemoclaw-sandbox policy-add

\# Verify it was added

nemoclaw nemoclaw-sandbox policy-list

\`\`\`

Presets are also available for: discord, slack, docker, huggingface, jira, npm, outlook, pypi

—

**\#\# 2\. Connect Telegram**

**\#\#\# Create a Bot**

1\. Open Telegram → message \`@BotFather\` (verify blue checkmark)

2\. Send \`/newbot\`

3\. Choose a name and username (must end in \`bot\`)

4\. Copy the token

**\#\#\# Start the Bridge (on HOST)**

In a separate terminal from your sandbox connection:

\`\`\`bash

export TELEGRAM\_BOT\_TOKEN\="8376185430:AAGnQMVCJlKJZxho47CkwZmAU0dQHziFULw"

nemoclaw start

\`\`\`

Make permanent:

\`\`\`bash

echo 'export TELEGRAM\_BOT\_TOKEN="8376185430:AAGnQMVCJlKJZxho47CkwZmAU0dQHziFULw"' \>\> \~/.bashrc

\`\`\`

export ALLOWED\_CHAT\_IDS="7871236037"

echo 'export ALLOWED\_CHAT\_IDS="7871236037"' \>\> \~/.bashrc

nemoclaw start

\> **\*\*NOTE:\*\*** \`nemoclaw start\` runs auxiliary services (Telegram bridge \+ cloudflared tunnel). Separate from \`nemoclaw nemoclaw-sandbox connect\`. Both run simultaneously.

**\#\#\# Lock Down Access (Dashboard UI)**

1\. Get your Telegram user ID: message \`@userinfobot\` on Telegram — it replies with your numeric ID

  \- Or use: https://web.telegram.org/k/\#@userinfobot

2\. Open Dashboard → Settings → Config

3\. Add in the channels section:

\`\`\`json5

channels: {

 telegram: {

   enabled: true,

   dmPolicy: 'allowlist',

   allowFrom: \[

     '7871236037',

   \],

   groupPolicy: 'allowlist',

   streaming: 'partial',

 },

},

\`\`\`

Replace \`YOUR\_NUMERIC\_ID\` with the number from userinfobot.

\- \`dmPolicy: 'allowlist'\` — only listed IDs can DM the bot

\- \`groupPolicy: 'allowlist'\` — only listed groups can interact

\- \`streaming: 'partial'\` — bot sends response as it generates (feels more natural)

**\#\#\# VPS Users — Fix Config Rewrite Bug**

In Dashboard → Settings → Config:

\- Set \`channels.telegram.configWrites\` to \`false\`

**\#\#\# Other Channels — Same Pattern**

1\. Create credentials on the platform

2\. Add endpoint to policy (or use \`nemoclaw nemoclaw-sandbox policy-add\` for presets)

3\. Configure token in Dashboard → Settings → Config

Available presets: discord, slack, telegram, docker, huggingface, jira, npm, outlook, pypi

\---

**\#\# 3\. Skills & Plugins**

**\#\#\# Check Available Skills (Inside Sandbox)**

\`\`\`bash

openclaw skills list          \# all skills \+ status

openclaw skills check         \# ready vs missing requirements

openclaw skills info \<name\>   \# details on a specific skill

\`\`\`

**\#\#\# Install Skills Safely (From HOST)**

Skills cannot be installed from inside the sandbox — the network policy blocks it. This is by design. Install on the host, review, then copy in.

**\*\*Step 1:\*\*** Install ClawHub CLI on the host:

\`\`\`bash

npm install \-g clawhub

\`\`\`

**\*\*Step 2:\*\*** Download a skill:

\`\`\`bash

clawhub install \<skill-name\>

\`\`\`

**\*\*Step 3:\*\*** Review the skill BEFORE putting it in the sandbox:

\`\`\`bash

cat /root/skills/\<skill-name\>/SKILL.md

\`\`\`

**\*\*Step 4:\*\*** Copy into the sandbox (two-step through the k3s cluster):

\`\`\`bash

\# Into Docker container first

docker cp /root/skills/\<skill-name\> openshell-cluster-nemoclaw:/tmp/\<skill-name\>

\# Then into the sandbox

docker exec openshell-cluster-nemoclaw kubectl cp \\

 /tmp/\<skill-name\> \\

 openshell/nemoclaw-sandbox:/sandbox/.openclaw-data/skills/\<skill-name\>

\`\`\`

**\*\*Batch copy all skills:\*\***

\`\`\`bash

for skill in /root/skills/\*/; do

 name\=$(basename "$skill")

 docker cp "$skill" openshell-cluster-nemoclaw:/tmp/$name

 docker exec openshell-cluster-nemoclaw kubectl exec \\

   \-n openshell nemoclaw-sandbox \-- rm \-rf /sandbox/.openclaw-data/skills/$name

 docker exec openshell-cluster-nemoclaw kubectl cp \\

   /tmp/$name openshell/nemoclaw-sandbox:/sandbox/.openclaw-data/skills/$name

done

\`\`\`

\> **\*\*TIP:\*\*** After copying, type \`/new\` in the dashboard chat to start a fresh session so the agent picks up the new skills.

**\#\#\# Plugins (Inside Sandbox)**

Plugins install through the \`openclaw\` binary which IS allowed by the network policy:

\`\`\`bash

openclaw plugins list

openclaw plugins install \<package-name\>

openclaw plugins enable \<name\>

openclaw plugins disable \<name\>

openclaw plugins update

openclaw plugins uninstall \<name\>

openclaw plugins info \<name\>

\`\`\`

**\#\#\# Key File Locations for Skills**

| What | Where |

|------|-------|

| Skills on host | \`/root/skills/\` |

| Skills in sandbox | \`/sandbox/.openclaw-data/skills/\` |

\---

**\#\# 4\. Switching AI Models**

One model at a time. No automatic fallback. Switch manually from the host — takes seconds, no restart.

\`\`\`bash

\# Register a new provider (one-time)

openshell provider create \--name anthropic \\

 \--type anthropic \\

 \--credential ANTHROPIC\_API\_KEY=sk-ant-your-key

\# Switch to Anthropic Claude

openshell inference set \--provider anthropic \\

 \--model claude-sonnet-4-20250514 \--no-verify

\# Switch back to NVIDIA Nemotron

openshell inference set \--provider nvidia-nim \\

 \--model nvidia/nemotron-3-super-120b-a12b

\# Check what's active

openshell inference get

\`\`\`

\> Anthropic (\`api.anthropic.com\`) is already in the baseline policy. If adding OpenAI, add \`api.openai.com\` to the policy file first.

\---

**\#\# 5\. Privacy Router — What It Actually Does**

**\*\*Protects:\*\*** API keys and credentials

**\*\*Does NOT protect:\*\*** Message content (names, emails, PII)

How it works:

1\. Agent sends request to \`inference.local\` (virtual endpoint inside sandbox)

2\. OpenShell intercepts, strips agent's placeholder API key

3\. Injects real API key from gateway storage, rewrites model to configured one

4\. Forwards to actual provider (NVIDIA, Anthropic, etc.)

Your real API keys never enter the sandbox. Content-level PII filtering (replacing "John Smith" with \`\[PERSON\_1\]\`) is NOT built in as of March 2026\.

\---

**\#\# 6\. Monitoring & Logs**

\`\`\`bash

\# TUI — real-time network monitor (run on HOST)

openshell term

\# Sandbox logs — live agent activity

nemoclaw nemoclaw-sandbox logs \--follow

\# Sandbox status

nemoclaw nemoclaw-sandbox status

\# Current inference provider

openshell inference get

\`\`\`

\---

**\#\# 7\. Security — NemoClaw vs Vanilla OpenClaw**

| Protection | Vanilla OpenClaw | NemoClaw |

|---|---|---|

| File access | No restrictions | \`/sandbox\` \+ \`/tmp\` only |

| Network access | No restrictions | Deny-by-default policy |

| API key exposure | Keys in agent's environment | Keys in gateway, never in sandbox |

| Visibility | No audit trail | TUI \+ logs \+ policy revision history |

| Policy enforcement | Application-level (bypassable) | OS-level (Landlock \+ seccomp) |

\> **\*\*Known gap:\*\*** Telegram and Discord policy entries don't restrict which programs (\`binaries\`) can use them. A malicious skill could exfiltrate data through these already-approved endpoints.

\---

**\#\# 8\. Commands to AVOID**

| Command | Why |

|---|---|

| \`openclaw configure\` | Known bug — can wipe workspace, sessions, API keys. Use Dashboard UI or \`openclaw config set\` instead |

| \`nemoclaw onboard\` (to change policy) | Recreates sandbox from scratch, losing all state. Use \`openshell policy set\` instead |

| \`openshell gateway destroy\` | Deletes ALL state — policies, providers, sandbox. Only use if starting completely fresh |

\---

**\#\# 9\. Key File Locations**

| What | Where |

|---|---|

| Policy file | \`$(npm root \-g)/nemoclaw/nemoclaw-blueprint/policies/openclaw-sandbox.yaml\` |

| Policy presets | \`$(npm root \-g)/nemoclaw/nemoclaw-blueprint/policies/presets/\` |

| Skills (host) | \`/root/skills/\` |

| Skills (sandbox) | \`/sandbox/.openclaw-data/skills/\` |

| OpenClaw config (sandbox) | \`/sandbox/.openclaw/openclaw.json\` |

| NemoClaw credentials (host) | \`\~/.nemoclaw/credentials.json\` |

| Agent data (sandbox) | \`\~/.openclaw/agents/\<id\>/\` |

\---

*\*Guide by Future Minds | Join our free Skool community for more guides and templates\**

*\*NemoClaw v0.1.0 | OpenClaw 2026.3.11 | March 2026\**

sudo tee /etc/caddy/Caddyfile \> /dev/null \<\< 'CADDYEOF'

srv1534809.hstgr.cloud {

   reverse\_proxy 127.0.0.1:18789 {

       header\_up Host 127.0.0.1:18789

       header\_up Origin http://127.0.0.1:18789

   }

}

CADDYEOF

