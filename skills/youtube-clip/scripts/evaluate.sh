#!/bin/bash
# evaluate.sh - Score youtube-clip output (1-5)
# Reads clip search results or explore output from stdin or file arg.
#
# Usage:
#   echo "$OUTPUT" | scripts/evaluate.sh
#   scripts/evaluate.sh output.json
#
# Scoring:
#   5: Precise, relevant segments with clear boundaries and valid URLs
#   4: Relevant segments, reasonable boundaries
#   3: Matches found but noisy context or imprecise boundaries
#   2: Few/poor matches
#   1: No matches or transcript unavailable
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
evaluate.sh - Score youtube-clip output quality (1-5)

Usage:
  echo "$OUTPUT" | scripts/evaluate.sh
  scripts/evaluate.sh output.json

Reads clip search results or explore output (JSON envelope) from stdin or file.

Scoring:
  5: Precise, relevant segments with clear boundaries and valid URLs
  4: Relevant segments, reasonable boundaries
  3: Matches found but noisy context or imprecise boundaries
  2: Few/poor matches
  1: No matches or transcript unavailable

Output: JSON to stdout: {"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}
Exit:   Always 0.

Examples:
  scripts/get-transcript "VIDEO_ID" | scripts/search-transcript "query" | scripts/evaluate.sh
  scripts/evaluate.sh explore-output.json
USAGE
  exit 0
fi

# Read input from file arg or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

outcome=1
note=""
has_success="false"
has_data="false"
match_count=0
has_urls="false"
has_sections="false"
has_output_path="false"
is_explore="false"

# Check if valid JSON
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  outcome=1
  note="Input is not valid JSON"
  printf '{"outcome":%d,"note":"%s","checks":{"valid_json":false},"source":"script"}\n' "$outcome" "$note"
  exit 0
fi

# Check success field
has_success=$(echo "$INPUT" | jq -r '.success // false')

# Detect if this is explore output or search output
is_explore=$(echo "$INPUT" | jq -r 'if .data.output_path then "true" else "false" end' 2>/dev/null || echo "false")

if [ "$is_explore" = "true" ]; then
  # Evaluate explore output
  output_path=$(echo "$INPUT" | jq -r '.data.output_path // ""')
  chapter_count=$(echo "$INPUT" | jq -r '.data.chapter_count // 0')
  heatmap_points=$(echo "$INPUT" | jq -r '.data.heatmap_points // 0')
  transcript_segments=$(echo "$INPUT" | jq -r '.data.transcript_segments // 0')

  if [ "$has_success" = "true" ]; then
    if [ -f "$output_path" ]; then
      has_output_path="true"
      # Check HTML content
      has_html_links="false"
      if grep -q "youtube.com/watch" "$output_path" 2>/dev/null; then
        has_html_links="true"
      fi

      if [ "$has_html_links" = "true" ] && [ "$transcript_segments" -gt 0 ]; then
        if [ "$chapter_count" -gt 0 ] && [ "$heatmap_points" -gt 0 ]; then
          outcome=5
          note="Complete explorer with chapters, heatmap, and transcript"
        elif [ "$chapter_count" -gt 0 ] || [ "$heatmap_points" -gt 0 ]; then
          outcome=4
          note="Explorer with transcript and partial metadata"
        else
          outcome=3
          note="Explorer with transcript only, no chapters or heatmap"
        fi
      elif [ "$transcript_segments" -gt 0 ]; then
        outcome=3
        note="HTML generated but missing youtube links"
      else
        outcome=2
        note="HTML generated but no transcript segments"
      fi
    else
      outcome=2
      note="Output path reported but file not found: $output_path"
    fi
  else
    outcome=1
    note="Explore reported failure"
  fi
else
  # Evaluate search/transcript output
  has_data=$(echo "$INPUT" | jq -r 'if (.data | type) == "array" then "true" else "false" end' 2>/dev/null || echo "false")
  match_count=$(echo "$INPUT" | jq -r 'if (.data | type) == "array" then (.data | length) else 0 end' 2>/dev/null || echo "0")
  has_urls=$(echo "$INPUT" | jq -r 'if (.data | type) == "array" and (.data | length) > 0 then (if .data[0].watch_url then "true" else "false" end) else "false" end' 2>/dev/null || echo "false")
  has_sections=$(echo "$INPUT" | jq -r 'if (.data | type) == "array" and (.data | length) > 0 then (if .data[0].download_section then "true" else "false" end) else "false" end' 2>/dev/null || echo "false")

  if [ "$has_success" = "true" ] && [ "$match_count" -gt 0 ]; then
    if [ "$has_urls" = "true" ] && [ "$has_sections" = "true" ]; then
      if [ "$match_count" -ge 3 ]; then
        outcome=5
        note="$match_count precise matches with URLs and download sections"
      else
        outcome=4
        note="$match_count match(es) with valid URLs and sections"
      fi
    elif [ "$has_urls" = "true" ]; then
      outcome=3
      note="$match_count match(es) with URLs but missing download sections"
    else
      outcome=2
      note="$match_count match(es) but missing structured fields"
    fi
  elif [ "$has_success" = "true" ] && [ "$match_count" -eq 0 ]; then
    outcome=2
    note="Search succeeded but returned no matches"
  else
    outcome=1
    note="Search failed or returned no data"
  fi
fi

printf '{"outcome":%d,"note":"%s","checks":{"success":%s,"is_explore":%s,"match_count":%d,"has_urls":%s,"has_sections":%s},"source":"script"}\n' \
  "$outcome" "$note" "$has_success" "$is_explore" "$match_count" "$has_urls" "$has_sections"
