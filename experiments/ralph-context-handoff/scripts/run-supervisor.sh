#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FAKE_FIXTURE_DIR="$EXPERIMENT_DIR/fixtures/supervisor-fake"

usage() {
  cat >&2 <<EOF_USAGE
usage: $0 [options] <workspace>

Options:
  --harness codex|claude|kimi|fake
  --scenario complete|valid-handoff|missing-handoff|malformed-handoff|rate-limit|harness-failure
  --mode budget|no-budget
  --token-budget N
  --max-hops N
  --max-issues-total N
  --max-rate-limit-retries N
  --rate-limit-base-sleep SECONDS
  --bd-lock-timeout SECONDS
  --handoff-dir DIR
  --run-id ID
  --validate-cmd CMD
  --dry-run
  --no-yolo
  --require-clean-start
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

is_non_negative_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
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
      echo "Recovery: rerun with --no-yolo for dry-run inspection, or copy the disposable workspace under ~/Development/sandbox." >&2
      exit 10
      ;;
  esac
}

assert_clean_start() {
  local workspace="$1"
  local status_output

  if ! git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "--require-clean-start needs a git workspace: $workspace" >&2
    echo "Recovery: initialize git, choose a git workspace, or rerun without --require-clean-start after inspecting the state." >&2
    exit 11
  fi

  status_output="$(git -C "$workspace" status --porcelain)"
  if [[ -n "$status_output" ]]; then
    echo "Refusing dirty workspace with --require-clean-start: $workspace" >&2
    echo "$status_output" >&2
    echo "Recovery: commit, stash, or otherwise preserve these changes before rerunning. No harness was launched." >&2
    exit 11
  fi
}

