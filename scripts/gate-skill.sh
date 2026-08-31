#!/bin/bash
# gate-skill.sh - Blind live regression gate for programmatic skills
#
# Usage:
#   scripts/gate-skill.sh skills/<name>/ [--baseline <sha>] [--dry-run]
#                                        [--model <alias>] [--timeout <seconds>]
#
# Runs the skill against every held-out prompt in skills/<name>/fixtures/,
# scores each run with the skill's own evaluate script, appends one gate trace
# per fixture to the repo's FEEDBACK.jsonl, and compares the result to the
# baseline. Exit 1 on a regression, with the revert line printed; the gate
# never reverts. Exit 3 when the skill cannot be gated at all.
#
# Blind: the copy the runner loads has no MEMO.md, no memo/ and no
# loading.on_failure, so the score measures the skill alone (ADR 0003). Real
# runs still load the wiki on failure; only the gate is blind.
#
# --- The runner invocation, established empirically on 2026-08-31 -----------
#
# claude 2.1.251. What works, and is what this script runs:
#
#   claude -p --model <alias> --output-format json \
#          --plugin-dir <tmp>/<plugin> -- "/<plugin>:<skill> <fixture prompt>"
#
# where <tmp>/<plugin>/ is plugin-shaped:
#
#   <tmp>/<plugin>/.claude-plugin/plugin.json   {"name": "<plugin>", ...}
#   <tmp>/<plugin>/skills/<skill>/SKILL.md      the blind copy
#
# Three things that did NOT work, and why the invocation looks like this:
#
#   * `--bare` cannot authenticate here. It reads only ANTHROPIC_API_KEY or an
#     apiKeyHelper, never OAuth or the keychain, and prints
#     "Not logged in . Please run /login". The roadmap's sketched
#     `claude -p --bare --plugin-dir <tmp>` therefore never runs; the gate
#     drops --bare and keeps --plugin-dir.
#
#   * `--add-dir <tmp>` with the skill at <tmp>/.claude/skills/<name>/ does not
#     make that skill loadable. Probed with a sentinel line planted in the temp
#     SKILL.md, the run answered NO-SENTINEL: it had loaded the *deployed*
#     ~/.claude/skills/<name> instead. --add-dir grants tool access to a
#     directory; it is not a skill source.
#
#   * Naming the skill in prose ("Use the centers-of-excellence skill") also
#     resolves the deployed copy, which still has its wiki and is not the copy
#     under test. There is no flag that hides ~/.claude/skills. The plugin
#     namespace is what separates them: the temp copy is only ever reachable as
#     /<plugin>:<skill>, so an explicit slash invocation cannot be shadowed.
#     The same sentinel probe under --plugin-dir answered with the sentinel,
#     which is the proof this script relies on.
#
#   * `--add-dir` is variadic, so `--add-dir DIR "prompt"` eats the prompt as a
#     second directory. Every invocation here puts the prompt after `--`.
#
# `--output-format json` returns an array of events, not one object: the
# skill's output is every assistant text block in order (the last message alone
# is often the epilogue's bookkeeping, not the answer), and session_id comes
# from the same array so a gate trace can point at its session.
#
# There is no --max-turns in 2.1.251; a live run is bounded by --timeout here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE_PY="$SCRIPT_DIR/lib/gate.py"
LOG_FEEDBACK="$SCRIPT_DIR/log-feedback.sh"

PLUGIN_UNDER_TEST="smgate"
PLUGIN_BASELINE="smgatebase"
PROMPT_TRUNCATE=200

MODEL="${SKILLMONGER_GATE_MODEL:-sonnet}"
TIMEOUT="${SKILLMONGER_GATE_TIMEOUT:-900}"
BASELINE_SHA=""
DRY_RUN=0
SKILL_ARG=""

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") skills/<name>/ [options]

Options:
  --baseline <sha>   Re-run that commit's SKILL.md as the baseline instead of
                     reading the previous gate traces out of FEEDBACK.jsonl
  --dry-run          Print the plan (fixtures, blind changes, invocation,
                     baseline source) and exit without invoking the model
  --model <alias>    Runner model (default: $MODEL; SKILLMONGER_GATE_MODEL)
  --timeout <secs>   Per-fixture wall clock (default: $TIMEOUT; SKILLMONGER_GATE_TIMEOUT)

Exit: 0 ok, 1 regression, 2 usage, 3 not gateable, 4 the run itself failed
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline) [ $# -ge 2 ] || usage; BASELINE_SHA="$2"; shift 2 ;;
    --baseline=*) BASELINE_SHA="${1#--baseline=}"; shift ;;
    --model) [ $# -ge 2 ] || usage; MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#--model=}"; shift ;;
    --timeout) [ $# -ge 2 ] || usage; TIMEOUT="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#--timeout=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    -*) echo "gate-skill.sh: unknown option: $1" >&2; usage ;;
    *) [ -z "$SKILL_ARG" ] || usage; SKILL_ARG="$1"; shift ;;
  esac
