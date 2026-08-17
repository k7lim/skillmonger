#!/bin/bash
# check-prereqs.sh - Verify prerequisites for youtube-clip skill
# Outputs JSON for agent consumption. Exit 0 always — readiness is in the JSON.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
check-prereqs.sh - Verify prerequisites for youtube-clip skill

Usage: scripts/check-prereqs.sh

Checks: Python 3.10+, npx, jq, sibling yt-dlp runner; yt-fts (optional)
Output: JSON to stdout with {"ready": bool, "checks": [...], "context": {}}
Exit:   Always 0. Readiness is in the JSON, not the exit code.

Examples:
  scripts/check-prereqs.sh
  scripts/check-prereqs.sh | jq '.ready'
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
      version=$("$candidate" --version 2>&1 | sed 's/Python //')
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
  version=$(jq --version 2>&1 | sed 's/jq-//')
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_ytfts() {
  local name="yt-fts"
  if ! command -v yt-fts &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"optional — enables channel indexing and semantic search\"}")
    return
  fi
  local version
  version=$(yt-fts --version 2>&1 | head -1 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\",\"note\":\"optional — enables channel indexing and semantic search\"}")
}

# --- Run checks ---
check_python3
check_npx
check_runner
check_jq
check_ytfts

# --- Output JSON ---
checks_json=""
for i in "${!checks[@]}"; do
  if [ "$i" -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

cat << EOF
{
  "ready": $all_ok,
  "checks": [$checks_json],
  "context": {}
}
EOF
