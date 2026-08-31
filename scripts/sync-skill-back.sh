#!/bin/bash
# sync-skill-back.sh - Pull changes from deployed skill instances back to source
# Handles FEEDBACK.jsonl append, CONFIG.yaml merge, and content file diffing
#
# Concurrency: the FEEDBACK.jsonl dedupe-and-append and the CONFIG.yaml merge
# run as one critical section under the source skill's lock
# (skills/<name>/.lock/, lib/skill-lock.sh; log-feedback.sh and harvest.py
# take the same one), so two syncs of the same deployed copy cannot both
# find the same entries new, and a gate run appending meanwhile loses
# nothing. The lock is released before the interactive content-file prompts.
# CONFIG.yaml is merged by editing the lines the merge can change
# (skill.version, skill.updated; compaction.iteration_count is re-derived
# from the traces, as harvest-feedback.sh does) and renaming a temp file into
# place: comments, key order, quoting and fields this script does not know
# about all survive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLMONGER_SKILLS_DIR:-$PROJECT_ROOT/skills}"

# shellcheck source=lib/skill-lock.sh
. "$SCRIPT_DIR/lib/skill-lock.sh"

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
  FEEDBACK.jsonl   Append new entries (dedupe by timestamp), then re-derive
                   compaction.iteration_count from the traces
  CONFIG.yaml      Merge: take higher version, later date
  references/*.md  Show diff, prompt: keep/take/merge
  memo/**/*.md     Show diff, prompt: keep/take/merge (includes memo/patterns/)
  SKILL.md         Show diff, prompt: keep/take/merge
  MEMO.md          Show diff, prompt: keep/take/merge

Environment:
  SKILLMONGER_SKILLS_DIR  Repo-side skills/ directory (default: $PROJECT_ROOT/skills)
  SKILLMONGER_LOCK_WAIT   Seconds to wait for the skill's writer lock (default 60)
  SKILLMONGER_LOCK_STALE  Age in seconds past which a leftover lock is removed (default 120)

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
  # A key the file lacks is an empty value, not (under pipefail) a fatal grep;
  # a trailing comment is not part of the value.
  { grep "^[[:space:]]*$key:" "$file" 2>/dev/null || true; } | head -1 \
    | sed "s/.*$key:[[:space:]]*//; s/[[:space:]]\{1,\}#.*$//" | tr -d '"' | tr -d "'" | xargs
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

# iteration_count is derived from the traces, the same way harvest-feedback.sh
# derives it, so an append here leaves the count equal to the lines in the
# file. Without python3 the next harvest (which needs python3) sets it.
recount_iteration() {
  command -v python3 &> /dev/null || return 0
  python3 - "$SCRIPT_DIR/lib" "$SOURCE_DIR" <<'PYEOF'
import os
import sys

sys.path.insert(0, sys.argv[1])
from compaction import load_traces, read_compaction, traces_since, write_iteration_count

skill_dir = sys.argv[2]
config = os.path.join(skill_dir, "CONFIG.yaml")
block = read_compaction(config)
if block is not None:
    traces = load_traces(os.path.join(skill_dir, "FEEDBACK.jsonl"))
    count = len(traces_since(traces, block.get("last_compaction")))
    if write_iteration_count(config, count):
        print("  iteration_count: %d (derived from the traces)" % count)
PYEOF
}

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
      recount_iteration
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
    recount_iteration
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

  # Extract key fields. iteration_count is not merged: it is derived from
  # the traces (recount_iteration), and a deployed copy's counter is whatever
  # its epilogue last wrote, which under format 2 is nothing.
  local source_version deployed_version
  local source_updated deployed_updated

  source_version=$(yaml_get "$source_config" "version")
  deployed_version=$(yaml_get "$deployed_config" "version")
  source_updated=$(yaml_get "$source_config" "updated")
  deployed_updated=$(yaml_get "$deployed_config" "updated")

  source_version="${source_version:-0.0.0}"
  deployed_version="${deployed_version:-0.0.0}"

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

  # The values the merge decided on, already compared above with the same
  # grep the fallback uses, so python and sed apply the same decision.
  local new_version="" new_updated=""
  if compare_versions "$deployed_version" "$source_version"; then
    new_version="$deployed_version"
  fi
  if [ -n "$deployed_updated" ] && [ -n "$source_updated" ]; then
    if compare_dates "$deployed_updated" "$source_updated"; then
      new_updated="$deployed_updated"
    fi
  fi

  # Edit the lines in place and land the file by rename. A yaml.dump here
  # would drop every comment and unquote every string (that is how
  # handoff's upstream.repo lost its quotes); replacing the values on their
  # own lines keeps the file as its author wrote it.
  if command -v python3 &> /dev/null; then
    SOURCE_CONFIG="$source_config" NEW_VERSION="$new_version" \
    NEW_UPDATED="$new_updated" python3 <<'PYEOF'
