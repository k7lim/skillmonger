# Skill Design: ai-talking-heads

> Fill this out before writing SKILL.md. The goal: separate what can be **known deterministically** from what requires **reasoning**.

## Skill Overview

**Name:** ai-talking-heads
**One-liner:** Guide agents through realistic longform AI talking-head/UGC video production

---

## State Detection

What needs to be true before this skill can work?

| Prerequisite | Can script detect it? | How? |
|--------------|----------------------|------|
| Node.js >=14 | ✅ Yes | `command -v node` + version check |
| npm | ✅ Yes | `command -v npm` |
| ffmpeg >=4.1 | ✅ Yes | `command -v ffmpeg` + version check |
| yt-dlp (optional) | ✅ Yes | `command -v yt-dlp` |
| Remotion skill deployed | ✅ Yes | Check sibling skills directory |
| User has script content | ❌ No | Ask in workflow Phase 1 |
| Image gen tool access | ❌ No | Ask in workflow Phase 2 |
| Video gen tool access | ❌ No | Ask in workflow Phase 3 |

**Action:** Detectable items → `scripts/check-prereqs.sh`. Non-detectable → questions in SKILL.md workflow.

---

## Decision Points

| Decision | Data needed | Source |
|----------|-------------|--------|
| Chunk boundaries | Syllable counts per sentence | `count-syllables.sh` |
| Filler sentence needed | Gap below 45 syllables | `count-syllables.sh` status flags |
| Image gen tool | User preference | Ask user |
| Video gen tool (Kling vs Veo) | User preference + access | Ask user |
| Audio cleanup approach | Audio source + quality | User judgment |
| Transition style for jump cuts | Number of clips, tone | Guidance + remotion skill |

---

## Actions

### Deterministic Actions (script candidates)
- [x] Check prerequisites (node, npm, ffmpeg, yt-dlp, remotion)
- [x] Count syllables and chunk script text
- [x] Evaluate skill output quality (post-execution scoring)

### Flexible Actions (prompt guidance)
- [x] Help user write/edit script
- [x] Construct image generation prompts
- [x] Construct video generation prompts with action clusters
- [x] Guide audio cleanup workflow
- [x] Guide post-production assembly (via remotion skill)

---

## Error Scenarios

| Error | Detection | Response |
|-------|-----------|----------|
| Script < 60 syllables | `count-syllables.sh` returns 1 chunk | Single-clip approach, skip multi-chunk workflow |
| Chunk > 65 syllables | `count-syllables.sh` status `over_limit` | Warn: rushed pacing. Suggest splitting the chunk. |
| Chunk < 45 syllables | `count-syllables.sh` status `needs_filler` | Warn: dead air. Suggest filler sentence. |
| Node/npm missing | `check-prereqs.sh` status `missing` | Guide install (needed for Remotion post-production) |
| Remotion skill not deployed | `check-prereqs.sh` context `false` | Provide direct remotion.dev links and manual alternatives |
| No input to count-syllables.sh | Script outputs error JSON | Prompt user for script content |

---

## Feedback Mechanism

**Pattern:** Hybrid — evaluate.sh handles structural checks, but prompt quality and video output are subjective.

**Programmatic checks** (evaluate.sh):
- Chunk structure present (chunks array, syllable counts)
- Syllable ranges within 45-65 tolerance
- Image prompts include realism markers (skin pores, natural lighting, mobile camera specs)
- Video prompts include timestamped action clusters
- Post-production plan references remotion

**Qualitative question** (ask user on 1st run and every 3rd run):
- "Did the generated clips match your character consistently? Would you use these prompts as-is?"

**Language note:** Bash is adequate for grep-based structural checks. `count-syllables.sh` could benefit from Python (syllapy library) for accuracy, but bash is acceptable with the documented +/-5 tolerance.

---

## Status Check Script Design

`scripts/check-prereqs.sh` outputs:

```json
{
  "ready": true,
  "checks": [
    {"name": "node", "status": "ok", "version": "20.11.0", "required": ">=14"},
    {"name": "npm", "status": "ok", "version": "10.2.4"},
    {"name": "ffmpeg", "status": "ok", "version": "6.1", "required": ">=4.1"},
    {"name": "yt-dlp", "status": "missing", "note": "optional, for downloading reference footage"}
  ],
  "context": {
    "remotion_skill_available": true,
    "remotion_path": "/path/to/skills/remotion"
  }
}
```

`ready: true` when node + npm are present. ffmpeg and yt-dlp are soft-fail.

---

## SKILL.md Structure

1. **Prerequisites section** → Run `check-prereqs.sh`, interpretation table
2. **Phase 1: Script Preparation** → count-syllables.sh, chunk review, filler guidance
3. **Phase 2: Image Generation** → Character details, imperfection principle, prompt building
4. **Phase 3: Video Generation** → Tool selection, timestamped action clusters, audio prep
5. **Phase 4: Post-Production** → Remotion assembly or manual fallback
6. **Reference Index** → Links to all 6 reference files
7. **After Execution** → Feedback epilogue

---

## Checklist Before Promoting

- [x] `scripts/check-prereqs.sh` covers all detectable prerequisites
- [x] `scripts/count-syllables.sh` produces valid JSON with chunk boundaries
- [x] `scripts/evaluate.sh` scores output deterministically
- [x] Script outputs valid JSON
- [x] SKILL.md explains how to interpret every status
- [x] Decision points have clear guidance
- [x] Error scenarios are documented
- [x] Reference files cover all workflow phases
- [x] Cross-skill dependency (remotion) is documented in CONFIG.yaml
- [x] Tested in sandbox with edge cases
- [x] Language choice: bash for all scripts; count-syllables.sh could be Python (syllapy) but bash is sufficient with documented +/-5 tolerance
