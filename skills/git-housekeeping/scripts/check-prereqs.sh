#!/usr/bin/env bash
set -euo pipefail

json_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

if ! command -v git >/dev/null 2>&1; then
  printf '{"ready":false,"checks":[{"name":"git","ok":false,"note":"git not found on PATH"}],"context":{}}\n'
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '{"ready":false,"checks":[{"name":"git-worktree","ok":false,"note":"current directory is not inside a Git worktree"}],"context":{"git_available":true}}\n'
  exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || printf '')"
branch="$(git branch --show-current 2>/dev/null || printf '')"
head_sha="$(git rev-parse --short HEAD 2>/dev/null || printf '')"
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || printf '')"
remote_count="$(git remote 2>/dev/null | wc -l | tr -d ' ')"
dirty_count="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

ahead=0
behind=0
if [ -n "$upstream" ]; then
  counts="$(git rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || printf '0 0')"
  behind="$(printf '%s' "$counts" | awk '{print $1}')"
  ahead="$(printf '%s' "$counts" | awk '{print $2}')"
fi

ready=true
checks='{"name":"git","ok":true,"note":"git found"},{"name":"git-worktree","ok":true,"note":"inside a Git worktree"}'
if [ "$dirty_count" -gt 0 ]; then
  checks="$checks"',{"name":"working-tree","ok":false,"note":"working tree has local changes"}'
else
  checks="$checks"',{"name":"working-tree","ok":true,"note":"working tree clean"}'
fi

printf '{"ready":%s,"checks":[%s],"context":{"root":"%s","branch":"%s","head":"%s","upstream":"%s","remote_count":%s,"dirty_count":%s,"ahead":%s,"behind":%s}}\n' \
  "$ready" \
  "$checks" \
  "$(json_string "$root")" \
  "$(json_string "$branch")" \
  "$(json_string "$head_sha")" \
  "$(json_string "$upstream")" \
  "$remote_count" \
  "$dirty_count" \
  "$ahead" \
  "$behind"
