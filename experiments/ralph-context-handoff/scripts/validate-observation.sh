#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <run-dir> [pj-session-id|--preflight]" >&2
  exit 2
fi

RUN_DIR="$1"
MODE="postrun"
PJ_SESSION_ID=""

if [[ "${2:-}" == "--preflight" ]]; then
  MODE="preflight"
else
  PJ_SESSION_ID="${2:-}"
fi

if [[ ! -f "$RUN_DIR/RUN_INFO.env" ]]; then
  echo "FAIL missing RUN_INFO.env in $RUN_DIR" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$RUN_DIR/RUN_INFO.env"

failures=0

check_pass() {
  echo "PASS $1"
}

check_fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

[[ -d "$WORKSPACE" ]] && check_pass "workspace exists" || check_fail "workspace missing: $WORKSPACE"
[[ -f "$RUN_DIR/STARTER_PROMPT.md" ]] && check_pass "starter prompt exists" || check_fail "starter prompt missing"
[[ -f "$RUN_DIR/STARTER_PROMPT_NO_BUDGET.md" ]] && check_pass "no-budget prompt exists" || check_fail "no-budget prompt missing"

if [[ -d "$WORKSPACE" ]]; then
  ready_output="$(cd "$WORKSPACE" && bd ready 2>&1 || true)"
  if grep -Eq 'Ready: [1-9][0-9]* issues?' <<<"$ready_output"; then
    check_pass "bd ready still has remaining issues"
  else
    check_fail "bd ready does not show remaining issues"
  fi

  status_output="$(cd "$WORKSPACE" && git status --short --branch)"
  printf '%s\n' "$status_output" > "$WORKSPACE/observations/git-status.txt"
  if grep -q '^## ' <<<"$status_output"; then
    check_pass "git status captured"
  else
    check_fail "git status unavailable"
  fi

  if [[ -f "$WORKSPACE/results.log" ]]; then
    completed_count="$(grep -Ec '^issue-[0-9][0-9] complete$' "$WORKSPACE/results.log" || true)"
    echo "INFO completed result lines: $completed_count"
  else
    echo "INFO results.log not present yet"
  fi
fi

if [[ "$MODE" == "preflight" ]]; then
  if [[ -f "$HANDOFF_PATH" ]]; then
    check_fail "handoff already exists before run: $HANDOFF_PATH"
  else
    check_pass "handoff path is clear before run"
  fi
else
  if [[ -f "$HANDOFF_PATH" ]]; then
    check_pass "handoff exists at $HANDOFF_PATH"
    if grep -Eiq 'bd|issue|status|QA|next command|relevant files|handoff' "$HANDOFF_PATH"; then
      check_pass "handoff contains expected continuation vocabulary"
    else
      check_fail "handoff exists but lacks expected continuation vocabulary"
    fi
  else
    check_fail "handoff missing at $HANDOFF_PATH"
  fi
fi

if [[ "$MODE" == "preflight" ]]; then
  echo "INFO preflight mode; transcript checks skipped"
elif [[ -n "$PJ_SESSION_ID" ]]; then
  transcript="$WORKSPACE/observations/pj-chat-$PJ_SESSION_ID.json"
  if pj chat "$PJ_SESSION_ID" > "$transcript"; then
    check_pass "pj transcript captured"
    if grep -Eiq 'handoff|ralph-context-handoff|Context Budget Guardrail|fallback cycle cap|built-in chat compaction' "$transcript"; then
      check_pass "transcript contains handoff or guardrail evidence"
    else
      check_fail "transcript lacks handoff or guardrail evidence"
    fi
    if grep -Eiq 'Continuing .*compacted state|Continuing the Ralph relay from the compacted state' "$transcript"; then
      check_fail "transcript contains built-in compaction resume marker"
    else
      check_pass "transcript does not contain built-in compaction resume marker"
    fi
  else
    check_fail "pj chat failed for session $PJ_SESSION_ID"
  fi
else
  echo "INFO no pj session id supplied; transcript checks skipped"
fi

if [[ "$failures" -eq 0 ]]; then
  echo "Observation validation passed"
else
  echo "Observation validation failed with $failures failure(s)" >&2
fi

exit "$failures"
