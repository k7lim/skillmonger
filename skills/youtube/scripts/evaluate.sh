#!/bin/bash
# evaluate.sh - Hybrid evaluation for youtube orchestrator output
# Checks verifiable aspects of the workflow execution log.
# Reads workflow log from stdin or file argument.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: scripts/evaluate.sh [OPTIONS] [LOG_FILE]

Evaluate a youtube orchestrator workflow log for quality. Checks whether
the agent used youtube-search, paused for user vetting, applied rate
limiting, and got approval before actuator commands.

Reads from LOG_FILE if provided, otherwise reads from stdin.

Output: JSON to stdout with {outcome: 1-5, note, checks, source}.

Flags:
  --help    Show this help message and exit

Examples:
  scripts/evaluate.sh session.log
  echo "$LOG" | scripts/evaluate.sh
  scripts/evaluate.sh session.log | jq '.outcome'
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
elif [ $# -ge 1 ] && [ ! -f "$1" ]; then
  echo "Error: file not found: $1" >&2
  echo "Expected: path to a workflow log file, or pipe log via stdin" >&2
  echo "Try: scripts/evaluate.sh --help" >&2
  exit 1
elif [ -t 0 ]; then
  echo "Error: no input provided" >&2
  echo "Expected: workflow log via file argument or stdin" >&2
  echo "Try: scripts/evaluate.sh session.log" >&2
  echo "  or: echo \"\$LOG\" | scripts/evaluate.sh" >&2
  exit 1
else
  INPUT=$(cat)
fi

score=5
note=""
checks_json=""

add_check() {
  local name="$1" passed="$2" detail="$3"
  if [ -n "$checks_json" ]; then checks_json+=","; fi
  checks_json+="\"$name\":{\"passed\":$passed,\"detail\":\"$detail\"}"
}

# Check 1: Did the agent use youtube-search?
if echo "$INPUT" | grep -qi "youtube-search/scripts/search\|scripts/search.*--limit"; then
  echo "eval: used_search ... pass" >&2
  add_check "used_search" "true" "youtube-search invoked"
else
  echo "eval: used_search ... FAIL (no youtube-search invocation found in log)" >&2
  add_check "used_search" "false" "no youtube-search invocation detected"
  score=$((score - 1))
fi

# Check 2: Did the agent pause for user vetting?
if echo "$INPUT" | grep -qiE "approv|confirm|which.*video|select|pick|vet|would you like to proceed|before (I |we )?(proceed|download|continue)"; then
  echo "eval: user_vetting ... pass" >&2
  add_check "user_vetting" "true" "user vetting step detected"
else
  echo "eval: user_vetting ... FAIL (no vetting/approval language found)" >&2
  add_check "user_vetting" "false" "no user vetting pause detected"
  score=$((score - 2))
fi

# Check 3: Did the agent use rate limiting for batch operations?
if echo "$INPUT" | grep -qiE "sleep|paus|rate.?limit|batch|pacing"; then
  echo "eval: rate_limiting ... pass" >&2
  add_check "rate_limiting" "true" "rate limiting awareness detected"
else
  # Only penalize if batch operation was involved
  if echo "$INPUT" | grep -qiE "batch|bulk|multiple|each.*movie|each.*video|iterate"; then
    echo "eval: rate_limiting ... FAIL (batch operation without rate limiting)" >&2
    add_check "rate_limiting" "false" "batch operation without rate limiting"
    score=$((score - 1))
  else
    echo "eval: rate_limiting ... pass (single operation, not required)" >&2
    add_check "rate_limiting" "true" "single operation, rate limiting not required"
  fi
fi

# Check 4: Did actuator commands get user approval?
if echo "$INPUT" | grep -qiE "yt.dlp|download|explore.*\.html"; then
  if echo "$INPUT" | grep -qiB5 "approv\|confirm\|proceed\|yes\|go ahead" | grep -qiE "yt.dlp\|download\|explore"; then
    echo "eval: actuator_approval ... pass" >&2
    add_check "actuator_approval" "true" "actuator had approval"
  else
    echo "eval: actuator_approval ... FAIL (actuator may have run without approval)" >&2
    add_check "actuator_approval" "false" "actuator may have run without explicit approval"
    score=$((score - 1))
  fi
else
  echo "eval: actuator_approval ... pass (no actuators used)" >&2
  add_check "actuator_approval" "true" "no actuator commands used"
fi

# Clamp score
if [ "$score" -lt 1 ]; then score=1; fi

if [ "$score" -lt 4 ]; then
  note="Workflow gaps detected; see checks for details"
fi

cat << EOF
{"outcome":$score,"note":"$note","checks":{$checks_json},"source":"script"}
EOF
