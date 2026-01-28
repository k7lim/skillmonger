#!/bin/bash
# evaluate.sh - Deterministic scoring for ai-talking-heads skill output
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

has_chunks=false
syllable_range_ok=false
has_image_prompt=false
has_video_prompts=false
has_post_production=false

# 1. Chunk count: Are chunks/numbered sections present?
chunk_count=$(echo "$INPUT" | grep -ciE '(chunk|segment|part|clip)\s*[0-9]|##\s*(chunk|segment|clip)\s*[0-9]' || true)
if [ "$chunk_count" -ge 2 ]; then
  has_chunks=true
fi

# 2. Syllable range: Are syllable numbers referenced in the 45-65 range?
syllable_mentions=$(echo "$INPUT" | grep -oE '[0-9]+ syllable' | grep -oE '[0-9]+' || true)
if [ -n "$syllable_mentions" ]; then
  in_range=0
  total_mentions=0
  while IFS= read -r num; do
    total_mentions=$((total_mentions + 1))
    if [ "$num" -ge 45 ] && [ "$num" -le 65 ]; then
      in_range=$((in_range + 1))
    fi
  done <<< "$syllable_mentions"
  if [ "$total_mentions" -gt 0 ] && [ "$in_range" -gt 0 ]; then
    syllable_range_ok=true
  fi
fi

# 3. Image prompt: realism markers present?
image_markers=$(echo "$INPUT" | grep -ciE 'iphone|pores|iso [0-9]|natural light|skin texture|imperfection|ugc|selfie.style|no studio|nano banana|enhancor' || true)
if [ "$image_markers" -ge 2 ]; then
  has_image_prompt=true
fi

# 4. Video prompts: timestamped actions or gen tool references?
video_markers=$(echo "$INPUT" | grep -ciE 'kling|veo|timestamp|action cluster|reference frame|10.?s(econd)?|body language|lip.?sync|talking.head' || true)
if [ "$video_markers" -ge 2 ]; then
  has_video_prompts=true
fi

# 5. Post-production: remotion or assembly references?
postprod_markers=$(echo "$INPUT" | grep -ciE 'remotion|transition|assembly|caption|sequenc|composit|post.?prod' || true)
if [ "$postprod_markers" -ge 2 ]; then
  has_post_production=true
fi

# --- Score ---

outcome=5
note_parts=()

if [ "$has_chunks" = false ]; then
  outcome=$((outcome < 2 ? outcome : 2))
  note_parts+=("no chunk structure found")
fi

if [ "$syllable_range_ok" = false ]; then
  outcome=$((outcome < 3 ? outcome : 3))
  note_parts+=("no syllable counts in 45-65 range")
fi

if [ "$has_image_prompt" = false ]; then
  if [ "$outcome" -gt 3 ]; then
    outcome=3
  fi
  note_parts+=("missing image generation prompt with realism markers")
fi

if [ "$has_video_prompts" = false ]; then
  if [ "$outcome" -gt 3 ]; then
    outcome=3
  fi
  note_parts+=("missing video generation prompts")
fi

if [ "$has_post_production" = false ]; then
  if [ "$outcome" -gt 4 ]; then
    outcome=4
  fi
  note_parts+=("missing post-production references")
fi

# Build note string
note=""
if [ ${#note_parts[@]} -gt 0 ]; then
  note=$(printf '%s; ' "${note_parts[@]}")
  note="${note%; }"
fi

# --- Output JSON ---

cat << EOF
{"outcome":$outcome,"note":"$note","checks":{"chunks":$has_chunks,"chunk_count_value":$chunk_count,"syllable_range":$syllable_range_ok,"image_prompt":$has_image_prompt,"video_prompts":$has_video_prompts,"post_production":$has_post_production},"source":"script"}
EOF
