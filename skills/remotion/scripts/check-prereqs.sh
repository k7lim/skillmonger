#!/bin/bash
# check-prereqs.sh - Verify Remotion prerequisites
# Outputs JSON for agent consumption
set -euo pipefail

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

check_ffmpeg() {
  if ! command -v ffmpeg &>/dev/null; then
    echo '{"name":"ffmpeg","status":"missing","required":">=4.1","note":"remotion auto-installs if missing"}'
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

check_npm() {
  if ! command -v npm &>/dev/null; then
    echo '{"name":"npm","status":"missing"}'
    return
  fi
  version=$(npm -v)
  echo "{\"name\":\"npm\",\"status\":\"ok\",\"version\":\"$version\"}"
}

# Output as JSON array
echo "["
check_node
echo ","
check_npm
echo ","
check_ffmpeg
echo "]"
