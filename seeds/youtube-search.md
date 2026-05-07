# youtube-search

Search YouTube and evaluate video quality using metadata signals — the YouTube equivalent of github-search.

## SKILL.md Frontmatter

```yaml
---
name: youtube-search
description: >
  Search YouTube and evaluate video quality using metadata signals. Use when
  asked to find YouTube videos, compare video quality, find trailers, source
  educational content, or evaluate channels — even if the user doesn't
  explicitly mention "YouTube" but describes finding video content online.
  Supports filtered search (by date, duration, type, sort order) and deep
  metadata analysis (chapters, audience retention heatmaps, engagement ratios).
---
```

## Problem

Finding high-quality YouTube videos requires manually browsing, clicking through results, and guessing at quality. For batch use cases (finding trailers for a movie list, sourcing educational content for a syllabus), this doesn't scale. We need a CLI-first sensor that searches YouTube and returns structured quality signals in a standard envelope.

## User Stories

1. **Movie night curator:** "I have a list of 20 movies, find me the best official trailer for each."
2. **Teacher building a syllabus:** "Find the best videos explaining photosynthesis for 8th graders."
3. **Researcher:** "Find conference talks about WebAssembly from the last 2 years."

## Architecture

This skill contains **sensors only** — no side effects, safe to call speculatively.

### Dependency: yt-dlp

