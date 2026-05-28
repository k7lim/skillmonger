#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF_USAGE'
usage: validate-supervisor-run.sh --level preflight|hop|run [--hop 001|hop-001|hop-001-retry-001] <run-dir>

Validation levels:
  preflight  check run metadata and top-level supervisor artifacts
  hop        check one hop directory and its handoff contract
  run        check the aggregate run directory and all hop directories
EOF_USAGE
}

die_usage() {
  echo "error: $1" >&2
  usage
  exit 2
}

LEVEL="run"
HOP_ARG=""
RUN_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --level)
      [[ $# -ge 2 ]] || die_usage "--level requires a value"
      LEVEL="$2"
      shift 2
      ;;
    --level=*)
      LEVEL="${1#*=}"
      shift
      ;;
    --hop)
      [[ $# -ge 2 ]] || die_usage "--hop requires a value"
      HOP_ARG="$2"
      shift 2
      ;;
    --hop=*)
      HOP_ARG="${1#*=}"
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
      [[ -z "$RUN_DIR" ]] || die_usage "multiple run directories supplied"
      RUN_DIR="$1"
      shift
      ;;
  esac
done

case "$LEVEL" in
  preflight|hop|run) ;;
  *) die_usage "invalid --level: $LEVEL" ;;
esac

[[ -n "$RUN_DIR" ]] || die_usage "run directory is required"

failures=0
warnings=0
RUN_ENV_LOADED=0
SUPERVISOR_RUN_ID=""
WORKSPACE=""
RUN_DIR_FROM_ENV=""
HARNESS=""
HANDOFF_DIR=""

pass() {
  echo "PASS $1"
}

fail() {
  echo "FAIL $1"
  failures=$((failures + 1))
}

warn() {
  echo "WARN $1"
  warnings=$((warnings + 1))
}

require_file() {
  local path="$1"
  local label="$2"

  if [[ -f "$path" ]]; then
    pass "$label exists"
  else
    fail "$label missing: $path"
  fi
}

require_dir() {
  local path="$1"
  local label="$2"

  if [[ -d "$path" ]]; then
    pass "$label exists"
  else
    fail "$label missing: $path"
  fi
}

env_value() {
  local key="$1"
  local path="$RUN_DIR/run.env"

  if [[ ! -f "$path" ]]; then
    return 0
  fi

  sed -n "s/^${key}=//p" "$path" | tail -n 1
}

load_run_env() {
  if [[ "$RUN_ENV_LOADED" -eq 1 ]]; then
    return 0
  fi

  SUPERVISOR_RUN_ID="$(env_value "SUPERVISOR_RUN_ID")"
  WORKSPACE="$(env_value "WORKSPACE")"
  RUN_DIR_FROM_ENV="$(env_value "RUN_DIR")"
  HARNESS="$(env_value "HARNESS")"
  HANDOFF_DIR="$(env_value "HANDOFF_DIR")"
  RUN_ENV_LOADED=1
}

