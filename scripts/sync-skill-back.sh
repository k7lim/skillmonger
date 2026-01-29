#!/bin/bash
# sync-skill-back.sh - Pull changes from deployed skill instances back to source
# Handles FEEDBACK.jsonl append, CONFIG.yaml merge, and content file diffing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"

usage() {
  cat << EOF
Usage: $(basename "$0") <skill-name> --from <deployed-path> [options]

Syncs changes from a deployed skill instance back to the source skill.

Arguments:
  skill-name         Name of the skill (directory under skills/)

Options:
  --from <path>      Required: path to deployed skill instance
  --dry-run          Show what would sync without making changes
  --auto             Non-interactive mode (safe defaults: skip conflicts)
  --feedback-only    Only sync FEEDBACK.jsonl
  --help             Show this help message

File Sync Strategies:
  FEEDBACK.jsonl   Append new entries (dedupe by timestamp)
  CONFIG.yaml      Merge: take higher version, higher iteration_count, later date
  references/*.md  Show diff, prompt: keep/take/merge
  SKILL.md         Show diff, prompt: keep/take/merge
  MEMO.md          Show diff, prompt: keep/take/merge

Examples:
  $(basename "$0") ai-talking-heads --from ~/sandbox/.claude/skills/ai-talking-heads
  $(basename "$0") ai-talking-heads --from /path/to/deployed --dry-run
  $(basename "$0") ai-talking-heads --from /path/to/deployed --auto
EOF
}

# --- Parse Arguments ---

SKILL_NAME=""
FROM_PATH=""
DRY_RUN=""
AUTO_MODE=""
FEEDBACK_ONLY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --from)
      FROM_PATH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --auto)
      AUTO_MODE=1
      shift
      ;;
    --feedback-only)
      FEEDBACK_ONLY=1
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

if [ -z "$FROM_PATH" ]; then
  echo "Error: --from <path> is required"
  echo ""
  usage
  exit 1
fi

# --- Validate Paths ---

SOURCE_DIR="$SKILLS_DIR/$SKILL_NAME"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: Source skill not found: $SOURCE_DIR"
  exit 1
fi

if [ ! -d "$FROM_PATH" ]; then
  echo "Error: Deployed skill not found: $FROM_PATH"
  exit 1
fi

FROM_PATH="$(cd "$FROM_PATH" && pwd)"

echo "Syncing skill: $SKILL_NAME"
echo "  From: $FROM_PATH"
echo "  To:   $SOURCE_DIR"
[ -n "$DRY_RUN" ] && echo "  Mode: DRY RUN"
[ -n "$AUTO_MODE" ] && echo "  Mode: AUTO (non-interactive)"
echo ""

# --- Counters ---
CHANGES_MADE=0
CHANGES_SKIPPED=0

# --- Helper Functions ---

# Compare versions (returns 0 if $1 > $2, 1 if equal, 2 if $1 < $2)
compare_versions() {
  if [ "$1" = "$2" ]; then
    return 1
  fi
  # Use sort -V for version comparison
  local higher
  higher=$(printf '%s\n%s' "$1" "$2" | sort -V | tail -n1)
  if [ "$higher" = "$1" ]; then
    return 0  # $1 is higher
  else
    return 2  # $2 is higher
  fi
}

# Compare dates (returns 0 if $1 > $2, 1 if equal, 2 if $1 < $2)
compare_dates() {
  if [ "$1" = "$2" ]; then
    return 1
  fi
  # Simple string comparison works for ISO dates
  if [[ "$1" > "$2" ]]; then
    return 0
  else
    return 2
  fi
}

# Extract YAML value (simple grep-based for single values)
yaml_get() {
  local file="$1"
  local key="$2"
  grep "^[[:space:]]*$key:" "$file" 2>/dev/null | head -1 | sed "s/.*$key:[[:space:]]*//" | tr -d '"' | tr -d "'" | xargs
}

