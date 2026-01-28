#!/bin/bash
# count-syllables.sh - Split script text into chunks by syllable count
# Pure bash, no external deps. Uses vowel-group heuristic.
#
# Input: script text via stdin or file argument
# Output: JSON with chunk boundaries, syllable counts, and status flags
#
# Usage:
#   echo "Your script text here." | scripts/count-syllables.sh
#   scripts/count-syllables.sh script.txt
set -euo pipefail

# --- Configuration ---
TARGET_SYLLABLES=58    # ideal center of range
MIN_SYLLABLES=45       # below this: needs_filler
MAX_SYLLABLES=65       # above this: over_limit
BREAK_THRESHOLD=60     # break chunk when next sentence would exceed this

# --- Read input ---
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

if [ -z "$INPUT" ]; then
  cat << 'EOF'
{"error":"no input provided","total_syllables":0,"total_sentences":0,"chunks":[],"chunk_count":0,"estimated_duration_seconds":0}
EOF
  exit 0
fi

# --- Syllable counting function ---
# Counts syllables in a single word using vowel-group heuristic.
# Not perfect, but reasonable for English text (+/- 5% accuracy).
count_word_syllables() {
  local word="$1"
  # Lowercase and strip non-alpha
  word=$(echo "$word" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z]//g')

  if [ -z "$word" ]; then
    echo 0
    return
  fi

  # Count vowel groups (consecutive vowels = 1 syllable)
  local count
  count=$(echo "$word" | grep -oE '[aeiouy]+' | wc -l | tr -d ' ')

  # Adjust for silent-e at end (if word > 2 chars and ends in 'e' preceded by consonant)
  local len=${#word}
  if [ "$len" -gt 2 ]; then
    local last_char="${word: -1}"
    local second_last="${word: -2:1}"
    if [ "$last_char" = "e" ] && ! echo "$second_last" | grep -qE '[aeiouy]'; then
      # Silent e: subtract 1 (but never below 1)
      if [ "$count" -gt 1 ]; then
        count=$((count - 1))
      fi
    fi
  fi

  # Adjust for -le ending (e.g., "table", "simple") -- add back 1
  if [ "$len" -gt 2 ]; then
    local last_two="${word: -2}"
    local third_last="${word: -3:1}"
    if [ "$last_two" = "le" ] && ! echo "$third_last" | grep -qE '[aeiouy]'; then
      count=$((count + 1))
    fi
  fi

  # Minimum 1 syllable per word
  if [ "$count" -lt 1 ]; then
    count=1
  fi

  echo "$count"
}

# --- Count syllables in a sentence ---
count_sentence_syllables() {
  local sentence="$1"
  local total=0
  for word in $sentence; do
    local w_count
    w_count=$(count_word_syllables "$word")
    total=$((total + w_count))
  done
  echo "$total"
}

# --- Split text into sentences ---
# Split on sentence-ending punctuation followed by whitespace or end-of-text.
# Store sentences in an array.
sentences=()
# Replace newlines with spaces, normalize whitespace
normalized=$(echo "$INPUT" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')

# Split on .!? followed by a space using newline as delimiter
# Replace ". " / "! " / "? " with ".\n" etc., then read lines
delimited=$(echo "$normalized" | sed 's/\([.!?]\) /\1\
/g')

while IFS= read -r sentence; do
  # Trim whitespace
  sentence=$(echo "$sentence" | sed 's/^ *//; s/ *$//')
  if [ -n "$sentence" ]; then
    sentences+=("$sentence")
  fi
done <<< "$delimited"

# --- Build chunks ---
total_syllables=0
total_sentences=${#sentences[@]}

# Arrays for chunk building
chunk_sentences=()
chunk_syllable_count=0
chunk_index=1

# JSON output accumulator
chunks_json=""

emit_chunk() {
  local status="ok"
  if [ "$chunk_syllable_count" -lt "$MIN_SYLLABLES" ]; then
    status="needs_filler"
  elif [ "$chunk_syllable_count" -gt "$MAX_SYLLABLES" ]; then
    status="over_limit"
  fi

  # Build sentences JSON array
  local sentences_json="["
  local first=true
  for s in "${chunk_sentences[@]}"; do
    # Escape quotes and backslashes for JSON
    local escaped
    escaped=$(echo "$s" | sed 's/\\/\\\\/g; s/"/\\"/g')
    if [ "$first" = true ]; then
      sentences_json="$sentences_json\"$escaped\""
      first=false
    else
      sentences_json="$sentences_json,\"$escaped\""
    fi
  done
  sentences_json="$sentences_json]"

  local note_field=""
  if [ "$status" = "needs_filler" ]; then
    local gap=$((MIN_SYLLABLES - chunk_syllable_count))
    note_field=",\"note\":\"Consider adding ~${gap} syllables\""
  elif [ "$status" = "over_limit" ]; then
    local excess=$((chunk_syllable_count - MAX_SYLLABLES))
    note_field=",\"note\":\"Exceeds limit by ${excess} syllables. Consider splitting.\""
  fi

  local chunk_json="{\"index\":$chunk_index,\"sentences\":$sentences_json,\"syllable_count\":$chunk_syllable_count,\"status\":\"$status\"$note_field}"

  if [ -n "$chunks_json" ]; then
    chunks_json="$chunks_json,$chunk_json"
  else
    chunks_json="$chunk_json"
  fi

  chunk_index=$((chunk_index + 1))
}

for i in "${!sentences[@]}"; do
  sentence="${sentences[$i]}"
  s_count=$(count_sentence_syllables "$sentence")
  total_syllables=$((total_syllables + s_count))

  # Would adding this sentence exceed the break threshold?
  if [ ${#chunk_sentences[@]} -gt 0 ] && [ $((chunk_syllable_count + s_count)) -gt "$BREAK_THRESHOLD" ]; then
    # Emit current chunk
    emit_chunk
    # Start new chunk with this sentence
    chunk_sentences=("$sentence")
    chunk_syllable_count=$s_count
  else
    chunk_sentences+=("$sentence")
    chunk_syllable_count=$((chunk_syllable_count + s_count))
  fi
done

# Emit final chunk if non-empty
if [ ${#chunk_sentences[@]} -gt 0 ]; then
  emit_chunk
fi

chunk_count=$((chunk_index - 1))

# Estimate duration: ~6 syllables/second is natural speech pace
if [ "$total_syllables" -gt 0 ]; then
  estimated_duration=$(( (total_syllables * 10 + 5) / 6 / 10 ))
else
  estimated_duration=0
fi

# --- Output JSON ---
cat << EOF
{
  "total_syllables": $total_syllables,
  "total_sentences": $total_sentences,
  "chunks": [$chunks_json],
  "chunk_count": $chunk_count,
  "estimated_duration_seconds": $estimated_duration
}
EOF