done

[ -n "$SKILL_ARG" ] || usage
[ -d "$SKILL_ARG" ] || { echo "gate-skill.sh: not a directory: $SKILL_ARG" >&2; exit 2; }
command -v python3 &> /dev/null || { echo "gate-skill.sh: python3 is required" >&2; exit 2; }

SKILL_DIR="$(cd "$SKILL_ARG" && pwd)"
SKILLS_DIR="$(dirname "$SKILL_DIR")"

# --- The evaluation contract, and whether this skill can be gated at all ----

CONTRACT="$(python3 "$GATE_PY" config "$SKILL_DIR" --shell)" || {
  echo "gate: could not read $SKILL_DIR/CONFIG.yaml" >&2
  exit 2
}
eval "$CONTRACT"

if [ -n "$GATE_REFUSAL" ]; then
  echo "gate: $GATE_REFUSAL" >&2
  exit 3
fi

read -r -a FIXTURES <<< "$GATE_FIXTURES"
SKILL_NAME="$GATE_NAME"
SKILL_MD_REL="skills/$SKILL_NAME/SKILL.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Where a revert would come from ----------------------------------------
#
# The gate prints this line and stops. Which commit it names depends on where
# the edit under test lives: an uncommitted SKILL.md is reverted to the last
# commit that touched it; a committed one to the commit before that.

revert_sha() {
  if [ -n "$BASELINE_SHA" ]; then
    git -C "$PROJECT_ROOT" rev-parse --short "$BASELINE_SHA" 2>/dev/null || echo "$BASELINE_SHA"
    return
  fi
  git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local skip=0
  if git -C "$PROJECT_ROOT" diff --quiet HEAD -- "$SKILL_MD_REL" 2>/dev/null; then
    skip=1
  fi
  git -C "$PROJECT_ROOT" log -n 1 --skip="$skip" --format=%h HEAD -- "$SKILL_MD_REL" 2>/dev/null || true
}

REVERT_SHA="$(revert_sha)"
REVERT_LINE=""
if [ -n "$REVERT_SHA" ]; then
  REVERT_LINE="git checkout $REVERT_SHA -- $SKILL_MD_REL"
fi

# --- The baseline ----------------------------------------------------------
#
# Read before anything is written, so this run's own traces can never become
# their own baseline.

BASELINE_JSON='{"version":null,"label":"none","outcomes":{}}'
BASELINE_VERSION=""
if [ -z "$BASELINE_SHA" ]; then
  BASELINE_JSON="$(python3 "$GATE_PY" baseline "$SKILLS_DIR" "$SKILL_NAME" \
    --fixtures "$GATE_FIXTURES" --current-version "$GATE_VERSION")"
else
  # The sha's own CONFIG names the version that produced the baseline traces.
  mkdir -p "$TMP/baseline-config"
  git -C "$PROJECT_ROOT" show "$BASELINE_SHA:skills/$SKILL_NAME/CONFIG.yaml" \
    > "$TMP/baseline-config/CONFIG.yaml" 2>/dev/null || true
  BASELINE_VERSION="$(python3 "$GATE_PY" version "$TMP/baseline-config")"
fi

BASELINE_LABEL="$(printf '%s' "$BASELINE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["label"])')"
if [ "$BASELINE_LABEL" = "none" ]; then
  BASELINE_LABEL="no baseline yet; this run becomes one"
fi
if [ -n "$BASELINE_SHA" ]; then
  BASELINE_LABEL="re-run of $BASELINE_SHA (version $BASELINE_VERSION)"
  if [ "$BASELINE_VERSION" = "$GATE_VERSION" ]; then
    echo "gate: warning: $BASELINE_SHA names the same skill.version ($GATE_VERSION) as" >&2
    echo "      the working tree, so both sets of gate traces land in one bucket and" >&2
    echo "      a later --impact cannot tell them apart. Bump skill.version first." >&2
  fi
fi

# --- The blind copies ------------------------------------------------------

BLIND_FLAG=""
[ "$GATE_BLIND" = "true" ] || BLIND_FLAG="--no-blind"

# make_plugin <plugin-name> [skill-md-file] - print what blinding removed
make_plugin() {
  local plugin="$1" skill_md="${2:-}"
  local root="$TMP/$plugin"
  mkdir -p "$root/.claude-plugin" "$root/skills"
  cat > "$root/.claude-plugin/plugin.json" <<EOF
{
  "name": "$plugin",
  "description": "skillmonger gate harness for $SKILL_NAME",
  "version": "0.0.0"
}
EOF
  if [ -n "$skill_md" ]; then
    python3 "$GATE_PY" blind "$SKILL_DIR" "$root/skills/$SKILL_NAME" \
      $BLIND_FLAG --skill-md "$skill_md"
  else
    python3 "$GATE_PY" blind "$SKILL_DIR" "$root/skills/$SKILL_NAME" $BLIND_FLAG
  fi
}

