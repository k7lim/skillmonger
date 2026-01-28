#!/bin/bash
# analyze-feedback.sh - Summarize feedback across all skills
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"

usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Analyzes FEEDBACK.jsonl files across all skills.

Options:
  --skill NAME    Analyze only the named skill
  --version VER   Filter to a specific version
  --export        Output raw JSONL (all entries, for piping to jq)
  --help          Show this help message

Examples:
  $(basename "$0")                              # summary of all skills
  $(basename "$0") --skill centers-of-excellence # one skill detail
  $(basename "$0") --export | jq '.outcome'     # raw data pipeline
EOF
}

FILTER_SKILL=""
FILTER_VERSION=""
EXPORT_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skill)
      FILTER_SKILL="$2"
      shift 2
      ;;
    --version)
      FILTER_VERSION="$2"
      shift 2
      ;;
    --export)
      EXPORT_MODE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1"
      usage
      exit 1
      ;;
  esac
done

# --- Collect feedback files ---

feedback_files=()
if [ -n "$FILTER_SKILL" ]; then
  f="$SKILLS_DIR/$FILTER_SKILL/FEEDBACK.jsonl"
  if [ -f "$f" ]; then
    feedback_files+=("$f")
  else
    echo "No feedback found for skill: $FILTER_SKILL"
    exit 0
  fi
else
  for skill_dir in "$SKILLS_DIR"/*/; do
    f="$skill_dir/FEEDBACK.jsonl"
    if [ -f "$f" ]; then
      feedback_files+=("$f")
    fi
  done
fi

if [ ${#feedback_files[@]} -eq 0 ]; then
  echo "No feedback data found."
  echo "Log feedback with: scripts/log-feedback.sh <skill-name>"
  exit 0
fi

# --- Export mode ---

if [ "$EXPORT_MODE" = true ]; then
  for f in "${feedback_files[@]}"; do
    if [ -n "$FILTER_VERSION" ]; then
      grep "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || true
    else
      cat "$f"
    fi
  done
  exit 0
fi

# --- Summary mode ---

echo "Feedback Summary"
echo "================"
echo ""

total_entries=0
total_outcome_sum=0

for f in "${feedback_files[@]}"; do
  skill_name=$(basename "$(dirname "$f")")
  entries=$(wc -l < "$f" | xargs)

  if [ "$entries" -eq 0 ]; then
    continue
  fi

  # Filter by version if specified
  if [ -n "$FILTER_VERSION" ]; then
    filtered=$(grep -c "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || echo "0")
    if [ "$filtered" -eq 0 ]; then
      continue
    fi
    entries="$filtered"
  fi

  echo "--- $skill_name ($entries entries) ---"

  # Calculate stats using awk (no jq dependency)
  if [ -n "$FILTER_VERSION" ]; then
    data=$(grep "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || true)
  else
    data=$(cat "$f")
  fi

  # Extract outcomes and compute stats
  stats=$(echo "$data" | grep -oE '"outcome":[1-5]' | grep -oE '[1-5]' | awk '
    BEGIN { sum=0; count=0; s1=0; s2=0; s3=0; s4=0; s5=0 }
    {
      sum += $1; count++
      if ($1==1) s1++
      if ($1==2) s2++
      if ($1==3) s3++
      if ($1==4) s4++
      if ($1==5) s5++
    }
    END {
      if (count > 0) {
        avg = sum / count
        printf "avg=%.1f count=%d s1=%d s2=%d s3=%d s4=%d s5=%d sum=%d\n", avg, count, s1, s2, s3, s4, s5, sum
      }
    }
  ')

  if [ -n "$stats" ]; then
    eval "$stats"
    echo "  Average: $avg / 5.0"
    echo "  Distribution: 1=$s1  2=$s2  3=$s3  4=$s4  5=$s5"
    total_entries=$((total_entries + count))
    total_outcome_sum=$((total_outcome_sum + sum))
  fi

  # Source breakdown
  llm_count=$(echo "$data" | grep -c '"source":"llm"' || true)
  script_count=$(echo "$data" | grep -c '"source":"script"' || true)
  user_count=$(echo "$data" | grep -c '"source":"user"' || true)
  echo "  Sources: llm=$llm_count  script=$script_count  user=$user_count"

  # Latest entry timestamp
  latest_ts=$(tail -1 "$f" | grep -oE '"ts":"[^"]*"' | head -1 | sed 's/"ts":"//;s/"//' || echo "unknown")
  echo "  Latest: $latest_ts"

  # Version breakdown if multiple versions
  versions=$(echo "$data" | grep -oE '"version":"[^"]*"' | sort -u | sed 's/"version":"//;s/"//')
  version_count=$(echo "$versions" | wc -l | xargs)
  if [ "$version_count" -gt 1 ]; then
    echo "  Versions: $version_count ($versions)"
  fi

  echo ""
done

# --- Overall ---

if [ "$total_entries" -gt 0 ]; then
  overall_avg=$(awk "BEGIN {printf \"%.1f\", $total_outcome_sum / $total_entries}")
  echo "================"
  echo "Total: $total_entries entries across ${#feedback_files[@]} skill(s)"
  echo "Overall average: $overall_avg / 5.0"
fi
