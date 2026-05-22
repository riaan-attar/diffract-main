# 🛠️ Diffract Guide: Installing NemoClaw from Local Git Repo (WSL2)

This guide walks you through building and installing your **custom, modified NemoClaw code** directly from your local repository inside your WSL2 environment, bypassing the public `curl` installer.

---

## 📋 Prerequisites

Before starting, ensure you have active WSL2 terminals and that **Docker Desktop** is running on your Windows host with **WSL2 Integration enabled** (Settings ➔ Resources ➔ WSL Integration).

---

## 🚶 Step-by-Step Installation

### Step 1: Install OpenShell Runtime (Host Egress Layer)
NemoClaw relies on the OpenShell binary to manage cluster gateways and intercept network policies. Install it first:
```bash
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
source ~/.bashrc
```

### Step 2: Navigate to your Local NemoClaw Directory
Open your WSL2 terminal and change directory to where your modified NemoClaw source code is located:
```bash
cd "/mnt/c/Users/Admin/Desktop/From Scrtch/From Scrtch/NemoClaw"
```

### Step 3: Install Dependencies & Build CLI
NemoClaw's CLI commands are written in TypeScript and must be compiled into JavaScript executable files:
```bash
# 1. Install development dependencies
npm install

# 2. Compile TypeScript source code to JavaScript
npm run build:cli
```

### Step 4: Install Your Local Build Globally
Instead of downloading from the npm registry, install the CLI globally using your local directory `.`:
```bash
npm install -g .
```

> 💡 **Tip for Active Development:**
> If you are frequently modifying the NemoClaw code, you can use `npm link` instead of `npm install -g .` so that changes in your local folder are immediately available in the global command without reinstalling:
> ```bash
> npm link
> ```

---

## 🧪 Verification & Bootstrapping

### Step 1: Verify the Command Points to Your Repo
Confirm that the global `nemoclaw` command points to your compiled local package:
```bash
which nemoclaw
# Output should point to your global node bin (e.g., /home/username/.nvm/.../bin/nemoclaw)
```

### Step 2: Run Your Modified Onboarding Wizard
Launch the onboarding flow to deploy your secure sandbox using your custom code:
```bash
nemoclaw onboard
```
*Follow the interactive prompts to name your sandbox, select inference models, and apply policy presets.*

### Step 3: Connect and Verify Sandbox Lifecycle
Connect to the secure environment to make sure everything works perfectly:
```bash
nemoclaw nemoclaw-sandbox connect
```

---

## ⚡ Troubleshooting Local Builds

* **TypeScript Compilation Failures**:
  If you made syntax edits to the CLI TypeScript files and compile fails, run `npm run typecheck` to find the exact errors.
* **Gateway Errors during `onboard`**:
  If OpenShell complains about a mismatch, make sure your Docker daemon is fully responsive in WSL:
  ```bash
  docker ps
  ```
