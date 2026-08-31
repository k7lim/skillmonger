#!/bin/bash
# log-feedback.sh - Record one feedback entry to FEEDBACK.jsonl and increment iteration_count
#
# Concurrency: a gate run calls this once per fixture, and several gate runs,
# a harvest or a sync-back may be writing the same skill at once. The append
# and the iteration_count bump are one critical section under the skill's
# lock (skills/<name>/.lock/, lib/skill-lock.sh; harvest.py and
# sync-skill-back.sh take the same one). The trace goes out as one
# `printf >>` of the whole line, so it can never be torn, and CONFIG.yaml is
# rewritten to a temp file beside it and renamed into place, so no reader
# ever sees a half-written CONFIG. The lock is taken only after every prompt
# has been answered, so an interactive session never holds it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLMONGER_SKILLS_DIR:-$PROJECT_ROOT/skills}"

# shellcheck source=lib/skill-lock.sh
. "$SCRIPT_DIR/lib/skill-lock.sh"

# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") <skill-name> [options]

Records a feedback entry to skills/<skill-name>/FEEDBACK.jsonl
and increments iteration_count in CONFIG.yaml.

Arguments:
  skill-name    Name of the skill (directory under skills/)

Options:
  --outcome N       Score 1-5 (1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent)
  --prompt TEXT     The prompt or task that was executed
  --note TEXT       Optional note about the outcome
  --source TYPE     Rating source: user (default), llm, or script
  --session ID      Session the run came from (a pj-indexed transcript id)
  --version VALUE   Skill version this run used, when it is not the version
                    CONFIG.yaml names today (gate-skill.sh --baseline <sha>
                    re-runs an older SKILL.md and must record its own version)
  --from-evaluate F Take outcome, note and checks from an evaluate script's
                    JSON (a file, or - for stdin). Implies --source script.
  --gate            Mark the trace as written by a gate run, not a real run
  --fixture NAME    Fixture the gate run used
  --help            Show this help message

Interactive mode: omit options to be prompted for each field.

Environment:
  SKILLMONGER_SKILLS_DIR  Repo-side skills/ directory (default: $PROJECT_ROOT/skills)
  SKILLMONGER_LOCK_WAIT   Seconds to wait for the skill's writer lock (default 60)
  SKILLMONGER_LOCK_STALE  Age in seconds past which a leftover lock is removed (default 120)

This is for in-repo use -- gate runs and manual logging. Agents run deployed
copies that cannot reach this repo, so their epilogues append the trace to the
deployed copy and harvest-feedback.sh brings it home (ADR 0002).

Examples:
  $(basename "$0") centers-of-excellence --outcome 4 --prompt "find CoE for tulips" --source user
  $(basename "$0") yt-dlp                # interactive mode
  skills/x/scripts/evaluate.sh out.md | $(basename "$0") x --from-evaluate - --prompt "..."
EOF
}

# --- Parse Arguments ---

SKILL_NAME=""
OUTCOME=""
PROMPT_TEXT=""
NOTE=""
SOURCE="user"
SESSION=""
VERSION_OVERRIDE=""
FIXTURE=""
GATE=false
CHECKS_JSON=""
FROM_EVALUATE=""
USE_EVALUATE=false
# Which fields the caller set explicitly. An explicit flag overrides whatever
# --from-evaluate read out of the evaluate script's JSON.
OUTCOME_SET=false
NOTE_SET=false
SOURCE_SET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --outcome)
      OUTCOME="$2"
      OUTCOME_SET=true
      shift 2
      ;;
    --prompt)
      PROMPT_TEXT="$2"
      shift 2
      ;;
    --note)
      NOTE="$2"
      NOTE_SET=true
      shift 2
      ;;
    --source)
      SOURCE="$2"
      SOURCE_SET=true
      shift 2
      ;;
    --session)
      SESSION="$2"
      shift 2
      ;;
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --fixture)
      FIXTURE="$2"
      shift 2
      ;;
    --gate)
      GATE=true
      shift
      ;;
    --from-evaluate)
      USE_EVALUATE=true
      # The argument is optional and stdin is the default. Only "-" or an
      # existing file is consumed, so `--from-evaluate my-skill` still names
      # the skill rather than swallowing it.
      FROM_EVALUATE="-"
      if [ $# -gt 1 ] && { [ "$2" = "-" ] || [ -f "$2" ]; }; then
        FROM_EVALUATE="$2"
        shift
      fi
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1"
      usage
      exit 1
      ;;
    *)
      if [ -z "$SKILL_NAME" ]; then
        skill_name_require "$1"
        SKILL_NAME="$1"
      else
        echo "Error: Unexpected argument $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$SKILL_NAME" ]; then
  echo "Error: skill-name is required"
  echo ""
  usage
  exit 1
