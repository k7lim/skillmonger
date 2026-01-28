#!/bin/bash
# develop-skill.sh - Create a skill scaffold in sandbox for development
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_SKILLS_DIR="$HOME/Development/sandbox/projects/skills"
TODAY=$(date +%Y-%m-%d)

echo "Creating skill scaffold in sandbox..."
echo "Location: $SANDBOX_SKILLS_DIR/"
echo ""

# Ensure sandbox skills directory exists
if [ ! -d "$SANDBOX_SKILLS_DIR" ]; then
  echo "Creating sandbox skills directory..."
  mkdir -p "$SANDBOX_SKILLS_DIR"
fi

# --- Input Collection ---

# Skill name
while true; do
  read -rp "Skill name (lowercase, hyphens only): " SKILL_NAME

  if [ -z "$SKILL_NAME" ]; then
    echo "  Error: Name is required"
    continue
  fi

  if ! echo "$SKILL_NAME" | grep -qE '^[a-z0-9-]+$'; then
    echo "  Error: Name must contain only lowercase letters, numbers, and hyphens"
    continue
  fi

  if [ -d "$SANDBOX_SKILLS_DIR/$SKILL_NAME" ]; then
    echo "  Error: Skill '$SKILL_NAME' already exists at $SANDBOX_SKILLS_DIR/$SKILL_NAME"
    continue
  fi

  # Also check if it exists in skillmonger
  if [ -d "$PROJECT_ROOT/skills/$SKILL_NAME" ]; then
    echo "  Warning: Skill '$SKILL_NAME' already exists in skillmonger at $PROJECT_ROOT/skills/$SKILL_NAME"
    read -rp "  Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
      continue
    fi
  fi

  break
done

# One-liner description
echo ""
read -rp "One-liner (what does it do?): " ONE_LINER
ONE_LINER="${ONE_LINER:-A skill that does something useful.}"

# --- Generate Files ---

SKILL_DIR="$SANDBOX_SKILLS_DIR/$SKILL_NAME"
SEED_FILE="$HOME/Development/sandbox/research/skilldev/$SKILL_NAME.md"
echo ""
echo "Creating skill stub at $SKILL_DIR/..."

mkdir -p "$SKILL_DIR/scripts"
mkdir -p "$SKILL_DIR/references"

# Copy seed file as PLAN.md if it exists
if [ -f "$SEED_FILE" ]; then
  cp "$SEED_FILE" "$SKILL_DIR/PLAN.md"
  echo "  ✓ Copied seed notes to PLAN.md"
fi

# Generate BRIEF.md from template for yolo agent session
if [ -f "$PROJECT_ROOT/templates/sandbox-brief.md" ]; then
  sed -e "s|{{SKILL_NAME}}|$SKILL_NAME|g" \
      -e "s|{{ONE_LINER}}|$ONE_LINER|g" \
      -e "s|{{SKILL_DIR}}|$SKILL_DIR|g" \
      "$PROJECT_ROOT/templates/sandbox-brief.md" > "$SKILL_DIR/BRIEF.md"
  echo "  ✓ Created BRIEF.md (task brief for sandbox agent)"
fi

# Copy DESIGN.md template
cp "$PROJECT_ROOT/templates/DESIGN.md" "$SKILL_DIR/DESIGN.md"
# Fill in the name and one-liner
sed -i '' "s/\[skill-name\]/$SKILL_NAME/g" "$SKILL_DIR/DESIGN.md"
sed -i '' "s/\[What does this skill do\?\]/$ONE_LINER/g" "$SKILL_DIR/DESIGN.md"
echo "  ✓ Created DESIGN.md (fill this out first!)"

# Generate minimal SKILL.md
cat > "$SKILL_DIR/SKILL.md" << EOF
---
name: $SKILL_NAME
description: $ONE_LINER
---

# ${SKILL_NAME//-/ }

> **Draft skill** - Iterate here in sandbox, then promote to skillmonger.

## When to use

[Describe trigger conditions]

## Prerequisites

