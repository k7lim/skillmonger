#!/bin/bash
# seed-skill.sh - Capture a skill idea with minimal friction
# Usage:
#   seed-skill.sh                     # interactive
#   seed-skill.sh my-skill            # just a name
#   seed-skill.sh my-skill "one-liner idea"
#   echo "idea" | seed-skill.sh my-skill  # pipe the idea
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEED_DIR="$PROJECT_ROOT/seeds"
mkdir -p "$SEED_DIR"

# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

# Get skill name
if [ $# -ge 1 ]; then
  NAME="$1"
else
  read -rp "Skill name: " NAME
fi

# Normalize name, then hold it to the contract: normalising strips the
# characters it cannot use, not a leading hyphen or a 65th character.
NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
skill_name_require "$NAME"

# Get idea - from arg, pipe, or prompt
IDEA=""
if [ $# -ge 2 ]; then
  IDEA="$2"
elif [ ! -t 0 ]; then
  IDEA=$(cat)
else
  read -rp "Idea (optional): " IDEA
fi

# Create the seed file
SEED_FILE="$SEED_DIR/$NAME.md"

if [ -f "$SEED_FILE" ]; then
  echo "Appending to existing seed..."
  echo "" >> "$SEED_FILE"
  echo "---" >> "$SEED_FILE"
  echo "" >> "$SEED_FILE"
fi

{
  echo "# $NAME"
  echo ""
  if [ -n "$IDEA" ]; then
    echo "$IDEA"
  else
    echo "_captured $(date +%Y-%m-%d)_"
  fi
  echo ""
} >> "$SEED_FILE"

echo "$SEED_FILE"