BLIND_REMOVED="$(make_plugin "$PLUGIN_UNDER_TEST" | paste -sd, - | sed 's/,/, /g')"
[ -n "$BLIND_REMOVED" ] || BLIND_REMOVED="(nothing; evaluation.blind is false)"

if [ -n "$BASELINE_SHA" ]; then
  git -C "$PROJECT_ROOT" show "$BASELINE_SHA:$SKILL_MD_REL" > "$TMP/baseline-SKILL.md" 2>/dev/null || {
    echo "gate: $BASELINE_SHA has no $SKILL_MD_REL" >&2
    exit 2
  }
  make_plugin "$PLUGIN_BASELINE" "$TMP/baseline-SKILL.md" >/dev/null
fi

# --- The plan --------------------------------------------------------------

echo "gate: $SKILL_NAME $GATE_VERSION ($GATE_MODE, runner $GATE_RUNNER, model $MODEL)"
echo "  fixtures:   ${#FIXTURES[@]} in $SKILL_DIR/fixtures/"
for case in "${FIXTURES[@]}"; do
  echo "    - $case: $(python3 "$GATE_PY" prompt "$SKILL_DIR" "$case" --truncate 72)"
done
echo "  blind:      removed $BLIND_REMOVED"
echo "  oracle:     $GATE_SCRIPT (skill output on ${GATE_INPUT_MODE})"
echo "  baseline:   $BASELINE_LABEL"
echo "  invocation: claude -p --model $MODEL --output-format json \\"
echo "                --plugin-dir \$TMP/$PLUGIN_UNDER_TEST -- \"/$PLUGIN_UNDER_TEST:$SKILL_NAME <fixture prompt>\""
echo "  traces:     appended to skills/$SKILL_NAME/FEEDBACK.jsonl (gate: true)"
if [ -n "$REVERT_LINE" ]; then
  echo "  on regression, the gate prints (and never runs): $REVERT_LINE"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo ""
  echo "  --dry-run: the model was not invoked."
  exit 0
fi

if [ "$SKILLS_DIR" != "$PROJECT_ROOT/skills" ]; then
  echo "gate: $SKILL_DIR is not under $PROJECT_ROOT/skills; a live run logs" >&2
  echo "      gate traces through log-feedback.sh, which writes there only." >&2
  exit 2
fi

# --- Running one fixture ---------------------------------------------------

RUNNER_BIN="${SKILLMONGER_GATE_RUNNER:-claude}"
command -v "$RUNNER_BIN" &> /dev/null || {
  echo "gate: runner not found on PATH: $RUNNER_BIN" >&2
  exit 4
}

TIMEOUT_BIN=""
if command -v timeout &> /dev/null; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout &> /dev/null; then
  TIMEOUT_BIN="gtimeout"
fi

# run_one <plugin> <case> <out-file> - prints the session id
run_one() {
  local plugin="$1" case="$2" out="$3"
  local prompt raw status
  prompt="$(python3 "$GATE_PY" prompt "$SKILL_DIR" "$case")"
  raw="$TMP/$plugin.$case.json"
  set +e
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$TIMEOUT" "$RUNNER_BIN" -p --model "$MODEL" --output-format json \
      --plugin-dir "$TMP/$plugin" -- "/$plugin:$SKILL_NAME $prompt" \
      > "$raw" 2> "$TMP/$plugin.$case.err"
  else
    "$RUNNER_BIN" -p --model "$MODEL" --output-format json \
      --plugin-dir "$TMP/$plugin" -- "/$plugin:$SKILL_NAME $prompt" \
      > "$raw" 2> "$TMP/$plugin.$case.err"
  fi
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    echo "gate: runner exited $status on fixture $case" >&2
    sed 's/^/      /' "$TMP/$plugin.$case.err" >&2 || true
    return 4
  fi
  OUT_FILE="$out" python3 -c '
import json, os, sys

raw = open(sys.argv[1]).read()
try:
    data = json.loads(raw)
except ValueError as exc:
    sys.stderr.write("gate: runner output is not JSON (%s)\n" % exc)
    sys.exit(4)
events = data if isinstance(data, list) else [data]

# The skill output is every assistant text block in order. The final message
# alone is often the epilogue doing its bookkeeping rather than the answer.
texts, session, result, failure = [], "", "", ""
for event in events:
    if not isinstance(event, dict):
        continue
    session = event.get("session_id") or session
    if event.get("type") == "assistant":
        for block in (event.get("message") or {}).get("content") or []:
            if isinstance(block, dict) and block.get("type") == "text" and block.get("text"):
                texts.append(block["text"])
    if event.get("type") == "result":
        result = event.get("result") or ""
        if event.get("is_error") or event.get("subtype") not in (None, "success"):
            failure = str(event.get("subtype") or "error")

body = "\n\n".join(texts).strip() or result.strip()
with open(os.environ["OUT_FILE"], "w") as handle:
    handle.write(body + "\n")
if failure:
    sys.stderr.write("gate: runner reported %s\n" % failure)
    sys.exit(4)
if not body:
    sys.stderr.write("gate: the runner produced no text\n")
    sys.exit(4)
print(session)
' "$raw"
}

