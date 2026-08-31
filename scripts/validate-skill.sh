#!/bin/bash
# validate-skill.sh - Validates skill structure per agentskills.io + tri-file extensions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

# --- Skill format (docs/skill-format.md: Format version) -------------------
# skill.format is an integer under skill: in CONFIG.yaml. Missing means 1.
# Each new format appends its integer here; nothing else in this script needs
# to know the set.
SUPPORTED_FORMATS=(1 2)
EVALUATION_MODES="programmatic qualitative delayed hybrid"

format_supported() {
  local candidate="$1" known
  for known in "${SUPPORTED_FORMATS[@]}"; do
    [ "$candidate" = "$known" ] && return 0
  done
  return 1
}

# Print a two-level scalar from CONFIG.yaml (e.g. skill.format,
# evaluation.mode), or nothing when the key is absent.
read_config_value() {
  local config="$1" path="$2"
  if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
    python3 - "$config" "$path" <<'PY' 2>/dev/null || true
import sys, yaml
try:
    node = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    sys.exit(0)
for part in sys.argv[2].split("."):
    if not isinstance(node, dict):
        sys.exit(0)
    node = node.get(part)
if node is None:
    sys.exit(0)
print("true" if node is True else "false" if node is False else node)
PY
  else
    # sed fallback: take the top-level block, then the first nested key
    local top="${path%%.*}" key="${path#*.}"
    sed -n "/^${top}:/,/^[^[:space:]#]/p" "$config" \
      | sed -n "s/^[[:space:]]\{1,\}${key}:[[:space:]]*\([^[:space:]#]*\).*/\1/p" \
      | head -1 | tr -d "\"'"
  fi
}

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

# Check 2b: memo/ directory (wiki overflow, format 2.1) - optional
if [ -d "$SKILL_DIR/memo" ]; then
  memo_count=$(find "$SKILL_DIR/memo" -type f | wc -l | xargs)
  ok "memo/ directory exists ($memo_count file(s), optional)"
else
  echo "  - memo/ not present (optional)"
fi

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

  # Skill format: missing means 1; anything outside SUPPORTED_FORMATS is an error
  skill_format="$(read_config_value "$SKILL_DIR/CONFIG.yaml" skill.format | head -1 | xargs || true)"
  if [ -z "$skill_format" ]; then
    skill_format=1
    ok "Format: 1 (skill.format absent, defaults to 1)"
  elif format_supported "$skill_format"; then
    ok "Format: $skill_format"
  else
    error "skill.format: $skill_format is not a supported skill format (supported: ${SUPPORTED_FORMATS[*]})"
  fi

  # Format 2 onward: the evaluation contract is declared, not inferred
  if [ "$skill_format" -ge 2 ] 2>/dev/null; then
    eval_mode="$(read_config_value "$SKILL_DIR/CONFIG.yaml" evaluation.mode | head -1 | xargs || true)"
    if [ -z "$eval_mode" ]; then
      error "format $skill_format requires evaluation.mode ($EVALUATION_MODES)"
    elif ! echo " $EVALUATION_MODES " | grep -q " $eval_mode "; then
      error "evaluation.mode: $eval_mode is not one of: $EVALUATION_MODES"
    else
      ok "evaluation.mode: $eval_mode"

      if [ "$eval_mode" = "programmatic" ] || [ "$eval_mode" = "hybrid" ]; then
        eval_script="$(read_config_value "$SKILL_DIR/CONFIG.yaml" evaluation.script | head -1 | xargs || true)"
        if [ -z "$eval_script" ]; then
          error "evaluation.mode $eval_mode requires evaluation.script"
        elif [ ! -f "$SKILL_DIR/$eval_script" ]; then
          error "evaluation.script not found: $eval_script"
        elif [ ! -x "$SKILL_DIR/$eval_script" ]; then
          error "evaluation.script is not executable: $eval_script"
        else
          ok "evaluation.script: $eval_script"
        fi
      fi
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

# Check 7: an adopted skill that lost its assets/ on the way in. The
# standard files ship on their own; assets/ is an "extra" and a half-shipped
# adoption is one whose upstream has it while the skill does not
# (skillmonger-j9f). Only checked when the vendored upstream is present.
if [ -f "$SKILL_DIR/CONFIG.yaml" ] && [ ! -d "$SKILL_DIR/assets" ]; then
  up_vendor="$(read_config_value "$SKILL_DIR/CONFIG.yaml" upstream.vendor | head -1 | xargs || true)"
  up_path="$(read_config_value "$SKILL_DIR/CONFIG.yaml" upstream.path | head -1 | xargs || true)"
  up_commit="$(read_config_value "$SKILL_DIR/CONFIG.yaml" upstream.commit | head -1 | xargs || true)"
  if [ -n "$up_vendor" ] && [ -n "$up_path" ]; then
    case "$up_vendor" in
      /*) vendor_dir="$up_vendor" ;;
      *) vendor_dir="$PROJECT_ROOT/$up_vendor" ;;
    esac
    if [ -d "$vendor_dir" ] && command -v git &> /dev/null \
      && git -C "$vendor_dir" cat-file -e "${up_commit:-HEAD}:${up_path%/}/assets" 2>/dev/null; then
      warn "upstream $up_path has assets/ but this skill does not; ship-skill.sh may have stopped before copying it (re-ship with --yes, or copy assets/ from $vendor_dir)"
    fi
  fi
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
