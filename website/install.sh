#!/usr/bin/env bash
# Diffract installer — from zero to running dashboard with one command.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hrubee/Diffraction/main/install.sh | bash
#
# With domain (full web stack — recommended on a VPS):
#   DIFFRACT_DOMAIN=example.com bash <(curl -fsSL https://raw.githubusercontent.com/hrubee/Diffraction/main/install.sh)
#
# What this does:
#   1. Installs system dependencies (git, curl) if missing
#   2. Installs Node.js via nvm if missing
#   3. Installs Docker if missing + applies cgroup v2 fix
#   4. Installs OpenShell CLI if missing
#   5. Clones/updates the Diffract repo
#   6. Installs CLI + API + UI dependencies
#   7. Builds the UI
#   8. Installs and starts systemd services (Linux only)
#   9. [Linux] Chains to scripts/deploy-vps.sh when DIFFRACT_DOMAIN is set
#      — installs Caddy, configures HTTPS, starts gateway, opens UFW 80/443
#
# Environment variables:
#   DIFFRACT_DOMAIN        Public domain or IP for HTTPS (triggers web-stack deploy)
#   DIFFRACT_REPO_URL      Override source URL — git clone URL or tarball (.tar.gz/.tgz/.zip)
#                          Default: https://diffraction.in/diffract.tar.gz
#                          Example: DIFFRACT_REPO_URL=https://diffraction.in/release.tar.gz

set -euo pipefail

REPO_URL="${DIFFRACT_REPO_URL:-https://diffraction.in/diffract.tar.gz}"
INSTALL_DIR="${DIFFRACT_HOME:-$HOME/.diffract}"
BIN_DIR="/usr/local/bin"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

echo ""
echo "  Diffract — Enterprise AI Agent Platform"
echo "  ========================================="
echo ""

# ── Helpers ────────────────────────────────────────────────────────

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    if ! command_exists sudo; then
      echo "  ERROR: This script needs root access. Run as root or install sudo."
      exit 1
    fi
    SUDO="sudo"
  else
    SUDO=""
  fi
}

# ── 1. System dependencies ────────────────────────────────────────

echo "  [1/8] Checking system dependencies..."
ensure_sudo

if ! command_exists git || ! command_exists curl; then
  echo "  Installing git and curl..."
  if command_exists apt-get; then
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git curl >/dev/null 2>&1
  elif command_exists yum; then
    $SUDO yum install -y git curl >/dev/null 2>&1
  elif command_exists dnf; then
    $SUDO dnf install -y git curl >/dev/null 2>&1
  elif command_exists brew; then
    brew install git curl >/dev/null 2>&1
  else
    echo "  ERROR: Could not install git/curl. Install them manually."
    exit 1
  fi
fi
echo "  ✓ git and curl available"

# ── 2. Node.js (via nvm) ──────────────────────────────────────────

echo "  [2/8] Checking Node.js..."

# Load nvm if already installed
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if ! command_exists node || [ "$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)" -lt 20 ] 2>/dev/null; then
  echo "  Installing Node.js 22 via nvm..."
  if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    \. "$NVM_DIR/nvm.sh"
  fi
  nvm install 22 >/dev/null 2>&1
  nvm use 22 >/dev/null 2>&1
  nvm alias default 22 >/dev/null 2>&1

  # Persist nvm in shell profile
  for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q "NVM_DIR" "$profile" 2>/dev/null; then
      echo 'export NVM_DIR="$HOME/.nvm"' >> "$profile"
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$profile"
    fi
  done
fi
echo "  ✓ Node.js $(node -v)"

# ── 3. Docker ─────────────────────────────────────────────────────

echo "  [3/8] Checking Docker..."

if ! command_exists docker; then
  echo "  Installing Docker..."
  if [ "$(uname)" = "Darwin" ]; then
    if command_exists brew; then
      brew install --cask docker-desktop 2>/dev/null || true
      open -a Docker 2>/dev/null || true
    else
      echo "  Install Docker Desktop from https://docker.com/get-docker"
      exit 1
    fi
  else
    curl -fsSL https://get.docker.com | $SUDO sh
    $SUDO usermod -aG docker "$(whoami)" 2>/dev/null || true
  fi
