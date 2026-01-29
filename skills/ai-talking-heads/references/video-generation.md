---
name: video-generation
description: Kling 2.6 vs Veo 3.1, timestamped action clusters, and natural motion prompting
tags: video-gen, kling, veo, motion, clips, talking-head
---

# Video Generation for Talking Heads

## Tool Comparison

| Feature | Kling 2.6 | Veo 3.1 |
|---------|-----------|---------|
| Max clip length | 10s | 8s |
| Reference frame support | Yes (image-to-video) | Yes |
| Lip movement | Generic mouth motion (not synced to audio) | Generic mouth motion (not synced to audio) |
| Availability | klingai.com / API | Google DeepMind / API |
| Cost | Mid-range | Higher |
| Best for | Consistent character, longer clips | Natural body language |

**Important:** Neither tool syncs lip movement to external audio. See "Lip Sync Post-Processing" below.

**Default recommendation:** Kling 2.6 for most talking-head projects (10s clips align with syllable chunks). Switch to Veo if the user needs superior body language or has access.

## The Pacing Fix: Syllables → 10-Second Clips

Each chunk from `count-syllables.sh` targets 55-60 syllables ≈ 10 seconds of speech. This maps directly to one video generation prompt per chunk. The workflow:

1. Chunk script → 55-60 syllable segments
2. Generate video prompt per chunk → 10s clip each
3. Assemble clips in Remotion → seamless long-form video

This eliminates the #1 problem with AI talking-head videos: pacing drift.

## Prompt Structure: Timestamped Action Clusters

Don't just describe the person talking. Describe **what they do while talking** in time-ordered clusters:

```
[0-3s] Subject looks directly at camera, slight head tilt, begins speaking
with engaged expression. Right hand rests on desk.

[3-6s] Subject leans forward slightly, gestures with left hand (open palm
toward camera) while making a key point. Eyebrows raise briefly.

[6-10s] Subject leans back, nods slowly, slight smile forms. Hands return
to resting position on desk.
```

### Why Action Clusters Work

AI video generators produce better results when given:
- **Temporal structure** -- not just "person talks" but time-phased actions
- **Specific body parts** -- "right hand" not "hands"
- **Micro-expressions** -- "eyebrows raise briefly" not "expressive face"
- **Transitions** -- movement from one pose to another

### Natural Body Language Prompts

Avoid robotic or exaggerated motion. Use these modifiers:

- "subtle head nod" not "nodding"
- "slight lean forward" not "leaning in"
- "gentle hand gesture" not "gesturing"
- "natural blink rate" (AI often forgets blinking)
- "slight weight shift" for seated subjects

## Reference Frame Usage

Feed the base character image (from image generation phase) as the reference frame:

- **Kling:** Upload as "Reference Image" in image-to-video mode
- **Veo:** Include as source frame parameter

This maintains character consistency across clips. The video generator will animate the reference image rather than generating a new face.

## Handling Jump Cuts Between Clips

Adjacent 10s clips will have slight discontinuities (pose jumps, lighting shifts). Strategies:

1. **Prompt continuity:** End one clip's action cluster with a pose that matches the next clip's start
2. **Transition coverage:** Use B-roll, text overlays, or zoom transitions in Remotion (see post-production.md)
3. **Accept imperfection:** In UGC-style content, minor jump cuts are expected and authentic

## InfiniteTalk Alternative

For projects requiring seamless multi-minute video without clip boundaries, InfiniteTalk (from MinMax) generates continuous talking-head video from audio + reference image. Trade-offs:

- **Pros:** No clip assembly needed, natural motion continuity
- **Cons:** Less control over body language, limited availability, audio must be pre-recorded
- **When to use:** If the user has final audio already and wants fastest path to video

## Lip Sync Post-Processing

**The problem:** Image-to-video tools generate generic "talking" mouth movements that are NOT synced to your audio. The subject may appear silent or have mismatched lip movement.

**Getting lip movement at all:** Kling won't always generate lip movement. You MUST include explicit cues:
- "Mouth moves naturally as she talks throughout"
- "Lips move as she speaks" in each time block
- **AVOID** phrases like "closed-lip smile", "holds the pose", or "still" which tell Kling to freeze the mouth

**Solutions for syncing to audio (in order of quality):**

1. **Wav2Lip** (recommended) -- Open-source lip sync that takes video + audio and generates matching lip movement
   - GitHub: `Rudrabha/Wav2Lip`
   - Can be run locally or via Replicate API
   - Best quality for talking heads

2. **SadTalker** -- Generates head motion + lip sync from audio + single image
   - Alternative if Wav2Lip produces artifacts
   - Better head motion, sometimes less precise lips

3. **Hedra / HeyGen** -- Commercial services with built-in lip sync
   - Higher cost but turnkey solution
   - Good for production workflows

4. **Accept generic motion** -- For some UGC content, slightly mismatched lips are acceptable
   - Works better with fast cuts and captions that draw attention away from lips

**Recommended workflow:** Generate all clips with Kling/Veo first, then batch-process through Wav2Lip with the corresponding audio chunks before assembly.

## Known Limitations

### Finger Counting is Unreliable

AI video generators consistently fail at specific hand poses:

| Prompt | Typical Result |
|--------|---------------|
| "holds up three fingers" | Wrong number of fingers, or hand in wrong position |
| "counting on fingers" | Random finger movements, not matching any count |
| "peace sign" / "thumbs up" | Sometimes works, often distorted |

**Recommendation:** Avoid specific finger counts in prompts. Use vague gesture descriptions instead:
- "emphatic hand gesture" instead of "holds up three fingers"
- "illustrative gesture" instead of "counting on fingers"
- "open palm toward camera" (more reliable than specific poses)

### Gesture Timing Won't Match Script

The video generator doesn't understand your script content. If your script says "there are THREE reasons" and you prompt "holds up three fingers at 3 seconds," the timing will likely be wrong.

**Recommendation:** Keep gestures generic and focus on emotional tone rather than script-specific actions.

## Common Mistakes

| Mistake | Why it fails | Fix |
|---------|-------------|-----|
| "Person talking to camera for 10 seconds" | Boring, static result | Add action clusters with timeline |
| No reference frame | Different face each clip | Always include base image |
| Overly dramatic actions | Looks unnatural | Use subtle/slight modifiers |
| Ignoring clip boundaries | Jump cuts are jarring | Plan pose continuity or use transitions |
| Generating at wrong aspect ratio | Cropping ruins framing | Specify 9:16 vertical in prompt |
| Specific finger counts in prompts | Wrong number of fingers | Use vague gesture descriptions |
| Expecting lip sync to audio | Lips don't match external audio | Add Wav2Lip post-processing step |
