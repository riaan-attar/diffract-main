#!/bin/bash
# Keep the Hermes agent's home (/sandbox/.hermes) usable by the sandbox-user gateway.
#
# Root cause: `hermes dashboard` runs as ROOT and writes files all over
# /sandbox/.hermes (config.yaml, cron/jobs.json, profiles/*, runtime state) owned
# root:root. The `hermes gateway run` (chat + cron) runs as the low-priv `sandbox`
# user and cannot read root-owned mode-600/private files -> config reload falls
# back to a no-inference default (HTTP 500), and the cron poller errors
# ("Permission denied reading jobs.json") so scheduled jobs never run.
#
# Fix: (1) setgid every dir so new root-written files inherit group=sandbox, and
# (2) hand the gateway ownership of anything root wrote in its own home. This is a
# STOPGAP — the structural fix is to launch `hermes dashboard` as the sandbox user
# (then nothing it writes is root-owned). See setup.sh / NemoClaw runtime.
set -u
DOCKER="${DOCKER_PATH:-docker}"
INTERVAL="${DIFFRACT_GUARD_INTERVAL:-5}"
HOME_DIR="${DIFFRACT_AGENT_HOME:-/sandbox/.hermes}"
sandbox_name(){ jq -r '.defaultSandbox' ~/.nemoclaw/sandboxes.json 2>/dev/null; }
resolve_cid(){ "$DOCKER" ps -q -f "label=openshell.ai/managed-by=openshell" -f "label=openshell.ai/sandbox-name=$1" 2>/dev/null | head -1; }
echo "[config-guard] started (setgid + reclaim root-owned files under $HOME_DIR, every ${INTERVAL}s)"
while true; do
  sb="$(sandbox_name)"; { [ -z "$sb" ] || [ "$sb" = "null" ]; } && { sleep "$INTERVAL"; continue; }
  cid="$(resolve_cid "$sb")"; [ -z "$cid" ] && { sleep "$INTERVAL"; continue; }
  "$DOCKER" exec "$cid" sh -c '
    d="'"$HOME_DIR"'"; [ -d "$d" ] || exit 0
    # 1. setgid all dirs so future root writes inherit group=sandbox
    find "$d" -type d ! -perm -2000 -exec chmod g+s {} + 2>/dev/null
    # 2. reclaim anything root wrote in the gateway home (only acts if present)
    if [ -n "$(find "$d" -user root -print -quit 2>/dev/null)" ]; then
      find "$d" -user root -exec chown -h sandbox:sandbox {} + 2>/dev/null
      echo "[config-guard] reclaimed root-owned files under .hermes"
    fi
  ' 2>/dev/null
  sleep "$INTERVAL"
done