# Prompt for file action
prompt_file_action() {
  local file_name="$1"
  local source_file="$2"
  local deployed_file="$3"

  echo ""
  echo "=== $file_name ==="
  echo ""

  # Show diff
  if diff -q "$source_file" "$deployed_file" > /dev/null 2>&1; then
    echo "  No differences"
    return 0
  fi

  echo "Differences (source vs deployed):"
  diff -u "$source_file" "$deployed_file" 2>/dev/null | head -50 || true
  echo ""

  if [ -n "$AUTO_MODE" ]; then
    echo "  [AUTO] Skipping conflicting file"
    ((CHANGES_SKIPPED++)) || true
    return 0
  fi

  if [ -n "$DRY_RUN" ]; then
    echo "  [DRY RUN] Would prompt for action"
    return 0
  fi

  echo "Choose action:"
  echo "  k = keep source (no change)"
  echo "  t = take deployed (overwrite source)"
  echo "  s = skip (decide later)"

  while true; do
    read -rp "> " choice
    case "$choice" in
      k|K)
        echo "  Keeping source"
        ((CHANGES_SKIPPED++)) || true
        return 0
        ;;
      t|T)
        cp "$deployed_file" "$source_file"
        echo "  ✓ Took deployed version"
        ((CHANGES_MADE++)) || true
        return 0
        ;;
      s|S)
        echo "  Skipping"
        ((CHANGES_SKIPPED++)) || true
        return 0
        ;;
      *)
        echo "  Enter k, t, or s"
        ;;
    esac
  done
}

# --- Sync FEEDBACK.jsonl ---

sync_feedback() {
  local source_feedback="$SOURCE_DIR/FEEDBACK.jsonl"
  local deployed_feedback="$FROM_PATH/FEEDBACK.jsonl"

  echo "--- FEEDBACK.jsonl ---"

  if [ ! -f "$deployed_feedback" ]; then
    echo "  No FEEDBACK.jsonl in deployed skill"
    return 0
  fi

  if [ ! -f "$source_feedback" ]; then
    # No source file - just copy
    if [ -n "$DRY_RUN" ]; then
      local count
      count=$(wc -l < "$deployed_feedback" | xargs)
      echo "  [DRY RUN] Would copy $count entries (new file)"
    else
      cp "$deployed_feedback" "$source_feedback"
      local count
      count=$(wc -l < "$source_feedback" | xargs)
      echo "  ✓ Copied $count entries (new file)"
      ((CHANGES_MADE++)) || true
    fi
    return 0
  fi

  # Extract timestamps from source for deduplication
  local source_timestamps
  source_timestamps=$(grep -o '"ts":"[^"]*"' "$source_feedback" 2>/dev/null | sort -u || true)

  # Find new entries in deployed
  local new_entries=0
  local temp_new
  temp_new=$(mktemp)

  while IFS= read -r line || [ -n "$line" ]; do
    if [ -z "$line" ]; then continue; fi
    local ts
    ts=$(echo "$line" | grep -o '"ts":"[^"]*"' || true)
    if [ -n "$ts" ] && ! echo "$source_timestamps" | grep -qF "$ts"; then
      echo "$line" >> "$temp_new"
      ((new_entries++)) || true
    fi
  done < "$deployed_feedback"

  if [ "$new_entries" -eq 0 ]; then
    echo "  No new entries to sync"
    rm -f "$temp_new"
    return 0
  fi

  if [ -n "$DRY_RUN" ]; then
    echo "  [DRY RUN] Would append $new_entries new entries"
    rm -f "$temp_new"
  else
    cat "$temp_new" >> "$source_feedback"
    rm -f "$temp_new"
    echo "  ✓ Appended $new_entries new entries"
    ((CHANGES_MADE++)) || true
  fi
}

# --- Sync CONFIG.yaml ---

