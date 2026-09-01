#!/bin/bash
# check-prereqs.sh - Report the name to yell, or candidates when none is stored.
#
# Output (stdout): {"ready": bool, "checks": [...], "context": {...}}
# Exit: 0 always; readiness is in the JSON, not the exit code.
#
# Sources, first wins:
#   1. $YELL_AT_ME_NAME
#   2. ${XDG_CONFIG_HOME:-$HOME/.config}/yell-at-me/name  (written by set-name.sh)
#
# context.yell is the form to write (caps, exclamation mark), so SKILL.md never
# has to derive it. context.candidates are defaults for the onboarding question:
# the first word of `git config user.name`, then $USER and $LOGNAME.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yell-at-me"
NAME_FILE="$CONFIG_DIR/name"

# JSON string literal: escapes backslash, quote, tab, newline, carriage return.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
first_word() { printf '%s' "$1" | awk '{print $1; exit}'; }

# --- The stored name ---

name=""
source=""
if [ -n "${YELL_AT_ME_NAME:-}" ]; then
  name="$YELL_AT_ME_NAME"
  source="env"
elif [ -s "$NAME_FILE" ]; then
  name="$(head -n 1 "$NAME_FILE")"
  source="file"
fi

# --- Candidates (no arrays: bash 3.2 under set -u) ---

candidates_json=""
seen=" "
add_candidate() {
  local c
  c="$(upper "$(first_word "$1")")"
  [ -n "$c" ] || return 0
  case "$seen" in *" $c "*) return 0 ;; esac
  seen="$seen$c "
  [ -z "$candidates_json" ] || candidates_json="$candidates_json,"
  candidates_json="$candidates_json$(json_str "$c")"
}
add_candidate "$(git config --get user.name 2>/dev/null || true)"
add_candidate "${USER:-}"
add_candidate "${LOGNAME:-}"

# --- Output ---

set_with='scripts/set-name.sh \"<name>\"'
if [ -n "$name" ]; then
  ready=true
  yell="$(upper "$name")!"
  check="{\"name\":\"yell-name\",\"status\":\"ok\",\"value\":$(json_str "$name"),\"source\":\"$source\",\"path\":$(json_str "$NAME_FILE")}"
else
  ready=false
  yell=""
  check="{\"name\":\"yell-name\",\"status\":\"missing\",\"path\":$(json_str "$NAME_FILE"),\"fix\":\"$set_with\"}"
fi

cat <<JSON
{
  "ready": $ready,
  "checks": [$check],
  "context": {
    "name": $(json_str "$name"),
    "yell": $(json_str "$yell"),
    "source": $(json_str "$source"),
    "candidates": [$candidates_json],
    "name_file": $(json_str "$NAME_FILE"),
    "set_with": "$set_with"
  }
}
JSON
