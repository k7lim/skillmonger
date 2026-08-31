#!/bin/bash
# ship-skill.sh - Ship a developed skill from sandbox to skillmonger
#
# The copy is staged under .skill-staging/ and moved into skills/ in one
# step at the very end, so a run that is killed, aborted, or closed at a
# prompt never leaves a partial skill behind (skillmonger-j9f).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLMONGER_SKILLS_DIR:-$PROJECT_ROOT/skills}"
# Staging and backups sit beside skills/ so the final mv stays on one
# filesystem (and so a test pointing SKILLMONGER_SKILLS_DIR elsewhere never
# writes into the real repo).
STAGING_ROOT="$(dirname "$SKILLS_DIR")/.skill-staging"
BACKUP_ROOT="$(dirname "$SKILLS_DIR")/.skill-backups"
TODAY=$(date +%Y-%m-%d)

usage() {
  cat << EOF
Usage: $(basename "$0") <sandbox-skill-path> [options]

Promotes a skill from the sandbox to skillmonger for distribution.

Arguments:
  sandbox-skill-path    Path to the skill directory in sandbox

Options:
  --keep-sandbox        Don't delete the sandbox copy after promotion
  --skip-validation     Skip validation (not recommended)
  --yes, -y             Answer yes to every prompt: overwrite an existing
                        skill (after backing it up), continue past warnings,
                        ship every extra file, delete the sandbox copy
  --no-extras           Ship only the standard files; skip extra files and
                        directories (assets/, SOURCE.md, ...) without asking
  --ask                 Prompt even when stdin is not a terminal, reading
                        answers from stdin (for piped answers)
  --help                Show this help message

Non-interactive runs:
  When stdin is not a terminal and --ask is not given, the script never
  prompts. Each prompt takes a default instead, and prints it:
    overwrite an existing skill      abort, exit 1        (--yes: overwrite)
    SKILL.md template placeholders   abort, exit 1        (--yes: continue)
    extra files and directories      ship all of them     (--no-extras: skip)
    validation issues                abort, ship nothing  (--yes: continue)
    delete the sandbox copy          keep it              (--yes: delete)
  Shipping every extra file is the default because a skill missing its
  assets/ passes validation and breaks on first use.

Atomicity:
  Files are staged under $(basename "$STAGING_ROOT")/ and moved into skills/
  in a single step after validation. An interrupted or aborted run leaves
  no partial skill; anything not shipped is listed by name.

Example:
  $(basename "$0") ~/Development/sandbox/skills/my-skill
  $(basename "$0") ~/Development/sandbox/skills/my-skill --keep-sandbox
  $(basename "$0") ~/Development/sandbox/skills/my-skill --yes </dev/null
EOF
}

# --- Parse Arguments ---

SANDBOX_PATH=""
KEEP_SANDBOX=false
SKIP_VALIDATION=false
ASSUME_YES=false
NO_EXTRAS=false
FORCE_ASK=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-sandbox)
      KEEP_SANDBOX=true
      shift
      ;;
    --skip-validation)
      SKIP_VALIDATION=true
      shift
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --no-extras)
      NO_EXTRAS=true
      shift
      ;;
    --ask)
      FORCE_ASK=true
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
      if [ -z "$SANDBOX_PATH" ]; then
        SANDBOX_PATH="$1"
      else
        echo "Error: Unexpected argument $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$SANDBOX_PATH" ]; then
  echo "Error: sandbox-skill-path is required"
  usage
  exit 1
fi

# Interactive means: a terminal on stdin, or --ask. --yes never prompts.
if [ "$ASSUME_YES" = true ]; then
  INTERACTIVE=false
