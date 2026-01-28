---
name: audio-cleanup
description: Audio cleanup tools comparison and ffmpeg normalization for talking-head videos
tags: audio, cleanup, podcast, resemble, ffmpeg
---

# Audio Cleanup for Talking Heads

## Why Audio Cleanup Matters

AI-generated video has no real audio -- the voice track must be added separately. Options:

1. **User records their own voice** -- needs cleanup (noise, levels)
2. **AI voice generation** (ElevenLabs, Resemble AI) -- cleaner but needs normalization
3. **Text-to-speech** -- lowest effort but less natural

Regardless of source, the final audio needs processing before assembly.

## Tool Comparison

| Tool | Best For | Cost | Quality |
|------|----------|------|---------|
| Adobe Podcast (Enhance Speech) | Quick noise removal | Free tier available | Good |
| Resemble AI | Voice cloning + cleanup | Paid | Excellent |
| ElevenLabs | Voice generation | Paid | Excellent |
| Audacity | Manual editing | Free | Depends on skill |

**Minimum recommendation:** Run all voice audio through Adobe Podcast's Enhance Speech before assembly. It removes background noise, normalizes levels, and improves clarity in one step.

**For voice swap:** Resemble AI can clone a voice from a short sample, then generate speech from the script text. Useful when the user wants a consistent AI voice across all clips.

## ffmpeg Normalization

After cleanup, normalize audio levels for consistent volume across all chunks:

```bash
# Loudness normalization to broadcast standard (-16 LUFS)
ffmpeg -i input.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 output.wav

# Simple peak normalization (quick and dirty)
ffmpeg -i input.wav -af "volume=0dB" -af acompressor output.wav
```

Split audio to match chunk boundaries:

```bash
# Split at specific timestamp (e.g., 10 seconds per chunk)
ffmpeg -i full_audio.wav -ss 0 -t 10 chunk_01.wav
ffmpeg -i full_audio.wav -ss 10 -t 10 chunk_02.wav
```

## Audio-Video Sync

AI video lip movements won't perfectly match the audio. Mitigation strategies:

1. **Slight offset:** Try shifting audio 100-200ms earlier -- AI video tends to have slight motion delay
2. **B-roll coverage:** Use text overlays or zoom transitions during worst sync points
3. **Speed adjustment:** Remotion can slightly speed/slow audio to match clip duration (see remotion skill's `audio.md` reference)

## Cross-Reference: Remotion Audio

For final audio mixing and layering in the assembled video, see the remotion skill:

- `references/audio.md` -- Audio import, trimming, volume, speed, pitch
- `references/sequencing.md` -- Timing audio to visual sequences
- `references/transcribe-captions.md` -- Generating captions from final audio
