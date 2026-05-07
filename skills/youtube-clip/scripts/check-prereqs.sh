#!/bin/bash
# check-prereqs.sh - Verify prerequisites for youtube-clip skill
# Outputs JSON for agent consumption. Exit 0 always — readiness is in the JSON.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
check-prereqs.sh - Verify prerequisites for youtube-clip skill

Usage: scripts/check-prereqs.sh

Checks: python3, yt-dlp, jq (required); yt-fts (optional)
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
  if ! command -v python3 &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 --version 2>&1 | sed 's/Python //')
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
check_ytdlp
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
