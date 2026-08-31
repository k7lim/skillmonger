#!/bin/bash
# deploy-skill.sh - Deploy skill to tool directories
# Global: ~/.local/share/skillmonger/skills/ with links or copies to tool paths
# Local: copies skill into project tool directories
#
# --dry-run prints one line per target saying what would be harvested,
# removed, copied or symlinked, and changes nothing: no harvest (that writes
# into skills/), no rm, no cp, no ln, no zip.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# SKILLMONGER_DIR, TOOL_PATHS, YOLOBOX_SANDBOX_HOME and SANDBOX_TOOL_PATHS.
# harvest-feedback.sh reads the same file, so the harvester always knows every
# target this script is about to overwrite.
# shellcheck source=lib/deploy-targets.sh
. "$SCRIPT_DIR/lib/deploy-targets.sh"

# One planned action per line. Only --dry-run prints these.
plan() {
  printf '  %-8s %s\n' "$1" "$2"
}

# The harvester reads <root>/<skill> under every deploy target root plus any
# --target DIR it is given; list the copies it would find.
plan_harvest() {
  local root
  while IFS= read -r root; do
    if [ -n "$root" ] && [ -e "$root/$SKILL_NAME" ]; then
      plan harvest "$root/$SKILL_NAME"
    fi
  done < <(deploy_target_roots)
  while [ $# -gt 0 ]; do
    if [ "$1" = "--target" ] && [ -e "$2/$SKILL_NAME" ]; then
      plan harvest "$2/$SKILL_NAME"
    fi
    shift
  done
}

# Deploying replaces a deployed copy wholesale, and the deployed copy is where
# agents write their traces (ADR 0002). Harvest first, or rm -rf destroys them.
harvest_before_removal() {
  if [ -n "$DRY_RUN" ]; then
    plan_harvest "$@"
    return 0
  fi
  if ! "$SCRIPT_DIR/harvest-feedback.sh" "$SKILL_NAME" --quiet "$@"; then
    echo "ERROR: Harvest failed for $SKILL_NAME. Refusing to deploy: the" >&2
    echo "       deployed copies hold traces that deploy would destroy." >&2
    exit 1
  fi
}

# rm -rf of a target that is there; a line in the plan only when it is.
plan_remove_existing() {
  if [ -L "$1" ] || [ -e "$1" ]; then
    plan remove "$1"
  fi
}

# Parse arguments
SKILL_DIR=""
DO_GLOBAL=""
STORE_ONLY=""
LOCAL_DIR=""
TOOLS=""
FORMAT=""
DRY_RUN=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --global)
      DO_GLOBAL=1
      shift
      ;;
    --store-only)
      STORE_ONLY=1
      shift
      ;;
    --local)
      LOCAL_DIR="$2"
      shift 2
      ;;
    --tools)
      TOOLS="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      echo "Usage: deploy-skill.sh <skill-path> [options]"
      echo ""
      echo "Options:"
      echo "  --global          Install to ~/.local/share/skillmonger/skills/ and"
      echo "                    distribute to user-global tool directories"
      echo "  --store-only      Install to ~/.local/share/skillmonger/skills/ only"
      echo "                    (no symlinks to tool directories)"
      echo "  --local <dir>     Copy skill into project tool directories"
      echo "  --tools <list>    Comma-separated tools: claude,codex,opencode,pi (default: all)"
      echo "  --format zip      Also create zip in dist/ for Claude.ai upload"
      echo "  --dry-run, -n     Print what would be harvested, removed, copied or"
      echo "                    symlinked, one line per target, and change nothing"
      echo "                    (validation still runs; the harvest does not)"
      echo ""
      echo "At least one of --global, --store-only, or --local must be specified."
      echo ""
      echo "Global paths:"
      echo "  ~/.claude/skills/<name>           (Claude Code)"
      echo "  ~/.codex/skills/<name>            (Codex)"
      echo "  ~/.config/opencode/skills/<name>  (OpenCode)"
      echo "  ~/.pi/agent/skills/<name>         (Pi; copied for SRT access)"
      echo ""
      echo "SRT sandbox paths (copies, not symlinks; YOLOBOX_SANDBOX_HOME overrides):"
      echo "  $YOLOBOX_SANDBOX_HOME/.claude/skills/<name>"
      echo "  $YOLOBOX_SANDBOX_HOME/.codex/skills/<name>"
      echo ""
      echo "Local paths (copied):"
      echo "  <dir>/.claude/skills/<name>/      (Claude Code)"
      echo "  <dir>/.codex/skills/<name>/       (Codex)"
      echo "  <dir>/.opencode/skills/<name>/    (OpenCode)"
      echo "  <dir>/.pi/skills/<name>/          (Pi)"
      exit 0
      ;;
    *)
      SKILL_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: deploy-skill.sh <skill-path> [--global|--store-only] [--local <dir>] [--tools <list>] [--dry-run]"
  echo "Run with --help for more information."
  exit 1
