# AI Talking Heads - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

### Syllable Counting Inaccuracy

**Issue:** The bash vowel-group heuristic in `count-syllables.sh` miscounts foreign words, compound words, and unusual English words (e.g., "fire" = 1 or 2 syllables depending on dialect).

**Resolution:**
- Accept +/-5 syllable tolerance per chunk
- User can manually adjust counts if they notice the pacing feels off
- Write numbers as spoken words for accuracy ("twenty" not "20")

---

### Character Consistency Across Clips

**Issue:** AI video generators produce slight variations in face/body between clips, even with the same reference image. Hair position, skin tone, and clothing details may shift.

**Resolution:**
- Always use the same reference frame image for every clip
- Lock key attributes (hair, clothing, background) in every video prompt
- Minor inconsistencies actually match UGC aesthetic -- viewers expect slight shifts in selfie-style content
- For severe inconsistency, regenerate the problem clip

---

### Audio Lip Sync

**Issue:** Generated video lip movements won't perfectly match separately recorded or generated audio. This is inherent to the two-track approach (video + audio generated independently).

**Resolution:**
- Use B-roll, text overlays, or zoom transitions over worst sync points
- Shift audio 100-200ms earlier (AI video has slight motion delay)
- Adobe Podcast Enhance Speech improves clarity, which helps perceived sync
- For perfect sync, consider InfiniteTalk (generates video from audio directly)

---

### Long Scripts (>10 Minutes)

**Issue:** Scripts exceeding ~60 chunks compound character consistency problems. Each regenerated clip risks diverging further from the reference.

**Resolution:**
- Break into episodes of 5-6 minutes (30-36 chunks max)
- Re-anchor character by using a fresh reference image generation per episode
- Use consistent wardrobe/setting descriptions across episodes
- Consider InfiniteTalk for very long continuous segments

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

_None logged yet_

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-01-27 | 1.0.0 | Initial | Skill created with seeded edge cases |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
