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
| Lip sync quality | Good with clear prompts | Better natural motion |
| Availability | klingai.com / API | Google DeepMind / API |
| Cost | Mid-range | Higher |
| Best for | Consistent character, longer clips | Natural body language |

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

## Common Mistakes

| Mistake | Why it fails | Fix |
|---------|-------------|-----|
| "Person talking to camera for 10 seconds" | Boring, static result | Add action clusters with timeline |
| No reference frame | Different face each clip | Always include base image |
| Overly dramatic actions | Looks unnatural | Use subtle/slight modifiers |
| Ignoring clip boundaries | Jump cuts are jarring | Plan pose continuity or use transitions |
| Generating at wrong aspect ratio | Cropping ruins framing | Specify 9:16 vertical in prompt |
