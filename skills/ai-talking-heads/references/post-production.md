---
name: post-production
description: Bridge to remotion skill for video assembly, transitions, and captions
tags: post-production, remotion, assembly, transitions, captions
---

# Post-Production: Bridge to Remotion

This phase uses the **remotion skill** for final video assembly. This reference maps talking-head tasks to specific remotion references.

## Task → Remotion Reference Map

| Task | Remotion Reference | Notes |
|------|-------------------|-------|
| Sequencing clips in order | `references/sequencing.md` | Use `<Series>` for sequential playback |
| Transitions between clips | `references/transitions.md` | `TransitionSeries` with wipe/fade effects |
| Adding captions | `references/display-captions.md` | TikTok-style word highlighting |
| Generating captions from audio | `references/transcribe-captions.md` | Whisper-based transcription |
| Audio layering and mixing | `references/audio.md` | Background music, volume ducking |
| Trimming clip start/end | `references/trimming.md` | Remove AI generation artifacts |
| Importing video clips | `references/videos.md` | `<Video>` component with src |

## Composition Setup (9:16 Vertical)

Talking-head videos are vertical format. Remotion composition config:

```tsx
<Composition
  id="TalkingHead"
  component={TalkingHeadVideo}
  durationInFrames={totalFrames}  // sum of all clip durations
  fps={30}
  width={1080}
  height={1920}
/>
```

## Assembly Workflow

1. **Import all clips** into a Remotion project as video assets
2. **Create a `<TransitionSeries>`** to sequence clips with transitions
3. **Add captions** using `@remotion/captions` (generate from audio or import SRT)
4. **Layer background music** at low volume under speech
5. **Render** to MP4 with `npx remotion render`

## Transition Recommendations for Jump Cuts

Between talking-head clips, prefer subtle transitions:

- **Cross-fade (0.5s)** -- smoothest, works for most cuts
- **Slide** -- good for topic changes within the same speaker
- **None (hard cut)** -- acceptable for UGC style, feels authentic

Avoid flashy transitions (wipes, zooms) for talking heads -- they break the personal/direct feel.

## When Remotion Is Not Available

If the remotion skill is not deployed or the user prefers manual editing:

1. **Remotion docs:** https://remotion.dev/docs
2. **Manual alternative:** Import clips into any NLE (DaVinci Resolve, CapCut, Premiere)
3. **CapCut (free):** Good for quick assembly with auto-captions -- https://www.capcut.com
4. **ffmpeg concat** (no transitions):
   ```bash
   # Simple concatenation
   printf "file '%s'\n" clip_*.mp4 > filelist.txt
   ffmpeg -f concat -safe 0 -i filelist.txt -c copy output.mp4
   ```

## Check-Prereqs Context

`scripts/check-prereqs.sh` outputs `context.remotion_skill_available` (true/false). Use this to decide:

- **true:** Reference remotion skill directly, use its workflow
- **false:** Provide the fallback links above and manual workflow guidance
