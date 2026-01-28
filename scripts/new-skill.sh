#!/bin/bash
# new-skill.sh - Interactive script to create a new skill with sensible defaults
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"
TODAY=$(date +%Y-%m-%d)

echo "Creating a new skill..."
echo ""

# --- Input Collection ---

# Skill name
while true; do
  read -rp "Skill name (lowercase, hyphens only): " SKILL_NAME

  if [ -z "$SKILL_NAME" ]; then
    echo "  Error: Name is required"
    continue
  fi

  # Validate name constraints
  if ! echo "$SKILL_NAME" | grep -qE '^[a-z0-9-]+$'; then
    echo "  Error: Name must contain only lowercase letters, numbers, and hyphens"
    continue
  fi

  if [ ${#SKILL_NAME} -gt 64 ]; then
    echo "  Error: Name exceeds 64 characters"
    continue
  fi

  if [[ "$SKILL_NAME" == -* ]] || [[ "$SKILL_NAME" == *- ]]; then
    echo "  Error: Name cannot start or end with hyphen"
    continue
  fi

  if [[ "$SKILL_NAME" == *--* ]]; then
    echo "  Error: Name cannot contain consecutive hyphens"
    continue
  fi

  # Check if directory exists
  if [ -d "$SKILLS_DIR/$SKILL_NAME" ]; then
    echo "  Error: Skill '$SKILL_NAME' already exists at $SKILLS_DIR/$SKILL_NAME"
    continue
  fi

  break
done

# Description
while true; do
  echo ""
  echo "Description (what it does AND when to use it):"
  read -rp "> " DESCRIPTION

  if [ -z "$DESCRIPTION" ]; then
    echo "  Error: Description is required"
    continue
  fi

  if [ ${#DESCRIPTION} -gt 1024 ]; then
    echo "  Error: Description exceeds 1024 characters (${#DESCRIPTION})"
    continue
  fi

  break
done

# Author (default to $USER)
echo ""
read -rp "Author [$USER]: " AUTHOR
AUTHOR="${AUTHOR:-$USER}"

# Role description
echo ""
echo "Role description (e.g., \"You are a data analyst\"):"
read -rp "> " ROLE
ROLE="${ROLE:-You are an expert assistant.}"

# Trigger phrases (optional)
TRIGGER_PHRASES=()
echo ""
read -rp "Add trigger phrases? (y/N): " ADD_TRIGGERS
if [[ "$ADD_TRIGGERS" =~ ^[Yy]$ ]]; then
  i=1
  while true; do
    read -rp "  Phrase $i (empty to finish): " phrase
    if [ -z "$phrase" ]; then
      break
    fi
    TRIGGER_PHRASES+=("$phrase")
    ((i++))
  done
fi

# WebSearch dependency
echo ""
read -rp "Requires WebSearch tool? (y/N): " NEEDS_WEBSEARCH
NEEDS_WEBSEARCH="${NEEDS_WEBSEARCH:-n}"

# --- File Generation ---

SKILL_DIR="$SKILLS_DIR/$SKILL_NAME"
echo ""
echo "Creating skill at $SKILL_DIR/..."

# Create directories
mkdir -p "$SKILL_DIR/references"

# Generate SKILL.md
cat > "$SKILL_DIR/SKILL.md" << EOF
---
name: $SKILL_NAME
description: $DESCRIPTION
---

# ${SKILL_NAME//-/ }

$ROLE

## When to Use

- [Trigger condition 1]
- [Trigger condition 2]

## Execution Workflow

### Step 1: [Action]

[Instructions for this step]

### Step 2: [Action]

[Instructions for this step]

## Examples

**User:** "[Example input]"

**Response:**

[Example output]

---

## After Execution

After completing the skill output, log feedback to track quality over time.

**Priority cascade:**
1. If \`scripts/evaluate.sh\` exists in this skill directory, run it and use the JSON result
2. Otherwise, self-assess using the scale below

**Self-assessment scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

**To log feedback**, append one JSON line to \`FEEDBACK.jsonl\` in this skill directory:

\`\`\`json
{"ts":"<UTC ISO 8601>","skill":"$SKILL_NAME","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
\`\`\`

Then increment \`iteration_count\` under \`compaction\` in \`CONFIG.yaml\`.
EOF
echo "  ✓ Created SKILL.md"

# Generate CONFIG.yaml
{
  cat << EOF
# ${SKILL_NAME} Skill Configuration
# Tri-file architecture extension

skill:
  name: $SKILL_NAME
  version: 1.0.0
  created: $TODAY
  updated: $TODAY
  author: $AUTHOR

EOF

  # Triggers section
  if [ ${#TRIGGER_PHRASES[@]} -gt 0 ]; then
    echo "triggers:"
    echo "  phrases:"
    for phrase in "${TRIGGER_PHRASES[@]}"; do
      echo "    - \"$phrase\""
    done
    echo "  keywords:"
    echo "    - # add keywords"
  else
    cat << EOF
triggers:
  phrases:
    - # add trigger phrases
  keywords:
    - # add keywords
EOF
  fi

  # Dependencies section
  if [[ "$NEEDS_WEBSEARCH" =~ ^[Yy]$ ]]; then
    cat << EOF

dependencies:
  tools:
    - WebSearch
  permissions:
    - WebSearch
EOF
  else
    cat << EOF

dependencies:
  tools: []
EOF
  fi

  # Rest of config
  cat << EOF

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
} > "$SKILL_DIR/CONFIG.yaml"
echo "  ✓ Created CONFIG.yaml"

# Generate MEMO.md
cat > "$SKILL_DIR/MEMO.md" << EOF
# ${SKILL_NAME} - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

_No edge cases logged yet._

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

_None logged yet_

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| $TODAY | 1.0.0 | Initial | Skill created |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
EOF
echo "  ✓ Created MEMO.md"
echo "  ✓ Created references/"

# --- Validation ---

echo ""
echo "Running validation..."
if "$SCRIPT_DIR/validate-skill.sh" "$SKILL_DIR" 2>/dev/null | grep -q "Validation PASSED"; then
  echo "  ✓ Validation PASSED"
else
  echo ""
  "$SCRIPT_DIR/validate-skill.sh" "$SKILL_DIR"
fi

# --- Next Steps ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next steps:"
echo "  1. Edit $SKILL_DIR/SKILL.md to add your workflow"
echo "  2. Add reference docs to $SKILL_DIR/references/"
echo "  3. Deploy: scripts/deploy-skill.sh $SKILL_DIR/"
echo ""