fi

# Ensure Docker is running
if ! docker info >/dev/null 2>&1; then
  echo "  Starting Docker..."
  $SUDO systemctl start docker 2>/dev/null || true
  $SUDO systemctl enable docker 2>/dev/null || true
  for i in $(seq 1 40); do
    docker info >/dev/null 2>&1 && break
    sleep 3
    [ $((i % 5)) -eq 0 ] && echo "  Still waiting for Docker... (${i}s)"
  done
fi

if ! docker info >/dev/null 2>&1; then
  echo "  ERROR: Docker is not running. Start it manually and re-run this script."
  exit 1
fi

# Apply cgroup v2 fix for Ubuntu 24.04+ (required by OpenShell)
if [ "$(uname)" != "Darwin" ]; then
  if [ ! -f /etc/docker/daemon.json ] || ! grep -q "cgroupns" /etc/docker/daemon.json 2>/dev/null; then
    echo "  Applying cgroup v2 fix..."
    echo '{"default-cgroupns-mode": "host"}' | $SUDO tee /etc/docker/daemon.json >/dev/null
    $SUDO systemctl restart docker 2>/dev/null || true
    sleep 3
  fi
fi
echo "  ✓ Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"

# ── 4. OpenShell CLI ──────────────────────────────────────────────

echo "  [4/8] Checking OpenShell CLI..."

export PATH="$PATH:$HOME/.local/bin"

if ! command_exists openshell; then
  echo "  Installing OpenShell CLI (v0.0.21 — v0.0.22 has port forward regression)..."
  # Pin to v0.0.21: v0.0.22 SSH port forwarding returns empty replies
  curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION=v0.0.21 sh
  export PATH="$PATH:$HOME/.local/bin"

  # Persist PATH
  for profile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$profile" ] && ! grep -q '\.local/bin' "$profile" 2>/dev/null; then
      echo 'export PATH="$PATH:$HOME/.local/bin"' >> "$profile"
    fi
  done
fi
echo "  ✓ OpenShell $(openshell --version 2>/dev/null || echo 'installed')"

# ── 5. Clone/update Diffract ──────────────────────────────────────

echo "  [5/8] Setting up Diffract..."

CODE_CHANGED=0

case "$REPO_URL" in
  *.tar.gz|*.tgz) _REPO_MODE=tarball ;;
  *.zip)          _REPO_MODE=zip ;;
  *)              _REPO_MODE=git ;;
esac

