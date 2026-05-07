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
  if ! command -v python3 &>/dev/null; then
    echo "check: python3 ... missing" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 --version 2>&1 | awk '{print $2}')
  echo "check: python3 ... ok ($version)" >&2
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
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

check_yt_dlp() {
  local name="yt-dlp"
  if ! python3 -m yt_dlp --version &>/dev/null 2>&1; then
    echo "check: yt-dlp ... missing" >&2
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 -m yt_dlp --version 2>&1)
  echo "check: yt-dlp ... ok ($version)" >&2
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
check_yt_dlp
check_ffmpeg
check_sibling_skill "youtube-search" "SKILL.md"
check_sibling_skill "youtube-clip" "SKILL.md"

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
