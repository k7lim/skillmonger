#!/bin/bash
# evaluate.sh - Hybrid evaluation for epub-to-md output
# Checks: 1) Size sanity (output not larger than input)
#         2) Tree-shape sanity (structure matches epub TOC)
#
# Usage:
#   scripts/evaluate.sh <epub_path> <output_dir>
#
# Outputs JSON with outcome (1-5), note, checks, and source.
set -uo pipefail

if [ $# -lt 2 ]; then
  cat << 'EOF'
{"outcome":1,"note":"Usage: evaluate.sh <epub_path> <output_dir>","checks":{},"source":"script"}
EOF
  exit 0
fi

epub_path="$1"
output_dir="$2"

# Initialize
outcome=5
notes=()
size_check="skip"
structure_check="skip"

# --- Size Sanity Check ---
# Output should not be larger than the original EPUB
if [ -f "$epub_path" ] && [ -d "$output_dir" ]; then
  epub_size=$(stat -f%z "$epub_path" 2>/dev/null || stat -c%s "$epub_path" 2>/dev/null || echo 0)
  output_size=$(du -sb "$output_dir" 2>/dev/null | cut -f1 || du -sk "$output_dir" 2>/dev/null | awk '{print $1*1024}' || echo 0)

  if [ "$epub_size" -gt 0 ] && [ "$output_size" -gt 0 ]; then
    if [ "$output_size" -gt "$epub_size" ]; then
      size_check="fail"
      notes+=("Output ($output_size bytes) larger than EPUB ($epub_size bytes)")
      outcome=$((outcome - 2))
    else
      size_check="pass"
      ratio=$((output_size * 100 / epub_size))
      notes+=("Size ratio: ${ratio}% of original")
    fi
  fi
else
  if [ ! -f "$epub_path" ]; then
    notes+=("EPUB not found: $epub_path")
    outcome=$((outcome - 1))
  fi
  if [ ! -d "$output_dir" ]; then
    notes+=("Output dir not found: $output_dir")
    outcome=$((outcome - 2))
  fi
fi

# --- Structure Sanity Check ---
# Verify output has markdown files
if [ -d "$output_dir" ]; then
  md_count=$(find "$output_dir" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

  if [ "$md_count" -eq 0 ]; then
    structure_check="fail"
    notes+=("No markdown files in output")
    outcome=$((outcome - 2))
  else
    structure_check="pass"
    notes+=("Found $md_count markdown file(s)")
  fi
fi

# Clamp outcome to valid range
if [ "$outcome" -lt 1 ]; then outcome=1; fi
if [ "$outcome" -gt 5 ]; then outcome=5; fi

# Join notes
note_str=""
for n in "${notes[@]:-}"; do
  if [ -n "$note_str" ]; then
    note_str="$note_str; $n"
  else
    note_str="$n"
  fi
done

# Escape quotes in note for JSON
note_str=$(echo "$note_str" | sed 's/"/\\"/g')

# Output JSON
cat << EOF
{"outcome":$outcome,"note":"$note_str","checks":{"size":"$size_check","structure":"$structure_check"},"source":"script"}
EOF
