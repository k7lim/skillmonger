#!/bin/bash
# render-epilogue.sh - Print the format-2 "After Execution" epilogue for a skill
#
# Usage:
#   scripts/render-epilogue.sh skills/<name>/ [--question-file <path>]
#
# The epilogue is rendered from CONFIG.yaml so all skills say the same thing in
# the same words. It never mentions iteration_count (harvest derives it, ADR
# 0002) and never references scripts/log-feedback.sh (a deployed copy on SRT or
# Pi cannot reach it).
#
# Inputs read from CONFIG.yaml:
#   skill.name                        - defaults to the directory name
#   evaluation.mode                   - programmatic | qualitative | delayed | hybrid
#                                       defaults to programmatic when an
#                                       evaluate script exists, else qualitative
#   evaluation.script                 - path, relative to the skill directory
#   evaluation.script_emits_outcome   - default true
#
# script_emits_outcome is the generic escape hatch for an evaluator whose JSON
# has no trustworthy `outcome` for this skill's own work (writing-voice-coach's
# evaluate.py scores the text the user brought in, not the critique the skill
# produced). Declaring it in CONFIG was chosen over sniffing the script: it is
# one grep to audit, it needs no execution of arbitrary code at render time, and
# a skill that changes its evaluator changes one line beside it.
#
# --question-file supplies the skill's own self-assessment question, used by
# qualitative, delayed and hybrid modes. Without it the generic 1-5 scale from
# docs/skill-format.md is rendered.
set -euo pipefail

SKILL_DIR=""
QUESTION_FILE=""

usage() {
  echo "Usage: render-epilogue.sh <skill-dir> [--question-file <path>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --question-file)
      [ $# -ge 2 ] || usage
      QUESTION_FILE="$2"
      shift 2
      ;;
    --question-file=*)
      QUESTION_FILE="${1#--question-file=}"
      shift
      ;;
    -h|--help) usage ;;
    -*) echo "render-epilogue.sh: unknown option: $1" >&2; usage ;;
    *)
      [ -z "$SKILL_DIR" ] || usage
      SKILL_DIR="$1"
      shift
      ;;
  esac
done

[ -n "$SKILL_DIR" ] || usage
[ -d "$SKILL_DIR" ] || { echo "render-epilogue.sh: not a directory: $SKILL_DIR" >&2; exit 1; }

SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
CONFIG="$SKILL_DIR/CONFIG.yaml"

have_pyyaml() {
  command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null
}

# cfg_get <dotted.path> - print a scalar from CONFIG.yaml, or nothing.
# PyYAML when available, two-level sed otherwise.
cfg_get() {
  local path="$1"
  [ -f "$CONFIG" ] || return 0
  if have_pyyaml; then
    python3 - "$CONFIG" "$path" <<'PY' 2>/dev/null || true
import sys, yaml
try:
    node = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(0)
for part in sys.argv[2].split("."):
    if not isinstance(node, dict):
        sys.exit(0)
    node = node.get(part)
if node is None:
    sys.exit(0)
print("true" if node is True else "false" if node is False else node)
PY
  else
    local top="${path%%.*}" key="${path#*.}"
    if [ "$top" = "$key" ]; then
      sed -n "s/^${top}:[[:space:]]*\([^#]*\)/\1/p" "$CONFIG" \
        | head -1 | sed 's/[[:space:]]*$//' | tr -d "\"'"
    else
      sed -n "/^${top}:/,/^[^[:space:]#]/p" "$CONFIG" \
        | sed -n "s/^[[:space:]]\{1,\}${key}:[[:space:]]*\([^#]*\)/\1/p" \
        | head -1 | sed 's/[[:space:]]*$//' | tr -d "\"'"
    fi
  fi
}

