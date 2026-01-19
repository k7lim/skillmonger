#!/bin/bash
# deploy-skill.sh - Build skill for deployment
# Outputs to .claude/skills/ for local use, or dist/ for external deployment
set -euo pipefail

# Parse arguments
SKILL_DIR=""
FORMAT="dir"
TARGET="local"

while [[ $# -gt 0 ]]; do
  case $1 in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: deploy-skill.sh <skill-path> [--format dir|zip] [--target local|dist]"
      echo ""
      echo "Options:"
      echo "  --format dir    Output as directory (default)"
      echo "  --format zip    Output as zip archive"
      echo "  --target local  Deploy to .claude/skills/ (default)"
      echo "  --target dist   Deploy to dist/ for external distribution"
      echo ""
      echo "Output:"
      echo "  .claude/skills/<skill-name>/   Local deployment (Claude Code reads this)"
      echo "  dist/<skill-name>/             External distribution"
      echo ""
      echo "External deployment targets:"
      echo "  Claude Code:   ~/.claude/skills/ or .claude/skills/"
      echo "  Codex:         ~/.codex/skills/ or .codex/skills/"
      echo "  Antigravity:   ~/.gemini/antigravity/skills/ or .agent/skills/"
      echo "  Claude.ai:     Upload zip via Settings > Features"
      exit 0
      ;;
    *)
      SKILL_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$SKILL_DIR" ]; then
  echo "Usage: deploy-skill.sh <skill-path> [--format dir|zip]"
  echo "Run with --help for more information."
  exit 1
fi

SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set output directory based on target
if [ "$TARGET" = "local" ]; then
  DIST_DIR="$PROJECT_ROOT/.claude/skills"
else
  DIST_DIR="$PROJECT_ROOT/dist"
fi

echo "Deploying skill: $SKILL_NAME"
echo "Format: $FORMAT"
echo "Target: $TARGET ($DIST_DIR)"
echo ""

# Run validation first
echo "Running validation..."
if ! "$SCRIPT_DIR/validate-skill.sh" "$SKILL_DIR"; then
  echo ""
  echo "ERROR: Validation failed. Fix errors before deploying."
  exit 1
fi
echo ""

# Create dist directory
mkdir -p "$DIST_DIR"

# Clean previous build
rm -rf "${DIST_DIR:?}/$SKILL_NAME" "${DIST_DIR:?}/$SKILL_NAME.zip"

if [ "$FORMAT" = "dir" ]; then
  # Copy skill directory to dist
  echo "Building directory..."
  cp -r "$SKILL_DIR" "$DIST_DIR/$SKILL_NAME"

  # Remove any .git directories
  find "$DIST_DIR/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

  OUTPUT_PATH="$DIST_DIR/$SKILL_NAME/"
  echo ""
  echo "✓ Built: $OUTPUT_PATH"

elif [ "$FORMAT" = "zip" ]; then
  # Create zip archive
  echo "Building zip archive..."

  # Create temp directory for clean zip
  TEMP_DIR=$(mktemp -d)
  cp -r "$SKILL_DIR" "$TEMP_DIR/$SKILL_NAME"
  find "$TEMP_DIR/$SKILL_NAME" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
  find "$TEMP_DIR/$SKILL_NAME" -name ".DS_Store" -delete 2>/dev/null || true

  # Create zip
  (cd "$TEMP_DIR" && zip -r "$DIST_DIR/$SKILL_NAME.zip" "$SKILL_NAME" -x "*.git*")

  # Cleanup
  rm -rf "$TEMP_DIR"

  OUTPUT_PATH="$DIST_DIR/$SKILL_NAME.zip"
  echo ""
  echo "✓ Built: $OUTPUT_PATH"

else
  echo "ERROR: Unknown format '$FORMAT'. Use 'dir' or 'zip'."
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$TARGET" = "local" ]; then
  echo "✓ Skill deployed to .claude/skills/"
  echo "  Claude Code will now use this skill in this project."
else
  echo "External deployment examples:"
  echo ""
  echo "  # Claude Code (user-global)"
  echo "  cp -r $OUTPUT_PATH ~/.claude/skills/"
  echo ""
  echo "  # OpenAI Codex (user-global)"
  echo "  cp -r $OUTPUT_PATH ~/.codex/skills/"
  echo ""
  echo "  # Antigravity (workspace)"
  echo "  cp -r $OUTPUT_PATH .agent/skills/"
  echo ""
  if [ "$FORMAT" = "zip" ]; then
    echo "  # Claude.ai"
    echo "  Upload $OUTPUT_PATH via Settings > Features"
    echo ""
  fi
fi