write_run_env() {
  local path="$1"

  cat > "$path" <<EOF_RUN_ENV
SUPERVISOR_RUN_ID=$RUN_ID
EXPERIMENT_RUN_ID=$EXPERIMENT_RUN_ID
WORKSPACE=$WORKSPACE
RUN_DIR=$RUN_DIR
HARNESS=$HARNESS
SCENARIO=$SCENARIO
MODE=$MODE
TOKEN_BUDGET=$TOKEN_BUDGET
MAX_HOPS=$MAX_HOPS
MAX_ISSUES_TOTAL=$MAX_ISSUES_TOTAL
MAX_RATE_LIMIT_RETRIES=$MAX_RATE_LIMIT_RETRIES
RATE_LIMIT_BASE_SLEEP=$RATE_LIMIT_BASE_SLEEP
HANDOFF_DIR=$HANDOFF_DIR
VALIDATE_CMD=$VALIDATE_CMD
DRY_RUN=$DRY_RUN
NO_YOLO=$NO_YOLO
REQUIRE_CLEAN_START=$REQUIRE_CLEAN_START
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
Supervisor limits:
- Max hops: $MAX_HOPS
- Max issues total for this supervisor run: $MAX_ISSUES_TOTAL

If max issues total is greater than 0, do not process, close, or otherwise advance more than that many BEADS issues across the whole supervisor run. Stop with the required handoff once the limit is reached.

If a prior handoff is supplied, read it first and do not reread the previous chat:
$previous_handoff

No prior handoff is expected for hop 1. If the placeholder above is empty or says none, start from the workspace state and the BEADS queue.

Use one worker subagent at a time. Process multiple BEADS issues until the context-budget guardrail says handoff is due. When handoff is due, write the expected handoff path and stop.

When writing the expected handoff, use this exact machine-validated shape. Keep field values plain text with no Markdown backticks:

# Ralph Orchestrator Handoff

Workspace: $WORKSPACE
Run id: $RUN_ID
Hop: $hop
Previous hop status: handoff
Built-in compaction avoided: yes

## BEADS State
- Current issue: <id and title, or none>
- Next issue: <id and title, or none>
- Ready issues remaining: <count or command/result>
- In-progress issues: <ids or none>

## Ledger
- <compact issue-cycle summary>

## QA
- Result: <passed|failed|not-run|blocked>
- Evidence: <commands or inspection>
- Gaps: <remaining uncertainty or none>

## Repository State
- Branch: <branch>
- Git status: <clean or exact dirty summary>
- Staged files: <files or none>
- Uncommitted files: <files or none>

## Next Step
Run:

\`\`\`bash
<exact next command, or true if no next command remains>
\`\`\`

Relevant files:
- <path>
EOF_PROMPT
}

render_fake_template() {
  local src="$1"
  local dest="$2"
  local scenario="$3"
  local status="$4"

  sed \
    -e "s|{{WORKSPACE}}|$WORKSPACE|g" \
    -e "s|{{RUN_ID}}|$RUN_ID|g" \
    -e "s|{{EXPERIMENT_RUN_ID}}|$EXPERIMENT_RUN_ID|g" \
    -e "s|{{HOP}}|${HOP:-1}|g" \
    -e "s|{{SCENARIO}}|$scenario|g" \
    -e "s|{{STATUS}}|$status|g" \
    -e "s|{{EXPECTED_HANDOFF}}|$EXPECTED_HANDOFF|g" \
    "$src" > "$dest"
}

require_fake_fixture_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "fake fixture file is missing: $path" >&2
    exit 11
  fi
}

format_hop_id() {
  printf 'hop-%03d\n' "$1"
}

set_hop_paths() {
  local hop="$1"
  local attempt="$2"
  local hop_id

  hop_id="$(format_hop_id "$hop")"
  if [[ "$attempt" -eq 1 ]]; then
    HOP_DIR="$RUN_DIR/$hop_id"
  else
    HOP_DIR="$RUN_DIR/$hop_id-retry-$(printf '%03d' "$((attempt - 1))")"
  fi
  EXPECTED_HANDOFF="$HANDOFF_DIR/ralph-orchestrator-$RUN_ID-hop-$hop.md"
}

log_supervisor() {
  printf '%s\n' "$1" >> "$RUN_DIR/supervisor.log"
}

exit_code_for_classification() {
  case "$1" in
    complete|handoff) printf '0\n' ;;
    fatal_infra) printf '11\n' ;;
    bad_handoff) printf '13\n' ;;
    agent_failure) printf '14\n' ;;
    rate_limited) printf '15\n' ;;
    manual_intervention) printf '16\n' ;;
    *) printf '14\n' ;;
  esac
}

print_failure_context() {
  local classification="$1"
  local exit_code

  exit_code="$(exit_code_for_classification "$classification")"
  {
    echo "supervisor stopped: $classification"
    echo "run directory: $RUN_DIR"
    echo "inspect from workspace:"
    echo "  cd $WORKSPACE"
    echo "  bd ready"
    echo "  bd list --status in_progress"
    echo "  git status"
  } >&2
  exit "$exit_code"
}

agent_session_started() {
  [[ -s "$HOP_DIR/stream.jsonl" || -s "$HOP_DIR/final.md" || -s "$HOP_DIR/stdout.txt" ]]
}

detect_rate_limit_text() {
  local path

  for path in "$HOP_DIR/stream.jsonl" "$HOP_DIR/stdout.txt" "$HOP_DIR/stderr.txt" "$HOP_DIR/final.md"; do
    if [[ -f "$path" ]] && grep -Eiq 'rate[_ -]?limit|rate_limit_exceeded|too many requests|(^|[^0-9])429([^0-9]|$)' "$path"; then
      return 0
    fi
  done
  return 1
}

final_says_complete() {
  [[ -f "$HOP_DIR/final.md" ]] && grep -Eiq 'Status:[[:space:]]*complete|relay complete|completed the bounded Ralph relay|completed .*Ralph relay' "$HOP_DIR/final.md"
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

describe_bd_lock() {
  if [[ -f "$BD_LOCK_DIR/owner" ]]; then
    echo "Ralph supervisor bd lock owner: $(cat "$BD_LOCK_DIR/owner" 2>/dev/null)"
  fi
  if [[ -e "$WORKSPACE/.beads/embeddeddolt/.lock" ]]; then
    echo "Embedded Dolt lock: $(ls -l "$WORKSPACE/.beads/embeddeddolt/.lock" 2>/dev/null)"
  fi
}

with_bd_process_lock() {
  local waited=0

  while ! mkdir "$BD_LOCK_DIR" 2>/dev/null; do
    if [[ "$waited" -ge "$BD_LOCK_WAIT_SECONDS" ]]; then
      echo "INFRA: timed out waiting for serialized bd command lock." >&2
      describe_bd_lock >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  printf 'pid=%s cwd=%s command=%s since=%s\n' "$$" "$WORKSPACE" "bd $*" "$(iso_now)" > "$BD_LOCK_DIR/owner" 2>/dev/null || true
  "$@"
  local rc=$?
  rm -f "$BD_LOCK_DIR/owner" 2>/dev/null || true
  rmdir "$BD_LOCK_DIR" 2>/dev/null || true
  return "$rc"
}

bd_cmd() {
  local tmp rc waited sleep_for

  tmp="$(mktemp -t ralph-supervisor-bd.XXXXXX)"
  waited=0

  while true; do
    set +e
    (
      cd "$WORKSPACE"
      with_bd_process_lock bd "$@"
    ) >"$tmp" 2>&1
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      cat "$tmp"
      rm -f "$tmp"
      return 0
    fi

    if grep -qi 'another process holds the exclusive lock' "$tmp"; then
      if [[ "$waited" -ge "$BD_EMBEDDED_LOCK_WAIT_SECONDS" ]]; then
        echo "INFRA: bd embedded Dolt lock persisted after ${BD_EMBEDDED_LOCK_WAIT_SECONDS}s: bd $*" >&2
        cat "$tmp" >&2
        describe_bd_lock >&2
        rm -f "$tmp"
        return "$rc"
      fi
      sleep_for=$((1 + waited / 5))
      sleep "$sleep_for"
      waited=$((waited + sleep_for))
      continue
    fi

    cat "$tmp" >&2
    rm -f "$tmp"
    return "$rc"
  done
}

ready_work_state() {
  local ready_json="$HOP_DIR/bd-ready.json"
  local ready_stderr="$HOP_DIR/bd-ready.stderr"

  if ! bd_cmd ready --json > "$ready_json" 2> "$ready_stderr"; then
    echo "unknown"
    return 0
  fi

  if grep -Eq '"id"[[:space:]]*:' "$ready_json"; then
    echo "yes"
  else
    echo "no"
  fi
}

fake_ready_work_remains() {
  case "$HARNESS:$SCENARIO" in
    fake:valid-handoff|fake:missing-handoff|fake:malformed-handoff|fake:rate-limit) return 0 ;;
    *) return 1 ;;
  esac
}

handoff_requests_manual_intervention() {
  [[ -f "$EXPECTED_HANDOFF" ]] && grep -Eiq 'manual[_ -]intervention|human decision|required before another hop' "$EXPECTED_HANDOFF"
}

run_external_validator() {
  "$VALIDATE_CMD" "$RUN_DIR" "$(basename "$HOP_DIR")" "$EXPECTED_HANDOFF" > "$HOP_DIR/validation.txt" 2>&1
}

validate_handoff_minimum() {
  local handoff="$1"
  local failures=0
  local pattern
  local status_output
  local git_status_line
  local staged_line
  local uncommitted_line

  {
    echo "minimum handoff validation"
    echo "handoff: $handoff"
  } > "$HOP_DIR/validation.txt"

  if [[ ! -f "$handoff" ]]; then
    echo "FAIL missing expected handoff" >> "$HOP_DIR/validation.txt"
    return 1
  fi

  for pattern in \
    '^# Ralph Orchestrator Handoff$' \
    '^Workspace: .+' \
    "^Run id: $RUN_ID$" \
    '^Hop: [0-9]+' \
    '^Built-in compaction avoided: (yes|no|unknown)$' \
    '^## BEADS State$' \
    '^- Current issue: .+' \
    '^- Next issue: .+' \
    '^## Ledger$' \
    '^## QA$' \
    '^- Result: (passed|failed|not-run|blocked)' \
    '^## Repository State$' \
    '^- Git status: .+' \
    '^## Next Step$' \
    '^```bash$' \
    '^Relevant files:'; do
    if ! grep -Eq "$pattern" "$handoff"; then
      echo "FAIL missing pattern: $pattern" >> "$HOP_DIR/validation.txt"
      failures=$((failures + 1))
    fi
  done

  if grep -Fxq "Built-in compaction avoided: no" "$handoff" 2>/dev/null; then
    echo "WARN built-in compaction avoidance was not preserved" >> "$HOP_DIR/validation.txt"
  elif grep -Fxq "Built-in compaction avoided: unknown" "$handoff" 2>/dev/null; then
    echo "WARN built-in compaction avoidance is unknown" >> "$HOP_DIR/validation.txt"
  fi

  if grep -Eq '^Workspace: .+' "$handoff" && ! grep -Fxq "Workspace: $WORKSPACE" "$handoff"; then
    echo "FAIL workspace does not match supervisor workspace" >> "$HOP_DIR/validation.txt"
    failures=$((failures + 1))
  fi

  if git -C "$WORKSPACE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    status_output="$(git -C "$WORKSPACE" status --porcelain --untracked-files=all)"
    if [[ -n "$status_output" ]]; then
      git_status_line="$(grep -E '^- Git status: ' "$handoff" | head -n 1 || true)"
      staged_line="$(grep -E '^- Staged files: ' "$handoff" | head -n 1 || true)"
      uncommitted_line="$(grep -E '^- Uncommitted files: ' "$handoff" | head -n 1 || true)"

      if [[ "$git_status_line" =~ ^-\ Git\ status:\ clean[[:space:]]*$ ]]; then
        echo "FAIL workspace is dirty, but handoff says git status is clean" >> "$HOP_DIR/validation.txt"
        failures=$((failures + 1))
      fi
      if [[ "$staged_line" =~ ^-\ Staged\ files:\ none([[:space:]].*)?$ && "$uncommitted_line" =~ ^-\ Uncommitted\ files:\ none([[:space:]].*)?$ ]]; then
        echo "FAIL workspace is dirty, but handoff records no staged or uncommitted files" >> "$HOP_DIR/validation.txt"
        failures=$((failures + 1))
      fi
    fi
  fi

  if [[ "$failures" -eq 0 ]]; then
    echo "PASS minimum handoff shape is usable" >> "$HOP_DIR/validation.txt"
    return 0
  fi

  return 1
}