trim() { sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//'; }

# --- Resolve the skill's evaluation contract --------------------------------

SKILL_NAME="$(cfg_get skill.name | trim)"
[ -n "$SKILL_NAME" ] || SKILL_NAME="$(basename "$SKILL_DIR")"

EVAL_SCRIPT="$(cfg_get evaluation.script | trim)"
if [ -z "$EVAL_SCRIPT" ]; then
  for candidate in "$SKILL_DIR"/scripts/evaluate*; do
    [ -f "$candidate" ] || continue
    EVAL_SCRIPT="scripts/$(basename "$candidate")"
    break
  done
fi

MODE="$(cfg_get evaluation.mode | trim)"
if [ -z "$MODE" ]; then
  if [ -n "$EVAL_SCRIPT" ]; then MODE="programmatic"; else MODE="qualitative"; fi
fi

case "$MODE" in
  programmatic|qualitative|delayed|hybrid) ;;
  *) echo "render-epilogue.sh: $SKILL_NAME: unknown evaluation.mode '$MODE'" >&2; exit 1 ;;
esac

EMITS_OUTCOME="$(cfg_get evaluation.script_emits_outcome | trim)"
[ -n "$EMITS_OUTCOME" ] || EMITS_OUTCOME="true"

if [ "$MODE" = "programmatic" ] || [ "$MODE" = "hybrid" ]; then
  if [ -z "$EVAL_SCRIPT" ]; then
    echo "render-epilogue.sh: $SKILL_NAME: mode $MODE needs evaluation.script" >&2
    exit 1
  fi
fi

# An evaluator that does not emit a usable outcome cannot decide the score, so
# the run is scored by self-assessment with the script's report as evidence.
SCRIPT_SCORES="yes"
if [ "$EMITS_OUTCOME" = "false" ]; then SCRIPT_SCORES="no"; fi

# The command line shown in the epilogue. The documented contract is "output on
# stdin or as $1"; evaluators that take something else (a project directory, a
# saved JSON file) declare their own line in evaluation.script_usage.
EVAL_USAGE="$(cfg_get evaluation.script_usage | trim)"
[ -n "$EVAL_USAGE" ] || EVAL_USAGE="$EVAL_SCRIPT   # takes the output on stdin, or as its first argument"

# --- Pieces ------------------------------------------------------------------

SCALE="1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent"