if [ "$_REPO_MODE" = "git" ]; then
  # Capture current HEAD before any update (for change detection)
  OLD_HEAD="$(cd "$INSTALL_DIR/repo" 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo '')"

  if [ -d "$INSTALL_DIR/repo" ]; then
    echo "  Updating existing installation..."
    (cd "$INSTALL_DIR/repo" && git pull --rebase --quiet 2>/dev/null || true)
  else
    mkdir -p "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR/repo"
  fi

  NEW_HEAD="$(cd "$INSTALL_DIR/repo" && git rev-parse HEAD)"
  if [ -z "$OLD_HEAD" ] || [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
    CODE_CHANGED=1
  fi

else
  # Tarball / zip download mode — no git history required
  SHA_MARKER="$INSTALL_DIR/.tarball-sha256"
  OLD_SHA="$(cat "$SHA_MARKER" 2>/dev/null || echo '')"

  _TMP_ARCHIVE="$(mktemp)"
  echo "  Downloading $REPO_URL..."
  curl -fsSL "$REPO_URL" -o "$_TMP_ARCHIVE"

  # sha256sum (Linux) or shasum -a 256 (macOS)
  NEW_SHA="$(sha256sum "$_TMP_ARCHIVE" 2>/dev/null | awk '{print $1}')"
  [ -z "$NEW_SHA" ] && NEW_SHA="$(shasum -a 256 "$_TMP_ARCHIVE" 2>/dev/null | awk '{print $1}')"

  if [ "$OLD_SHA" = "$NEW_SHA" ] && [ -d "$INSTALL_DIR/repo" ]; then
    echo "  No changes detected (sha256 unchanged) — skipping extract."
    rm -f "$_TMP_ARCHIVE"
  else
    mkdir -p "$INSTALL_DIR"
    _TMP_STAGE="$(mktemp -d)"

    if [ "$_REPO_MODE" = "zip" ]; then
      command_exists unzip || { $SUDO apt-get install -y -qq unzip >/dev/null 2>&1 || true; }
      unzip -q "$_TMP_ARCHIVE" -d "$_TMP_STAGE"
    else
      tar -xzf "$_TMP_ARCHIVE" -C "$_TMP_STAGE"
    fi

    # Handle both top-level-dir archives (e.g. diffract-main/...) and flat archives
    _ENTRIES="$(ls -1 "$_TMP_STAGE" | wc -l | tr -d '[:space:]')"
    if [ "$_ENTRIES" = "1" ] && [ -d "$_TMP_STAGE/$(ls -1 "$_TMP_STAGE")" ]; then
      _TOP="$_TMP_STAGE/$(ls -1 "$_TMP_STAGE")"
      rm -rf "$INSTALL_DIR/repo"
      mv "$_TOP" "$INSTALL_DIR/repo"
      rm -rf "$_TMP_STAGE"
    else
      rm -rf "$INSTALL_DIR/repo"
      mv "$_TMP_STAGE" "$INSTALL_DIR/repo"
    fi

    rm -f "$_TMP_ARCHIVE"
    printf '%s\n' "$NEW_SHA" > "$SHA_MARKER"
    CODE_CHANGED=1
  fi
fi

# ── 6. Install dependencies ──────────────────────────────────────

echo "  [6/8] Installing dependencies..."

(cd "$INSTALL_DIR/repo/cli" && npm install --ignore-scripts --silent 2>/dev/null)
(cd "$INSTALL_DIR/repo/api" && npm install --silent 2>/dev/null)
(cd "$INSTALL_DIR/repo/ui"  && npm install --silent 2>/dev/null)

# ── 7. Build UI ───────────────────────────────────────────────────

echo "  [7/8] Building dashboard UI..."

(cd "$INSTALL_DIR/repo/ui" && npm run build 2>/dev/null)

# ── Create diffract command ───────────────────────────────────────

WRAPPER="$BIN_DIR/diffract"
WRAPPER_CONTENT="#!/usr/bin/env bash
set -euo pipefail
export NVM_DIR=\"\${NVM_DIR:-\$HOME/.nvm}\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
export PATH=\"\$PATH:\$HOME/.local/bin\"
DIFFRACT_HOME=\"\${DIFFRACT_HOME:-\$HOME/.diffract}\"
exec \"\$DIFFRACT_HOME/repo/diffract.sh\" \"\$@\"
"

if [ -w "$BIN_DIR" ]; then
  echo "$WRAPPER_CONTENT" > "$WRAPPER"
  chmod +x "$WRAPPER"
else
  echo "$WRAPPER_CONTENT" | $SUDO tee "$WRAPPER" >/dev/null
  $SUDO chmod +x "$WRAPPER"
fi

# ── 8. Install and start systemd services (Linux only) ────────────

echo "  [8/8] Configuring services..."

detect_domain() {
  if [ -n "${DIFFRACT_DOMAIN:-}" ]; then echo "$DIFFRACT_DOMAIN"; return; fi
  local fqdn
  fqdn="$(hostname -f 2>/dev/null || true)"
  if echo "$fqdn" | grep -qE '\.' && ! echo "$fqdn" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "$fqdn"; return
  fi
  local ip
  ip="$(curl -sf --max-time 5 https://ifconfig.me 2>/dev/null)"
  [ -n "$ip" ] && { echo "$ip"; return; }
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "$ip" ] && { echo "$ip"; return; }
  echo localhost
}