validate_handoff_for_continuation() {
  if [[ -n "$VALIDATE_CMD" ]]; then
    run_external_validator
  else
    validate_handoff_minimum "$EXPECTED_HANDOFF"
  fi
}

validation_has_warnings() {
  [[ -f "$HOP_DIR/validation.txt" ]] && grep -Eq '^WARN ' "$HOP_DIR/validation.txt"
}

classify_result() {
  local harness_exit="$1"
  local ready_work_remains="1"
  local ready_state="yes"

  if ! agent_session_started && [[ "$harness_exit" -ne 0 ]]; then
    printf 'fatal_infra\n'
    return 0
  fi

  if detect_rate_limit_text; then
    printf 'rate_limited\n'
    return 0
  fi

  if [[ "$HARNESS" == "fake" ]]; then
    if fake_ready_work_remains; then
      ready_state="yes"
    else
      ready_state="no"
    fi
  else
    ready_state="$(ready_work_state)"
    if [[ "$ready_state" == "unknown" ]]; then
      printf 'fatal_infra\n'
      return 0
    fi
  fi

  if [[ "$ready_state" == "no" ]] && final_says_complete; then
    if [[ -f "$EXPECTED_HANDOFF" ]]; then
      validate_handoff_for_continuation || true
    fi
    printf 'complete\n'
    return 0
  fi

  if [[ -f "$EXPECTED_HANDOFF" ]]; then
    if validate_handoff_for_continuation; then
      if validation_has_warnings; then
        printf 'bad_handoff\n'
        return 0
      fi
      if handoff_requests_manual_intervention; then
        printf 'manual_intervention\n'
      else
        printf 'handoff\n'
      fi
    else
      printf 'bad_handoff\n'
    fi
    return 0
  fi

  validate_handoff_for_continuation || true

  if [[ "$HARNESS" == "fake" ]]; then
    if fake_ready_work_remains; then
      ready_work_remains="1"
    else
      ready_work_remains="0"
    fi
  fi

  if [[ "$ready_work_remains" == "1" ]]; then
    printf 'bad_handoff\n'
  else
    printf 'agent_failure\n'
  fi
}

