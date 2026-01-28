#!/bin/bash
# evaluate.sh - Deterministic scoring for centers-of-excellence skill output
# Reads skill output from stdin or a file argument, checks structural quality.
# Outputs JSON suitable for FEEDBACK.jsonl.
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

# --- Checks ---

entry_count=0
pct_sum=0
has_justifications=true
has_language_section=false

# Count numbered entries (lines starting with number followed by period or parenthesis)
entry_count=$(echo "$INPUT" | grep -cE '^\s*[0-9]+[\.\)]' || true)

# Check for language/percentage section
if echo "$INPUT" | grep -qiE '(language|languages)'; then
  has_language_section=true

  # Extract percentages and sum them
  # Match patterns like (45%), (30%), etc.
  percentages=$(echo "$INPUT" | grep -oE '\([0-9]+%\)' | grep -oE '[0-9]+' || true)
  if [ -n "$percentages" ]; then
    pct_sum=0
    while IFS= read -r pct; do
      pct_sum=$((pct_sum + pct))
    done <<< "$percentages"
  fi
fi

# Check justifications: entries should have a dash or colon after the location
justification_count=$(echo "$INPUT" | grep -cE '^\s*[0-9]+[\.\)].+[-–—:]' || true)
if [ "$entry_count" -gt 0 ] && [ "$justification_count" -lt "$entry_count" ]; then
  has_justifications=false
fi

# --- Score ---

outcome=5
note_parts=()

# Entry count check
if [ "$entry_count" -ge 10 ]; then
  entry_check=true
elif [ "$entry_count" -ge 5 ]; then
  entry_check=true
  outcome=$((outcome < 3 ? outcome : 3))
  note_parts+=("only $entry_count entries (expected 10)")
else
  entry_check=false
  outcome=$((outcome < 2 ? outcome : 2))
  note_parts+=("$entry_count entries (expected 10)")
fi

# Percentage sum check
if [ "$has_language_section" = true ]; then
  if [ "$pct_sum" -eq 100 ]; then
    pct_check=true
  elif [ "$pct_sum" -ge 95 ] && [ "$pct_sum" -le 105 ]; then
    pct_check=true
    outcome=$((outcome < 4 ? outcome : 4))
    note_parts+=("percentages sum to $pct_sum (expected 100)")
  else
    pct_check=false
    outcome=$((outcome < 2 ? outcome : 2))
    note_parts+=("percentages sum to $pct_sum (expected 100)")
  fi
else
  pct_check=false
  outcome=$((outcome < 2 ? outcome : 2))
  note_parts+=("no language section found")
fi

# Justifications check
if [ "$has_justifications" = true ]; then
  justification_check=true
else
  justification_check=false
  outcome=$((outcome < 3 ? outcome : 3))
  note_parts+=("some entries missing justifications")
fi

# Build note string
note=""
if [ ${#note_parts[@]} -gt 0 ]; then
  note=$(printf '%s; ' "${note_parts[@]}")
  note="${note%; }"  # trim trailing "; "
fi

# --- Output JSON ---

cat << EOF
{"outcome":$outcome,"note":"$note","checks":{"entry_count":$entry_check,"entry_count_value":$entry_count,"pct_sum":$pct_check,"pct_sum_value":$pct_sum,"justifications":$justification_check},"source":"script"}
EOF
