#!/bin/bash
# compact-memo.sh - The Maintainer's tool for one skill's wiki
#
# Compaction (CONTEXT.md) is the pass where traces become patterns and stable
# patterns graduate into SKILL.md. This script does none of that: it harvests
# the traces home, then prints the brief the agent needs to do it -- what
# arrived since the last compaction, which wiki entries predate the pattern
# layout, a pattern template with its evidence filled in, and, for a dependent
# skill, the owner skills a pattern might belong to instead.
#
# It is a guide, not an editor. Nothing under the skill directory is written
# except the traces the harvest brings home -- and, when the wiki has outgrown
# one file and you pass --overflow, the move of its pattern entries into
# memo/patterns/ (format 2.1). That flag is the one action this script has.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLMONGER_SKILLS_DIR:-$PROJECT_ROOT/skills}"

usage() {
  cat << EOF
Usage: $(basename "$0") <skill-dir> [options]

Prints the compaction brief for one skill's wiki (MEMO.md).

Options:
  --no-harvest   Skip the harvest; read the traces already in the repo
  --overflow     Move the wiki's \`### \` entries to memo/patterns/<slug>.md,
                 leaving one index line each in MEMO.md. Only acts when the
                 wiki is over budget.memo_max words or 12 pattern entries.
  --help         Show this help message

Examples:
  $(basename "$0") skills/yt-dlp/
  $(basename "$0") skills/yt-dlp/ --no-harvest
  $(basename "$0") skills/yt-dlp/ --overflow
EOF
}

SKILL_ARG=""
NO_HARVEST=""
OVERFLOW=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-harvest)
      NO_HARVEST=1
      shift
      ;;
    --overflow)
      OVERFLOW=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -z "$SKILL_ARG" ]; then
        SKILL_ARG="$1"
      else
        echo "Error: Unexpected argument $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

SKILL_DIR="${SKILL_ARG:-.}"
if [ ! -d "$SKILL_DIR" ]; then
  echo "Error: Skill directory not found: $SKILL_DIR" >&2
  exit 1
fi
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

MEMO_FILE="$SKILL_DIR/MEMO.md"

echo "Compaction Review: $SKILL_NAME"
echo "Path: $SKILL_DIR"
echo ""

if [ ! -f "$MEMO_FILE" ]; then
  echo "No MEMO.md found - this skill has no wiki to compact."
  exit 0
fi

# --- Harvest first ---
#
# Traces are written into the deployed copy, not here (ADR 0002), so a brief
# built before the harvest describes a repo that is behind the agents.
if [ -z "$NO_HARVEST" ]; then
  if [ "$SKILL_DIR" = "$SKILLS_DIR/$SKILL_NAME" ]; then
    echo "=== Harvest ==="
    "$SCRIPT_DIR/harvest-feedback.sh" "$SKILL_NAME" || true
    echo ""
  else
    echo "=== Harvest ==="
    echo "  Skipped: $SKILL_DIR is not $SKILLS_DIR/$SKILL_NAME, so the deploy"
    echo "  targets cannot be matched to it. Traces read as they are on disk."
    echo ""
  fi
fi

# --- Wiki size ---
#
# The wiki is one file until it outgrows one (roadmap 6). overflow.py owns
# both halves of that: the budget the wiki is measured against here, and the
# move --overflow performs.
echo "=== Wiki size ==="
echo "  Lines: $(wc -l < "$MEMO_FILE" | xargs)"
echo "  Words: $(wc -w < "$MEMO_FILE" | xargs)"
if command -v python3 &> /dev/null; then
  python3 "$SCRIPT_DIR/lib/overflow.py" --skill-dir "$SKILL_DIR" --label "${SKILL_ARG:-.}"
fi
echo ""

# --- Wiki overflow ---
#
# The one thing this script writes to the wiki, and only on the flag. It stops
# here afterwards: the brief below describes a MEMO.md that just changed shape,
# so re-run without --overflow to read it.
if [ -n "$OVERFLOW" ]; then
  if ! command -v python3 &> /dev/null; then
    echo "Error: --overflow needs python3" >&2
    exit 1
  fi
  echo "=== Wiki overflow ==="
  set +e
  python3 "$SCRIPT_DIR/lib/overflow.py" --skill-dir "$SKILL_DIR" --label "${SKILL_ARG:-.}" --apply
  overflow_status=$?
  set -e
  echo ""
  echo "Re-run without --overflow for the compaction brief."
  exit $overflow_status
fi

# --- The brief ---
#
# Trace analysis is python's job: the schemas in the wild differ enough
# (ts/date/timestamp, checks as dict or list) that grep would misread them.
if command -v python3 &> /dev/null; then
  python3 "$SCRIPT_DIR/lib/compact_memo.py" "$SKILL_DIR"
else
  echo "python3 not found - trace analysis skipped." >&2
  echo ""
fi

# --- The wiki as it stands ---
echo "=== Current MEMO.md ==="
echo ""
cat "$MEMO_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Compaction, as the Maintainer:"
echo ""
echo "1. ROOT-CAUSE: turn the traces above into patterns"
echo "   - One entry per root cause, in the pattern layout"
echo "     (docs/skill-format.md, MEMO.md section)"
echo "   - Every pattern cites its evidence; without evidence it is a"
echo "     hypothesis, not a pattern"
echo "   - A pattern whose mechanism belongs to another skill goes in that"
echo "     owner skill's wiki; this one points at it"
echo ""
echo "2. GRADUATE: move a stable pattern's workaround into SKILL.md"
echo "   - Mark the pattern 'status: graduated (vX.Y.Z)'"
echo "   - Name the graduated pattern slugs in the Iteration Log's"
echo "     'Patterns' column - that column is the provenance of the edit"
echo ""
echo "3. PURGE: drop what the skill no longer needs"
echo "   - 'status: purged', or delete the entry once the Iteration Log"
echo "     names its slug"
echo ""
echo "4. VERSION: update CONFIG.yaml"
echo "   - Bump the skill version (patch for a compaction)"
echo "   - Set compaction.last_compaction to today; the next harvest"
echo "     re-derives iteration_count from it"
echo ""
echo "To perform compaction, use Claude:"
echo "  'Compact $SKILL_NAME: root-cause the traces into patterns and"
echo "   graduate the stable ones'"