rate_limit_sleep_seconds() {
  local attempt="$1"

  if [[ "$RATE_LIMIT_BASE_SLEEP" -eq 0 || "$attempt" -eq 1 ]]; then
    printf '0\n'
  else
    printf '%d\n' "$((RATE_LIMIT_BASE_SLEEP * (2 ** (attempt - 2))))"
  fi
}

run_fake_harness() {
  local scenario="$1"
  local fixture_dir="$FAKE_FIXTURE_DIR/$scenario"
  local status_file="$fixture_dir/status"
  local status
  local name

  [[ -d "$fixture_dir" ]] || die_usage "unknown --scenario: $scenario"
  require_fake_fixture_file "$status_file"
  status="$(<"$status_file")"

  for name in stream.jsonl stdout.txt stderr.txt final.md; do
    require_fake_fixture_file "$fixture_dir/$name"
    render_fake_template "$fixture_dir/$name" "$HOP_DIR/$name" "$scenario" "$status"
  done

  if [[ -f "$fixture_dir/handoff.md" ]]; then
    mkdir -p "$(dirname "$EXPECTED_HANDOFF")"
    render_fake_template "$fixture_dir/handoff.md" "$EXPECTED_HANDOFF" "$scenario" "$status"
    ln -sf "$EXPECTED_HANDOFF" "$HOP_DIR/handoff.md"
  fi

  {
    printf 'fake_scenario=%s\n' "$scenario"
    printf 'fake_status=%s\n' "$status"
    printf 'fake_hop_dir=%s\n' "$HOP_DIR"
  } >> "$RUN_DIR/supervisor.log"

  case "$scenario" in
    complete|valid-handoff|missing-handoff|malformed-handoff|rate-limit)
      return 0
      ;;
    harness-failure)
      return 14
      ;;
    *)
      die_usage "unknown --scenario: $scenario"
      ;;
  esac
}

