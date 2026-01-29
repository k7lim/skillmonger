#!/bin/bash
# undeploy-skill.sh - Remove deployed skill symlinks and installed copies
# Inverse of deploy-skill.sh
set -euo pipefail

SKILLMONGER_DIR="$HOME/.local/share/skillmonger/skills"

# Tool directory mappings (mirrors deploy-skill.sh)
TOOL_PATHS=(
  "claude:$HOME/.claude/skills:.claude/skills"
  "codex:$HOME/.codex/skills:.codex/skills"
  "opencode:$HOME/.config/opencode/skills:.opencode/skills"
)

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
      echo "  --global          Remove from ~/.local/share/skillmonger/skills/ and"
      echo "                    remove symlinks from user-global tool directories"
      echo "  --local <dir>     Remove copies from project tool directories"
      echo "  --tools <list>    Comma-separated tools: claude,codex,opencode (default: all)"
      echo ""
      echo "At least one of --global or --local must be specified."
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
  TOOLS="claude,codex,opencode"
fi

echo "Undeploying skill: $SKILL_NAME"
echo "Tools: $TOOLS"
echo ""

# Helper: check if tool is in the list
tool_enabled() {
  [[ ",$TOOLS," == *",$1,"* ]]
}

REMOVED=0

# Global removal
if [ -n "$DO_GLOBAL" ]; then
  # Remove symlinks from tool directories
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path <<< "$entry"
    if tool_enabled "$tool"; then
      target="$global_path/$SKILL_NAME"
      if [ -L "$target" ] || [ -e "$target" ]; then
        rm -f "$target"
        echo "✓ Removed $target"
        REMOVED=$((REMOVED + 1))
      else
        echo "  Skipped $target (not found)"
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
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path <<< "$entry"
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