if [ "$(uname)" = "Darwin" ]; then
  echo "  systemd services are Linux-only."
  echo "  On macOS run: bash scripts/start-ui.sh to launch UI+API in the foreground."
  DOMAIN="localhost"
  URL="http://${DOMAIN}:3000/setup"
elif ! command_exists systemctl; then
  echo "  systemd not found — skipping service install"
  DOMAIN="$(detect_domain)"
  if echo "$DOMAIN" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || [ "$DOMAIN" = "localhost" ]; then
    URL="http://${DOMAIN}:3000/setup"
  else
    URL="https://${DOMAIN}/setup"
  fi
else
  # Resolve real user (may differ when run with sudo)
  REAL_USER="${SUDO_USER:-$USER}"
  [ -z "$REAL_USER" ] && REAL_USER=root
  REAL_GROUP="$(id -gn "$REAL_USER" 2>/dev/null || echo "$REAL_USER")"
  REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
  [ -z "$REAL_HOME" ] && REAL_HOME="$HOME"
  INSTALL_DIR_RESOLVED="$REAL_HOME/.diffract/repo"
  NODE_BIN="$(command -v node)"
  NODE_DIR="$(dirname "$NODE_BIN")"

  # Create writable state directory for UI credentials marker
  $SUDO mkdir -p /var/lib/diffract-ui
  $SUDO chown "${REAL_USER}:${REAL_GROUP}" /var/lib/diffract-ui
  $SUDO chmod 750 /var/lib/diffract-ui

  UNIT_CHANGED=0
  for svc in diffract-api diffract-ui; do
    SRC="$INSTALL_DIR/repo/systemd/${svc}.service"
    DST="/etc/systemd/system/${svc}.service"

    if [ ! -f "$SRC" ]; then
      echo "  WARNING: $SRC not found — skipping $svc"
      continue
    fi

    RENDERED="$(mktemp)"
    sed \
      -e "s|@@USER@@|${REAL_USER}|g" \
      -e "s|@@GROUP@@|${REAL_GROUP}|g" \
      -e "s|@@USER_HOME@@|${REAL_HOME}|g" \
      -e "s|@@INSTALL_DIR@@|${INSTALL_DIR_RESOLVED}|g" \
      -e "s|@@NODE_BIN@@|${NODE_BIN}|g" \
      -e "s|@@NODE_DIR@@|${NODE_DIR}|g" \
      "$SRC" > "$RENDERED"

    if [ ! -f "$DST" ] || ! cmp -s "$RENDERED" "$DST"; then
      $SUDO cp "$RENDERED" "$DST"
      $SUDO chmod 644 "$DST"
      UNIT_CHANGED=1
      echo "  ✓ Installed ${svc}.service"
    else
      echo "  ✓ ${svc}.service unchanged"
    fi
    rm -f "$RENDERED"
  done

  if [ "$UNIT_CHANGED" -eq 1 ]; then
    $SUDO systemctl daemon-reload
  fi

  # Enable (idempotent)
  $SUDO systemctl enable diffract-api.service diffract-ui.service 2>/dev/null

  # Restart only when something changed or services are down
  for svc in diffract-api diffract-ui; do
    if [ "$UNIT_CHANGED" -eq 1 ] || [ "$CODE_CHANGED" -eq 1 ] || \
       ! $SUDO systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
      $SUDO systemctl restart "${svc}.service"
    fi
  done
  echo "  ✓ Services running"

  # ── Wait for health (up to 60s) ──────────────────────────────────

  API_OK=0
  UI_OK=0
  for i in $(seq 1 60); do
    if [ "$API_OK" -eq 0 ] && curl -sf --max-time 2 http://127.0.0.1:3001/api/health >/dev/null 2>&1; then
      API_OK=1
    fi
    if [ "$UI_OK" -eq 0 ]; then
      HTTP_CODE="$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null || echo '')"
      if echo "$HTTP_CODE" | grep -qE '^[234]'; then
        UI_OK=1
      fi
    fi
    [ "$API_OK" -eq 1 ] && [ "$UI_OK" -eq 1 ] && break
    [ $((i % 10)) -eq 0 ] && echo "  Waiting for services... (${i}s)"
    sleep 1
  done

  if [ "$API_OK" -eq 0 ] || [ "$UI_OK" -eq 0 ]; then
    echo "  WARNING: Services may still be starting. Check logs:"
    echo "    journalctl -u diffract-api -n 30"
    echo "    journalctl -u diffract-ui  -n 30"
  fi

  DOMAIN="$(detect_domain)"
  if echo "$DOMAIN" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || [ "$DOMAIN" = "localhost" ]; then
    URL="http://${DOMAIN}:3000/setup"
  else
    URL="https://${DOMAIN}/setup"
  fi