run_codex_harness() {
  local prompt
  local harness_exit

  prompt="$(<"$HOP_DIR/prompt.md")"

  set +e
  codex exec \
    --dangerously-bypass-approvals-and-sandbox \
    --ignore-rules \
    --json \
    --skip-git-repo-check \
    -C "$WORKSPACE" \
    --output-last-message "$HOP_DIR/final.md" \
    -- "$prompt" \
    > "$HOP_DIR/stream.jsonl" \
    2> "$HOP_DIR/stderr.txt"
  harness_exit="$?"
  set -e

  cp "$HOP_DIR/stream.jsonl" "$HOP_DIR/stdout.txt"

  if [[ ! -f "$HOP_DIR/final.md" ]]; then
    {
      echo "Codex did not write an output-last-message file."
      echo
      echo "Last stream events:"
      tail -n 80 "$HOP_DIR/stream.jsonl" 2>/dev/null || true
    } > "$HOP_DIR/final.md"
  fi

  if [[ -f "$EXPECTED_HANDOFF" ]]; then
    mkdir -p "$(dirname "$EXPECTED_HANDOFF")"
    ln -sf "$EXPECTED_HANDOFF" "$HOP_DIR/handoff.md"
  fi

  {
    printf 'codex_hop_dir=%s\n' "$HOP_DIR"
    printf 'codex_harness_exit=%s\n' "$harness_exit"
  } >> "$RUN_DIR/supervisor.log"

  return "$harness_exit"
}