sync_config() {
  local source_config="$SOURCE_DIR/CONFIG.yaml"
  local deployed_config="$FROM_PATH/CONFIG.yaml"

  echo ""
  echo "--- CONFIG.yaml ---"

  if [ ! -f "$deployed_config" ]; then
    echo "  No CONFIG.yaml in deployed skill"
    return 0
  fi

  if [ ! -f "$source_config" ]; then
    if [ -n "$DRY_RUN" ]; then
      echo "  [DRY RUN] Would copy CONFIG.yaml (new file)"
    else
      cp "$deployed_config" "$source_config"
      echo "  ✓ Copied CONFIG.yaml (new file)"
      ((CHANGES_MADE++)) || true
    fi
    return 0
  fi

  # Extract key fields
  local source_version deployed_version
  local source_updated deployed_updated
  local source_iteration deployed_iteration

  source_version=$(yaml_get "$source_config" "version")
  deployed_version=$(yaml_get "$deployed_config" "version")
  source_updated=$(yaml_get "$source_config" "updated")
  deployed_updated=$(yaml_get "$deployed_config" "updated")
  source_iteration=$(yaml_get "$source_config" "iteration_count")
  deployed_iteration=$(yaml_get "$deployed_config" "iteration_count")

  source_version="${source_version:-0.0.0}"
  deployed_version="${deployed_version:-0.0.0}"
  source_iteration="${source_iteration:-0}"
  deployed_iteration="${deployed_iteration:-0}"

  local changes=""

  # Compare versions
  if compare_versions "$deployed_version" "$source_version"; then
    changes="${changes}version: $source_version -> $deployed_version\n"
  fi

  # Compare dates
  if [ -n "$deployed_updated" ] && [ -n "$source_updated" ]; then
    if compare_dates "$deployed_updated" "$source_updated"; then
      changes="${changes}updated: $source_updated -> $deployed_updated\n"
    fi
  fi

  # Compare iteration count
  if [ "$deployed_iteration" -gt "$source_iteration" ] 2>/dev/null; then
    changes="${changes}iteration_count: $source_iteration -> $deployed_iteration\n"
  fi

  if [ -z "$changes" ]; then
    echo "  No mergeable changes detected"
    return 0
  fi

  echo "  Mergeable changes:"
  echo -e "    $changes" | sed 's/^/    /'

  if [ -n "$DRY_RUN" ]; then
    echo "  [DRY RUN] Would merge these changes"
    return 0
  fi

  # Apply changes using Python if available, otherwise sed
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    python3 << PYEOF
import yaml

with open('$source_config', 'r') as f:
    config = yaml.safe_load(f)

with open('$deployed_config', 'r') as f:
    deployed = yaml.safe_load(f)

# Merge version (take higher)
src_ver = config.get('skill', {}).get('version', '0.0.0')
dep_ver = deployed.get('skill', {}).get('version', '0.0.0')
from packaging.version import Version
try:
    from packaging.version import Version
    if Version(dep_ver) > Version(src_ver):
        config.setdefault('skill', {})['version'] = dep_ver
except:
    # Fallback: string comparison
    if dep_ver > src_ver:
        config.setdefault('skill', {})['version'] = dep_ver

# Merge updated date (take later)
src_date = config.get('skill', {}).get('updated', '')
dep_date = deployed.get('skill', {}).get('updated', '')
if dep_date and (not src_date or dep_date > src_date):
    config.setdefault('skill', {})['updated'] = dep_date

# Merge iteration_count (take higher)
src_iter = config.get('compaction', {}).get('iteration_count', 0)
dep_iter = deployed.get('compaction', {}).get('iteration_count', 0)
if dep_iter > src_iter:
    config.setdefault('compaction', {})['iteration_count'] = dep_iter

with open('$source_config', 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)
PYEOF
    echo "  ✓ Merged CONFIG.yaml changes"
    ((CHANGES_MADE++)) || true
  else
    # Fallback: sed-based (less reliable)
    if compare_versions "$deployed_version" "$source_version"; then
      sed -i '' "s/version:[[:space:]]*$source_version/version: $deployed_version/" "$source_config"
    fi
    if [ -n "$deployed_updated" ] && [ -n "$source_updated" ]; then
      if compare_dates "$deployed_updated" "$source_updated"; then
        sed -i '' "s/updated:[[:space:]]*$source_updated/updated: $deployed_updated/" "$source_config"
      fi
    fi
    if [ "$deployed_iteration" -gt "$source_iteration" ] 2>/dev/null; then
      sed -i '' "s/iteration_count:[[:space:]]*$source_iteration/iteration_count: $deployed_iteration/" "$source_config"
    fi
    echo "  ✓ Merged CONFIG.yaml changes (sed fallback)"
    ((CHANGES_MADE++)) || true
  fi
}