fi

SKILL_DIR="$SKILLS_DIR/$SKILL_NAME"

if [ ! -d "$SKILL_DIR" ]; then
  echo "Error: Skill directory not found: $SKILL_DIR"
  exit 1
fi
skill_dir_require "$SKILL_DIR" "$SKILLS_DIR"

# --- Evaluate output (--from-evaluate) ---
#
# The evaluate script is the deterministic bookend: it has already scored the
# run and recorded which checks it ran. Copying its JSON into the trace keeps
# the score and its evidence together instead of asking the caller to retype
# them, which is what a gate run needs.

if [ "$USE_EVALUATE" = true ]; then
  if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required to read evaluate output (--from-evaluate)." >&2
    exit 1
  fi

  if [ "$FROM_EVALUATE" = "-" ]; then
    EVAL_RAW=$(cat)
  else
    EVAL_RAW=$(cat "$FROM_EVALUATE")
  fi

  # Three lines out: the outcome, the note already JSON-escaped (so a
  # multi-line note stays on one line), and the checks as compact JSON.
  set +e
  EVAL_FIELDS=$(EVAL_RAW="$EVAL_RAW" EVAL_SKILL="$SKILL_NAME" python3 -c '
import json, os, sys

raw = os.environ["EVAL_RAW"]
skill = os.environ["EVAL_SKILL"]
try:
    data = json.loads(raw)
except ValueError as exc:
    sys.stderr.write("Error: evaluate output is not JSON (%s)\n" % exc)
    sys.exit(1)
if not isinstance(data, dict):
    sys.stderr.write("Error: evaluate output is not a JSON object\n")
    sys.exit(1)

outcome = data.get("outcome")
if outcome is None:
    sys.stderr.write(
        "Error: evaluate output carries no outcome; this evaluate script does not "
        "score the run.\n"
        "       Take the self-assessment path instead: read the After Execution "
        "criteria in\n"
        "       skills/%s/SKILL.md, score the run 1-5 yourself, and log that score:\n"
        "         scripts/log-feedback.sh %s --outcome N --note ... --source llm\n"
        % (skill, skill)
    )
    sys.exit(2)

print(outcome if isinstance(outcome, int) else str(outcome).strip())
print(json.dumps(data.get("note") or "", ensure_ascii=False)[1:-1])
checks = data.get("checks")
if checks is None or checks == {} or checks == []:
    print("")
else:
    print(json.dumps(checks, ensure_ascii=False, separators=(",", ":")))
')
  EVAL_STATUS=$?
  set -e
  if [ "$EVAL_STATUS" -ne 0 ]; then
    exit "$EVAL_STATUS"
  fi

  EVAL_OUTCOME=$(printf '%s\n' "$EVAL_FIELDS" | sed -n '1p')
  EVAL_NOTE=$(printf '%s\n' "$EVAL_FIELDS" | sed -n '2p')
  CHECKS_JSON=$(printf '%s\n' "$EVAL_FIELDS" | sed -n '3p')

  if [ "$OUTCOME_SET" = false ]; then
    OUTCOME="$EVAL_OUTCOME"
  fi
  if [ "$NOTE_SET" = false ]; then
    # Already JSON-escaped by python, so json_escape must not run on it again.
    ESCAPED_EVAL_NOTE="$EVAL_NOTE"
    NOTE_SET=true
  fi
  if [ "$SOURCE_SET" = false ]; then
    SOURCE="script"
  fi
fi

# --- Interactive Mode (fill missing fields) ---

if [ -z "$OUTCOME" ]; then
  echo "Outcome (1-5):"
  echo "  1 = Failed (could not execute or wrong output)"
  echo "  2 = Poor (executed but required major rework)"
  echo "  3 = Acceptable (usable with minor edits)"
  echo "  4 = Good (correct, no edits needed)"
  echo "  5 = Excellent (exceeded expectations)"
  while true; do
    read -rp "> " OUTCOME
    if [[ "$OUTCOME" =~ ^[1-5]$ ]]; then
      break
    fi
    echo "  Enter a number 1-5"
  done
fi

# Validate outcome
if ! [[ "$OUTCOME" =~ ^[1-5]$ ]]; then
  echo "Error: outcome must be 1-5, got: $OUTCOME"
  exit 1
fi

if [ -z "$PROMPT_TEXT" ]; then
  read -rp "Prompt/task (what was executed): " PROMPT_TEXT
fi

if [ "$NOTE_SET" = false ] && [ -z "$NOTE" ]; then
  read -rp "Note (optional, press enter to skip): " NOTE
fi

# Validate source
case "$SOURCE" in
  user|llm|script) ;;
  *)
    echo "Error: source must be user, llm, or script, got: $SOURCE"
    exit 1
    ;;
