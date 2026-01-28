---
name: ai-talking-heads
description: Guide agents through producing realistic longform AI talking-head/UGC videos using syllable-counted script chunking, image/video generation prompts, and Remotion for post-production assembly.
---

# AI Talking Heads

Guide the user through producing realistic longform AI talking-head and UGC-style videos. The workflow covers four phases: script preparation (syllable-counted chunking), image generation (photorealistic character), video generation (per-chunk clips), and post-production (assembly via remotion skill).

## When to Use

Use this skill when the user wants to:

- Create an AI talking-head video (a person speaking to camera)
- Produce UGC-style (user-generated content) video with an AI character
- Make a longform AI video (>30 seconds) with consistent character
- Generate video prompts for Kling, Veo, or similar tools
- Understand the full pipeline from script to finished video

## Prerequisites

Before starting, run `scripts/check-prereqs.sh` (in this skill directory) using Bash.

**Interpreting results:**

| Check | If `ok` | If `missing` / `outdated` |
|-------|---------|--------------------------|
| node | Proceed | Install: `nvm install 20` or https://nodejs.org/ (needed for Remotion post-production) |
| npm | Proceed | Comes with Node; if missing, reinstall Node |
| ffmpeg | Proceed | macOS: `brew install ffmpeg`. Linux: `apt install ffmpeg`. Soft-fail: can continue without it, but audio processing and Remotion rendering need it |
| yt-dlp | Proceed | Optional. Only needed if downloading reference footage. Install: `pip install yt-dlp` |

**Remotion skill availability** is reported in `context.remotion_skill_available`:
- `true` → Phase 4 can use the remotion skill directly
- `false` → Phase 4 will provide manual assembly guidance and direct links to remotion.dev

**When to skip checks:**
- User explicitly says they have the tools
- User only needs help with script chunking (Phases 1-3 need no prerequisites)

## Workflow Phase 1: Script Preparation

**Goal:** Split the user's script into chunks of 55-60 syllables each, where each chunk becomes one 10-second video clip.

### Step 1: Get the Script

Ask the user for their full script text. It should be:
- Written out in full sentences (not bullet points)
- In the voice/tone they want for the final video
- Numbers written as spoken words ("twenty twenty-four" not "2024")

If the user doesn't have a script yet, help them write one. Ask about: topic, target audience, key points, desired tone, and target duration.

### Step 2: Run Syllable Counting

Pipe the script to `scripts/count-syllables.sh`:

```bash
echo "SCRIPT_TEXT_HERE" | scripts/count-syllables.sh
```

Or save to a file and pass as argument:

```bash
scripts/count-syllables.sh script.txt
```

### Step 3: Interpret the Output

The script outputs JSON with chunks, syllable counts, and status flags.

**Show the user:**
1. Number of chunks (= number of video clips needed)
2. Estimated duration in seconds
3. Any chunks with status issues

**Handle status flags:**

| Status | Meaning | Action |
|--------|---------|--------|
| `ok` | 45-65 syllables | No changes needed |
| `needs_filler` | < 45 syllables | Suggest a bridge sentence. See `references/script-chunking.md` for filler guidance |
| `over_limit` | > 65 syllables | Suggest splitting or trimming. Rushed pacing will result otherwise |

### Step 4: Iterate

If any chunks need adjustment:
1. Propose specific filler sentences or cuts
2. Get user approval on changes
3. Re-run `count-syllables.sh` on the updated script
4. Repeat until all chunks are `ok`

**Reference:** [references/script-chunking.md](references/script-chunking.md) for the full method, worked examples, and edge cases.

## Workflow Phase 2: Image Generation

**Goal:** Generate a photorealistic base character image that will be used as the reference frame for all video clips.

### Step 1: Gather Character Details

Ask the user about their character:
- **Appearance:** Age, ethnicity, gender, hair style/color
- **Clothing:** Casual/professional, specific items
- **Setting:** Where are they? Home office, kitchen, outdoors?
- **Mood/tone:** Matches the script -- confident, friendly, authoritative?

### Step 2: Build the Image Prompt

Construct a prompt using the template in `references/prompt-templates.md`. Key principles:

**The Imperfection Principle:** Real UGC footage has visible skin pores, natural oils, imperfect lighting, and casual framing. Your prompt must explicitly request these.

Essential prompt elements:
- iPhone/mobile camera specs (ISO, aperture)
- "Visible skin pores, natural skin oils"
- "No airbrushing, no studio lighting"
- Specific environment (not generic blur)
- Chest-up or waist-up framing (not tight headshot)

### Step 3: Generate and Review

Present the prompt to the user. They will generate the image using their preferred tool.

**Recommended tool:** Nano Banana Pro (via fal.ai). Alternatives: Flux, DALL-E 3, Midjourney v6.

### Step 4: Upscale

If the generated image is below 1080x1920 resolution:
- **Recommended:** Enhancor AI (preserves skin texture)
- **Alternative:** Real-ESRGAN with `realesrgan-x4plus` model

The upscaled image becomes the **reference frame** for all video generation.

