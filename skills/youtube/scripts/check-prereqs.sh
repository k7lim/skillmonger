#!/bin/bash
# check-prereqs.sh - Verify prerequisites for the youtube orchestrator skill
# Outputs JSON to stdout. Exit 0 always — readiness is in the JSON, not the exit code.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: scripts/check-prereqs.sh [--help]

Check whether required tools and sibling skills are installed for the
youtube orchestrator skill. Outputs a JSON object to stdout with:
  - ready: true/false
  - checks: array of {name, status, version?, note?}
  - context: skill directory info

Flags:
  --help    Show this help message and exit

Examples:
  scripts/check-prereqs.sh
  scripts/check-prereqs.sh | jq '.checks[] | select(.status=="missing")'
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

checks=()
all_ok=true

# --- Check functions ---

check_python3() {
  local name="python3"
  local candidate version
  for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10 /opt/homebrew/bin/python3; do
    if command -v "$candidate" &>/dev/null && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
      version=$("$candidate" --version 2>&1 | awk '{print $2}')
      echo "check: python3 ... ok ($version)" >&2
      checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
      return
    fi
  done
  echo "check: python3 ... missing (3.10+ required)" >&2
  checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"Python 3.10 or newer required\"}")
  all_ok=false
}

check_jq() {
  local name="jq"
  if ! command -v jq &>/dev/null; then
    echo "check: jq ... missing" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(jq --version 2>&1 || echo "unknown")
  echo "check: jq ... ok ($version)" >&2
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_npx() {
  local name="npx"
  if ! command -v npx &>/dev/null; then
    echo "check: npx ... missing" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"install Node.js 18 or newer\"}")
    all_ok=false
    return
  fi
  local version
  version=$(npx --version 2>&1)
  echo "check: npx ... ok ($version)" >&2
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_ffmpeg() {
  local name="ffmpeg"
  if ! command -v ffmpeg &>/dev/null; then
    echo "check: ffmpeg ... missing (optional)" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"optional, needed for --download-sections clip extraction\"}")
    # Not setting all_ok=false — ffmpeg is optional
    return
  fi
  local version
  version=$(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')
  echo "check: ffmpeg ... ok ($version)" >&2
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_sibling_skill() {
  local name="$1"
  local marker="$2"
  local path="$SKILL_DIR/../$name/$marker"
  if [ -f "$path" ]; then
    echo "check: $name ... ok" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"ok\"}")
  else
    echo "check: $name ... missing (sibling skill not deployed)" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"note\":\"sibling skill not deployed\"}")
    all_ok=false
  fi
}

# --- Run checks ---
check_python3
check_jq
check_npx
check_ffmpeg
check_sibling_skill "youtube-search" "SKILL.md"
check_sibling_skill "youtube-clip" "SKILL.md"
check_sibling_skill "yt-dlp" "scripts/run"

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
  "context": {
    "skill_dir": "$SKILL_DIR",
    "has_youtube_search": $([ -f "$SKILL_DIR/../youtube-search/SKILL.md" ] && echo true || echo false),
    "has_youtube_clip": $([ -f "$SKILL_DIR/../youtube-clip/SKILL.md" ] && echo true || echo false)
  }
}
EOF
