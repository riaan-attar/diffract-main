#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────
# Diffract universal tool connector — securely wire a baked CLI tool's
# credentials to the agent so it can call the tool's API WITHOUT ever holding
# the secret.
#
# Reads agents/hermes/diffract-tools.json and, for one tool:
#   1. Registers an OpenShell `generic` provider holding the tool's secret(s)
#      and non-secret config. The sandbox only ever sees PLACEHOLDERS
#      (openshell:resolve:env:...); the OpenShell L7 proxy substitutes the real
#      values at egress — in headers AND query params. The agent never holds the
#      secret, and it's never written to the sandbox filesystem or the backups.
#   2. Attaches the provider to the sandbox (detach+re-attach forces injection
#      of newly-added credentials into a running sandbox — a gotcha).
#   3. Allows egress to ONLY the tool's API hosts, attributed to the tool's
#      binaries (OpenShell 0.0.39 fail-closes egress unless the peer binary is
#      named — empty `binaries` => denied).
#
# Secret + config VALUES are read from THIS PROCESS'S ENVIRONMENT (never passed
# on argv, so they don't leak into the process list). Set them before calling:
#
#   GHL_PRIVATE_TOKEN=xxx GHL_LOCATION_ID=yyy \
#     diffract-tool-connect.sh hermes ghl
#
# Usage: diffract-tool-connect.sh <sandbox> <tool> [registry.json]
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SANDBOX="${1:-}"
TOOL="${2:-}"
REGISTRY="${3:-${DIFFRACT_TOOLS_REGISTRY:-}}"

if [ -z "$SANDBOX" ] || [ -z "$TOOL" ]; then
  echo "usage: diffract-tool-connect.sh <sandbox> <tool> [registry.json]" >&2
  exit 2
fi

# Locate the registry if not given.
if [ -z "$REGISTRY" ]; then
  for c in \
    "$(dirname "$0")/../NemoClaw/agents/hermes/diffract-tools.json" \
    "/opt/nemoclaw-diffract/diffract-tools.json" \
    "/usr/local/share/diffract/diffract-tools.json"; do
    [ -f "$c" ] && REGISTRY="$c" && break
  done
fi
if [ -z "$REGISTRY" ] || [ ! -f "$REGISTRY" ]; then
  echo "[connect] tool registry not found (pass it as arg 3 or set DIFFRACT_TOOLS_REGISTRY)" >&2
  exit 1
fi

# Pull this tool's wiring out of the registry as shell-eval'able assignments.
eval "$(node -e '
const fs = require("fs");
const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const t = (reg.tools || []).find(x => x.name === process.argv[2]);
if (!t) { console.error("[connect] tool not in registry: " + process.argv[2]); process.exit(3); }
const sh = s => "'"'"'" + String(s).replace(/'"'"'/g, "'"'"'\\'"'"''"'"'") + "'"'"'";
const cfg = Object.keys(t.configEnv || {});
console.log("SECRET_ENV=" + sh(t.secretEnv || ""));
console.log("CONFIG_ENVS=(" + cfg.map(sh).join(" ") + ")");
console.log("API_HOSTS=(" + (t.apiHosts || []).map(sh).join(" ") + ")");
console.log("BINARIES=(" + (t.binaries || []).map(sh).join(" ") + ")");
' "$REGISTRY" "$TOOL")"

# Collect the credential keys we will register (secret + non-secret config), and
# verify each has a value in the environment.
CRED_KEYS=()
[ -n "${SECRET_ENV:-}" ] && CRED_KEYS+=("$SECRET_ENV")
for k in "${CONFIG_ENVS[@]:-}"; do [ -n "$k" ] && CRED_KEYS+=("$k"); done

missing=()
for k in "${CRED_KEYS[@]:-}"; do
  [ -z "$k" ] && continue
  if [ -z "${!k:-}" ]; then missing+=("$k"); fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "[connect] missing values in environment: ${missing[*]}" >&2
  echo "[connect] re-run with e.g.: ${missing[*]/%/=<value>} diffract-tool-connect.sh $SANDBOX $TOOL" >&2
  exit 1
fi

# --credential <KEY> (env-lookup form) reads the value from THIS process's env,
# so secrets never appear in argv / the process list.
cred_args=()
for k in "${CRED_KEYS[@]:-}"; do [ -n "$k" ] && cred_args+=(--credential "$k"); done

echo "[connect] registering provider '$TOOL' (generic) with: ${CRED_KEYS[*]}"
if openshell provider get "$TOOL" >/dev/null 2>&1; then
  openshell provider update "$TOOL" "${cred_args[@]}" >/dev/null
else
  openshell provider create --name "$TOOL" --type generic "${cred_args[@]}" >/dev/null
fi

echo "[connect] attaching to sandbox '$SANDBOX' (detach+attach forces re-injection)"
openshell sandbox provider detach "$SANDBOX" "$TOOL" >/dev/null 2>&1 || true
openshell sandbox provider attach "$SANDBOX" "$TOOL" >/dev/null

echo "[connect] allowing egress to: ${API_HOSTS[*]:-(none)}"
for host in "${API_HOSTS[@]:-}"; do
  [ -z "$host" ] && continue
  bin_args=()
  for b in "${BINARIES[@]:-}"; do [ -n "$b" ] && bin_args+=(--binary "$b"); done
  openshell policy update "$SANDBOX" \
    --add-endpoint "${host}:full" \
    --rule-name "${TOOL}-api" \
    "${bin_args[@]}" --wait >/dev/null
  echo "[connect]   allowed ${host} (binaries: ${BINARIES[*]:-any})"
done

echo "[connect] done — '$TOOL' is wired to sandbox '$SANDBOX'. The secret stays host-side; the agent sees only placeholders."
