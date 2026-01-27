#!/bin/bash
# seed-skill.sh - Capture a skill idea with minimal friction
# Usage:
#   seed-skill.sh                     # interactive
#   seed-skill.sh my-skill            # just a name
#   seed-skill.sh my-skill "one-liner idea"
#   echo "idea" | seed-skill.sh my-skill  # pipe the idea
set -euo pipefail

SEED_DIR="$HOME/Development/sandbox/research/skilldev"
mkdir -p "$SEED_DIR"

# Get skill name
if [ $# -ge 1 ]; then
  NAME="$1"
else
  read -rp "Skill name: " NAME
fi

# Normalize name
NAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')

if [ -z "$NAME" ]; then
  echo "Need a name." >&2
  exit 1
fi

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