# --- The gate run ----------------------------------------------------------

echo ""
CURRENT_JSON="$TMP/current.json"
BASELINE_RUN_JSON="$TMP/baseline-run.json"
echo '{}' > "$CURRENT_JSON"
echo '{}' > "$BASELINE_RUN_JSON"

# record <results-file> <case> <eval-json>
record() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, case, raw = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as handle:
    data = json.load(handle)
data[case] = json.loads(raw)["outcome"]
with open(path, "w") as handle:
    json.dump(data, handle)
PY
}

# one_pass <plugin> <case> <version-override> <results-file> <label>
one_pass() {
  local plugin="$1" case="$2" version="$3" results="$4" label="$5"
  local out session eval_json started elapsed
  out="$TMP/$plugin.$case.md"
  started="$(date +%s)"
  session="$(run_one "$plugin" "$case" "$out")" || return 4
  elapsed=$(( $(date +%s) - started ))
  eval_json="$(python3 "$GATE_PY" evaluate "$SKILL_DIR" "$out")"

  local args=("$SKILL_NAME" --from-evaluate - --gate --fixture "$case"
              --prompt "$(python3 "$GATE_PY" prompt "$SKILL_DIR" "$case" --truncate "$PROMPT_TRUNCATE")")
  [ -n "$session" ] && args+=(--session "$session")
  [ -n "$version" ] && args+=(--version "$version")
  printf '%s' "$eval_json" | "$LOG_FEEDBACK" "${args[@]}" > "$TMP/log.$plugin.$case" || {
    echo "gate: log-feedback.sh failed for $case" >&2
    cat "$TMP/log.$plugin.$case" >&2
    return 4
  }
  record "$results" "$case" "$eval_json"
  echo "  $label $case: outcome $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["outcome"])' "$eval_json") in ${elapsed}s -- $(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("note") or "no note")' "$eval_json")"
}

for case in "${FIXTURES[@]}"; do
  if [ -n "$BASELINE_SHA" ]; then
    one_pass "$PLUGIN_BASELINE" "$case" "$BASELINE_VERSION" "$BASELINE_RUN_JSON" "baseline" || exit 4
  fi
  one_pass "$PLUGIN_UNDER_TEST" "$case" "" "$CURRENT_JSON" "run     " || exit 4
done

# --- The verdict -----------------------------------------------------------

echo ""
set +e
BASELINE_JSON="$BASELINE_JSON" \
BASELINE_RUN="$(cat "$BASELINE_RUN_JSON")" \
BASELINE_SHA="$BASELINE_SHA" \
BASELINE_LABEL="$BASELINE_LABEL" \
CURRENT="$(cat "$CURRENT_JSON")" \
EXPECT="$(python3 "$GATE_PY" expect "$SKILL_DIR")" \
TOLERANCE="$GATE_TOLERANCE" \
REVERT="$REVERT_LINE" \
SKILL="$SKILL_NAME" \
VERSION="$GATE_VERSION" \
python3 -c '
import json, os
payload = {
    "skill": os.environ["SKILL"],
    "version": os.environ["VERSION"],
    "tolerance": float(os.environ["TOLERANCE"]),
    "baseline_label": os.environ["BASELINE_LABEL"],
    "current": json.loads(os.environ["CURRENT"]),
    "expect": json.loads(os.environ["EXPECT"]),
    "revert": os.environ["REVERT"],
}
if os.environ["BASELINE_SHA"]:
    payload["baseline"] = json.loads(os.environ["BASELINE_RUN"])
else:
    payload["baseline"] = json.loads(os.environ["BASELINE_JSON"])["outcomes"]
print(json.dumps(payload))
' | python3 "$GATE_PY" compare
VERDICT=$?
set -e

echo ""
if [ "$VERDICT" -eq 0 ]; then
  echo "gate: passed. ${#FIXTURES[@]} gate trace(s) appended to skills/$SKILL_NAME/FEEDBACK.jsonl"
else
  echo "gate: regression. The traces are kept; nothing was reverted."
fi
exit "$VERDICT"
