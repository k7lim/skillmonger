#!/bin/bash
# log-feedback.sh - Record one feedback entry to FEEDBACK.jsonl and increment iteration_count
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"

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
  --help            Show this help message

Interactive mode: omit options to be prompted for each field.

Examples:
  $(basename "$0") centers-of-excellence --outcome 4 --prompt "find CoE for tulips" --source user
  $(basename "$0") yt-dlp                # interactive mode
EOF
}

# --- Parse Arguments ---

SKILL_NAME=""
OUTCOME=""
PROMPT_TEXT=""
NOTE=""
SOURCE="user"

while [[ $# -gt 0 ]]; do
  case $1 in
    --outcome)
      OUTCOME="$2"
      shift 2
      ;;
    --prompt)
      PROMPT_TEXT="$2"
      shift 2
      ;;
    --note)
      NOTE="$2"
      shift 2
      ;;
    --source)
      SOURCE="$2"
      shift 2
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

if [ -z "$NOTE" ]; then
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

if [ -f "$CONFIG_FILE" ]; then
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
ESCAPED_NOTE=$(json_escape "$NOTE")

JSON_LINE="{\"ts\":\"$TIMESTAMP\",\"skill\":\"$SKILL_NAME\",\"version\":\"$VERSION\",\"prompt\":\"$ESCAPED_PROMPT\",\"outcome\":$OUTCOME,\"note\":\"$ESCAPED_NOTE\",\"source\":\"$SOURCE\",\"schema_version\":1}"

# --- Append to FEEDBACK.jsonl ---

FEEDBACK_FILE="$SKILL_DIR/FEEDBACK.jsonl"
echo "$JSON_LINE" >> "$FEEDBACK_FILE"
echo "Logged feedback to $FEEDBACK_FILE"

# --- Increment iteration_count in CONFIG.yaml ---

if [ -f "$CONFIG_FILE" ]; then
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    python3 << PYEOF
import yaml

with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)

if 'compaction' not in config:
    config['compaction'] = {}

current = config['compaction'].get('iteration_count', 0)
config['compaction']['iteration_count'] = current + 1

with open('$CONFIG_FILE', 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print(f"  iteration_count: {current} -> {current + 1}")

threshold = config['compaction'].get('cycle_threshold', 15)
if current + 1 >= threshold:
    print(f"  Compaction recommended! ({current + 1} >= {threshold})")
    print(f"  Run: scripts/compact-memo.sh skills/{config.get('skill',{}).get('name','')}/")
PYEOF
  else
    # Fallback: sed-based increment (less reliable but works without PyYAML)
    current=$(grep "iteration_count:" "$CONFIG_FILE" | head -1 | sed 's/.*iteration_count:[[:space:]]*//' | xargs)
    current="${current:-0}"
    new_count=$((current + 1))
    sed -i '' "s/iteration_count:[[:space:]]*$current/iteration_count: $new_count/" "$CONFIG_FILE"
    echo "  iteration_count: $current -> $new_count"
  fi
else
  echo "  No CONFIG.yaml found - skipping iteration_count increment"
fi