elif [ "$FORCE_ASK" = true ] || [ -t 0 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# ask VAR "prompt" "non-interactive default" "answer under --yes"
# Interactive: read from stdin; a closed stdin is an abort, not a hang.
# Otherwise: take the default (or the --yes answer) and say so.
ask() {
  local var="$1" prompt="$2" default="$3" yes_answer="$4" reply
  if [ "$ASSUME_YES" = true ]; then
    reply="$yes_answer"
    echo "${prompt}${reply}  [--yes]"
  elif [ "$INTERACTIVE" = true ]; then
    # read -p only shows the prompt on a terminal; with piped answers
    # (--ask) print it, and the answer taken, so the transcript is complete.
    [ -t 0 ] || printf '%s' "$prompt"
    if ! read -rp "$prompt" reply; then
      echo ""
      echo "Error: stdin closed at prompt: ${prompt%: }"
      echo "Nothing was shipped. Run with a terminal, --yes, or answer every prompt."
      exit 1
    fi
    [ -t 0 ] || echo "$reply"
  else
    reply="$default"
    echo "${prompt}${reply}  [non-interactive default]"
  fi
  printf -v "$var" '%s' "$reply"
}

# Resolve to absolute path
SANDBOX_PATH="$(cd "$SANDBOX_PATH" 2>/dev/null && pwd)" || {
  echo "Error: Cannot access $SANDBOX_PATH"
  exit 1
}

SKILL_NAME="$(basename "$SANDBOX_PATH")"
TARGET_DIR="$SKILLS_DIR/$SKILL_NAME"

echo "Promoting skill: $SKILL_NAME"
echo "From: $SANDBOX_PATH"
echo "To:   $TARGET_DIR"
if [ "$INTERACTIVE" = false ]; then
  if [ "$ASSUME_YES" = true ]; then
    echo "Mode: --yes (no prompts; every answer is yes)"
  else
    echo "Mode: non-interactive (stdin is not a terminal; no prompts, defaults apply)"
  fi
fi
echo ""

# --- Pre-flight Checks ---

# Check sandbox skill exists
if [ ! -f "$SANDBOX_PATH/SKILL.md" ]; then
  echo "Error: No SKILL.md found at $SANDBOX_PATH"
  echo "This doesn't look like a valid skill directory."
  exit 1
fi

# Check if skill already exists in skillmonger
if [ -d "$TARGET_DIR" ]; then
  echo "Warning: Skill '$SKILL_NAME' already exists in skillmonger."
  ask OVERWRITE "Overwrite? (y/N): " "n" "y"
  if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
    echo "Aborted: '$SKILL_NAME' already exists. Nothing was shipped."
    if [ "$INTERACTIVE" = false ]; then
      echo "Pass --yes to overwrite (the existing skill is backed up first)."
      exit 1
    fi
    exit 0
  fi
  echo "Will overwrite existing skill (after backing it up)."
  OVERWRITING=true
else
  OVERWRITING=false
fi

# --- Readiness Checks ---

echo "Running pre-promotion checks..."
echo ""

# Check for DESIGN.md completion (soft check)
if [ -f "$SANDBOX_PATH/DESIGN.md" ]; then
  if grep -q '\[ \]' "$SANDBOX_PATH/DESIGN.md"; then
    echo "  ⚠ DESIGN.md has unchecked items"
    echo "    Consider completing DESIGN.md before promoting."
    echo ""
  else
    echo "  ✓ DESIGN.md appears complete"
  fi
else
  echo "  ⚠ No DESIGN.md found (optional but recommended)"
fi

# Check for check-prereqs.sh
if [ -f "$SANDBOX_PATH/scripts/check-prereqs.sh" ]; then
  echo "  ✓ scripts/check-prereqs.sh exists"

  # Try to run it and validate JSON output. stdin is closed so a prereq
  # script can never swallow the answers meant for our prompts.
  if output=$("$SANDBOX_PATH/scripts/check-prereqs.sh" 2>/dev/null </dev/null); then
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
      echo "  ✓ check-prereqs.sh outputs valid JSON"
    else
      echo "  ⚠ check-prereqs.sh output is not valid JSON"
    fi
  else
    echo "  ⚠ check-prereqs.sh failed to run (may need dependencies)"
  fi
else
  echo "  ⚠ No scripts/check-prereqs.sh (consider adding prerequisite checks)"
fi

# Check SKILL.md has real content (not just template)
if grep -q '\[Describe trigger conditions\]' "$SANDBOX_PATH/SKILL.md" 2>/dev/null; then
  echo "  ⚠ SKILL.md appears to still have template placeholders"
  ask CONTINUE "  Continue anyway? (y/N): " "n" "y"
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    echo "Aborted. Please complete SKILL.md first. Nothing was shipped."
    if [ "$INTERACTIVE" = false ]; then
      exit 1
    fi
    exit 0
  fi
else
  echo "  ✓ SKILL.md has content"
fi

# Check for empty triggers in CONFIG.yaml
if [ -f "$SANDBOX_PATH/CONFIG.yaml" ]; then
  if grep -A 2 'phrases:' "$SANDBOX_PATH/CONFIG.yaml" | grep -qE '^\s*-\s*(TODO|"TODO)'; then
    echo "  ⚠ CONFIG.yaml has placeholder trigger phrases"
    echo "    Triggers help the skill get invoked. Consider populating them."
    echo ""
  elif ! grep -q 'phrases:' "$SANDBOX_PATH/CONFIG.yaml"; then
    echo "  ⚠ CONFIG.yaml missing triggers.phrases section"
    echo ""
  else
    echo "  ✓ CONFIG.yaml has trigger phrases"
  fi
fi

echo ""

# --- Stage ---
#
# Everything is assembled in a staging directory named after the skill (so
# validate-skill.sh sees the right directory name) and moved into skills/
# only after the last prompt and the validation pass. The trap removes the
# staging area on every exit path, including a killed run; a SIGKILL leaves
# a directory under .skill-staging/, never under skills/.

mkdir -p "$STAGING_ROOT"
STAGE_PARENT="$(mktemp -d "$STAGING_ROOT/$SKILL_NAME.XXXXXX")"
STAGE_DIR="$STAGE_PARENT/$SKILL_NAME"
mkdir "$STAGE_DIR"

cleanup_staging() {
  rm -rf "$STAGE_PARENT"
  rmdir "$STAGING_ROOT" 2>/dev/null || true
}
trap cleanup_staging EXIT
trap 'exit 1' INT TERM HUP

# --- Copy Files ---

echo "Staging skill files in $STAGE_DIR..."

# Copy SKILL.md (required)
cp "$SANDBOX_PATH/SKILL.md" "$STAGE_DIR/"
echo "  ✓ SKILL.md"

# Copy scripts/ if exists
if [ -d "$SANDBOX_PATH/scripts" ]; then
  cp -r "$SANDBOX_PATH/scripts" "$STAGE_DIR/"
  echo "  ✓ scripts/"
fi

# Copy references/ if exists and has content
if [ -d "$SANDBOX_PATH/references" ] && [ "$(ls -A "$SANDBOX_PATH/references" 2>/dev/null)" ]; then
  cp -r "$SANDBOX_PATH/references" "$STAGE_DIR/"
  echo "  ✓ references/"
else
  mkdir -p "$STAGE_DIR/references"
  echo "  ✓ references/ (empty)"
fi

# Copy FEEDBACK.jsonl if exists
if [ -f "$SANDBOX_PATH/FEEDBACK.jsonl" ]; then
  cp "$SANDBOX_PATH/FEEDBACK.jsonl" "$STAGE_DIR/"
  fb_count=$(wc -l < "$SANDBOX_PATH/FEEDBACK.jsonl" | xargs)
  echo "  ✓ FEEDBACK.jsonl ($fb_count entries)"
fi

# Generate CONFIG.yaml if not exists
if [ -f "$SANDBOX_PATH/CONFIG.yaml" ]; then
  cp "$SANDBOX_PATH/CONFIG.yaml" "$STAGE_DIR/"
  echo "  ✓ CONFIG.yaml (copied)"
else
  # Extract description from SKILL.md frontmatter
  DESCRIPTION=$(sed -n '/^---$/,/^---$/p' "$SANDBOX_PATH/SKILL.md" | grep '^description:' | sed 's/description: *//')
  DESCRIPTION="${DESCRIPTION:-A skill promoted from sandbox.}"

  cat > "$STAGE_DIR/CONFIG.yaml" << EOF
# ${SKILL_NAME} Skill Configuration

skill:
  name: $SKILL_NAME
  version: 1.0.0
  created: $TODAY
  updated: $TODAY
  author: ${USER}

triggers:
  phrases: []
  keywords: []

dependencies:
  tools: []

loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml

compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0

budget:
  metadata_max: 100
  skill_max: 5000
  memo_max: 2000
EOF
  echo "  ✓ CONFIG.yaml (generated)"
fi

# Generate MEMO.md if not exists
if [ -f "$SANDBOX_PATH/MEMO.md" ]; then
  cp "$SANDBOX_PATH/MEMO.md" "$STAGE_DIR/"
  echo "  ✓ MEMO.md (copied)"
else
  cat > "$STAGE_DIR/MEMO.md" << EOF
# ${SKILL_NAME} - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases.

## Edge Cases Log

_No edge cases logged yet._

---

## Learnings

_Patterns will graduate from iterations._

---

## Iteration Log

| Date | Version | Change Type | Description | Patterns |
|------|---------|-------------|-------------|----------|
| $TODAY | 1.0.0 | Initial | Promoted from sandbox | - |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
EOF
  echo "  ✓ MEMO.md (generated)"
fi

# --- Check for additional files ---

# Known files we've already handled (includes sandbox-only files)
KNOWN_FILES="SKILL.md CONFIG.yaml MEMO.md DESIGN.md README.md BRIEF.md PLAN.md FEEDBACK.jsonl"
KNOWN_DIRS="scripts references memo fixtures"

# Find extra files
EXTRA_FILES=()
for f in "$SANDBOX_PATH"/*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")

  # Skip known files
  if [[ " $KNOWN_FILES " =~ " $name " ]]; then
    continue
  fi

  # Skip known directories
  if [ -d "$f" ] && [[ " $KNOWN_DIRS " =~ " $name " ]]; then
    continue
  fi

  EXTRA_FILES+=("$name")
done

# Everything the run decided not to ship, listed by name at the end.
SKIPPED_FILES=()

copy_extra() {
  cp -r "$SANDBOX_PATH/$1" "$STAGE_DIR/"
  echo "  ✓ $1"
}

skip_extra() {
  echo "  ⊘ $1 (not shipped: $2)"
  SKIPPED_FILES+=("$1")
}

# Offer to copy extra files
if [ ${#EXTRA_FILES[@]} -gt 0 ]; then
  echo ""
  echo "Found additional files/directories:"
  for item in "${EXTRA_FILES[@]}"; do
    if [ -d "$SANDBOX_PATH/$item" ]; then
      count=$(find "$SANDBOX_PATH/$item" -type f | wc -l | tr -d ' ')
      echo "  📁 $item/ ($count files)"
    else
      size=$(ls -lh "$SANDBOX_PATH/$item" | awk '{print $5}')
      echo "  📄 $item ($size)"
    fi
  done
  echo ""

  if [ "$NO_EXTRAS" = true ]; then
    echo "Skipping additional files (--no-extras):"
    for item in "${EXTRA_FILES[@]}"; do
      skip_extra "$item" "--no-extras"
    done
  else
    if [ "$INTERACTIVE" = false ] && [ "$ASSUME_YES" = false ]; then
      echo "Shipping all of them (non-interactive default; pass --no-extras to skip):"
    fi
    ask COPY_EXTRA "Copy these to the skill? (Y/n/[i]ndividual): " "y" "y"

    if [[ "$COPY_EXTRA" =~ ^[Ii]$ ]]; then
      # Individual confirmation
      for item in "${EXTRA_FILES[@]}"; do
        if [ -d "$SANDBOX_PATH/$item" ]; then
          ask COPY_THIS "  Copy $item/? (y/N): " "y" "y"
        else
          ask COPY_THIS "  Copy $item? (y/N): " "y" "y"
        fi
        if [[ "$COPY_THIS" =~ ^[Yy]$ ]]; then
          copy_extra "$item"
        else
          skip_extra "$item" "declined"
        fi
      done
    elif [[ ! "$COPY_EXTRA" =~ ^[Nn]$ ]]; then
      # Default yes - copy all
      for item in "${EXTRA_FILES[@]}"; do
        copy_extra "$item"
      done
    else
      for item in "${EXTRA_FILES[@]}"; do
        skip_extra "$item" "declined"
      done
    fi
  fi
fi

# --- Validation ---

if [ "$SKIP_VALIDATION" = false ]; then
  echo ""
  echo "Running validation..."
  if "$SCRIPT_DIR/validate-skill.sh" "$STAGE_DIR" 2>/dev/null | grep -q "Validation PASSED"; then
    echo "  ✓ Validation PASSED"
  else
    echo ""
    "$SCRIPT_DIR/validate-skill.sh" "$STAGE_DIR" || true
    echo ""
    ask CONTINUE "Validation issues found. Continue anyway? (y/N): " "n" "y"
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
      echo "Aborted. Fix issues and try again. Nothing was shipped."
      exit 1
    fi
  fi
fi

# --- Move Into Place ---
#
# The only step that touches skills/. The staged tree is complete and
# validated; an existing skill is moved aside first.

echo ""
if [ "$OVERWRITING" = true ]; then
  BACKUP_DIR="$BACKUP_ROOT/$SKILL_NAME-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_ROOT"
  echo "Backing up existing skill to: $BACKUP_DIR"
  mv "$TARGET_DIR" "$BACKUP_DIR"
fi

mv "$STAGE_DIR" "$TARGET_DIR"
echo "Moved into place: $TARGET_DIR"

# --- Cleanup Sandbox ---

if [ "$KEEP_SANDBOX" = false ]; then
  echo ""
  ask DELETE_SANDBOX "Delete sandbox copy? (Y/n): " "n" "y"
  if [[ ! "$DELETE_SANDBOX" =~ ^[Nn]$ ]]; then
    rm -rf "$SANDBOX_PATH"
    echo "  ✓ Deleted sandbox copy"
  else
    echo "  Kept sandbox copy at $SANDBOX_PATH"
  fi
else
  echo ""
  echo "  Kept sandbox copy (--keep-sandbox)"
fi

# --- Clear State ---

# shellcheck source=lib/skill-state.sh
. "$SCRIPT_DIR/lib/skill-state.sh"
STATE_FILE="$HOME/.skillmonger-state"
if [ -f "$STATE_FILE" ]; then
  # Only clear if this was the skill in progress. The file is parsed as data;
  # one that fails to parse is left for `scripts/skill clear`.
  if skill_state_load "$STATE_FILE" 2>/dev/null; then
    if [ "$STATE_SKILL_NAME" = "$SKILL_NAME" ]; then
      rm "$STATE_FILE"
    fi
  else
    echo "  Note: $STATE_FILE could not be read; run 'scripts/skill clear' to reset it."
  fi
fi

# --- Summary ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Skill promoted successfully!"
echo ""
echo "Location: $TARGET_DIR"
echo ""
if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
  echo "Not shipped (still in the sandbox copy, if kept):"
  for item in "${SKIPPED_FILES[@]}"; do
    echo "  - $item"
  done
  echo ""
fi
echo "Next steps:"
echo "  1. Review and edit CONFIG.yaml triggers"
echo "  2. Deploy: scripts/deploy-skill.sh $TARGET_DIR/"
echo "  3. Test in production environment"
echo ""
if [ "$OVERWRITING" = true ]; then
  echo "Backup of previous version: $BACKUP_DIR"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
