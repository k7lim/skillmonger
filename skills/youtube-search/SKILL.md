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
| python3  | Install Python 3.10+ via system package mgr  |
| npx      | Install Node.js 18+                          |
| yt-dlp runner | Deploy sibling `yt-dlp`; no global install |
| jq       | `brew install jq` (offer to run)             |

If `ready: true`, proceed. Otherwise resolve missing items first.

## Workflow

### 1. Brainstorm Queries

Generate 3-5 search variations: direct terms, audience-specific, format-specific, channel-type. Pick filters for each (`--subtitles-only`, `--filter views`, `--date year`).

### 2. Execute Searches

```bash
scripts/search "photosynthesis explained" --limit 10 --subtitles-only
scripts/search "photosynthesis" --filter views --type video --date year
scripts/search "photosynthesis" --limit 3 --quality-rank --pretty
```

| Flag              | Values                                |
|-------------------|---------------------------------------|
| `--filter`        | newest, views, rating                 |
| `--date`          | hour, today, week, month, year        |
| `--type`          | video, playlist, channel, short, long |
| `--subtitles-only`| (flag)                                |
| `--channel-url`   | search within a specific channel      |
| `--fields`        | comma-separated output fields         |
| `--quality-rank`  | for `--limit <= 5`, deep-dive extra candidates and rank by quality |
| `--limit/--offset`| pagination (rate-limited when >5)     |

Search returns title, channel, views, duration, date. Does NOT include likes, comments, chapters, or heatmap -- those require deep-dive.

### 3. Deduplicate and Rank

Merge across queries, deduplicate by video ID, rank by view count, recency, channel reputation, duration fit. Present as a table.

For a small final set, prefer `scripts/search "<query>" --limit 3 --quality-rank`: it fetches extra candidates, deep-dives each one, scores quality signals with the evaluator logic, and returns the top N with deep metadata included.

### 4. Deep Dive (optional)

```bash
scripts/deep-dive "VIDEO_ID" --pretty
```

Returns: like_count, comment_count, chapters, heatmap, captions, channel_followers, tags, full description. Shared state contract (schema_version: 1).
Use `--fields id,title,like_count` to return only selected deep-dive fields.

### 5. Recommend

Present 3-5 top videos with quality assessment. For batch queries, one pick per item with alternatives noted.

## Gotchas

- `--flat-playlist` does NOT return like_count, comment_count, chapters, or heatmap. Search gives a fast overview; deep-dive gives the full picture.
- YouTube search is non-deterministic -- the same query returns different results across runs.
- Extractor/integration failure: run `../yt-dlp/scripts/run --version` to trigger the lazy stable update, then retry once.
- The sp filter codes may silently break if YouTube updates their protobuf schema. If filter results look wrong, re-verify codes against `references/sp-filters.md`.
- Channel-specific search may require cookies for age-restricted or region-locked channels -- the scripts do not pass cookies.
- Heatmap data is null for very new or low-view videos. The evaluate script skips the heatmap check when absent.
- Only the first sp filter is applied when multiple flags are given (combining is unreliable). Run separate searches and merge instead.
- Read `references/sp-filters.md` if you need filter codes beyond the ones exposed as flags.
- Read `references/youtube-urls.md` if you need channel-specific or personal feed URL patterns.

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
cat results.json | scripts/evaluate
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

**Score >= 4:** Log and proceed.
**Score < 4:** Ask "Do these results match what you were looking for, or should I refine?" Map: yes=4, partially=3, no=2. On alternate runs, self-assess instead of asking.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"youtube-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"youtube-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