import os
import re

path = os.environ["SOURCE_CONFIG"]
wanted = {
    ("skill", "version"): os.environ["NEW_VERSION"],
    ("skill", "updated"): os.environ["NEW_UPDATED"],
}
wanted = {k: v for k, v in wanted.items() if v}

with open(path) as handle:
    text = handle.read()
lines = text.splitlines(True)

KEY = re.compile(r"^(\s*)([A-Za-z0-9_.-]+):(\s*)(.*?)(\s*)$")


def requote(old, new):
    """Wrap the new value the way the old one was wrapped."""
    old = old.strip()
    if len(old) >= 2 and old[0] == old[-1] and old[0] in "\"'":
        return old[0] + new + old[0]
    return new


block = None
for index, line in enumerate(lines):
    match = KEY.match(line.rstrip("\n"))
    if not match:
        continue
    indent, key, gap, value, tail = match.groups()
    if not indent:
        block = key
        continue
    target = (block, key)
    if target not in wanted:
        continue
    # A trailing comment rides along with the old value, spacing and all.
    comment = ""
    trailing = re.match(r"^(.*?)(\s+#.*)$", value)
    if trailing:
        value, comment = trailing.group(1), trailing.group(2)
    newline = "\n" if line.endswith("\n") else ""
    lines[index] = "%s%s:%s%s%s%s" % (
        indent, key, gap or " ", requote(value, wanted[target]), comment, newline
    )
    del wanted[target]

for (section, key), value in wanted.items():
    # The block exists but lacks the key (or the block is missing): add it.
    for index, line in enumerate(lines):
        if line.startswith(section + ":"):
            lines.insert(index + 1, "  %s: %s\n" % (key, value))
            break
    else:
        if lines and not lines[-1].endswith("\n"):
            lines.append("\n")
        lines.append("\n%s:\n  %s: %s\n" % (section, key, value))

tmp = "%s.tmp.%d" % (path, os.getpid())
with open(tmp, "w") as handle:
    handle.write("".join(lines))
try:
    os.chmod(tmp, os.stat(path).st_mode)
except OSError:
    pass
os.replace(tmp, path)
PYEOF
    echo "  ✓ Merged CONFIG.yaml changes"
    ((CHANGES_MADE++)) || true
  else
    # Fallback: sed-based (less reliable), still landed by rename
    local config_tmp="$source_config.tmp.$$"
    cp "$source_config" "$config_tmp"
    if [ -n "$new_version" ]; then
      sed -i.bak "s/version:[[:space:]]*$source_version/version: $new_version/" "$config_tmp"
    fi
    if [ -n "$new_updated" ]; then
      sed -i.bak "s/updated:[[:space:]]*$source_updated/updated: $new_updated/" "$config_tmp"
    fi
    rm -f "$config_tmp.bak"
    mv -f "$config_tmp" "$source_config"
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

  # memo/**/*.md (wiki overflow, format 2.1: includes memo/patterns/<slug>.md)
  if [ -d "$FROM_PATH/memo" ]; then
    while IFS= read -r deployed_memo; do
      [ -f "$deployed_memo" ] || continue
      local memo_rel="${deployed_memo#"$FROM_PATH"/memo/}"
      local source_memo="$SOURCE_DIR/memo/$memo_rel"

      if [ -f "$source_memo" ]; then
        prompt_file_action "memo/$memo_rel" "$source_memo" "$deployed_memo"
      else
        # New memo file
        if [ -n "$DRY_RUN" ]; then
          echo "  [DRY RUN] Would copy memo/$memo_rel (new file)"
        elif [ -n "$AUTO_MODE" ]; then
          mkdir -p "$(dirname "$source_memo")"
          cp "$deployed_memo" "$source_memo"
          echo "  ✓ Copied memo/$memo_rel (new file)"
          ((CHANGES_MADE++)) || true
        else
          echo ""
          echo "New memo file: memo/$memo_rel"
          read -rp "Copy to source? (y/n) " yn
          if [[ "$yn" =~ ^[Yy] ]]; then
            mkdir -p "$(dirname "$source_memo")"
            cp "$deployed_memo" "$source_memo"
            echo "  ✓ Copied memo/$memo_rel"
            ((CHANGES_MADE++)) || true
          fi
        fi
      fi
    done < <(find "$FROM_PATH/memo" -type f -name '*.md' | sort)
  fi
}

# --- Main ---

# Feedback and CONFIG are the shared state other writers race on; hold the
# skill's lock across both and let it go before anything asks a question.
# A dry run only reads, but reading under the lock keeps its report exact.
skill_lock "$SOURCE_DIR" || exit 1
trap skill_unlock EXIT

sync_feedback

if [ -z "$FEEDBACK_ONLY" ]; then
  sync_config
fi

skill_unlock

if [ -z "$FEEDBACK_ONLY" ]; then
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
