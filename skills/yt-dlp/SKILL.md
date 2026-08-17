---
name: yt-dlp
description: Download videos, audio, and subtitles/transcripts from YouTube and other sites through an auto-updating yt-dlp nightly runner. Use when the user wants playlists, clips, transcripts, audio-only media, or rate-limit-safe downloads.
---

# yt-dlp Agent

Run `scripts/check-prereqs.sh`, then construct yt-dlp arguments and pass them to `scripts/run`. The runner acquires the official binary through `npx` on first use and checks yt-dlp's recommended nightly channel daily. A global yt-dlp installation is neither required nor used.

When an extractor fails after an upstream site change, retry once with `scripts/run --refresh ...` before diagnosing further.

## Quick Reference

### Essential Patterns

| Goal | Command |
|------|---------|
| Best video+audio | `scripts/run URL` |
| Audio only (mp3) | `scripts/run -x --audio-format mp3 URL` |
| Subtitles embedded | `scripts/run --write-subs --sub-lang en --embed-subs URL` |
| Auto-generated subs | `scripts/run --write-auto-subs --sub-lang en URL` |
| Rate-limit safe | `scripts/run -t sleep URL` |
| With cookies | `scripts/run --cookies-from-browser firefox URL` |

### Playlist Downloads

```bash
# Basic playlist with numbered files
scripts/run -o "%(playlist_index)s - %(title)s.%(ext)s" "PLAYLIST_URL"

# Skip already downloaded
scripts/run --download-archive archive.txt "PLAYLIST_URL"
```

## Execution Workflow

### Step 1: Assess Requirements

Determine what user needs:
- **Video**: Default, or specify format with `-f`
- **Audio only**: Use `-x --audio-format FORMAT`
- **Transcripts**: Use `--write-subs` or `--write-auto-subs`
- **Playlist vs single**: Check URL type

### Step 2: Handle Rate Limits

For bulk downloads, **always use the sleep preset**:

```bash
scripts/run -t sleep URL
```

This applies: `--sleep-subtitles 5 --sleep-requests 0.75 --sleep-interval 10 --max-sleep-interval 20`

If hitting "Sign in to confirm you're not a bot":

```bash
scripts/run --cookies-from-browser firefox URL
```

### Step 3: Construct Command

Build command progressively:

```bash
scripts/run \
  -t sleep \                                    # Rate limiting
  --cookies-from-browser firefox \              # If needed
  -o "%(playlist_index)s - %(title)s.%(ext)s" \ # Output template
  --write-subs --sub-lang en \                  # Subtitles
  "URL"
```

### Step 4: Execute & Monitor

Run with `--verbose` first on a single video to verify settings work.

## Common Scenarios

### Full Playlist with Transcripts + Audio + Video

```bash
scripts/run -t sleep \
  --cookies-from-browser firefox \
  -o "%(playlist_title)s/%(playlist_index)03d - %(title)s.%(ext)s" \
  --write-subs --write-auto-subs --sub-lang en \
  --write-info-json \
  "PLAYLIST_URL"
```

### Transcripts Only (no video download)

```bash
scripts/run --skip-download \
  --write-subs --write-auto-subs --sub-lang en \
  --convert-subs srt \
  "URL"
```

### Audio + Transcript for Analysis

```bash
scripts/run -t sleep \
  -x --audio-format mp3 \
  --write-subs --write-auto-subs --sub-lang en \
  --convert-subs srt \
  -o "%(title)s.%(ext)s" \
  "URL"
```

## Key Options Reference

| Option | Purpose |
|--------|---------|
| `-t sleep` | Preset for rate-limit safety |
| `--cookies-from-browser BROWSER` | Use browser cookies (firefox/chrome/safari) |
| `-o TEMPLATE` | Output filename template |
| `--write-subs` | Download manual subtitles |
| `--write-auto-subs` | Download auto-generated subtitles |
| `--sub-lang LANG` | Subtitle language (e.g., `en`, `en.*`, `all`) |
| `--convert-subs FORMAT` | Convert to srt/vtt/ass |
| `--embed-subs` | Embed subtitles in video |
| `-x` | Extract audio only |
| `--audio-format FORMAT` | mp3/m4a/opus/wav |
| `-F` | List available formats |
| `--download-archive FILE` | Track downloaded videos |
| `--skip-download` | Metadata/subs only |
| `--write-info-json` | Save metadata JSON |
| `-N COUNT` | Concurrent fragment downloads |

## Output Template Variables

| Variable | Description |
|----------|-------------|
| `%(title)s` | Video title |
| `%(id)s` | Video ID |
| `%(playlist_index)s` | Position in playlist |
| `%(playlist_title)s` | Playlist name |
| `%(upload_date)s` | Upload date YYYYMMDD |
| `%(ext)s` | File extension |

## External Resources

- Full docs: https://github.com/yt-dlp/yt-dlp#readme
- Supported sites: https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md
- Format selection: https://github.com/yt-dlp/yt-dlp#format-selection

---

## After Execution

After completing the skill output, log feedback to track quality over time.

**Priority cascade:**
1. If `scripts/evaluate.sh` exists in this skill directory, run it and use the JSON result
2. Otherwise, self-assess using the scale below

**Self-assessment scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

**To log feedback**, append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"yt-dlp","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
