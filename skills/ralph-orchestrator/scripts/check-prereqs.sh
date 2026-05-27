#!/usr/bin/env bash
set -euo pipefail

checks_json='[]'
ready=true

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

add_check() {
  local name="$1"
  local ok="$2"
  local note="$3"
  local item
  item="{\"name\":\"$(json_escape "$name")\",\"ok\":$ok,\"note\":\"$(json_escape "$note")\"}"
  if [ "$checks_json" = "[]" ]; then
    checks_json="[$item]"
  else
    checks_json="${checks_json%]} ,$item]"
  fi
}

if command -v bd >/dev/null 2>&1; then
  add_check "bd" "true" "$(command -v bd)"
else
  ready=false
  add_check "bd" "false" "bd command not found"
fi

if command -v git >/dev/null 2>&1; then
  add_check "git" "true" "$(command -v git)"
else
  ready=false
  add_check "git" "false" "git command not found"
fi

bd_ready_note="not checked"
if command -v bd >/dev/null 2>&1; then
  if bd ready >/dev/null 2>&1; then
    bd_ready_note="bd ready succeeded"
  else
    ready=false
    bd_ready_note="bd ready failed in current directory"
  fi
fi
add_check "bd-ready" "$([ "$bd_ready_note" = "bd ready succeeded" ] && echo true || echo false)" "$bd_ready_note"

printf '{"ready":%s,"checks":%s,"context":{"relay":"ralph-orchestrator"}}\n' "$ready" "$checks_json"
