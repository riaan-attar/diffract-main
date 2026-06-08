#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
# Diffract gateway watchdog — keeps the agent CHAT BACKEND alive.
#
# The dashboard (9119) is a separate process and is kept up by the
# sandbox-port-forwarder. NOTHING used to watch the OpenAI-compatible gateway on
# 8642 (the backend that actually answers chat messages), so a crashed gateway
# or a dead 8642 forward could silently 502 every "send" for hours. This service
# closes that gap: it continuously health-checks 8642 and recovers it.
#
# Installed + enabled by setup.sh, so EVERY Diffract deployment runs it.
#
# Recovery is least-disruptive first and capped, so it can never thrash:
#   * gateway daemon UP but 8642 path dead  → restart sandbox-port-forwarder
#     (its cleanup stops the stale ssh -L tunnel, then rebuilds the forward).
#   * gateway daemon DOWN                    → restart the sandbox container
#     (re-runs the entrypoint, which relaunches the gateway), then rebuild forwards.
#   * still down after MAX_RECOVERIES        → log a clear ALERT (and optional
#     webhook) and back off; a wedged gateway needs a manual recreate, which we
#     must NOT do automatically (it's destructive).
#
# Tunables via env: DIFFRACT_WATCHDOG_INTERVAL, DIFFRACT_GATEWAY_PORT,
# DIFFRACT_WATCHDOG_FAILS, DIFFRACT_WATCHDOG_MAX_RECOVERIES,
# DIFFRACT_WATCHDOG_ALERT_URL (optional webhook).
# ─────────────────────────────────────────────────────────────────────────
set -u

INTERVAL="${DIFFRACT_WATCHDOG_INTERVAL:-20}"
GATEWAY_PORT="${DIFFRACT_GATEWAY_PORT:-8642}"
FAIL_THRESHOLD="${DIFFRACT_WATCHDOG_FAILS:-2}"          # consecutive fails before acting (debounce)
MAX_RECOVERIES="${DIFFRACT_WATCHDOG_MAX_RECOVERIES:-4}" # then alert + back off
ALERT_URL="${DIFFRACT_WATCHDOG_ALERT_URL:-}"
DOCKER="${DOCKER_PATH:-docker}"
OPENSHELL="${OPENSHELL_PATH:-openshell}"
FORWARDER_SERVICE="sandbox-port-forwarder.service"
HEALTH_URL="http://127.0.0.1:${GATEWAY_PORT}/v1/models"

log() { echo "[gateway-watchdog] $*"; }

sandbox_name() { jq -r '.defaultSandbox' ~/.nemoclaw/sandboxes.json 2>/dev/null; }

resolve_cid() {
  "$DOCKER" ps -q -f "label=openshell.ai/managed-by=openshell" \
    -f "label=openshell.ai/sandbox-name=$1" 2>/dev/null | head -1
}

gateway_healthy() {
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$HEALTH_URL" 2>/dev/null)" = "200" ]
}

alert() {
  log "ALERT: $1"
  [ -n "$ALERT_URL" ] && curl -s -o /dev/null --max-time 8 -X POST "$ALERT_URL" \
    -H "Content-Type: application/json" \
    -d "{\"service\":\"diffract-gateway-watchdog\",\"level\":\"alert\",\"message\":\"$1\"}" 2>/dev/null || true
}

log "started (interval=${INTERVAL}s, port=${GATEWAY_PORT}, fail_threshold=${FAIL_THRESHOLD}, max_recoveries=${MAX_RECOVERIES})"

fails=0
recoveries=0
alerted=0

while true; do
  sleep "$INTERVAL"

  sb="$(sandbox_name)"
  { [ -z "$sb" ] || [ "$sb" = "null" ]; } && continue
  cid="$(resolve_cid "$sb")"
  [ -z "$cid" ] && continue   # sandbox not running (e.g. destroyed) — nothing to watch

  if gateway_healthy; then
    if [ "$recoveries" -gt 0 ] || [ "$fails" -gt 0 ]; then
      log "gateway healthy again (sandbox=$sb)"
    fi
    fails=0; recoveries=0; alerted=0
    continue
  fi

  fails=$((fails + 1))
  [ "$fails" -lt "$FAIL_THRESHOLD" ] && continue   # debounce transient blips

  if [ "$recoveries" -ge "$MAX_RECOVERIES" ]; then
    [ "$alerted" -eq 0 ] && { alert "gateway on '$sb' still down after ${MAX_RECOVERIES} recovery attempts — manual intervention (likely a sandbox recreate) required."; alerted=1; }
    continue
  fi

  recoveries=$((recoveries + 1))

  if "$DOCKER" exec "$cid" pgrep -f 'gateway run' >/dev/null 2>&1; then
    log "gateway 8642 unreachable but daemon is up (sandbox=$sb) — rebuilding forwards (attempt ${recoveries}/${MAX_RECOVERIES})"
    systemctl restart "$FORWARDER_SERVICE" 2>/dev/null || true
  else
    log "gateway daemon is DOWN (sandbox=$sb) — restarting container to relaunch (attempt ${recoveries}/${MAX_RECOVERIES})"
    "$DOCKER" restart "$cid" >/dev/null 2>&1 || true
    sleep 25
    systemctl restart "$FORWARDER_SERVICE" 2>/dev/null || true
  fi
  fails=0   # let the recovery take effect before counting failures again
done