All YouTube data is fetched via `python3 -m yt_dlp` (the pip package is installed but may not be on PATH). The scripts are **facades** (engineering principle #4) — yt-dlp's raw ~80-field JSON output is normalized into our ~15-field schema. One script changes if yt-dlp's output changes; callers never see yt-dlp's shapes.

### Dependency: yt-x (reference only, NOT a runtime dependency)

yt-x reverse-engineered 19 YouTube search filter `sp` parameter codes (protobuf-encoded). These are stored as static reference data in `references/sp-filters.md`. yt-x also documented YouTube feed URL patterns stored in `references/youtube-urls.md`.

## Envelope (engineering principle #2)

Every script outputs this shape to stdout. Errors go to stderr. No exceptions.

```json
{"success": true, "data": [...], "meta": {"source": "yt-dlp", "query": "...", "total": 30, "offset": 0, "limit": 10, "latency_ms": 2340}}
```

```json
{"success": false, "data": [], "meta": {"source": "yt-dlp", "query": "...", "error": "upstream timeout", "latency_ms": 5000}}
```

Empty results are NOT errors: `{"success": true, "data": [], ...}`.

## Scripts

All scripts support `--help` (usage, flags, examples). Exit codes: 0 success, 1 input error, 2 upstream failure, 3 dependency missing.

### scripts/check-prereqs

Check for: `python3`, `python3 -m yt_dlp` (pip package at `~/.local/lib/python3.12/site-packages`), `jq`.

Output envelope:
```json
{
  "success": true,
  "data": {"ready": true},
  "meta": {
    "checks": [
      {"name": "python3", "status": "ok", "version": "3.12.x"},
      {"name": "yt-dlp", "status": "ok", "version": "2026.02.21"},
      {"name": "jq", "status": "ok", "version": "1.x"}
    ]
  }
}
```

### scripts/search

**Type:** Sensor (no side effects)

```
Usage: scripts/search <query> [--limit 10] [--offset 0]
                               [--filter newest|views|rating]
                               [--date hour|today|week|month|year]
                               [--type video|playlist|channel|short|long]
                               [--subtitles-only]
                               [--channel-url URL]
                               [--pretty]

Examples:
  scripts/search "rust tutorial" --limit 5
  scripts/search "dune trailer" --filter views --type video
  scripts/search "photosynthesis" --subtitles-only --date year
  scripts/search "WebAssembly" --channel-url "https://www.youtube.com/@GoogleChromeDevelopers"
```

**Implementation — uses yt-x's pattern (NOT `ytsearch:`):**

```bash
python3 -m yt_dlp \
  "https://www.youtube.com/results?search_query=$(encode "$QUERY")&sp=$SP_CODE" \
  -J --flat-playlist \
  --extractor-args youtubetab:approximate_date \
  --playlist-start $((OFFSET + 1)) \
  --playlist-end $((OFFSET + LIMIT))
```

Key flags:
- `-J` produces a single JSON document (vs `-j` which is one line per entry)
- `--flat-playlist` avoids per-video metadata fetch — fast but returns limited fields
- `--extractor-args youtubetab:approximate_date` gives approximate upload dates in flat mode
- `--playlist-start`/`--playlist-end` handles pagination

When `--channel-url URL` is provided, use channel-specific search:
```bash
python3 -m yt_dlp "$CHANNEL_URL/search?query=$(encode "$QUERY")" -J --flat-playlist ...
```

**sp filter code mapping** (read from `references/sp-filters.md`):

The `--filter`, `--date`, `--type`, and `--subtitles-only` flags map to YouTube's `sp` parameter codes. The script reads the mapping from the reference file and constructs the search URL. Multiple filters may need to be combined — document any known incompatible combinations in `MEMO.md`.

**Rate limiting:** When `--limit` > 5, add `--sleep-requests 1` to avoid bot detection. Consistent with yt-dlp skill's `-t sleep` philosophy.

**Output envelope:**
```json
{
  "success": true,
  "data": [
    {
      "id": "CMiPYHNNg28",
      "title": "Photosynthesis (UPDATED)",
      "channel": "Amoeba Sisters",
      "channel_id": "UCQnQPECGMTMi2r7P3FD0-Gg",
      "duration": 479,
      "view_count": 5742020,
      "upload_date": "2021-07-14",
      "url": "https://www.youtube.com/watch?v=CMiPYHNNg28",
      "thumbnail": "https://i.ytimg.com/vi/CMiPYHNNg28/maxresdefault.jpg",
      "description_snippet": "first 200 chars..."
    }
  ],
  "meta": {
    "source": "yt-dlp",
    "query": "photosynthesis",
    "filters": {"type": "video", "date": "year"},
    "total": 30,
    "offset": 0,
    "limit": 10,
    "latency_ms": 2340
  }
}
```

Note: flat-playlist mode does NOT return like_count, comment_count, chapters, or heatmap. For those, follow up with `deep-dive` on specific videos.

### scripts/deep-dive

**Type:** Sensor (no side effects)

```
Usage: scripts/deep-dive <video-id-or-url> [--pretty]

Examples:
  scripts/deep-dive "rQ_J9WH6CGk"
  scripts/deep-dive "https://www.youtube.com/watch?v=rQ_J9WH6CGk" --pretty
```

Full metadata fetch for a single video. This is the **shared state contract** (engineering principle #11) — its output schema is consumed by youtube-clip's `explore` script.

**Implementation:**

```bash
python3 -m yt_dlp --dump-json --no-download "https://www.youtube.com/watch?v=$VIDEO_ID"
```

The script extracts and normalizes ~15 fields from yt-dlp's ~80-field output. The facade boundary — yt-dlp's shapes stay inside this script.

**Output envelope (this IS the shared state contract, versioned):**

```json
{
  "success": true,
  "data": {
    "id": "rQ_J9WH6CGk",
    "title": "Rust Programming Full Course",
    "channel": "BekBrace",
    "channel_id": "UC7EVS...",
    "channel_followers": 44500,
    "duration": 11104,
    "view_count": 513832,
    "like_count": 11482,
    "comment_count": 683,
    "upload_date": "2024-05-21",
    "categories": ["Science & Technology"],
    "tags": [],
    "description": "full text...",
    "url": "https://www.youtube.com/watch?v=rQ_J9WH6CGk",
    "thumbnail": "https://i.ytimg.com/vi/.../maxresdefault.jpg",
    "chapters": [
      {"title": "Introduction to Rust", "start": 0, "end": 485},
      {"title": "Install Rust", "start": 485, "end": 566}
    ],
    "heatmap": [
      {"start": 0, "end": 111, "value": 0.162},
      {"start": 111, "end": 222, "value": 0.201}
    ],
    "captions": {
      "manual": [],
      "auto": ["en", "es", "fr"]
    }
  },
  "meta": {
    "source": "yt-dlp",
    "video_id": "rQ_J9WH6CGk",
    "schema_version": 1,
    "latency_ms": 3100
  }
}
```

**Contract rules (principle #11):**
- `meta.schema_version` is always present and starts at 1
- Readers MUST ignore unrecognized fields (forward-compat)
- Writers MUST preserve all existing fields on schema evolution

**Fields extracted from yt-dlp raw output:**

| Our field | yt-dlp field | Notes |
|-----------|-------------|-------|
| id | id | |
| title | title | |
| channel | channel | |
| channel_id | channel_id | |
| channel_followers | channel_follower_count | |
| duration | duration | seconds (int) |
| view_count | view_count | |
| like_count | like_count | |
| comment_count | comment_count | |
| upload_date | upload_date | YYYYMMDD → YYYY-MM-DD |
| categories | categories | array |
| tags | tags | array |
| description | description | full text |
| url | webpage_url | |
| thumbnail | thumbnail | best available |
| chapters | chapters | `[{title, start_time, end_time}]` → `[{title, start, end}]` |
| heatmap | heatmap | `[{start_time, end_time, value}]` → `[{start, end, value}]` |
| captions.manual | subtitles | keys of dict |
| captions.auto | automatic_captions | keys of dict |

### scripts/evaluate

**Type:** Sensor

```
Usage: scripts/evaluate [FILE]
       cat results.json | scripts/evaluate

Reads search or deep-dive results (JSON envelope or raw array) from file or stdin.
Outputs quality score 1-5 with checks.
```

**Quality signals:**

| Signal | Computation | Good | Bad |
|--------|------------|------|-----|
| Views/day | view_count / days_since_upload | >1000 | <10 |
| Like ratio | like_count / view_count | >3% | <1% |
| Channel size | channel_followers | >10k | <100 |
| Has chapters | chapter_count > 0 | effort signal | — |
| Has captions | manual captions exist | accessibility | — |
| Heatmap peak | max(heatmap.value) | >0.5 (high retention) | <0.1 |
| Comment count | absolute | active discussion | 0 |

When evaluating search results (array), score is aggregate. When evaluating deep-dive (single video), score is per-video.

**Output envelope:**
```json
{
  "success": true,
  "data": {
    "outcome": 4,
    "note": "3 results, 2 with >100k views, 1 with chapters",
    "checks": {
      "results_found": 3,
      "total_views": 1500000,
      "has_popular": true,
      "high_engagement_count": 2
    }
  },
  "meta": {"source": "script"}
}
```

## Reference Data

### references/sp-filters.md

The 19 YouTube search filter codes reverse-engineered from yt-x. These are YouTube's internal protobuf-encoded `sp` parameter values:

```
Upload date filters:
  hour    -> EgIIAQ%253D%253D
  today   -> EgIIAg%253D%253D
  week    -> EgIIAw%253D%253D
  month   -> EgIIBA%253D%253D
  year    -> EgIIBQ%253D%253D

Content type filters:
  video    -> EgIQAQ%253D%253D
  movie    -> EgIQBA%253D%253D
  live     -> EgJAAQ%253D%253D
  playlist -> EgIQAw%253D%253D
  short    -> EgQQARgB
  long     -> EgQQARgC

Quality/feature filters:
  4k        -> EgJwAQ%253D%253D
  hd        -> EgIgAQ%253D%253D
  subtitles -> EgIoAQ%253D%253D
  360       -> EgJ4AQ%253D%253D
  vr        -> EgLIAQ%253D%253D
  3d        -> EgI4AQ%253D%253D
  hdr       -> EgPIAQ%253D%253D
  local     -> EgO4AQ%253D%253D

Sort options:
  newest -> CAISAhAB
  views  -> CAMSAhAB
  rating -> CAESAhAB
```

### references/youtube-urls.md

YouTube URL patterns from yt-x for various access modes:

```
Search (videos):     https://www.youtube.com/results?search_query=$q&sp=EgIQAQ%253D%253D
Search (channels):   https://www.youtube.com/results?search_query=$q&sp=EgIQAg%253D%253D
Search (playlists):  https://www.youtube.com/results?search_query=$q&sp=EgIQAw%253D%253D

Channel-specific search: $channel_url/search?query=$term
Channel videos:          $channel_url/videos
Channel streams:         $channel_url/streams
Channel shorts:          $channel_url/shorts
Channel podcasts:        $channel_url/podcasts

Personal feeds (require --cookies-from-browser):
  Watch history:       https://www.youtube.com/feed/history
  Liked videos:        https://www.youtube.com/playlist?list=LL
  Watch later:         https://www.youtube.com/playlist?list=WL
  Subscriptions feed:  https://www.youtube.com/feed/subscriptions
  Subscribed channels: https://www.youtube.com/feed/channels
  Playlists:           https://www.youtube.com/feed/playlists
```

## SKILL.md Workflow

### 1. Brainstorm Queries (LLM)

From user's description, generate 3-5 search variations using different angles:
- Direct terms: `"photosynthesis explained"`
- Audience-specific: `"photosynthesis for kids"`
- Format-specific: `"photosynthesis lecture"`
- Channel-type: `"photosynthesis crash course"`

For each, decide which filters narrow results (`:subtitles` for clip-friendly, `:views` sort for popular, date filter for recent).

### 2. Execute Searches (Script)

```bash
scripts/search "photosynthesis explained" --limit 10 --subtitles-only
scripts/search "photosynthesis for students" --limit 10 --filter views
```

### 3. Deduplicate & Rank (LLM)

Merge results across queries, deduplicate by video ID, rank by quality signals. Present top candidates with title, channel, duration, view count, upload date, URL.

### 4. Deep Dive (Script, optional)

For top picks, run `scripts/deep-dive` to get chapters, heatmap, full description:
```bash
scripts/deep-dive "CMiPYHNNg28"
```

### 5. Recommend (LLM)

Present 3-5 top videos with quality assessment. For batch queries (movie list), present one pick per item with alternatives.

### After Execution

Run `scripts/evaluate`, ask user for feedback, log to `FEEDBACK.jsonl`.

## Gotchas

- `--flat-playlist` does NOT return like_count, comment_count, chapters, or heatmap. Always tell the user that search gives a fast overview; deep-dive gives the full picture.
- yt-dlp may return fewer results than requested, or fail with exit code 1 if a result can't be extracted. The script should still output valid JSON for whatever it got.
- YouTube search results are non-deterministic — the same query can return different results on different runs.
- The `sp` filter codes may change if YouTube updates their protobuf schema. If filters stop working, re-verify codes against yt-x's source.
- Channel-specific search (`$channel_url/search?query=$term`) may require cookies for age-restricted or region-locked channels.
- Heatmap data is only available for videos with sufficient view count — very new or very low-view videos may have `null` heatmap.

## Evals

```json
{
  "skill_name": "youtube-search",
  "evals": [
    {
      "id": 1,
      "prompt": "Find the best official trailer for The Iron Giant",
      "expected_output": "Top result should be an official trailer, from a verified/official channel, 1-3 minutes long, high view count",
      "assertions": [
        "Envelope has success: true",
        "At least 1 result returned",
        "Top result duration is between 60 and 240 seconds",
        "Top result view_count is > 100000"
      ]
    },
    {
      "id": 2,
      "prompt": "Find educational videos about photosynthesis for middle school students",
      "expected_output": "Results should favor educational channels with good engagement, has captions",
      "assertions": [
        "Envelope has success: true",
        "At least 3 results returned",
        "Results include videos from known educational channels (Amoeba Sisters, CrashCourse, etc.)",
        "At least one result has subtitles-only filter applied"
      ]
    },
    {
      "id": 3,
      "prompt": "Search for recent WebAssembly conference talks from 2025",
      "expected_output": "Results should use date filter and favor longer-form content",
      "assertions": [
        "Envelope has success: true",
        "Date filter was applied (year or custom range)",
        "Results contain videos with duration > 600 seconds (10+ min talks)"
      ]
    }
  ]
}
```

## CONFIG.yaml

```yaml
skill:
  name: youtube-search
  version: 0.1.0
  created: 2026-04-19
  updated: 2026-04-19
  author: kevin

triggers:
  phrases:
    - "find youtube videos"
    - "search youtube for"
    - "find trailers for"
    - "find educational videos"
    - "youtube search"
    - "find videos about"
    - "best youtube videos for"
  keywords:
    - youtube search
    - find videos
    - video quality
    - trailer
    - educational video

dependencies:
  tools:
    - Bash
  cli:
    - python3
    - jq
  pip:
    - yt-dlp

loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml
  references:
    - references/sp-filters.md
    - references/youtube-urls.md

compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0
```

## Key Design Decisions

- **yt-x's search URL pattern over `ytsearch:`** — using `youtube.com/results?search_query=...&sp=...` with `-J --flat-playlist` is faster and supports filters. `ytsearch:` is a simpler scraper with no filter support.
- **Facade over yt-dlp** — scripts normalize yt-dlp's output into our envelope schema. yt-dlp's raw shapes never leak (principle #4).
- **Pagination via `--playlist-start`/`--playlist-end`** — maps directly to `--offset`/`--limit` in our interface (principle #5).
- **deep-dive output is the shared state contract** — versioned via `meta.schema_version`, consumed by youtube-clip's explore script (principle #11).
- **Rate limiting consistent with yt-dlp skill** — `--sleep-requests 1` for bulk, documented in SKILL.md not hidden in script internals.
- **Invoke as `python3 -m yt_dlp`** — the binary may not be on PATH but the pip package is installed.
- **No YouTube Data API** — 100 searches/day quota cap, requires API key setup, can't do captions without OAuth. yt-dlp is zero-setup and richer per-call.