HARNESS="codex"
SCENARIO="complete"
MODE="no-budget"
TOKEN_BUDGET="60000"
MAX_HOPS="8"
MAX_ISSUES_TOTAL="0"
MAX_RATE_LIMIT_RETRIES="3"
RATE_LIMIT_BASE_SLEEP="0"
BD_LOCK_DIR="${BD_LOCK_DIR:-/tmp/ralph-supervisor-bd.lock}"
BD_LOCK_WAIT_SECONDS="15"
BD_EMBEDDED_LOCK_WAIT_SECONDS="20"
HANDOFF_DIR="/private/tmp"
RUN_ID="$(timestamp_run_id)"
VALIDATE_CMD=""
DRY_RUN="0"
NO_YOLO="0"
REQUIRE_CLEAN_START="0"
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
    --scenario)
      [[ $# -ge 2 ]] || die_usage "--scenario requires a value"
      SCENARIO="$2"
      shift 2
      ;;
    --scenario=*)
      SCENARIO="${1#*=}"
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
    --max-rate-limit-retries)
      [[ $# -ge 2 ]] || die_usage "--max-rate-limit-retries requires a value"
      MAX_RATE_LIMIT_RETRIES="$2"
      shift 2
      ;;
    --max-rate-limit-retries=*)
      MAX_RATE_LIMIT_RETRIES="${1#*=}"
      shift
      ;;
    --rate-limit-base-sleep)
      [[ $# -ge 2 ]] || die_usage "--rate-limit-base-sleep requires a value"
      RATE_LIMIT_BASE_SLEEP="$2"
      shift 2
      ;;
    --rate-limit-base-sleep=*)
      RATE_LIMIT_BASE_SLEEP="${1#*=}"
      shift
      ;;
    --bd-lock-timeout)
      [[ $# -ge 2 ]] || die_usage "--bd-lock-timeout requires a value"
      BD_EMBEDDED_LOCK_WAIT_SECONDS="$2"
      shift 2
      ;;
    --bd-lock-timeout=*)
      BD_EMBEDDED_LOCK_WAIT_SECONDS="${1#*=}"
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
    --require-clean-start)
      REQUIRE_CLEAN_START="1"
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
  codex|claude|kimi|fake) ;;
  *) die_usage "invalid --harness: $HARNESS" ;;
esac

case "$SCENARIO" in
  complete|valid-handoff|missing-handoff|malformed-handoff|rate-limit|harness-failure) ;;
  *) die_usage "unknown --scenario: $SCENARIO" ;;
esac

case "$MODE" in
  budget|no-budget) ;;
  *) die_usage "invalid --mode: $MODE" ;;
esac

is_positive_integer "$TOKEN_BUDGET" || die_usage "--token-budget must be a positive integer"
is_positive_integer "$MAX_HOPS" || die_usage "--max-hops must be a positive integer"
is_positive_integer "$MAX_ISSUES_TOTAL" || [[ "$MAX_ISSUES_TOTAL" == "0" ]] || die_usage "--max-issues-total must be 0 or a positive integer"
is_non_negative_integer "$MAX_RATE_LIMIT_RETRIES" || die_usage "--max-rate-limit-retries must be 0 or a positive integer"
is_non_negative_integer "$RATE_LIMIT_BASE_SLEEP" || die_usage "--rate-limit-base-sleep must be 0 or a positive integer"
is_non_negative_integer "$BD_EMBEDDED_LOCK_WAIT_SECONDS" || die_usage "--bd-lock-timeout must be 0 or a positive integer"

[[ -n "$RUN_ID" ]] || die_usage "--run-id must not be empty"
[[ -n "$HANDOFF_DIR" ]] || die_usage "--handoff-dir must not be empty"
if [[ -n "$VALIDATE_CMD" ]] && ! command -v "$VALIDATE_CMD" >/dev/null 2>&1 && [[ ! -x "$VALIDATE_CMD" ]]; then
  echo "--validate-cmd is not executable or on PATH: $VALIDATE_CMD" >&2
  exit 11
fi

if [[ ! -d "$WORKSPACE_ARG" ]]; then
  echo "workspace does not exist: $WORKSPACE_ARG" >&2
  exit 11
fi

WORKSPACE="$(resolve_path "$WORKSPACE_ARG")"

if [[ "$NO_YOLO" != "1" ]]; then
  assert_sandbox_for_yolo "$WORKSPACE"
fi

if [[ "$REQUIRE_CLEAN_START" == "1" ]]; then
  assert_clean_start "$WORKSPACE"
fi

EXPERIMENT_RUN_ID="$(extract_experiment_run_id "$WORKSPACE")"
RUN_DIR="$WORKSPACE/.ralph-orchestrator-runs/$RUN_ID"
HOP_DIR=""
EXPECTED_HANDOFF=""
PREVIOUS_HANDOFF="<none>"

set_hop_paths 1 1
mkdir -p "$HOP_DIR"
write_run_env "$RUN_DIR/run.env"

