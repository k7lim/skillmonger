#!/bin/bash
# deploy-skill.sh - Deploy skill via symlinks
# Global: ~/.local/share/skillmonger/skills/ with symlinks to tool locations
# Local: symlink in project tool directories pointing to source
set -euo pipefail

SKILLMONGER_DIR="$HOME/.local/share/skillmonger/skills"

# Tool directory mappings
# Format: tool:global_path:local_path
TOOL_PATHS=(
  "claude:$HOME/.claude/skills:.claude/skills"
  "codex:$HOME/.codex/skills:.codex/skills"
  "opencode:$HOME/.config/opencode/skills:.opencode/skills"
)

# Parse arguments
SKILL_DIR=""
DO_GLOBAL=""
LOCAL_DIR=""
TOOLS=""
FORMAT=""

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
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: deploy-skill.sh <skill-path> [options]"
      echo ""
      echo "Options:"
      echo "  --global          Install to ~/.local/share/skillmonger/skills/ and"
      echo "                    symlink from user-global tool directories"
      echo "  --local <dir>     Symlink from project tool directories to source skill"
      echo "  --tools <list>    Comma-separated tools: claude,codex,opencode (default: all)"
      echo "  --format zip      Also create zip in dist/ for Claude.ai upload"
      echo ""
      echo "At least one of --global or --local must be specified."
      echo ""
      echo "Global paths:"
      echo "  ~/.claude/skills/<name>           (Claude Code)"
      echo "  ~/.codex/skills/<name>            (Codex)"
      echo "  ~/.config/opencode/skills/<name>  (OpenCode)"
      echo ""
      echo "Local paths:"
      echo "  <dir>/.claude/skills/<name>       (Claude Code)"
      echo "  <dir>/.codex/skills/<name>        (Codex)"
      echo "  <dir>/.opencode/skills/<name>     (OpenCode)"
      exit 0
      ;;
    *)
      SKILL_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: deploy-skill.sh <skill-path> [--global] [--local <dir>] [--tools <list>]"
  echo "Run with --help for more information."
  exit 1
fi

if [ -z "$DO_GLOBAL" ] && [ -z "$LOCAL_DIR" ]; then
  echo "ERROR: Specify --global and/or --local <dir>"
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to all tools if not specified
if [ -z "$TOOLS" ]; then
  TOOLS="claude,codex,opencode"
fi

echo "Deploying skill: $SKILL_NAME"
echo "Tools: $TOOLS"
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

# Global deployment
if [ -n "$DO_GLOBAL" ]; then
  # Install to skillmonger directory
  mkdir -p "$SKILLMONGER_DIR"
  rm -rf "${SKILLMONGER_DIR:?}/$SKILL_NAME"
  cp -r "$SKILL_DIR" "$SKILLMONGER_DIR/$SKILL_NAME"

  # Remove .git directories from installed copy
  find "$SKILLMONGER_DIR/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

  echo "✓ Installed to $SKILLMONGER_DIR/$SKILL_NAME"

  # Create symlinks in tool directories
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path <<< "$entry"
    if tool_enabled "$tool"; then
      mkdir -p "$global_path"
      rm -f "$global_path/$SKILL_NAME"
      ln -s "$SKILLMONGER_DIR/$SKILL_NAME" "$global_path/$SKILL_NAME"
      echo "✓ Symlinked $global_path/$SKILL_NAME"
    fi
  done
fi

# Local deployment
if [ -n "$LOCAL_DIR" ]; then
  LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"
  echo ""
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path <<< "$entry"
    if tool_enabled "$tool"; then
      target_dir="$LOCAL_DIR/$local_path"
      mkdir -p "$target_dir"
      rm -f "$target_dir/$SKILL_NAME"
      ln -s "$SKILL_DIR" "$target_dir/$SKILL_NAME"
      echo "✓ Symlinked $local_path/$SKILL_NAME -> $SKILL_DIR"
    fi
  done
fi

# Create zip if requested
if [ "$FORMAT" = "zip" ]; then
  echo ""
  echo "Building zip archive..."
  DIST_DIR="$PROJECT_ROOT/dist"
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
