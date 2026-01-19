#!/bin/bash
# compact-memo.sh - Compaction process for MEMO.md
# Reviews edge cases and learnings for graduation to SKILL.md
set -euo pipefail

SKILL_DIR="${1:-.}"
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_NAME="$(basename "$SKILL_DIR")"

MEMO_FILE="$SKILL_DIR/MEMO.md"
CONFIG_FILE="$SKILL_DIR/CONFIG.yaml"
SKILL_FILE="$SKILL_DIR/SKILL.md"

echo "Compaction Review: $SKILL_NAME"
echo "Path: $SKILL_DIR"
echo ""

if [ ! -f "$MEMO_FILE" ]; then
  echo "No MEMO.md found - nothing to compact."
  exit 0
fi

# Display current stats
echo "=== MEMO.md Statistics ==="
word_count=$(wc -w < "$MEMO_FILE" | xargs)
line_count=$(wc -l < "$MEMO_FILE" | xargs)
echo "  Lines: $line_count"
echo "  Words: $word_count"

# Count sections
edge_cases=$(grep -c "^### " "$MEMO_FILE" 2>/dev/null || echo "0")
echo "  Edge case entries: ~$edge_cases"
echo ""

# Check iteration count from CONFIG.yaml
if [ -f "$CONFIG_FILE" ] && command -v python3 &> /dev/null; then
  iteration_count=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('compaction',{}).get('iteration_count',0))" 2>/dev/null || echo "0")
  threshold=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(c.get('compaction',{}).get('cycle_threshold',15))" 2>/dev/null || echo "15")

  echo "=== Compaction Status ==="
  echo "  Iteration count: $iteration_count"
  echo "  Threshold: $threshold"

  if [ "$iteration_count" -ge "$threshold" ]; then
    echo ""
    echo "  ⚠ COMPACTION RECOMMENDED"
    echo "  Iteration count ($iteration_count) >= threshold ($threshold)"
  else
    remaining=$((threshold - iteration_count))
    echo "  Next compaction in ~$remaining iterations"
  fi
  echo ""
fi

# Display MEMO.md content for review
echo "=== Current MEMO.md Content ==="
echo ""
cat "$MEMO_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Compaction Process:"
echo ""
echo "1. REVIEW: Identify patterns that have stabilized"
echo "   - Edge cases that are now well-understood"
echo "   - Learnings that should be standard practice"
echo ""
echo "2. GRADUATE: Move stable patterns to SKILL.md"
echo "   - Add to appropriate section in SKILL.md"
echo "   - Update as permanent guidance"
echo ""
echo "3. PURGE: Remove from MEMO.md"
echo "   - Delete graduated items"
echo "   - Remove resolved/outdated edge cases"
echo ""
echo "4. VERSION: Update CONFIG.yaml"
echo "   - Increment version (patch for compaction)"
echo "   - Reset iteration_count to 0"
echo "   - Update last_compaction date"
echo ""
echo "To perform compaction, use Claude:"
echo "  'Review MEMO.md in $SKILL_NAME and graduate stable patterns to SKILL.md'"