{
  printf 'supervisor_run_id=%s\n' "$RUN_ID"
  printf 'experiment_run_id=%s\n' "$EXPERIMENT_RUN_ID"
  printf 'workspace=%s\n' "$WORKSPACE"
  printf 'harness=%s\n' "$HARNESS"
  printf 'scenario=%s\n' "$SCENARIO"
  printf 'mode=%s\n' "$MODE"
  printf 'max_rate_limit_retries=%s\n' "$MAX_RATE_LIMIT_RETRIES"
  printf 'rate_limit_base_sleep=%s\n' "$RATE_LIMIT_BASE_SLEEP"
  printf 'bd_lock_dir=%s\n' "$BD_LOCK_DIR"
  printf 'bd_embedded_lock_wait_seconds=%s\n' "$BD_EMBEDDED_LOCK_WAIT_SECONDS"
  printf 'dry_run=%s\n' "$DRY_RUN"
  printf 'no_yolo=%s\n' "$NO_YOLO"
  printf 'require_clean_start=%s\n' "$REQUIRE_CLEAN_START"
} > "$RUN_DIR/supervisor.log"

write_prompt "$HOP_DIR/prompt.md" "1" "$EXPECTED_HANDOFF" "$PREVIOUS_HANDOFF"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "dry-run: wrote $RUN_DIR"
  echo "dry-run: wrote $HOP_DIR/prompt.md"
  exit 0
fi

if [[ "$HARNESS" == "fake" ]]; then
  HOP=1
  RATE_LIMIT_RETRIES_USED=0

  while [[ "$HOP" -le "$MAX_HOPS" ]]; do
    ATTEMPT=1

    while :; do
      set_hop_paths "$HOP" "$ATTEMPT"
      mkdir -p "$HOP_DIR"
      write_prompt "$HOP_DIR/prompt.md" "$HOP" "$EXPECTED_HANDOFF" "$PREVIOUS_HANDOFF"

      HARNESS_EXIT=0
      run_fake_harness "$SCENARIO" || HARNESS_EXIT="$?"
      CLASSIFICATION="$(classify_result "$HARNESS_EXIT")"
      log_supervisor "hop=$HOP attempt=$ATTEMPT classification=$CLASSIFICATION harness_exit=$HARNESS_EXIT"

      case "$CLASSIFICATION" in
        complete)
          printf 'hop %d: complete, fake scenario %s\n' "$HOP" "$SCENARIO"
          exit 0
          ;;
        handoff)
          printf 'hop %d: handoff, validation passed\n' "$HOP"
          PREVIOUS_HANDOFF="$EXPECTED_HANDOFF"
          if [[ "$HOP" -ge "$MAX_HOPS" ]]; then
            log_supervisor "max_hops_reached=$MAX_HOPS final_classification=handoff"
            exit 0
          fi
          HOP=$((HOP + 1))
          break
          ;;
        manual_intervention)
          printf 'hop %d: manual_intervention, validation passed\n' "$HOP"
          print_failure_context "$CLASSIFICATION"
          ;;
        rate_limited)
          if [[ "$RATE_LIMIT_RETRIES_USED" -lt "$MAX_RATE_LIMIT_RETRIES" ]]; then
            RATE_LIMIT_RETRIES_USED=$((RATE_LIMIT_RETRIES_USED + 1))
            SLEEP_SECONDS="$(rate_limit_sleep_seconds "$RATE_LIMIT_RETRIES_USED")"
            log_supervisor "rate_limit_retry=$RATE_LIMIT_RETRIES_USED max=$MAX_RATE_LIMIT_RETRIES sleep_seconds=$SLEEP_SECONDS preserved_hop_dir=$HOP_DIR"
            printf 'hop %d: rate_limited, retry %d/%d\n' "$HOP" "$RATE_LIMIT_RETRIES_USED" "$MAX_RATE_LIMIT_RETRIES"
            if [[ "$SLEEP_SECONDS" -gt 0 ]]; then
              sleep "$SLEEP_SECONDS"
            fi
            ATTEMPT=$((ATTEMPT + 1))
            continue
          fi
          log_supervisor "rate_limit_retry_budget_exhausted=$MAX_RATE_LIMIT_RETRIES preserved_hop_dir=$HOP_DIR"
          printf 'hop %d: rate_limited, retry budget exhausted\n' "$HOP"
          print_failure_context "$CLASSIFICATION"
          ;;
        bad_handoff|agent_failure|fatal_infra)
          printf 'hop %d: %s\n' "$HOP" "$CLASSIFICATION"
          print_failure_context "$CLASSIFICATION"
          ;;
        *)
          printf 'hop %d: agent_failure\n' "$HOP"
          print_failure_context "agent_failure"
          ;;
      esac
    done
  done

  log_supervisor "max_hops_reached=$MAX_HOPS"
  exit 0