fi

if [ -z "$DO_GLOBAL" ] && [ -z "$STORE_ONLY" ] && [ -z "$LOCAL_DIR" ]; then
  echo "ERROR: Specify --global, --store-only, and/or --local <dir>"
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

# Default to all tools if not specified
if [ -z "$TOOLS" ]; then
  TOOLS="claude,codex,opencode,pi"
fi

echo "Deploying skill: $SKILL_NAME"
echo "Tools: $TOOLS"
if [ -n "$DRY_RUN" ]; then
  echo "Dry run: the plan is printed, nothing is changed."
fi
echo ""

# Run validation first
echo "Running validation..."
if ! "$SCRIPT_DIR/validate-skill.sh" "$SKILL_DIR"; then
  echo ""
  echo "ERROR: Validation failed. Fix errors before deploying."
  exit 1
fi
echo ""

# Helper: check if tool is in the list
tool_enabled() {
  [[ ",$TOOLS," == *",$1,"* ]]
}

# Check skill dependencies
CONFIG_FILE="$SKILL_DIR/CONFIG.yaml"
if [ -f "$CONFIG_FILE" ]; then
  # Extract dependencies.skills list from CONFIG.yaml
  DEP_SKILLS=$(grep -A 50 '^dependencies:' "$CONFIG_FILE" 2>/dev/null \
    | grep '^\s*skills:' \
    | sed 's/.*\[//;s/\].*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -v '^$') || true

  if [ -n "$DEP_SKILLS" ]; then
    MISSING_DEPS=()
    while IFS= read -r dep; do
      found=0
      if { [ -n "$DO_GLOBAL" ] || [ -n "$STORE_ONLY" ]; } && [ -d "$SKILLMONGER_DIR/$dep" ]; then
        found=1
      fi
      if [ -n "$LOCAL_DIR" ] && [ -n "$LOCAL_DIR" ]; then
        for entry in "${TOOL_PATHS[@]}"; do
          IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
          if tool_enabled "$tool"; then
            if [ -n "$DO_GLOBAL" ] && [ -L "$global_path/$dep" -o -d "$global_path/$dep" ]; then
              found=1
            fi
            if [ -n "$LOCAL_DIR" ] && [ -d "$LOCAL_DIR/$local_path/$dep" ]; then
              found=1
            fi
          fi
        done
      elif [ -n "$DO_GLOBAL" ]; then
        for entry in "${TOOL_PATHS[@]}"; do
          IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
          if tool_enabled "$tool" && [ -L "$global_path/$dep" -o -d "$global_path/$dep" ]; then
            found=1
          fi
        done
      fi
      if [ "$found" -eq 0 ]; then
        MISSING_DEPS+=("$dep")
      fi
    done <<< "$DEP_SKILLS"

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
      for dep in "${MISSING_DEPS[@]}"; do
        echo "⚠ Dependency '$dep' is not deployed"
        echo "  Deploy it with: scripts/deploy-skill.sh skills/$dep${DO_GLOBAL:+ --global}${STORE_ONLY:+ --store-only}${LOCAL_DIR:+ --local $LOCAL_DIR}"
      done
      echo ""
    fi
  fi
fi

# Global deployment (--global or --store-only)
if [ -n "$DO_GLOBAL" ] || [ -n "$STORE_ONLY" ]; then
  # Every global target below is about to be rm -rf'd; collect their traces
  # first. One call covers them all: the harvester reads every target before
  # anything is removed.
  harvest_before_removal

  # Install to skillmonger directory
  if [ -n "$DRY_RUN" ]; then
    plan_remove_existing "$SKILLMONGER_DIR/$SKILL_NAME"
    plan copy "$SKILL_DIR -> $SKILLMONGER_DIR/$SKILL_NAME"
  else
    mkdir -p "$SKILLMONGER_DIR"
    rm -rf "${SKILLMONGER_DIR:?}/$SKILL_NAME"
    cp -r "$SKILL_DIR" "$SKILLMONGER_DIR/$SKILL_NAME"

    # Remove .git directories from installed copy
    find "$SKILLMONGER_DIR/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

    echo "✓ Installed to $SKILLMONGER_DIR/$SKILL_NAME"
  fi

  # Create symlinks in tool directories (only for --global, not --store-only)
  if [ -n "$DO_GLOBAL" ]; then
    for entry in "${TOOL_PATHS[@]}"; do
      IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
      if tool_enabled "$tool"; then
        if [ -n "$DRY_RUN" ]; then
          plan_remove_existing "$global_path/$SKILL_NAME"
          if [ "$global_mode" = "copy" ]; then
            plan copy "$SKILLMONGER_DIR/$SKILL_NAME -> $global_path/$SKILL_NAME"
          else
            plan symlink "$global_path/$SKILL_NAME -> $SKILLMONGER_DIR/$SKILL_NAME"
          fi
          continue
        fi
        mkdir -p "$global_path"
        rm -rf "$global_path/$SKILL_NAME"
        if [ "$global_mode" = "copy" ]; then
          cp -r "$SKILLMONGER_DIR/$SKILL_NAME" "$global_path/$SKILL_NAME"
          find "$global_path/$SKILL_NAME" -name ".DS_Store" -delete 2>/dev/null || true
          echo "✓ Copied to $global_path/$SKILL_NAME"
        else
          ln -s "$SKILLMONGER_DIR/$SKILL_NAME" "$global_path/$SKILL_NAME"
          echo "✓ Symlinked $global_path/$SKILL_NAME"
        fi
      fi
    done

    # SRT agent homes need real copies: the sandbox cannot follow the host
    # symlinks into the denied ~/.local skill store.
    for entry in "${SANDBOX_TOOL_PATHS[@]}"; do
      IFS=':' read -r tool sandbox_path <<< "$entry"
      if tool_enabled "$tool"; then
        if [ ! -d "$(dirname "$sandbox_path")" ]; then
          if [ -n "$DRY_RUN" ]; then
            plan skip "$sandbox_path/$SKILL_NAME (no $(dirname "$sandbox_path") in the SRT sandbox home)"
          fi
          continue
        fi
        if [ -n "$DRY_RUN" ]; then
          plan_remove_existing "$sandbox_path/$SKILL_NAME"
          plan copy "$SKILLMONGER_DIR/$SKILL_NAME -> $sandbox_path/$SKILL_NAME (SRT sandbox)"
          continue
        fi
        mkdir -p "$sandbox_path"
        rm -rf "$sandbox_path/$SKILL_NAME"
        cp -r "$SKILLMONGER_DIR/$SKILL_NAME" "$sandbox_path/$SKILL_NAME"
        find "$sandbox_path/$SKILL_NAME" -name ".DS_Store" -delete 2>/dev/null || true
        echo "✓ Copied to $sandbox_path/$SKILL_NAME (SRT sandbox)"
      fi
    done
  fi
fi

# Local deployment (copy)
if [ -n "$LOCAL_DIR" ]; then
  LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"

  # The project's own copies are deploy targets too, and the harvester cannot
  # guess where a project lives, so name them explicitly before removing them.
  LOCAL_TARGETS=()
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool" && [ -d "$LOCAL_DIR/$local_path" ]; then
      LOCAL_TARGETS+=(--target "$LOCAL_DIR/$local_path")
    fi
  done
  if [ ${#LOCAL_TARGETS[@]} -gt 0 ]; then
    harvest_before_removal "${LOCAL_TARGETS[@]}"
  fi

  echo ""
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool"; then
      target_dir="$LOCAL_DIR/$local_path"
      if [ -n "$DRY_RUN" ]; then
        plan_remove_existing "$target_dir/$SKILL_NAME"
        plan copy "$SKILL_DIR -> $target_dir/$SKILL_NAME"
        continue
      fi
      mkdir -p "$target_dir"
      rm -rf "$target_dir/$SKILL_NAME"
      cp -r "$SKILL_DIR" "$target_dir/$SKILL_NAME"
      find "$target_dir/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
      find "$target_dir/$SKILL_NAME" -name ".DS_Store" -delete 2>/dev/null || true
      echo "✓ Copied to $local_path/$SKILL_NAME"
    fi
  done
fi

# Create zip if requested
if [ "$FORMAT" = "zip" ]; then
  echo ""
  DIST_DIR="$PROJECT_ROOT/dist"
  if [ -n "$DRY_RUN" ]; then
    plan_remove_existing "$DIST_DIR/$SKILL_NAME.zip"
    plan zip "$SKILL_DIR -> $DIST_DIR/$SKILL_NAME.zip"
  else
    echo "Building zip archive..."
    mkdir -p "$DIST_DIR"

    TEMP_DIR=$(mktemp -d)
    cp -r "$SKILL_DIR" "$TEMP_DIR/$SKILL_NAME"
    find "$TEMP_DIR/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
    find "$TEMP_DIR/$SKILL_NAME" -name ".DS_Store" -delete 2>/dev/null || true

    rm -f "$DIST_DIR/$SKILL_NAME.zip"
    (cd "$TEMP_DIR" && zip -rq "$DIST_DIR/$SKILL_NAME.zip" "$SKILL_NAME" -x "*.git*")
    rm -rf "$TEMP_DIR"

    echo "✓ Built dist/$SKILL_NAME.zip (for Claude.ai upload)"
  fi
fi

if [ -n "$DRY_RUN" ]; then
  echo ""
  echo "Dry run complete. Nothing was changed."
fi
