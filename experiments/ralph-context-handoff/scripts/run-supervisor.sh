#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<EOF_USAGE
usage: $0 [options] <workspace>

Options:
  --harness codex|claude|kimi
  --mode budget|no-budget
  --token-budget N
  --max-hops N
  --max-issues-total N
  --handoff-dir DIR
  --run-id ID
  --validate-cmd CMD
  --dry-run
  --no-yolo
  -h, --help
EOF_USAGE
}

die_usage() {
  echo "error: $1" >&2
  usage
  exit 2
}

is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

timestamp_run_id() {
  date -u +%Y%m%dT%H%M%SZ
}

resolve_path() {
  local path="$1"
  cd "$path" && pwd -P
}

extract_experiment_run_id() {
  local workspace="$1"
  local parent
  local grandparent

  parent="$(basename "$(dirname "$workspace")")"
  grandparent="$(basename "$(dirname "$(dirname "$workspace")")")"

  if [[ "$(basename "$workspace")" == "workspace" && "$grandparent" == "runs" ]]; then
    printf '%s\n' "$parent"
  else
    printf 'unknown\n'
  fi
}

assert_sandbox_for_yolo() {
  local workspace="$1"

  case "$workspace" in
    "$HOME"/Development/sandbox|"$HOME"/Development/sandbox/*) ;;
    *)
      echo "Refusing yolo supervisor outside ~/Development/sandbox: $workspace" >&2
      exit 10
      ;;
  esac
}

write_run_env() {
  local path="$1"

  cat > "$path" <<EOF_RUN_ENV
SUPERVISOR_RUN_ID=$RUN_ID
EXPERIMENT_RUN_ID=$EXPERIMENT_RUN_ID
WORKSPACE=$WORKSPACE
RUN_DIR=$RUN_DIR
HARNESS=$HARNESS
MODE=$MODE
TOKEN_BUDGET=$TOKEN_BUDGET
MAX_HOPS=$MAX_HOPS
MAX_ISSUES_TOTAL=$MAX_ISSUES_TOTAL
HANDOFF_DIR=$HANDOFF_DIR
VALIDATE_CMD=$VALIDATE_CMD
DRY_RUN=$DRY_RUN
NO_YOLO=$NO_YOLO
EOF_RUN_ENV
}

write_prompt() {
  local path="$1"
  local hop="$2"
  local handoff_path="$3"
  local previous_handoff="$4"

  cat > "$path" <<EOF_PROMPT
\$ralph-orchestrator

Continue or start the Ralph relay for this workspace.

Run id: $RUN_ID
Hop: $hop
Expected handoff path: $handoff_path

If a prior handoff is supplied, read it first and do not reread the previous chat:
$previous_handoff

No prior handoff is expected for hop 1. If the placeholder above is empty or says none, start from the workspace state and the BEADS queue.

Use one worker subagent at a time. Process multiple BEADS issues until the context-budget guardrail says handoff is due. When handoff is due, write the expected handoff path and stop.
EOF_PROMPT
}

HARNESS="codex"
MODE="no-budget"
TOKEN_BUDGET="60000"
MAX_HOPS="8"
MAX_ISSUES_TOTAL="0"
HANDOFF_DIR="/private/tmp"
RUN_ID="$(timestamp_run_id)"
VALIDATE_CMD=""
DRY_RUN="0"
NO_YOLO="0"
WORKSPACE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --harness)
      [[ $# -ge 2 ]] || die_usage "--harness requires a value"
      HARNESS="$2"
      shift 2
      ;;
    --harness=*)
      HARNESS="${1#*=}"
      shift
      ;;
    --mode)
      [[ $# -ge 2 ]] || die_usage "--mode requires a value"
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --token-budget)
      [[ $# -ge 2 ]] || die_usage "--token-budget requires a value"
      TOKEN_BUDGET="$2"
      shift 2
      ;;
    --token-budget=*)
      TOKEN_BUDGET="${1#*=}"
      shift
      ;;
    --max-hops)
      [[ $# -ge 2 ]] || die_usage "--max-hops requires a value"
      MAX_HOPS="$2"
      shift 2
      ;;
    --max-hops=*)
      MAX_HOPS="${1#*=}"
      shift
      ;;
    --max-issues-total)
      [[ $# -ge 2 ]] || die_usage "--max-issues-total requires a value"
      MAX_ISSUES_TOTAL="$2"
      shift 2
      ;;
    --max-issues-total=*)
      MAX_ISSUES_TOTAL="${1#*=}"
      shift
      ;;
    --handoff-dir)
      [[ $# -ge 2 ]] || die_usage "--handoff-dir requires a value"
      HANDOFF_DIR="$2"
      shift 2
      ;;
    --handoff-dir=*)
      HANDOFF_DIR="${1#*=}"
      shift
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die_usage "--run-id requires a value"
      RUN_ID="$2"
      shift 2
      ;;
    --run-id=*)
      RUN_ID="${1#*=}"
      shift
      ;;
    --validate-cmd)
      [[ $# -ge 2 ]] || die_usage "--validate-cmd requires a value"
      VALIDATE_CMD="$2"
      shift 2
      ;;
    --validate-cmd=*)
      VALIDATE_CMD="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --no-yolo)
      NO_YOLO="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      die_usage "unknown option: $1"
      ;;
    *)
      if [[ -n "$WORKSPACE_ARG" ]]; then
        die_usage "multiple workspace arguments supplied"
      fi
      WORKSPACE_ARG="$1"
      shift
      ;;
  esac
done

[[ -n "$WORKSPACE_ARG" ]] || die_usage "workspace is required"

case "$HARNESS" in
  codex|claude|kimi) ;;
  *) die_usage "invalid --harness: $HARNESS" ;;
esac

case "$MODE" in
  budget|no-budget) ;;
  *) die_usage "invalid --mode: $MODE" ;;
esac

is_positive_integer "$TOKEN_BUDGET" || die_usage "--token-budget must be a positive integer"
is_positive_integer "$MAX_HOPS" || die_usage "--max-hops must be a positive integer"
is_positive_integer "$MAX_ISSUES_TOTAL" || [[ "$MAX_ISSUES_TOTAL" == "0" ]] || die_usage "--max-issues-total must be 0 or a positive integer"

[[ -n "$RUN_ID" ]] || die_usage "--run-id must not be empty"
[[ -n "$HANDOFF_DIR" ]] || die_usage "--handoff-dir must not be empty"

if [[ ! -d "$WORKSPACE_ARG" ]]; then
  echo "workspace does not exist: $WORKSPACE_ARG" >&2
  exit 11
fi

WORKSPACE="$(resolve_path "$WORKSPACE_ARG")"

if [[ "$NO_YOLO" != "1" ]]; then
  assert_sandbox_for_yolo "$WORKSPACE"
fi

EXPERIMENT_RUN_ID="$(extract_experiment_run_id "$WORKSPACE")"
RUN_DIR="$WORKSPACE/.ralph-orchestrator-runs/$RUN_ID"
HOP_DIR="$RUN_DIR/hop-001"
EXPECTED_HANDOFF="$HANDOFF_DIR/ralph-orchestrator-$RUN_ID-hop-1.md"
PREVIOUS_HANDOFF="<none>"

mkdir -p "$HOP_DIR"
write_run_env "$RUN_DIR/run.env"

{
  printf 'supervisor_run_id=%s\n' "$RUN_ID"
  printf 'experiment_run_id=%s\n' "$EXPERIMENT_RUN_ID"
  printf 'workspace=%s\n' "$WORKSPACE"
  printf 'harness=%s\n' "$HARNESS"
  printf 'mode=%s\n' "$MODE"
  printf 'dry_run=%s\n' "$DRY_RUN"
  printf 'no_yolo=%s\n' "$NO_YOLO"
} > "$RUN_DIR/supervisor.log"

write_prompt "$HOP_DIR/prompt.md" "1" "$EXPECTED_HANDOFF" "$PREVIOUS_HANDOFF"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "dry-run: wrote $RUN_DIR"
  echo "dry-run: wrote $HOP_DIR/prompt.md"
  exit 0
fi

echo "harness execution is not implemented in this dry-run supervisor skeleton" >&2
exit 14
