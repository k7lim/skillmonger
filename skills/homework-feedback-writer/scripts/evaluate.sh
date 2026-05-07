#!/bin/bash
# evaluate.sh - Check feedback quality for homework-feedback-writer
# Detects slop words, hedging, passive voice, and verbosity
set -uo pipefail

# Read input from file arg or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

# Initialize
outcome=5
note=""
declare -A checks

# Helper: count matches (handles grep exit code 1 when no match)
count_matches() {
  local pattern="$1"
  local count
  count=$(echo "$INPUT" | grep -ioE "$pattern" 2>/dev/null | wc -l | tr -d ' ') || true
  echo "${count:-0}"
}

# Helper: get unique matches
get_matches() {
  local pattern="$1"
  echo "$INPUT" | grep -ioE "$pattern" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true
}

# --- Slop words check ---
SLOP_WORDS="delve|crucial|pivotal|showcase|foster|landscape|tapestry|groundbreaking|utilize|facilitate|leverage|underscore"
slop_count=$(count_matches "$SLOP_WORDS")
checks["slop_words"]=$slop_count

if [ "$slop_count" -gt 0 ]; then
  slop_found=$(get_matches "$SLOP_WORDS")
  note="slop words: $slop_found"
  if [ "$slop_count" -ge 3 ]; then
    outcome=2
  else
    outcome=$((outcome - slop_count))
  fi
fi

# --- Hedge words check ---
HEDGE_WORDS="somewhat|arguably|perhaps|a bit|tends to|might be|could potentially|may potentially"
hedge_count=$(count_matches "$HEDGE_WORDS")
checks["hedge_words"]=$hedge_count

if [ "$hedge_count" -gt 0 ]; then
  hedge_found=$(get_matches "$HEDGE_WORDS")
  if [ -n "$note" ]; then
    note="$note; hedges: $hedge_found"
  else
    note="hedges: $hedge_found"
  fi
  outcome=$((outcome - hedge_count))
fi

# --- Passive voice check (common patterns) ---
PASSIVE_PATTERNS="could be|should be|would be|can be|is being|was being|has been|have been|had been|will be"
passive_count=$(count_matches "$PASSIVE_PATTERNS")
checks["passive_voice"]=$passive_count

if [ "$passive_count" -gt 2 ]; then
  if [ -n "$note" ]; then
    note="$note; passive voice: $passive_count instances"
  else
    note="passive voice: $passive_count instances"
  fi
  outcome=$((outcome - 1))
fi

# --- Verbosity check (wordy phrases) ---
WORDY_PHRASES="serves as|in order to|a wide variety of|due to the fact|at this point in time|for the purpose of"
wordy_count=$(count_matches "$WORDY_PHRASES")
checks["wordy_phrases"]=$wordy_count

if [ "$wordy_count" -gt 0 ]; then
  wordy_found=$(get_matches "$WORDY_PHRASES")
  if [ -n "$note" ]; then
    note="$note; wordy: $wordy_found"
  else
    note="wordy: $wordy_found"
  fi
  outcome=$((outcome - wordy_count))
fi

# Clamp outcome to 1-5
if [ "$outcome" -lt 1 ]; then
  outcome=1
elif [ "$outcome" -gt 5 ]; then
  outcome=5
fi

# If no issues, clear note
if [ "$outcome" -eq 5 ]; then
  note="clean"
fi

# --- Output JSON ---
cat << EOF
{"outcome":$outcome,"note":"$note","checks":{"slop_words":${checks[slop_words]},"hedge_words":${checks[hedge_words]},"passive_voice":${checks[passive_voice]},"wordy_phrases":${checks[wordy_phrases]}},"source":"script"}
EOF