**Reference:** [references/image-generation.md](references/image-generation.md) for the imperfection principle, tool details, and character consistency guidance.

## Workflow Phase 3: Video Generation

**Goal:** Generate one 10-second video clip per script chunk, using the base image as reference frame.

### Step 1: Choose Video Generation Tool

Ask the user which tool they have access to:

| Tool | Clip Length | Best For |
|------|------------|----------|
| **Kling 2.6** (recommended) | 10s | Consistent character, standard talking heads |
| **Veo 3.1** | 8s | Superior body language, natural motion |
| **InfiniteTalk** | Continuous | Pre-recorded audio, no clip assembly needed |

### Step 2: Build Video Prompts

For each chunk, construct a video prompt using `references/prompt-templates.md`. Each prompt must include:

1. **Reference image** attachment (the base character from Phase 2)
2. **Subject description** matching the base image
3. **Script text** for that chunk
4. **Tone** matching the script
5. **Timestamped action clusters** -- 3 time blocks describing body language:
   - `[0-3s]` Opening pose and initial gesture
   - `[3-6s]` Emphasis gesture at the key point
   - `[6-10s]` Settling gesture, transition-ready pose

**Clip boundary continuity:** End each clip with a neutral/settled pose that the next clip can start from. See `references/video-generation.md` for continuity techniques.

### Step 3: Generate Clips

Present all video prompts to the user (one per chunk). They generate clips in order. After generation:

- **Check each clip** for acceptable lip movement and body language
- **Regenerate** any clips where the character looks significantly different
- **Note problem clips** for transition coverage in post-production

### Step 4: Audio Preparation

The video clips have no usable audio. The user needs voice audio:

1. **Record their own voice** reading each chunk, or
2. **Generate AI voice** using ElevenLabs, Resemble AI, or similar, or
3. **Use text-to-speech** as a quick option

**Minimum audio cleanup:** Run through Adobe Podcast Enhance Speech (free tier). Then normalize with ffmpeg:

```bash
ffmpeg -i voice.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 voice_normalized.wav
```

**Reference:** [references/video-generation.md](references/video-generation.md) for tool comparison, action clusters, and the InfiniteTalk alternative. [references/audio-cleanup.md](references/audio-cleanup.md) for audio processing.

## Workflow Phase 4: Post-Production

**Goal:** Assemble all clips into a final video with transitions, captions, and audio.

### If Remotion Skill Is Available

Reference the **remotion skill** for assembly. The key remotion references for this workflow:

| Task | Remotion Reference |
|------|-------------------|
| Clip sequencing | `references/sequencing.md` — Use `<Series>` or `<TransitionSeries>` |
| Transitions | `references/transitions.md` — Cross-fade (0.5s) recommended for talking heads |
| Captions | `references/display-captions.md` — TikTok-style word highlighting |
| Caption generation | `references/transcribe-captions.md` — Whisper transcription from audio |
| Audio mixing | `references/audio.md` — Voice + background music layering |
| Clip trimming | `references/trimming.md` — Remove generation artifacts at clip edges |

**Composition setup** for talking-head vertical video:
- Width: 1080, Height: 1920 (9:16)
- FPS: 30
- Duration: sum of all clip durations

**Jump cut coverage:** Where clips transition poorly, use:
- Cross-fade transitions (0.5s)
- Brief text overlay or zoom effect
- B-roll footage if available

### If Remotion Skill Is Not Available

Guide the user to assemble manually:

1. **Remotion directly:** https://remotion.dev/docs — set up a project with `npx create-video@latest`
2. **CapCut (free):** https://www.capcut.com — drag-and-drop assembly with auto-captions
3. **DaVinci Resolve (free):** Professional NLE for manual editing
4. **ffmpeg concat** (no transitions):
   ```bash
   printf "file '%s'\n" clip_*.mp4 > filelist.txt
   ffmpeg -f concat -safe 0 -i filelist.txt -c copy output.mp4
   ```

**Reference:** [references/post-production.md](references/post-production.md) for the full remotion task map and fallback options.

## Reference Index

| Reference | Content |
|-----------|---------|
| [references/script-chunking.md](references/script-chunking.md) | 55-60 syllable method, worked example, filler guidance |
| [references/image-generation.md](references/image-generation.md) | Nano Banana Pro, imperfection principle, character consistency |
| [references/video-generation.md](references/video-generation.md) | Kling/Veo comparison, timestamped action clusters, reference frames |
| [references/audio-cleanup.md](references/audio-cleanup.md) | Adobe Podcast vs Resemble AI, ffmpeg normalization |
| [references/post-production.md](references/post-production.md) | Bridge to remotion skill, fallback assembly options |
| [references/prompt-templates.md](references/prompt-templates.md) | Full copy-pasteable image and video prompt templates |

---

## After Execution

After completing the skill output, log feedback to track quality over time.

**Priority cascade:**
1. If `scripts/evaluate.sh` exists in this skill directory, run it and use the JSON result
2. Otherwise, self-assess using the scale below

**Self-assessment scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

**To log feedback**, append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"ai-talking-heads","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
