---
name: youtube-clip
description: >
  Search inside YouTube video transcripts to find specific moments, generate
  timestamped URLs, and create visual explorer pages. Use when asked to find
  where something is discussed in a video, extract clips or timestamps from
  long-form content, create a navigable overview of a long video, or build
  a playlist of specific segments. Works with both auto-generated and manual
  captions.
---

## Prerequisites

Run `scripts/check-prereqs.sh` and interpret results.

| Missing | Action |
|---------|--------|
| python3 | Install via system package manager or `brew install python3` |
| yt-dlp | `pip install yt-dlp` -- offer to run |
| jq | `brew install jq` or `apt install jq` -- offer to run |
| yt-fts | Optional. `pip install yt-fts` for channel indexing and semantic search |

## Workflow

### 1. Get Transcript

```bash
scripts/get-transcript "VIDEO_ID_OR_URL" --lang en
```

If transcript unavailable: suggest a different language (`--lang es`) or confirm the video has captions.

### 2. Search Within Transcript

**Keyword search:** `scripts/search-transcript "query" --video "VIDEO_ID" --context 30`
Also accepts `--input FILE` or piped stdin from get-transcript.

**Conceptual search** (keyword match insufficient): read `full_text` from get-transcript output, identify relevant sections, format with same fields: `start`, `end`, `watch_url`, `download_section`.

### 3. Present Results

For each match:
```
**[MM:SS] Topic** (start -> end)
> "...matched transcript text..."
- Watch: https://youtube.com/watch?v=VIDEO_ID&t=SECONDS
- Download clip: `python3 -m yt_dlp --download-sections "*MM:SS-MM:SS" --force-keyframes-at-cuts "URL"`
```

### 4. Batch Mode

When searching across multiple videos, present as a table:

| Video | Match | Time | Watch URL |
|-------|-------|------|-----------|
| Title | Topic found | MM:SS-MM:SS | link |

### 5. Explore (optional)

Generate a navigable HTML page for long-form videos:
```bash
scripts/explore "VIDEO_ID" -o explore.html       # generate
scripts/explore "VIDEO_ID" --dry-run             # preview without writing
```
Accepts `--deep-dive-json FILE` to reuse youtube-search metadata. Report output path.

### Enhanced Mode (yt-fts)

When yt-fts is installed (check prereqs output), additional capabilities are available. See `references/yt-fts-modes.md` for commands. Key additions: indexed channel search, semantic/embedding search (`vsearch`), video summarization, and RAG chatbot over channel transcripts.

If json3 parsing issues arise, see `references/json3-format.md` for the subtitle format structure and merging strategy.

## Gotchas

| Issue | Handling |
|-------|----------|
| No captions on video | Report clearly; suggest alternative language or video |
| Transcript fetch fails on captioned video | YouTube may block requests (geo/bot detection) even when `--subtitles-only` search found the video. Try 2-3 candidates; skip failures gracefully. |
| Cross-segment phrase match | Read `full_text` and search manually; substring match misses phrases spanning segments |
| Heatmap null (new/low-view video) | Explorer works without it -- chapters and transcript still render |
| Auto-captions lack punctuation | Merge logic uses timing gaps as primary boundary signal |

## After Execution

Run `echo "$OUTPUT" | scripts/evaluate.sh` and use the score. On alternate runs, ask: "Did these timestamps point to the right moments?" Map: exactly=5, mostly=4, some=3, mostly wrong=2, useless=1.

Log to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO 8601>","skill":"youtube-clip","version":"0.1.0","prompt":"<request>","outcome":<1-5>,"note":"...","source":"script|user|llm","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