fi

if [[ "$HARNESS" != "codex" ]]; then
  echo "live harness execution is implemented only for --harness codex; unsupported live harness: $HARNESS" >&2
  exit 14
fi

HOP=1
RATE_LIMIT_RETRIES_USED=0

while [[ "$HOP" -le "$MAX_HOPS" ]]; do
  ATTEMPT=1

  while :; do
    set_hop_paths "$HOP" "$ATTEMPT"
    mkdir -p "$HOP_DIR"
    write_prompt "$HOP_DIR/prompt.md" "$HOP" "$EXPECTED_HANDOFF" "$PREVIOUS_HANDOFF"

    HARNESS_EXIT=0
    run_codex_harness || HARNESS_EXIT="$?"
    CLASSIFICATION="$(classify_result "$HARNESS_EXIT")"
    log_supervisor "hop=$HOP attempt=$ATTEMPT classification=$CLASSIFICATION harness_exit=$HARNESS_EXIT"

    case "$CLASSIFICATION" in
      complete)
        printf 'hop %d: complete\n' "$HOP"
        exit 0
        ;;
      handoff)
        printf 'hop %d: handoff, validation passed\n' "$HOP"
        PREVIOUS_HANDOFF="$EXPECTED_HANDOFF"
        if [[ "$HOP" -ge "$MAX_HOPS" ]]; then
          log_supervisor "max_hops_reached=$MAX_HOPS final_classification=handoff"
          exit 0
        fi
        HOP=$((HOP + 1))
        break
        ;;
      manual_intervention)
        printf 'hop %d: manual_intervention, validation passed\n' "$HOP"
        print_failure_context "$CLASSIFICATION"
        ;;
      rate_limited)
        if [[ "$RATE_LIMIT_RETRIES_USED" -lt "$MAX_RATE_LIMIT_RETRIES" ]]; then
          RATE_LIMIT_RETRIES_USED=$((RATE_LIMIT_RETRIES_USED + 1))
          SLEEP_SECONDS="$(rate_limit_sleep_seconds "$RATE_LIMIT_RETRIES_USED")"
          log_supervisor "rate_limit_retry=$RATE_LIMIT_RETRIES_USED max=$MAX_RATE_LIMIT_RETRIES sleep_seconds=$SLEEP_SECONDS preserved_hop_dir=$HOP_DIR"
          printf 'hop %d: rate_limited, retry %d/%d\n' "$HOP" "$RATE_LIMIT_RETRIES_USED" "$MAX_RATE_LIMIT_RETRIES"
          if [[ "$SLEEP_SECONDS" -gt 0 ]]; then
            sleep "$SLEEP_SECONDS"
          fi
          ATTEMPT=$((ATTEMPT + 1))
          continue
        fi
        log_supervisor "rate_limit_retry_budget_exhausted=$MAX_RATE_LIMIT_RETRIES preserved_hop_dir=$HOP_DIR"
        printf 'hop %d: rate_limited, retry budget exhausted\n' "$HOP"
        print_failure_context "$CLASSIFICATION"
        ;;
      bad_handoff|agent_failure|fatal_infra)
        printf 'hop %d: %s\n' "$HOP" "$CLASSIFICATION"
        print_failure_context "$CLASSIFICATION"
        ;;
      *)
        printf 'hop %d: agent_failure\n' "$HOP"
        print_failure_context "agent_failure"
        ;;
    esac
  done
done

log_supervisor "max_hops_reached=$MAX_HOPS"
exit 0