Before proceeding, run \`scripts/status-check.sh\` in this skill directory.

**Interpreting results:**
- \`"ready": true\` → proceed with workflow
- \`"ready": false\` → help user resolve issues listed in \`checks\`

| Check | If missing/outdated |
|-------|---------------------|
| [dep1] | [How to install] |

## Workflow

### Step 1: [Action]

[Instructions]

### Step 2: [Action]

[Instructions]

## Examples

**User:** "[Example request]"

**Response:** [Example response]

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
echo "  ✓ Created SKILL.md (draft)"

# Generate status-check.sh template
cat > "$SKILL_DIR/scripts/status-check.sh" << 'EOF'
#!/bin/bash
# status-check.sh - Verify prerequisites for this skill
# Outputs JSON for agent consumption
set -euo pipefail

# Track overall readiness
all_ok=true

# --- Add your checks here ---

check_example() {
  # Example: check if a command exists
  if ! command -v example_cmd &>/dev/null; then
    echo '{"name":"example","status":"missing","required":">=1.0"}'
    all_ok=false
    return
  fi
  version=$(example_cmd --version 2>&1 | head -1)
  echo "{\"name\":\"example\",\"status\":\"ok\",\"version\":\"$version\"}"
}

# --- Output JSON ---

echo "{"
echo "  \"ready\": READY_PLACEHOLDER,"
echo "  \"checks\": ["

# Call your check functions here, comma-separated
# check_example

echo "  ],"
echo "  \"context\": {}"
echo "}"
EOF

# Fix the ready placeholder logic with a proper script
cat > "$SKILL_DIR/scripts/status-check.sh" << 'OUTER'
#!/bin/bash
# status-check.sh - Verify prerequisites for this skill
# Outputs JSON for agent consumption
set -euo pipefail

checks=()
all_ok=true

# --- Check functions ---
# Each should append to checks array and set all_ok=false if not ok

check_example() {
  # Example: check if a command exists
  # Replace 'example_cmd' with actual dependency
  local name="example"
  local required=">=1.0"

  if ! command -v example_cmd &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"required\":\"$required\"}")
    all_ok=false
    return
  fi

  local version
  version=$(example_cmd --version 2>&1 | head -1 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\"$required\"}")
}

# --- Run checks ---
# Uncomment and add your checks:
# check_example

# --- Output JSON ---

# Build checks array
checks_json=""
for i in "${!checks[@]}"; do
  if [ $i -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

# Output
cat << EOF
{
  "ready": $all_ok,
  "checks": [$checks_json],
  "context": {}
}
EOF
OUTER

chmod +x "$SKILL_DIR/scripts/status-check.sh"
echo "  ✓ Created scripts/status-check.sh (template)"

# Generate evaluate.sh template
cat > "$SKILL_DIR/scripts/evaluate.sh" << 'EVALEOF'
#!/bin/bash
# evaluate.sh - Deterministic scoring for skill output
# Reads skill output from stdin or a file argument.
# Outputs JSON with outcome (1-5), note, and checks.
#
# Usage:
#   echo "$OUTPUT" | scripts/evaluate.sh
#   scripts/evaluate.sh output.md
set -euo pipefail

# Read input from file arg or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

# --- Add your checks here ---
# Example: count entries, validate structure, check completeness

outcome=4
note=""

# --- Output JSON ---
cat << EOF
{"outcome":$outcome,"note":"$note","checks":{},"source":"script"}
EOF
EVALEOF

chmod +x "$SKILL_DIR/scripts/evaluate.sh"
echo "  ✓ Created scripts/evaluate.sh (template)"

# Create a simple README for the sandbox skill
cat > "$SKILL_DIR/README.md" << EOF
# $SKILL_NAME (sandbox draft)

Created: $TODAY

## Development Workflow

1. **Fill out DESIGN.md** - Think through deterministic vs natural language
2. **Build status-check.sh** - Add checks for all detectable prerequisites
3. **Iterate on SKILL.md** - Test with yolo permissions in sandbox
4. **Ship to skillmonger** when stable:
   \`\`\`bash
   ship-skill ~/Development/sandbox/projects/skills/$SKILL_NAME
   \`\`\`

## Testing

\`\`\`bash
# Test your status check
./scripts/status-check.sh | jq .

# Test the skill with an agent (in sandbox with yolo)
cd ~/Development/sandbox/projects/skills/$SKILL_NAME
claude  # or your preferred agent
\`\`\`
EOF
echo "  ✓ Created README.md"
echo "  ✓ Created references/ (empty)"

# --- Summary ---

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Skill scaffold created: $SKILL_DIR"
echo ""
echo "Next step — launch a yolo agent in the sandbox:"
echo ""
echo "  cd $SKILL_DIR && claude \"Read BRIEF.md and build the skill\""
echo ""
if [ -f "$SKILL_DIR/PLAN.md" ]; then
  echo "PLAN.md has the seed notes. BRIEF.md has the build specs."
else
  echo "BRIEF.md has the build specs. Add a PLAN.md for detailed context."
fi
echo ""
echo "When done, ship from the host:"
echo ""
echo "  scripts/ship-skill.sh $SKILL_DIR"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
