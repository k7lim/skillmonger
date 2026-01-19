#!/bin/bash
# validate-skill.sh - Validates skill structure per agentskills.io + tri-file extensions
set -euo pipefail

SKILL_DIR="${1:-.}"

# Resolve to absolute path
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

echo "Validating skill: $SKILL_NAME"
echo "Path: $SKILL_DIR"
echo ""

error_count=0
warning_count=0

# Helper functions
error() { echo "ERROR: $1"; ((error_count++)) || true; }
warn() { echo "WARNING: $1"; ((warning_count++)) || true; }
ok() { echo "  ✓ $1"; }

# Check 1: SKILL.md exists (required)
echo "Checking required files..."
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  error "Missing required file: SKILL.md"
else
  ok "SKILL.md exists"
fi

# Check 2: Tri-file extensions (optional but noted)
for file in CONFIG.yaml MEMO.md; do
  if [ -f "$SKILL_DIR/$file" ]; then
    ok "$file exists (tri-file extension)"
  else
    echo "  - $file not present (optional)"
  fi
done

# Check 3: SKILL.md frontmatter validation
echo ""
echo "Validating SKILL.md frontmatter..."
if [ -f "$SKILL_DIR/SKILL.md" ]; then
  # Check for YAML frontmatter delimiters
  if ! head -1 "$SKILL_DIR/SKILL.md" | grep -q "^---$"; then
    error "SKILL.md missing YAML frontmatter (must start with ---)"
  else
    # Extract frontmatter (between first and second --- lines)
    # Use awk for cross-platform compatibility
    frontmatter=$(awk 'NR==1 && /^---$/ {found=1; next} found && /^---$/ {exit} found {print}' "$SKILL_DIR/SKILL.md")

    # Extract name field
    name=$(echo "$frontmatter" | grep "^name:" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'")

    # Extract description field
    description=$(echo "$frontmatter" | grep "^description:" | head -1 | sed 's/^description:[[:space:]]*//')

    # Validate name
    if [ -z "$name" ]; then
      error "Missing required 'name' field in frontmatter"
    else
      ok "name: $name"

      # Name constraints per agentskills.io
      if [ ${#name} -gt 64 ]; then
        error "name exceeds 64 characters (${#name})"
      fi

      if ! echo "$name" | grep -qE '^[a-z0-9-]+$'; then
        error "name must contain only lowercase letters, numbers, and hyphens"
      fi

      if [[ "$name" == -* ]] || [[ "$name" == *- ]]; then
        error "name cannot start or end with hyphen"
      fi

      if [[ "$name" == *--* ]]; then
        error "name cannot contain consecutive hyphens"
      fi

      # Check name matches directory
      if [ "$name" != "$SKILL_NAME" ]; then
        warn "name ($name) does not match directory name ($SKILL_NAME)"
      fi
    fi

    # Validate description
    if [ -z "$description" ]; then
      error "Missing required 'description' field in frontmatter"
    else
      ok "description present"

      if [ ${#description} -gt 1024 ]; then
        error "description exceeds 1024 characters (${#description})"
      fi
    fi
  fi

  # Check word count
  word_count=$(wc -w < "$SKILL_DIR/SKILL.md" | xargs)
  echo "  Word count: $word_count"
  if [ "$word_count" -gt 5000 ]; then
    warn "SKILL.md exceeds 5000 words - consider moving content to references/"
  fi
fi

# Check 4: CONFIG.yaml validation (if present)
if [ -f "$SKILL_DIR/CONFIG.yaml" ]; then
  echo ""
  echo "Validating CONFIG.yaml..."

  # Try to validate YAML using python3 with PyYAML
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$SKILL_DIR/CONFIG.yaml'))" 2>/dev/null; then
      ok "Valid YAML syntax"

      # Extract version from CONFIG.yaml
      config_version=$(python3 -c "import yaml; c=yaml.safe_load(open('$SKILL_DIR/CONFIG.yaml')); print(c.get('skill',{}).get('version',''))" 2>/dev/null || echo "")

      if [ -n "$config_version" ]; then
        ok "Version: $config_version"
      else
        warn "No skill.version in CONFIG.yaml"
      fi
    else
      error "CONFIG.yaml is not valid YAML"
    fi
  else
    # Fallback: basic syntax check (look for obvious errors)
    if grep -qE "^[[:space:]]*[^:#]+:[^:]*$" "$SKILL_DIR/CONFIG.yaml" 2>/dev/null; then
      ok "CONFIG.yaml present (install PyYAML for full validation)"
      # Try to extract version with grep
      config_version=$(grep "^[[:space:]]*version:" "$SKILL_DIR/CONFIG.yaml" | head -1 | sed 's/.*version:[[:space:]]*//' | tr -d '"' | tr -d "'" | xargs)
      if [ -n "$config_version" ]; then
        ok "Version: $config_version"
      fi
    else
      warn "CONFIG.yaml present but couldn't validate (install PyYAML)"
    fi
  fi
fi

# Check 5: References directory
if [ -d "$SKILL_DIR/references" ]; then
  ref_count=$(find "$SKILL_DIR/references" -type f | wc -l | xargs)
  ok "references/ directory with $ref_count file(s)"
fi

# Check 6: Scripts directory
if [ -d "$SKILL_DIR/scripts" ]; then
  script_count=$(find "$SKILL_DIR/scripts" -type f | wc -l | xargs)
  ok "scripts/ directory with $script_count file(s)"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $error_count -eq 0 ] && [ $warning_count -eq 0 ]; then
  echo "✓ Validation PASSED"
  exit 0
elif [ $error_count -eq 0 ]; then
  echo "✓ Validation PASSED with $warning_count warning(s)"
  exit 0
else
  echo "✗ Validation FAILED: $error_count error(s), $warning_count warning(s)"
  exit 1
fi
