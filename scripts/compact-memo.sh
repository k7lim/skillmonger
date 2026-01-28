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

# Display feedback summary if FEEDBACK.jsonl exists
FEEDBACK_FILE="$SKILL_DIR/FEEDBACK.jsonl"
if [ -f "$FEEDBACK_FILE" ]; then
  fb_count=$(wc -l < "$FEEDBACK_FILE" | xargs)
  echo "=== Feedback Summary ($fb_count entries) ==="

  # Calculate average outcome
  avg=$(grep -oE '"outcome":[1-5]' "$FEEDBACK_FILE" | grep -oE '[1-5]' | awk '{ sum+=$1; count++ } END { if (count>0) printf "%.1f", sum/count }')
  if [ -n "$avg" ]; then
    echo "  Average outcome: $avg / 5.0"
  fi

  # Source breakdown
  llm_count=$(grep -c '"source":"llm"' "$FEEDBACK_FILE" 2>/dev/null || echo "0")
  script_count=$(grep -c '"source":"script"' "$FEEDBACK_FILE" 2>/dev/null || echo "0")
  user_count=$(grep -c '"source":"user"' "$FEEDBACK_FILE" 2>/dev/null || echo "0")
  echo "  Sources: llm=$llm_count  script=$script_count  user=$user_count"

  # Show recent low scores (outcome <= 2) as compaction signals
  low_scores=$(grep -E '"outcome":[12]' "$FEEDBACK_FILE" 2>/dev/null | tail -3)
  if [ -n "$low_scores" ]; then
    echo ""
    echo "  Recent low scores (signals for compaction):"
    echo "$low_scores" | while IFS= read -r line; do
      note=$(echo "$line" | grep -oE '"note":"[^"]*"' | sed 's/"note":"//;s/"//')
      prompt=$(echo "$line" | grep -oE '"prompt":"[^"]*"' | sed 's/"prompt":"//;s/"//' | cut -c1-50)
      outcome=$(echo "$line" | grep -oE '"outcome":[1-5]' | grep -oE '[1-5]')
      echo "    [$outcome] $prompt${note:+ - $note}"
    done
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