fi

# ── VPS web-stack chain (Linux only) ──────────────────────────────

WEB_STACK_DEPLOYED=0
if [ "$(uname)" != "Darwin" ] && command_exists systemctl; then
  DEPLOY_SCRIPT="$INSTALL_DIR/repo/scripts/deploy-vps.sh"

  # Prompt only when stdin is a real TTY (not a curl pipe)
  if [ -z "${DIFFRACT_DOMAIN:-}" ] && [ -t 0 ]; then
    printf "\n  Enter your public domain or IP for HTTPS (leave blank to skip): "
    read -r _domain_input
    [ -n "${_domain_input:-}" ] && DIFFRACT_DOMAIN="$_domain_input"
  fi

  if [ -n "${DIFFRACT_DOMAIN:-}" ]; then
    if [ -f "$DEPLOY_SCRIPT" ]; then
      echo ""
      echo "  ─────────────────────────────────────────────────────────"
      echo "  Chaining web-stack deploy for DIFFRACT_DOMAIN=${DIFFRACT_DOMAIN}..."
      echo "  ─────────────────────────────────────────────────────────"
      DIFFRACT_DOMAIN="${DIFFRACT_DOMAIN}" \
      REPO_DIR="$INSTALL_DIR/repo" \
      SANDBOX_NAME="${SANDBOX_NAME:-my-assistant}" \
        bash "$DEPLOY_SCRIPT"
      URL="https://${DIFFRACT_DOMAIN}/dashboard"
      WEB_STACK_DEPLOYED=1
    else
      echo "  WARNING: $DEPLOY_SCRIPT not found — skipping web-stack deploy"
    fi
  else
    echo ""
    echo "  ─────────────────────────────────────────────────────────"
    echo "  CLI-only install complete."
    echo "  To also deploy the web dashboard (Caddy, HTTPS, gateway),"
    echo "  re-run with DIFFRACT_DOMAIN set:"
    echo ""
    echo "    DIFFRACT_DOMAIN=yourdomain.com \\"
    echo "      bash <(curl -fsSL https://raw.githubusercontent.com/hrubee/Diffraction/main/install.sh)"
    echo "  ─────────────────────────────────────────────────────────"
  fi
fi

# ── Auto-open browser (best effort) ──────────────────────────────

if [ "$(uname)" = "Darwin" ]; then
  open "$URL" 2>/dev/null || true
elif [ -n "${DISPLAY:-}" ] && command_exists xdg-open; then
  xdg-open "$URL" 2>/dev/null || true
fi

# ── Final output ─────────────────────────────────────────────────

echo ""
echo "  ========================================="
echo "  Diffract installed successfully!"
echo "  ========================================="
echo ""
if [ "$WEB_STACK_DEPLOYED" -eq 1 ] 2>/dev/null; then
  echo "  Dashboard: $URL"
  echo ""
  echo "  Service logs:"
  echo "    journalctl -u diffract-api -f"
  echo "    journalctl -u diffract-ui  -f"
  echo "    journalctl -u caddy        -f"
else
  echo "  Next step:  diffract onboard"
  if [ -n "${URL:-}" ]; then
    echo "  Dev URL:    $URL"
  fi
fi
echo ""
