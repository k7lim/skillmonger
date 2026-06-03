#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

score=1
notes=()

has_commit=0
has_status=0
has_remote=0
has_verify=0
has_residuals=0

printf '%s' "$lower" | grep -Eq 'commit|committed|[0-9a-f]{7,}' && has_commit=1
printf '%s' "$lower" | grep -Eq 'status|working tree|uncommitted|left uncommitted|clean' && has_status=1
printf '%s' "$lower" | grep -Eq 'remote|upstream|push|pushed|no remote|origin' && has_remote=1
printf '%s' "$lower" | grep -Eq 'test|lint|build|validate|verification|not run|unable to run' && has_verify=1
printf '%s' "$lower" | grep -Eq 'left uncommitted|remaining|residual|untracked|unstaged|clean' && has_residuals=1

[ "$has_commit" -eq 1 ] || notes+=("missing commit summary")
[ "$has_status" -eq 1 ] || notes+=("missing final working-tree status")
[ "$has_remote" -eq 1 ] || notes+=("missing remote/upstream state")
[ "$has_verify" -eq 1 ] || notes+=("missing verification result")
[ "$has_residuals" -eq 1 ] || notes+=("missing residual-change accounting")

passed=$((has_commit + has_status + has_remote + has_verify + has_residuals))
case "$passed" in
  5) score=5 ;;
  4) score=4 ;;
  3) score=3 ;;
  2) score=2 ;;
  *) score=1 ;;
esac

if [ "${#notes[@]}" -eq 0 ]; then
  note="final report covers commits, status, remote state, verification, and residual changes"
else
  note="$(IFS='; '; printf '%s' "${notes[*]}")"
fi

printf '{"outcome":%s,"note":"%s","checks":{"commit_summary":%s,"final_status":%s,"remote_state":%s,"verification":%s,"residual_changes":%s},"source":"script"}\n' \
  "$score" \
  "$(printf '%s' "$note" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
  "$([ "$has_commit" -eq 1 ] && printf true || printf false)" \
  "$([ "$has_status" -eq 1 ] && printf true || printf false)" \
  "$([ "$has_remote" -eq 1 ] && printf true || printf false)" \
  "$([ "$has_verify" -eq 1 ] && printf true || printf false)" \
  "$([ "$has_residuals" -eq 1 ] && printf true || printf false)"
