---
name: script-chunking
description: The 55-60 syllable method for splitting scripts into video-length chunks
tags: syllables, chunking, pacing, script
---

# Script Chunking: The 55-60 Syllable Method

## Why Syllables, Not Words

Word count is unreliable for video pacing. "Cat" and "beautiful" are both one word but take different time to speak. Syllables correlate directly with spoken duration: natural English speech averages ~6 syllables/second, making a 55-60 syllable chunk approximately 10 seconds of speech -- the ideal clip length for AI video generators.

## The Method

1. **Get the full script** from the user (written out, not bullet points)
2. **Run `scripts/count-syllables.sh`** to split automatically
3. **Review the JSON output** for status flags
4. **Adjust** any chunks flagged `needs_filler` or `over_limit`

## Interpreting Output

| Status | Syllable Range | Action |
|--------|---------------|--------|
| `ok` | 45-65 | No changes needed |
| `needs_filler` | < 45 | Add a transitional sentence. See Filler Guidance below. |
| `over_limit` | > 65 | Split into two chunks or trim a sentence |

## Filler Guidance

When a chunk is under 45 syllables, the video clip will feel rushed or leave dead air. Add a **bridge sentence** that:

- Restates the previous idea in different words ("In other words...")
- Adds a brief example ("For instance...")
- Creates a beat before the next point ("And here's why that matters.")

Filler should feel natural, not padded. Avoid pure throat-clearing ("So, moving on...").

## Edge Cases

**Very short scripts (< 60 syllables total):** Skip chunking entirely. Treat as a single clip. The `count-syllables.sh` script handles this -- you'll get 1 chunk.

**Very long scripts (> 600 syllables / ~10 chunks):** Consider splitting into episodes. Character consistency degrades across many clips. See MEMO.md for the long-script pattern.

**Non-English scripts:** The vowel-group heuristic is tuned for English. For other languages, tell the user to manually verify counts. The script will still split on sentence boundaries.

**Numbers and abbreviations:** "2024" = "twenty twenty-four" (5 syllables spoken). "CEO" = 3 syllables. The heuristic counts written form; coach the user to write numbers as spoken words for accuracy.

## Worked Example

**Input script:**
> Artificial intelligence is changing how we create video content. What used to take a full production crew can now be done with just a laptop. The key is understanding the tools and using them in the right order. Let me walk you through the exact process I use.

**count-syllables.sh output (simplified):**

- Chunk 1: "Artificial intelligence is changing how we create video content. What used to take a full production crew can now be done with just a laptop." → 44 syllables → `needs_filler`
- Chunk 2: "The key is understanding the tools and using them in the right order. Let me walk you through the exact process I use." → 34 syllables → `needs_filler`

**After adding fillers:**

- Chunk 1: "Artificial intelligence is changing how we create video content. What used to take a full production crew with cameras, lights, and editors can now be done with just a laptop and the right AI tools." → 56 syllables → `ok`
- Chunk 2: "The key is understanding these tools and using them in the right order. That's exactly what separates amateur results from professional-looking content. Let me walk you through the exact process I use." → 55 syllables → `ok`
