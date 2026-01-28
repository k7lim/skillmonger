#!/bin/bash
# check-prereqs.sh - Verify ai-talking-heads prerequisites
# Outputs JSON for agent consumption.
#
# Checks: node, npm, ffmpeg (soft-fail), yt-dlp (optional),
# plus context about remotion skill availability.
#
# Usage:
#   scripts/check-prereqs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"

check_node() {
  if ! command -v node &>/dev/null; then
    echo '{"name":"node","status":"missing","required":">=14"}'
    return
  fi
  version=$(node -v | sed 's/v//')
  major=$(echo "$version" | cut -d. -f1)
  if [ "$major" -ge 14 ]; then
    echo "{\"name\":\"node\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\">=14\"}"
  else
    echo "{\"name\":\"node\",\"status\":\"outdated\",\"version\":\"$version\",\"required\":\">=14\"}"
  fi
}

check_npm() {
  if ! command -v npm &>/dev/null; then
    echo '{"name":"npm","status":"missing"}'
    return
  fi
  version=$(npm -v)
  echo "{\"name\":\"npm\",\"status\":\"ok\",\"version\":\"$version\"}"
}

check_ffmpeg() {
  if ! command -v ffmpeg &>/dev/null; then
    echo '{"name":"ffmpeg","status":"missing","required":">=4.1","note":"needed for audio/video processing"}'
    return
  fi
  version=$(ffmpeg -version 2>&1 | head -1 | sed -n 's/.*version \([0-9.]*\).*/\1/p')
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  if [ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 1 ]; }; then
    echo "{\"name\":\"ffmpeg\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\">=4.1\"}"
  else
    echo "{\"name\":\"ffmpeg\",\"status\":\"outdated\",\"version\":\"$version\",\"required\":\">=4.1\"}"
  fi
}

check_ytdlp() {
  if ! command -v yt-dlp &>/dev/null; then
    echo '{"name":"yt-dlp","status":"missing","note":"optional, for downloading reference footage"}'
    return
  fi
  version=$(yt-dlp --version 2>/dev/null || echo "unknown")
  echo "{\"name\":\"yt-dlp\",\"status\":\"ok\",\"version\":\"$version\",\"note\":\"optional\"}"
}

# Detect remotion skill availability
detect_remotion() {
  local remotion_available=false
  local remotion_path=""

  # Check in sibling skills directory
  if [ -f "$PROJECT_ROOT/skills/remotion/SKILL.md" ]; then
    remotion_available=true
    remotion_path="$PROJECT_ROOT/skills/remotion"
  fi

  echo "{\"remotion_skill_available\":$remotion_available,\"remotion_path\":\"$remotion_path\"}"
}

# Determine overall readiness: node + npm required; ffmpeg and yt-dlp are soft-fail
node_json=$(check_node)
npm_json=$(check_npm)
ffmpeg_json=$(check_ffmpeg)
ytdlp_json=$(check_ytdlp)
context_json=$(detect_remotion)

ready=true
if echo "$node_json" | grep -q '"status":"missing"\|"status":"outdated"'; then
  ready=false
fi
if echo "$npm_json" | grep -q '"status":"missing"'; then
  ready=false
fi

cat << EOF
{
  "ready": $ready,
  "checks": [
    $node_json,
    $npm_json,
    $ffmpeg_json,
    $ytdlp_json
  ],
  "context": $context_json
}
EOF
