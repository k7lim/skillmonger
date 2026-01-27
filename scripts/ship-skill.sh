#!/bin/bash
# ship-skill.sh - Ship a developed skill from sandbox to skillmonger
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"
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
  --help                Show this help message

Example:
  $(basename "$0") ~/Development/sandbox/projects/skills/my-skill
  $(basename "$0") ~/Development/sandbox/projects/skills/my-skill --keep-sandbox
EOF
}

# --- Parse Arguments ---

SANDBOX_PATH=""
KEEP_SANDBOX=false
SKIP_VALIDATION=false

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

# Resolve to absolute path
SANDBOX_PATH="$(cd "$SANDBOX_PATH" 2>/dev/null && pwd)" || {
  echo "Error: Cannot access $SANDBOX_PATH"
  exit 1
}

SKILL_NAME="$(basename "$SANDBOX_PATH")"

echo "Promoting skill: $SKILL_NAME"
echo "From: $SANDBOX_PATH"
echo "To:   $SKILLS_DIR/$SKILL_NAME"
echo ""

# --- Pre-flight Checks ---

# Check sandbox skill exists
if [ ! -f "$SANDBOX_PATH/SKILL.md" ]; then
  echo "Error: No SKILL.md found at $SANDBOX_PATH"
  echo "This doesn't look like a valid skill directory."
  exit 1
fi

# Check if skill already exists in skillmonger
if [ -d "$SKILLS_DIR/$SKILL_NAME" ]; then
  echo "Warning: Skill '$SKILL_NAME' already exists in skillmonger."
  read -rp "Overwrite? (y/N): " OVERWRITE
  if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
  echo "Will overwrite existing skill."
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

# Check for status-check.sh
if [ -f "$SANDBOX_PATH/scripts/status-check.sh" ]; then
  echo "  ✓ scripts/status-check.sh exists"

  # Try to run it and validate JSON output
  if output=$("$SANDBOX_PATH/scripts/status-check.sh" 2>/dev/null); then
    if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
      echo "  ✓ status-check.sh outputs valid JSON"
    else
      echo "  ⚠ status-check.sh output is not valid JSON"
    fi
  else
    echo "  ⚠ status-check.sh failed to run (may need dependencies)"
  fi
else
  echo "  ⚠ No scripts/status-check.sh (consider adding prerequisite checks)"
fi

# Check SKILL.md has real content (not just template)
if grep -q '\[Describe trigger conditions\]' "$SANDBOX_PATH/SKILL.md" 2>/dev/null; then
  echo "  ⚠ SKILL.md appears to still have template placeholders"
  read -rp "  Continue anyway? (y/N): " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    echo "Aborted. Please complete SKILL.md first."
    exit 0
  fi
else
  echo "  ✓ SKILL.md has content"
fi

echo ""

# --- Prepare for Promotion ---

# Create target directory
TARGET_DIR="$SKILLS_DIR/$SKILL_NAME"

if [ "$OVERWRITING" = true ]; then
  echo "Backing up existing skill..."
  BACKUP_DIR="$PROJECT_ROOT/.skill-backups/$SKILL_NAME-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$(dirname "$BACKUP_DIR")"
  mv "$TARGET_DIR" "$BACKUP_DIR"
  echo "  Backed up to: $BACKUP_DIR"
fi

# --- Copy Files ---

echo "Copying skill files..."
mkdir -p "$TARGET_DIR"

# Copy SKILL.md (required)
cp "$SANDBOX_PATH/SKILL.md" "$TARGET_DIR/"
echo "  ✓ SKILL.md"

# Copy scripts/ if exists
if [ -d "$SANDBOX_PATH/scripts" ]; then
  cp -r "$SANDBOX_PATH/scripts" "$TARGET_DIR/"
  echo "  ✓ scripts/"
fi

# Copy references/ if exists and has content
if [ -d "$SANDBOX_PATH/references" ] && [ "$(ls -A "$SANDBOX_PATH/references" 2>/dev/null)" ]; then
  cp -r "$SANDBOX_PATH/references" "$TARGET_DIR/"
  echo "  ✓ references/"