esac

# --- Read current version from CONFIG.yaml ---

VERSION="unknown"
CONFIG_FILE="$SKILL_DIR/CONFIG.yaml"

# A run against an older SKILL.md is a run of that older version, whatever
# CONFIG.yaml says today. Only the caller knows; --version is how it says so.
if [ -n "$VERSION_OVERRIDE" ]; then
  VERSION="$VERSION_OVERRIDE"
elif [ -f "$CONFIG_FILE" ]; then
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    VERSION=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('skill',{}).get('version','unknown'))" 2>/dev/null || echo "unknown")
  else
    VERSION=$(grep "^[[:space:]]*version:" "$CONFIG_FILE" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
    VERSION="${VERSION:-unknown}"
  fi
fi

# --- Build JSON entry ---

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escape strings for JSON (handle quotes and backslashes)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

ESCAPED_PROMPT=$(json_escape "$PROMPT_TEXT")
if [ -n "${ESCAPED_EVAL_NOTE+set}" ]; then
  ESCAPED_NOTE="$ESCAPED_EVAL_NOTE"
else
  ESCAPED_NOTE=$(json_escape "$NOTE")
fi

# Optional fields are written only when set, so a plain manual entry is the
# line it has always been. Readers tolerate extra fields; schema_version
# stays 1.
OPTIONAL_FIELDS=""
if [ -n "$SESSION" ]; then
  OPTIONAL_FIELDS="$OPTIONAL_FIELDS,\"session\":\"$(json_escape "$SESSION")\""
fi
if [ -n "$CHECKS_JSON" ]; then
  OPTIONAL_FIELDS="$OPTIONAL_FIELDS,\"checks\":$CHECKS_JSON"
fi
if [ "$GATE" = true ]; then
  OPTIONAL_FIELDS="$OPTIONAL_FIELDS,\"gate\":true"
fi
if [ -n "$FIXTURE" ]; then
  OPTIONAL_FIELDS="$OPTIONAL_FIELDS,\"fixture\":\"$(json_escape "$FIXTURE")\""
fi

JSON_LINE="{\"ts\":\"$TIMESTAMP\",\"skill\":\"$SKILL_NAME\",\"version\":\"$VERSION\",\"prompt\":\"$ESCAPED_PROMPT\",\"outcome\":$OUTCOME,\"note\":\"$ESCAPED_NOTE\",\"source\":\"$SOURCE\"$OPTIONAL_FIELDS,\"schema_version\":1}"

# --- Append to FEEDBACK.jsonl ---
#
# From here to the CONFIG rewrite is the critical section: everything the
# caller could be asked has been asked, and the lock is released on exit
# whichever way the script leaves.

skill_lock "$SKILL_DIR" || exit 1
trap skill_unlock EXIT

FEEDBACK_FILE="$SKILL_DIR/FEEDBACK.jsonl"
# One write of the whole line into an O_APPEND file: a concurrent appender
# can land before or after it, never inside it.
printf '%s\n' "$JSON_LINE" >> "$FEEDBACK_FILE"
echo "Logged feedback to $FEEDBACK_FILE"

# --- Increment iteration_count in CONFIG.yaml ---
#
# One line changes, in place. This used to be a PyYAML load-and-dump, which
# rewrites the whole file: every comment gone, every list re-indented. Nobody
# noticed while the only caller was a human logging one trace by hand; a gate
# run calls this once per fixture and would strip a CONFIG on its first pass.
# The result lands by rename, so the file is never seen half-written.

if [ -f "$CONFIG_FILE" ]; then
  if command -v python3 &> /dev/null; then
    CONFIG_FILE="$CONFIG_FILE" python3 <<'PYEOF'
import os
import re

path = os.environ["CONFIG_FILE"]
with open(path) as handle:
    lines = handle.read().splitlines(True)

KEY = re.compile(r"^(\s*)([A-Za-z0-9_.-]+):(.*)$")


def top_level(line):
    return bool(line.strip()) and not line[:1].isspace()


# The compaction: block, as a line range.
start = end = None
for index, line in enumerate(lines):
    if not top_level(line):
        continue
    if start is not None:
        end = index
        break
    match = KEY.match(line)
    if match and match.group(2) == "compaction":
        start = index
if start is not None and end is None:
    end = len(lines)

current = None
if start is not None:
    for index in range(start + 1, end):
        match = KEY.match(lines[index])
        if match and match.group(1) and match.group(2) == "iteration_count":
            current = int(re.sub(r"[^0-9-]", "", match.group(3)) or 0)
            lines[index] = "%siteration_count: %d\n" % (match.group(1), current + 1)
            break

if current is None:
    current = 0
    if start is not None:
        insert = start + 1
        for index in range(start + 1, end):
            if lines[index].strip():
                insert = index + 1
        lines.insert(insert, "  iteration_count: 1\n")
    else:
        if lines and not lines[-1].endswith("\n"):
            lines.append("\n")
        lines.append("\ncompaction:\n  iteration_count: 1\n")

tmp = "%s.tmp.%d" % (path, os.getpid())
with open(tmp, "w") as handle:
    handle.write("".join(lines))
try:
    os.chmod(tmp, os.stat(path).st_mode)
except OSError:
    pass
os.replace(tmp, path)

print("  iteration_count: %d -> %d" % (current, current + 1))
PYEOF
  else
    # Fallback: sed-based increment (less reliable but works without python3)
    current=$(grep "iteration_count:" "$CONFIG_FILE" | head -1 | sed 's/.*iteration_count:[[:space:]]*//' | xargs)
    current="${current:-0}"
    new_count=$((current + 1))
    CONFIG_TMP="$CONFIG_FILE.tmp.$$"
    sed "s/iteration_count:[[:space:]]*$current/iteration_count: $new_count/" "$CONFIG_FILE" > "$CONFIG_TMP"
    mv -f "$CONFIG_TMP" "$CONFIG_FILE"
    echo "  iteration_count: $current -> $new_count"
  fi
else
  echo "  No CONFIG.yaml found - skipping iteration_count increment"
fi

skill_unlock

# --- Is compaction due? ---
#
# The trigger is not this script's to decide: harvest-feedback.sh and
# compact-memo.sh must answer identically, so all three call compaction.py.
# It counts the failing traces itself, so the trace just written is included.
if command -v python3 &> /dev/null; then
  echo ""
  python3 "$SCRIPT_DIR/lib/compaction.py" --skill-dir "$SKILL_DIR"
fi
