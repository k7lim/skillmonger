#!/bin/bash
# check-prereqs.sh - Verify prerequisites for youtube-search skill
# Outputs JSON envelope. Exit 0 always — readiness is in the JSON.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
check-prereqs.sh - Verify prerequisites for youtube-search skill

Usage: scripts/check-prereqs.sh

Checks for: Python 3.10+, npx, jq, and the sibling yt-dlp runner.
Outputs a JSON envelope to stdout with ready: true/false and per-tool status.
Exit code is always 0 — readiness is in the JSON, not the exit code.

Examples:
  scripts/check-prereqs.sh
  scripts/check-prereqs.sh | jq '.data.ready'
USAGE
  exit 0
fi

checks=()
all_ok=true

check_python3() {
  local name="python3"
  local candidate version
  for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10 /opt/homebrew/bin/python3; do
    if command -v "$candidate" &>/dev/null && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
      version=$("$candidate" --version 2>&1 | awk '{print $2}')
      checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
      return
    fi
  done
  checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"Python 3.10 or newer required\"}")
  all_ok=false
}

check_npx() {
  if ! command -v npx &>/dev/null; then
    checks+=("{\"name\":\"npx\",\"status\":\"missing\",\"note\":\"install Node.js 18 or newer\"}")
    all_ok=false
    return
  fi
  checks+=("{\"name\":\"npx\",\"status\":\"ok\",\"version\":\"$(npx --version 2>&1)\"}")
}

check_runner() {
  local runner="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/yt-dlp/scripts/run"
  if [[ ! -x "$runner" ]]; then
    checks+=("{\"name\":\"yt-dlp-runner\",\"status\":\"missing\",\"note\":\"deploy sibling yt-dlp skill\"}")
    all_ok=false
    return
  fi
  checks+=("{\"name\":\"yt-dlp-runner\",\"status\":\"ok\"}")
}

check_jq() {
  local name="jq"
  if ! command -v jq &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(jq --version 2>&1 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

# --- Run checks ---
check_python3
check_npx
check_runner
check_jq

# --- Build JSON output ---
checks_json=""
for i in "${!checks[@]}"; do
  if [ "$i" -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

cat << EOF
{"success":true,"data":{"ready":$all_ok},"meta":{"checks":[$checks_json]}}
EOF
