#!/bin/bash
# check-prereqs.sh - Verify prerequisites for youtube-search skill
# Outputs JSON envelope. Exit 0 always — readiness is in the JSON.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
check-prereqs.sh - Verify prerequisites for youtube-search skill

Usage: scripts/check-prereqs.sh

Checks for: python3, yt-dlp (pip package), jq.
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
  if ! command -v python3 &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 --version 2>&1 | awk '{print $2}')
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_ytdlp() {
  local name="yt-dlp"
  if ! python3 -m yt_dlp --version &>/dev/null 2>&1; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 -m yt_dlp --version 2>&1)
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
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
check_ytdlp
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
