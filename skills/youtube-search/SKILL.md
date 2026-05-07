---
name: youtube-search
description: >
  Use this skill when asked to find YouTube videos, compare video quality, find
  trailers, source educational content, or evaluate channels -- even when
  "YouTube" is not mentioned explicitly but the user describes finding video
  content online. Supports filtered search and deep metadata analysis.
---

## Prerequisites

Run `scripts/check-prereqs.sh` and parse JSON output.

| Missing  | Action                                       |
|----------|----------------------------------------------|
| python3  | `brew install python3` or system package mgr |
| yt-dlp   | `pip install yt-dlp` (offer to run)          |
| jq       | `brew install jq` (offer to run)             |

If `ready: true`, proceed. Otherwise resolve missing items first.

## Workflow

### 1. Brainstorm Queries

Generate 3-5 search variations: direct terms, audience-specific, format-specific, channel-type. Pick filters for each (`--subtitles-only`, `--filter views`, `--date year`).

### 2. Execute Searches

```bash
scripts/search "photosynthesis explained" --limit 10 --subtitles-only
scripts/search "photosynthesis" --filter views --type video --date year
```

| Flag              | Values                                |
|-------------------|---------------------------------------|
| `--filter`        | newest, views, rating                 |
| `--date`          | hour, today, week, month, year        |
| `--type`          | video, playlist, channel, short, long |
| `--subtitles-only`| (flag)                                |
| `--channel-url`   | search within a specific channel      |
| `--limit/--offset`| pagination (rate-limited when >5)     |

Search returns title, channel, views, duration, date. Does NOT include likes, comments, chapters, or heatmap -- those require deep-dive.

### 3. Deduplicate and Rank

Merge across queries, deduplicate by video ID, rank by view count, recency, channel reputation, duration fit. Present as a table.

### 4. Deep Dive (optional)

```bash
scripts/deep-dive "VIDEO_ID" --pretty
```

Returns: like_count, comment_count, chapters, heatmap, captions, channel_followers, tags, full description. Shared state contract (schema_version: 1).

### 5. Recommend

Present 3-5 top videos with quality assessment. For batch queries, one pick per item with alternatives noted.

## Gotchas

- `--flat-playlist` does NOT return like_count, comment_count, chapters, or heatmap. Search gives a fast overview; deep-dive gives the full picture.
- YouTube search is non-deterministic -- the same query returns different results across runs.
- The sp filter codes may silently break if YouTube updates their protobuf schema. If filter results look wrong, re-verify codes against `references/sp-filters.md`.
- Channel-specific search may require cookies for age-restricted or region-locked channels -- the scripts do not pass cookies.
- Heatmap data is null for very new or low-view videos. The evaluate script skips the heatmap check when absent.
- Only the first sp filter is applied when multiple flags are given (combining is unreliable). Run separate searches and merge instead.
- Read `references/sp-filters.md` if you need filter codes beyond the ones exposed as flags.
- Read `references/youtube-urls.md` if you need channel-specific or personal feed URL patterns.

## After Execution

Run the evaluator:

```bash
cat results.json | scripts/evaluate
```

Scores 1-5 based on views/day, like ratio, channel size, chapters, captions, heatmap.

**Score >= 4:** Log and proceed.
**Score < 4:** Ask "Do these results match what you were looking for, or should I refine?" Map: yes=4, partially=3, no=2. On alternate runs, self-assess instead of asking.

Append to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO 8601>","skill":"youtube-search","version":"0.1.0","prompt":"<request>","outcome":<1-5>,"note":"...","source":"script|user|llm","schema_version":1}
```
Increment `iteration_count` in `CONFIG.yaml`.
