#!/bin/bash
# set-name.sh - Store the name to yell.
#
# Usage: scripts/set-name.sh "<name>"
#
# Writes ${XDG_CONFIG_HOME:-$HOME/.config}/yell-at-me/name and prints
#   {"ok":true,"name":"...","yell":"...!","path":"..."}
# A bad name (empty, more than one line, over 40 characters) prints
#   {"ok":false,"error":"...","usage":"..."} and exits 1.
# Surrounding whitespace and a trailing "!" are dropped; the yell form is
# derived, not stored.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yell-at-me"
NAME_FILE="$CONFIG_DIR/name"
MAX_LEN=40

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

fail() {
  printf '{"ok":false,"error":%s,"usage":"scripts/set-name.sh \\"<name>\\""}\n' "$(json_str "$1")"
  exit 1
}

raw="${1:-}"
case "$raw" in *$'\n'*|*$'\r'*) fail "name must be one line" ;; esac
name="$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/!*$//' -e 's/[[:space:]]*$//')"

[ -n "$name" ] || fail "name is empty"
[ "${#name}" -le "$MAX_LEN" ] || fail "name is longer than $MAX_LEN characters"

if ! mkdir -p "$CONFIG_DIR" 2>/dev/null || ! printf '%s\n' "$name" > "$NAME_FILE" 2>/dev/null; then
  fail "cannot write $NAME_FILE; use YELL_AT_ME_NAME in the environment instead"
fi

yell="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')!"
printf '{"ok":true,"name":%s,"yell":%s,"path":%s}\n' \
  "$(json_str "$name")" "$(json_str "$yell")" "$(json_str "$NAME_FILE")"