# The skill's own question, verbatim. A question that does not already anchor
# the scale (its own "Map: 5=..." line) gets the standard one appended, so the
# epilogue is never a question with no numbers attached.
# Reads through cat rather than testing -s so a process substitution works.
question_block() {
  local text=""
  if [ -n "$QUESTION_FILE" ]; then
    # A caller may hand over a raw slice of the old epilogue. Normalise it so
    # the rendered epilogue keeps its invariants whatever it is given: no second
    # "## After Execution" heading, and no line that names the plumbing format 2
    # removed.
    text="$(cat "$QUESTION_FILE" | sed '/^## After Execution[[:space:]]*$/d')"
    local plumbing
    plumbing="$(printf '%s\n' "$text" | grep -nE 'iteration_count|log-feedback' || true)"
    if [ -n "$plumbing" ]; then
      echo "render-epilogue.sh: $SKILL_NAME: dropping question lines that name format-1 plumbing:" >&2
      printf '%s\n' "$plumbing" | sed 's/^/  /' >&2
      text="$(printf '%s\n' "$text" | grep -vE 'iteration_count|log-feedback')"
    fi
    # collapse the blank lines the deletions leave behind
    text="$(printf '%s\n' "$text" | cat -s)"
  fi
  if [ -z "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    echo "Self-assess this run on the standard scale: $SCALE."
    return
  fi
  printf '%s\n' "$text"
  if ! printf '%s' "$text" | grep -qE '[1-5][[:space:]]*=|=[[:space:]]*[1-5]'; then
    echo ""
    echo "Score it on the standard scale: $SCALE."
  fi
}

run_the_evaluator() {
  cat <<EOF
Run this skill's evaluator on the output you just produced:

\`\`\`bash
$EVAL_USAGE
\`\`\`
EOF
  echo ""
  if [ "$SCRIPT_SCORES" = "yes" ]; then
    echo "It prints \`{\"outcome\":1-5,\"note\":\"...\",\"checks\":{...},\"source\":\"script\"}\`."
  else
    echo "It prints a JSON report of what it checked."
  fi
}

trace_block() { # trace_block <source> <outcome-slot> <note-slot> [checks]
  local source="$1" outcome="$2" note="$3" checks="${4:-}"
  local checks_field=""
  [ -n "$checks" ] && checks_field="\"checks\":$checks,"

  cat <<EOF
Append one JSON line to \`FEEDBACK.jsonl\` in this skill directory — the copy you
are running from, not the skillmonger repo:

\`\`\`json
{"ts":"<UTC ISO 8601>","skill":"$SKILL_NAME","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":$outcome,"note":"$note",${checks_field}"source":"$source","session":"<this session's id>","schema_version":1}
\`\`\`

Drop \`session\` if you do not know this session's id. That line is the whole
record: nothing in \`CONFIG.yaml\` is edited by a run.
EOF
}

fallback_block() {
  cat <<'EOF'
If the evaluator cannot run, say why in `note`, score the run yourself on the
standard scale (1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent), and set
`"source":"llm"`.
EOF
}

no_outcome_note() {
  cat <<'EOF'
`CONFIG.yaml` marks this evaluator as not producing the run's `outcome`
(`evaluation.script_emits_outcome: false`), so read its report as evidence and
score the run yourself.
EOF
}

# --- Render ------------------------------------------------------------------

echo "## After Execution"
echo ""

case "$MODE" in
  programmatic)
    if [ "$SCRIPT_SCORES" = "yes" ]; then
      run_the_evaluator
      echo ""
      echo "Copy its \`outcome\`, \`note\` and \`checks\` straight through — do not re-score"
      echo "them yourself."
      echo ""
      trace_block script "<the evaluator's outcome>" "<the evaluator's note>" "<the evaluator's checks object>"
      echo ""
      fallback_block
    else
      run_the_evaluator
      echo ""
      no_outcome_note
      echo ""
      question_block
      echo ""
      trace_block llm "<1-5>" "<one line, especially when the outcome is not 4>"
      echo ""
      echo "Use \`\"source\":\"user\"\` when the score came from the user rather than from your"
      echo "own assessment."
    fi
    ;;

  hybrid)
    echo "Two things are worth recording about this run: what the evaluator can check,"
    echo "and what only a person can judge."
    echo ""
    echo "**1. Run the evaluator.**"
    echo ""
    run_the_evaluator
    echo ""
    echo "**2. Ask, then judge.**"
    echo ""
    question_block
    echo ""
    echo "**3. Record both.** Append one JSON line per source to \`FEEDBACK.jsonl\` in this"
    echo "skill directory — the copy you are running from, not the skillmonger repo:"
    echo ""
    cat <<EOF
\`\`\`json
{"ts":"<UTC ISO 8601>","skill":"$SKILL_NAME","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"$SKILL_NAME","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
\`\`\`
EOF
    echo ""
    echo "Use \`\"source\":\"llm\"\` on the second line when you judged the run yourself"
    echo "instead of asking. Drop \`session\` if you do not know this session's id. Those"
    echo "lines are the whole record: nothing in \`CONFIG.yaml\` is edited by a run."
    ;;

  qualitative)
    question_block
    echo ""
    trace_block llm "<1-5>" "<one line, especially when the outcome is not 4>"
    echo ""
    echo "Use \`\"source\":\"user\"\` when the score came from the user rather than from your"
    echo "own assessment."
    ;;

  delayed)
    echo "Do not score this run now — the ground truth for it arrives later. When it"
    echo "does, come back to this skill directory and record what actually happened."
    echo ""
    question_block
    echo ""
    trace_block user "<1-5>" "<what the ground truth showed>"
    ;;
esac