# --- Sync Content Files ---

sync_content_files() {
  echo ""
  echo "--- Content Files ---"

  # SKILL.md
  if [ -f "$FROM_PATH/SKILL.md" ] && [ -f "$SOURCE_DIR/SKILL.md" ]; then
    prompt_file_action "SKILL.md" "$SOURCE_DIR/SKILL.md" "$FROM_PATH/SKILL.md"
  fi

  # MEMO.md
  if [ -f "$FROM_PATH/MEMO.md" ] && [ -f "$SOURCE_DIR/MEMO.md" ]; then
    prompt_file_action "MEMO.md" "$SOURCE_DIR/MEMO.md" "$FROM_PATH/MEMO.md"
  elif [ -f "$FROM_PATH/MEMO.md" ] && [ ! -f "$SOURCE_DIR/MEMO.md" ]; then
    if [ -n "$DRY_RUN" ]; then
      echo "  [DRY RUN] Would copy MEMO.md (new file)"
    elif [ -n "$AUTO_MODE" ]; then
      cp "$FROM_PATH/MEMO.md" "$SOURCE_DIR/MEMO.md"
      echo "  ✓ Copied MEMO.md (new file)"
      ((CHANGES_MADE++)) || true
    else
      echo ""
      echo "MEMO.md exists in deployed but not in source."
      read -rp "Copy to source? (y/n) " yn
      if [[ "$yn" =~ ^[Yy] ]]; then
        cp "$FROM_PATH/MEMO.md" "$SOURCE_DIR/MEMO.md"
        echo "  ✓ Copied MEMO.md"
        ((CHANGES_MADE++)) || true
      fi
    fi
  fi

  # references/*.md
  if [ -d "$FROM_PATH/references" ]; then
    for deployed_ref in "$FROM_PATH/references"/*.md; do
      [ -f "$deployed_ref" ] || continue
      local ref_name
      ref_name=$(basename "$deployed_ref")
      local source_ref="$SOURCE_DIR/references/$ref_name"

      if [ -f "$source_ref" ]; then
        prompt_file_action "references/$ref_name" "$source_ref" "$deployed_ref"
      else
        # New reference file
        if [ -n "$DRY_RUN" ]; then
          echo "  [DRY RUN] Would copy references/$ref_name (new file)"
        elif [ -n "$AUTO_MODE" ]; then
          mkdir -p "$SOURCE_DIR/references"
          cp "$deployed_ref" "$source_ref"
          echo "  ✓ Copied references/$ref_name (new file)"
          ((CHANGES_MADE++)) || true
        else
          echo ""
          echo "New reference file: references/$ref_name"
          read -rp "Copy to source? (y/n) " yn
          if [[ "$yn" =~ ^[Yy] ]]; then
            mkdir -p "$SOURCE_DIR/references"
            cp "$deployed_ref" "$source_ref"
            echo "  ✓ Copied references/$ref_name"
            ((CHANGES_MADE++)) || true
          fi
        fi
      fi
    done
  fi
}

# --- Main ---

sync_feedback

if [ -z "$FEEDBACK_ONLY" ]; then
  sync_config
  sync_content_files
fi

# --- Summary ---

echo ""
echo "=== Summary ==="
echo "  Changes made: $CHANGES_MADE"
echo "  Changes skipped: $CHANGES_SKIPPED"

if [ -n "$DRY_RUN" ]; then
  echo ""
  echo "This was a dry run. Run without --dry-run to apply changes."
fi
