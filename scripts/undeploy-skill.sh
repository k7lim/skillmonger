#!/bin/bash
# undeploy-skill.sh - Remove deployed skill symlinks and installed copies
# Inverse of deploy-skill.sh
#
# The deploy targets are defined once, in lib/deploy-targets.sh, and this
# script removes from exactly the places deploy-skill.sh writes to. A deployed
# copy is where agents write their traces (ADR 0002), so every target is
# harvested before it is removed -- undeploy must never be the step that
# destroys a trace deploy would have brought home.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/deploy-targets.sh
. "$SCRIPT_DIR/lib/deploy-targets.sh"

# Parse arguments
SKILL_NAME=""
DO_GLOBAL=""
LOCAL_DIR=""
TOOLS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --global)
      DO_GLOBAL=1
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
    --help|-h)
      echo "Usage: undeploy-skill.sh <skill-name> [options]"
      echo ""
      echo "Options:"
      echo "  --global          Remove from the store ($SKILLMONGER_DIR),"
      echo "                    the user-global tool directories, and the SRT"
      echo "                    sandbox home ($YOLOBOX_SANDBOX_HOME)"
      echo "  --local <dir>     Remove copies from project tool directories"
      echo "  --tools <list>    Comma-separated tools: claude,codex,opencode,pi (default: all)"
      echo ""
      echo "At least one of --global or --local must be specified."
      echo "Every copy is harvested (harvest-feedback.sh) before it is removed."
      exit 0
      ;;
    *)
      SKILL_NAME="$1"
      shift
      ;;
  esac
done

if [ -z "$SKILL_NAME" ]; then
  echo "Usage: undeploy-skill.sh <skill-name> [--global] [--local <dir>] [--tools <list>]"
  echo "Run with --help for more information."
  exit 1
fi

# Accept a path or bare name
SKILL_NAME="$(basename "$SKILL_NAME")"

if [ -z "$DO_GLOBAL" ] && [ -z "$LOCAL_DIR" ]; then
  echo "ERROR: Specify --global and/or --local <dir>"
  exit 1
fi

# Default to all tools if not specified
if [ -z "$TOOLS" ]; then
  TOOLS="claude,codex,opencode,pi"
fi

echo "Undeploying skill: $SKILL_NAME"
echo "Tools: $TOOLS"
echo ""

# Helper: check if tool is in the list
tool_enabled() {
  [[ ",$TOOLS," == *",$1,"* ]]
}

# Same contract as deploy-skill.sh: a copy is removed only after its traces
# are home. A failed harvest aborts before anything is touched.
harvest_before_removal() {
  if ! "$SCRIPT_DIR/harvest-feedback.sh" "$SKILL_NAME" --quiet "$@"; then
    echo "ERROR: Harvest failed for $SKILL_NAME. Refusing to undeploy: the" >&2
    echo "       deployed copies hold traces that undeploy would destroy." >&2
    exit 1
  fi
}

REMOVED=0

# Global removal
if [ -n "$DO_GLOBAL" ]; then
  harvest_before_removal

  # Remove links or copies from tool directories.
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool"; then
      target="$global_path/$SKILL_NAME"
      if [ -L "$target" ] || [ -e "$target" ]; then
        rm -rf "$target"
        echo "✓ Removed $target"
        REMOVED=$((REMOVED + 1))
      else
        echo "  Skipped $target (not found)"
      fi
    fi
  done

  # Remove the real copies deploy-skill.sh made in the SRT sandbox home.
  for entry in "${SANDBOX_TOOL_PATHS[@]}"; do
    IFS=':' read -r tool sandbox_path <<< "$entry"
    if tool_enabled "$tool"; then
      target="$sandbox_path/$SKILL_NAME"
      if [ -d "$target" ]; then
        rm -rf "$target"
        echo "✓ Removed $target (SRT sandbox)"
        REMOVED=$((REMOVED + 1))
      fi
    fi
  done

  # Remove installed copy
  installed="$SKILLMONGER_DIR/$SKILL_NAME"
  if [ -d "$installed" ]; then
    rm -r "$installed"
    echo "✓ Removed $installed"
    REMOVED=$((REMOVED + 1))
  else
    echo "  Skipped $installed (not found)"
  fi
fi

# Local removal
if [ -n "$LOCAL_DIR" ]; then
  LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"

  # The project's copies are deploy targets the harvester cannot enumerate on
  # its own, so name them explicitly before removing them.
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

  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool"; then
      target="$LOCAL_DIR/$local_path/$SKILL_NAME"
      if [ -L "$target" ] || [ -d "$target" ]; then
        rm -rf "$target"
        echo "✓ Removed $local_path/$SKILL_NAME"
        REMOVED=$((REMOVED + 1))
      else
        echo "  Skipped $local_path/$SKILL_NAME (not found)"
      fi
    fi
  done
fi

echo ""
if [ "$REMOVED" -gt 0 ]; then
  echo "Done. Removed $REMOVED item(s)."
else
  echo "Nothing to remove. Skill '$SKILL_NAME' was not deployed."
fi