normalize_hop_id() {
  local raw="$1"

  if [[ "$raw" =~ ^hop-[0-9][0-9][0-9](-retry-[0-9][0-9][0-9])?$ ]]; then
    printf '%s\n' "$raw"
  elif [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf 'hop-%03d\n' "$((10#$raw))"
  else
    die_usage "invalid --hop: $raw"
  fi
}

hop_number_from_id() {
  local hop_id="$1"
  local base="${hop_id#hop-}"
  base="${base%%-retry-*}"
  printf '%d\n' "$((10#$base))"
}

line_matches() {
  local pattern="$1"
  local path="$2"

  grep -Eq "$pattern" "$path"
}

section_has_bullet() {
  local heading="$1"
  local path="$2"

  awk -v heading="$heading" '
    $0 == heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section && /^- .+/ { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$path"
}

next_step_has_fenced_command() {
  local path="$1"

  awk '
    /^## Next Step$/ { in_next = 1; next }
    in_next && /^## / { in_next = 0; in_fence = 0 }
    in_next && /^```bash$/ { in_fence = 1; next }
    in_fence && /^```$/ {
      if (command_seen) {
        found = 1
      }
      in_fence = 0
      next
    }
    in_fence && $0 !~ /^[[:space:]]*$/ { command_seen = 1 }
    END { exit found ? 0 : 1 }
  ' "$path"
}

relevant_files_has_entry() {
  local path="$1"

  awk '
    /^Relevant files:$/ { in_section = 1; next }
    in_section && /^- .+/ { found = 1; exit }
    in_section && /^## / { exit }
    END { exit found ? 0 : 1 }
  ' "$path"
}

first_matching_line() {
  local pattern="$1"
  local path="$2"

  grep -E "$pattern" "$path" | head -n 1 || true
}

check_required_handoff_line() {
  local pattern="$1"
  local label="$2"
  local handoff="$3"

  if line_matches "$pattern" "$handoff"; then
    pass "handoff $label"
  else
    fail "handoff missing or malformed $label"
  fi
}

check_dirty_workspace_documented() {
  local handoff="$1"
  local workspace="$2"
  local status_output
  local git_status_line
  local staged_line
  local uncommitted_line

  if [[ -z "$workspace" || ! -d "$workspace" ]]; then
    warn "workspace dirty-state check skipped; workspace path unavailable"
    return 0
  fi

  if ! git -C "$workspace" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "workspace dirty-state check skipped; not a git repository: $workspace"
    return 0
  fi

  status_output="$(git -C "$workspace" status --porcelain --untracked-files=all)"
  if [[ -z "$status_output" ]]; then
    pass "workspace is clean"
    return 0
  fi

  git_status_line="$(first_matching_line '^- Git status: ' "$handoff")"
  staged_line="$(first_matching_line '^- Staged files: ' "$handoff")"
  uncommitted_line="$(first_matching_line '^- Uncommitted files: ' "$handoff")"

  if [[ "$git_status_line" =~ ^-\ Git\ status:\ clean[[:space:]]*$ ]]; then
    fail "workspace is dirty, but handoff says git status is clean"
  elif [[ -n "$git_status_line" ]]; then
    pass "handoff records dirty workspace git status"
  fi

  if [[ "$staged_line" =~ ^-\ Staged\ files:\ none([[:space:]].*)?$ && "$uncommitted_line" =~ ^-\ Uncommitted\ files:\ none([[:space:]].*)?$ ]]; then
    fail "workspace is dirty, but handoff records no staged or uncommitted files"
  elif [[ -n "$staged_line" && -n "$uncommitted_line" ]]; then
    pass "handoff records staged and uncommitted file state"
  fi
}

check_no_compaction_markers() {
  local hop_dir="$1"
  local path
  local marker='Continuing .*compacted state|Continuing the Ralph relay from the compacted state|continue from chat history|previous chat history'

  for path in "$hop_dir/stream.jsonl" "$hop_dir/stdout.txt" "$hop_dir/stderr.txt" "$hop_dir/final.md" "$hop_dir/handoff.md"; do
    if [[ -f "$path" ]] && grep -Eiq "$marker" "$path"; then
      fail "compacted-state or chat-history continuation marker found in $(basename "$path")"
      return 0
    fi
  done

  pass "no compacted-state continuation marker found"
}

validate_handoff() {
  local handoff="$1"
  local expected_hop="$2"
  local workspace_for_check="$WORKSPACE"
  local handoff_workspace

  if [[ ! -f "$handoff" ]]; then
    fail "handoff missing: $handoff"
    return 0
  fi

  check_required_handoff_line '^# Ralph Orchestrator Handoff$' "title" "$handoff"
  check_required_handoff_line '^Workspace: /.+$' "Workspace field" "$handoff"
  check_required_handoff_line '^Run id: .+$' "Run id field" "$handoff"
  check_required_handoff_line '^Hop: [0-9]+$' "Hop field" "$handoff"
  check_required_handoff_line '^Previous hop status: (handoff|manual_intervention|rate_limited|fatal_infra)$' "Previous hop status field" "$handoff"
  check_required_handoff_line '^Built-in compaction avoided: (yes|no|unknown)$' "Built-in compaction avoided field" "$handoff"
  check_required_handoff_line '^## BEADS State$' "BEADS State section" "$handoff"
  check_required_handoff_line '^- Current issue: .+$' "Current issue field" "$handoff"
  check_required_handoff_line '^- Next issue: .+$' "Next issue field" "$handoff"
  check_required_handoff_line '^- Ready issues remaining: .+$' "Ready issues remaining field" "$handoff"
  check_required_handoff_line '^- In-progress issues: .+$' "In-progress issues field" "$handoff"
  check_required_handoff_line '^## Ledger$' "Ledger section" "$handoff"
  check_required_handoff_line '^## QA$' "QA section" "$handoff"
  check_required_handoff_line '^- Result: (passed|failed|not-run|blocked)$' "QA Result field" "$handoff"
  check_required_handoff_line '^- Evidence: .+$' "QA Evidence field" "$handoff"
  check_required_handoff_line '^- Gaps: .+$' "QA Gaps field" "$handoff"
  check_required_handoff_line '^## Repository State$' "Repository State section" "$handoff"
  check_required_handoff_line '^- Branch: .+$' "Branch field" "$handoff"
  check_required_handoff_line '^- Git status: .+$' "Git status field" "$handoff"
  check_required_handoff_line '^- Staged files: .+$' "Staged files field" "$handoff"
  check_required_handoff_line '^- Uncommitted files: .+$' "Uncommitted files field" "$handoff"
  check_required_handoff_line '^## Next Step$' "Next Step section" "$handoff"
  check_required_handoff_line '^Run:$' "Run prompt" "$handoff"
  check_required_handoff_line '^Relevant files:$' "Relevant files heading" "$handoff"

  if section_has_bullet "## Ledger" "$handoff"; then
    pass "handoff Ledger has at least one entry"
  else
    fail "handoff Ledger has no compact ledger entry"
  fi

  if next_step_has_fenced_command "$handoff"; then
    pass "handoff Next Step has fenced bash command"
  else
    fail "handoff Next Step is missing a fenced bash command"
  fi

  if relevant_files_has_entry "$handoff"; then
    pass "handoff Relevant files has at least one entry"
  else
    fail "handoff Relevant files has no entries"
  fi

  if [[ -n "$SUPERVISOR_RUN_ID" ]]; then
    if grep -Fxq "Run id: $SUPERVISOR_RUN_ID" "$handoff"; then
      pass "handoff run id matches run.env"
    else
      fail "handoff run id does not match run.env SUPERVISOR_RUN_ID=$SUPERVISOR_RUN_ID"
    fi
  fi

  if grep -Fxq "Hop: $expected_hop" "$handoff"; then
    pass "handoff hop matches $expected_hop"
  else
    fail "handoff hop does not match expected hop $expected_hop"
  fi

  handoff_workspace="$(sed -n 's/^Workspace: //p' "$handoff" | head -n 1)"
  if [[ -n "$WORKSPACE" && -n "$handoff_workspace" ]]; then
    if [[ "$handoff_workspace" == "$WORKSPACE" ]]; then
      pass "handoff workspace matches run.env"
    else
      fail "handoff workspace does not match run.env WORKSPACE=$WORKSPACE"
    fi
  elif [[ -n "$handoff_workspace" ]]; then
    workspace_for_check="$handoff_workspace"
  fi

  if grep -Fxq "Built-in compaction avoided: no" "$handoff"; then
    warn "handoff says built-in compaction was not avoided"
  elif grep -Fxq "Built-in compaction avoided: unknown" "$handoff"; then
    warn "handoff says built-in compaction avoidance is unknown"
  fi

  check_dirty_workspace_documented "$handoff" "$workspace_for_check"
}

validate_preflight() {
  require_dir "$RUN_DIR" "run directory"
  require_file "$RUN_DIR/run.env" "run.env"
  require_file "$RUN_DIR/supervisor.log" "supervisor.log"

  if [[ -f "$RUN_DIR/run.env" ]]; then
    load_run_env

    if [[ -n "$SUPERVISOR_RUN_ID" ]]; then
      pass "run.env has SUPERVISOR_RUN_ID"
    else
      fail "run.env missing SUPERVISOR_RUN_ID"
    fi

    if [[ -n "$WORKSPACE" ]]; then
      pass "run.env has WORKSPACE"
    else
      fail "run.env missing WORKSPACE"
    fi

    if [[ -n "$RUN_DIR_FROM_ENV" ]]; then
      pass "run.env has RUN_DIR"
    else
      fail "run.env missing RUN_DIR"
    fi

    if [[ -n "$HARNESS" ]]; then
      pass "run.env has HARNESS"
    else
      warn "run.env missing HARNESS"
    fi

    if [[ -n "$HANDOFF_DIR" ]]; then
      pass "run.env has HANDOFF_DIR"
    else
      warn "run.env missing HANDOFF_DIR"
    fi

    if [[ -n "$RUN_DIR_FROM_ENV" ]]; then
      if [[ "$(cd "$RUN_DIR" && pwd -P)" == "$(cd "$RUN_DIR_FROM_ENV" 2>/dev/null && pwd -P)" ]]; then
        pass "run.env RUN_DIR matches validated run directory"
      else
        fail "run.env RUN_DIR does not match validated run directory"
      fi
    fi

    if [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]]; then
      pass "workspace exists"
    elif [[ -n "$WORKSPACE" ]]; then
      fail "workspace missing: $WORKSPACE"
    fi
  fi
}

validate_hop_dir() {
  local hop_id="$1"
  local hop_dir="$RUN_DIR/$hop_id"
  local hop_number

  hop_number="$(hop_number_from_id "$hop_id")"

  require_dir "$hop_dir" "$hop_id directory"
  if [[ ! -d "$hop_dir" ]]; then
    return 0
  fi

  require_file "$hop_dir/prompt.md" "$hop_id prompt.md"
  require_file "$hop_dir/stream.jsonl" "$hop_id stream.jsonl"
  require_file "$hop_dir/stdout.txt" "$hop_id stdout.txt"
  require_file "$hop_dir/stderr.txt" "$hop_id stderr.txt"
  require_file "$hop_dir/final.md" "$hop_id final.md"
  require_file "$hop_dir/handoff.md" "$hop_id handoff.md"
  require_file "$hop_dir/validation.txt" "$hop_id validation.txt"

  if [[ -f "$hop_dir/validation.txt" ]]; then
    if grep -Eq '^FAIL ' "$hop_dir/validation.txt"; then
      fail "$hop_id validation.txt contains FAIL lines"
    elif grep -Eq '^PASS ' "$hop_dir/validation.txt"; then
      pass "$hop_id validation.txt records PASS"
    else
      warn "$hop_id validation.txt has no PASS/FAIL lines"
    fi
  fi

  if [[ -f "$hop_dir/prompt.md" ]]; then
    if grep -Fxq "Run id: $SUPERVISOR_RUN_ID" "$hop_dir/prompt.md"; then
      pass "$hop_id prompt run id matches run.env"
    elif [[ -n "$SUPERVISOR_RUN_ID" ]]; then
      fail "$hop_id prompt run id does not match run.env"
    fi

    if grep -Fxq "Hop: $hop_number" "$hop_dir/prompt.md"; then
      pass "$hop_id prompt hop matches"
    else
      fail "$hop_id prompt hop does not match $hop_number"
    fi
  fi

  validate_handoff "$hop_dir/handoff.md" "$hop_number"
  check_no_compaction_markers "$hop_dir"
}

validate_run() {
  local hop_paths=()
  local hop_path

  validate_preflight
  load_run_env

  while IFS= read -r hop_path; do
    hop_paths+=("$hop_path")
  done < <(find "$RUN_DIR" -maxdepth 1 -type d -name 'hop-[0-9][0-9][0-9]*' | sort)

  if [[ "${#hop_paths[@]}" -eq 0 ]]; then
    fail "run has no hop directories"
    return 0
  fi

  if [[ "${#hop_paths[@]}" -eq 1 ]]; then
    pass "run has 1 hop directory"
  else
    pass "run has ${#hop_paths[@]} hop directories"
  fi

  for hop_path in "${hop_paths[@]}"; do
    validate_hop_dir "$(basename "$hop_path")"
  done
}

case "$LEVEL" in
  preflight)
    validate_preflight
    ;;
  hop)
    load_run_env
    validate_preflight
    if [[ -z "$HOP_ARG" ]]; then
      HOP_ARG="001"
    fi
    validate_hop_dir "$(normalize_hop_id "$HOP_ARG")"
    ;;
  run)
    validate_run
    ;;
esac

if [[ "$failures" -eq 0 ]]; then
  echo "PASS supervisor validation passed with $warnings warning(s)"
  exit 0
fi

echo "FAIL supervisor validation failed with $failures failure(s) and $warnings warning(s)" >&2
exit 1