else
  mkdir -p "$TARGET_DIR/references"
  echo "  ✓ references/ (empty)"
fi

# Generate CONFIG.yaml if not exists
if [ -f "$SANDBOX_PATH/CONFIG.yaml" ]; then
  cp "$SANDBOX_PATH/CONFIG.yaml" "$TARGET_DIR/"
  echo "  ✓ CONFIG.yaml (copied)"
else
  # Extract description from SKILL.md frontmatter
  DESCRIPTION=$(sed -n '/^---$/,/^---$/p' "$SANDBOX_PATH/SKILL.md" | grep '^description:' | sed 's/description: *//')
  DESCRIPTION="${DESCRIPTION:-A skill promoted from sandbox.}"

  cat > "$TARGET_DIR/CONFIG.yaml" << EOF
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
  cp "$SANDBOX_PATH/MEMO.md" "$TARGET_DIR/"
  echo "  ✓ MEMO.md (copied)"
else
  cat > "$TARGET_DIR/MEMO.md" << EOF
# ${SKILL_NAME} - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases.

## Edge Cases Log

_No edge cases logged yet._

---

## Learnings

_Patterns will graduate from iterations._

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| $TODAY | 1.0.0 | Initial | Promoted from sandbox |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
EOF
  echo "  ✓ MEMO.md (generated)"
fi

# --- Check for additional files ---

# Known files we've already handled
KNOWN_FILES="SKILL.md CONFIG.yaml MEMO.md DESIGN.md README.md"
KNOWN_DIRS="scripts references"

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
  read -rp "Copy these to the skill? (Y/n/[i]ndividual): " COPY_EXTRA

  if [[ "$COPY_EXTRA" =~ ^[Ii]$ ]]; then
    # Individual confirmation
    for item in "${EXTRA_FILES[@]}"; do
      if [ -d "$SANDBOX_PATH/$item" ]; then
        read -rp "  Copy $item/? (y/N): " COPY_THIS
      else
        read -rp "  Copy $item? (y/N): " COPY_THIS
      fi
      if [[ "$COPY_THIS" =~ ^[Yy]$ ]]; then
        cp -r "$SANDBOX_PATH/$item" "$TARGET_DIR/"
        echo "    ✓ $item"
      else
        echo "    ⊘ $item (skipped)"
      fi
    done
  elif [[ ! "$COPY_EXTRA" =~ ^[Nn]$ ]]; then
    # Default yes - copy all
    for item in "${EXTRA_FILES[@]}"; do
      cp -r "$SANDBOX_PATH/$item" "$TARGET_DIR/"
      echo "  ✓ $item"
    done
  else
    echo "  Skipped additional files"
  fi
fi

# --- Validation ---

if [ "$SKIP_VALIDATION" = false ]; then
  echo ""
  echo "Running validation..."
  if "$SCRIPT_DIR/validate-skill.sh" "$TARGET_DIR" 2>/dev/null | grep -q "Validation PASSED"; then
    echo "  ✓ Validation PASSED"
  else
    echo ""
    "$SCRIPT_DIR/validate-skill.sh" "$TARGET_DIR"
    echo ""
    read -rp "Validation issues found. Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
      echo "Aborted. Fix issues and try again."
      # Clean up
      rm -rf "$TARGET_DIR"
      if [ "$OVERWRITING" = true ]; then
        mv "$BACKUP_DIR" "$TARGET_DIR"
        echo "Restored backup."
      fi
      exit 1
    fi
  fi
fi

# --- Cleanup Sandbox ---

if [ "$KEEP_SANDBOX" = false ]; then
  echo ""
  read -rp "Delete sandbox copy? (Y/n): " DELETE_SANDBOX
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

# --- Summary ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Skill promoted successfully!"
echo ""
echo "Location: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. Review and edit CONFIG.yaml triggers"
echo "  2. Deploy: scripts/deploy-skill.sh $TARGET_DIR/"
echo "  3. Test in production environment"
echo ""
if [ "$OVERWRITING" = true ]; then
  echo "Backup of previous version: $BACKUP_DIR"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
