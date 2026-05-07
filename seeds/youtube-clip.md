# youtube-clip

Search inside YouTube video transcripts to find specific moments, generate timestamped URLs, and create visual longform-explorer pages.

## SKILL.md Frontmatter

```yaml
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
```

## Problem

You've found a good 45-minute video, but you only need the 3 minutes where they explain a specific concept. Scrubbing through manually is slow. Transcripts exist but there's no good CLI workflow for searching them and getting back actionable timestamps and clip URLs.

## User Stories

1. **Teacher curating clips:** "In these 5 videos about the water cycle, find every segment that discusses evaporation — I need timestamped links for my playlist."
2. **Researcher extracting quotes:** "Find where this speaker talks about 'supply chain' in their keynote."
3. **Longform explorer:** "This 3-hour lecture has 22 chapters. Show me which parts people actually watch and let me jump to any section."

## Architecture

This skill has **sensors** (read-only) and **one actuator** (writes an HTML file).

### Dependencies

**Required:**
- `python3`, `python3 -m yt_dlp` (pip package), `jq`

**Optional:**
- `yt-fts` (pip) — enables indexed channel search, semantic/embedding search (`vsearch`), video summarization, and RAG chatbot over channel transcripts. When not installed, skill works fine using yt-dlp for ad-hoc single-video transcript fetch.

### Relationship to youtube-search

youtube-clip's `explore` script can accept deep-dive JSON from youtube-search (via `--deep-dive-json FILE`) to avoid re-fetching metadata. The deep-dive output is a **shared state contract** (principle #11) with `meta.schema_version`. When run standalone, explore fetches its own metadata.

## Envelope (engineering principle #2)

Same envelope as youtube-search — every script outputs `{"success": bool, "data": ..., "meta": {...}}` to stdout, errors to stderr.

## Scripts

All scripts support `--help`. Exit codes: 0 success, 1 input error, 2 upstream failure, 3 dependency missing.

### scripts/check-prereqs

Check for: `python3`, `python3 -m yt_dlp`, `jq`. Optionally check for `yt-fts` and report its status.

```json
{
  "success": true,
  "data": {"ready": true},
  "meta": {
    "checks": [
      {"name": "python3", "status": "ok"},
      {"name": "yt-dlp", "status": "ok", "version": "2026.02.21"},
      {"name": "jq", "status": "ok"},
      {"name": "yt-fts", "status": "ok", "version": "0.1.62", "note": "optional — enables channel indexing and semantic search"}
    ]
  }
}
```

### scripts/get-transcript

**Type:** Sensor (no side effects — temp files cleaned up)

```
Usage: scripts/get-transcript <video-id-or-url> [--lang en] [--prefer manual|auto] [--pretty]

Examples:
  scripts/get-transcript "rQ_J9WH6CGk"
  scripts/get-transcript "https://www.youtube.com/watch?v=rQ_J9WH6CGk" --lang es
  scripts/get-transcript "rQ_J9WH6CGk" --prefer manual --pretty
```

**Implementation — two paths:**

**Path 1: Ad-hoc single video (default).** Uses yt-dlp:

```bash
python3 -m yt_dlp \
  --write-auto-subs --write-subs \
  --sub-lang "$LANG" --sub-format json3 \
  --skip-download \
  -o "/tmp/yt-clip-$VIDEO_ID" \
  "https://www.youtube.com/watch?v=$VIDEO_ID"
```

Then parse the json3 file. The json3 format has:
- `events[]` array, each with `tStartMs` (milliseconds), `dDurationMs`, and `segs[]`
- Each `seg` has `utf8` (word text) and optional `tOffsetMs` (offset within event)

The script **merges word-level segments into sentence-level chunks** (~10-15 second chunks) based on:
- Punctuation (`.`, `!`, `?`) as sentence boundaries
- Timing gaps > 1 second as natural breaks
- Maximum chunk duration of ~15 seconds

This merging is critical — raw json3 is word-by-word, unusably granular for search.

Prefer manual subtitles when both manual and auto exist (higher quality). The `--write-subs --write-auto-subs` combo downloads both; pick the manual file if present.

Clean up temp files (`/tmp/yt-clip-*`) after parsing.

**Path 2: Indexed channel via yt-fts (when available).**

When yt-fts is installed AND the channel is already indexed:
```bash
yt-fts search "query" -c CHANNEL_NAME
```

The facade wraps yt-fts's Rich terminal output (which is NOT JSON) into our envelope format. This requires parsing the colored terminal output.

Falls back to Path 1 if yt-fts is not installed or channel is not indexed.

**Output envelope:**

```json
{
  "success": true,
  "data": {
    "video_id": "rQ_J9WH6CGk",
    "title": "Rust Programming Full Course",
    "language": "en",
    "source": "auto",
    "segments": [
      {"start": 0.64, "end": 5.84, "text": "Hello and welcome to the Rust programming"},
      {"start": 2.96, "end": 8.08, "text": "language full course"},
      {"start": 5.84, "end": 9.76, "text": "In this course, I will be covering everything"}
    ],
    "full_text": "Hello and welcome to the Rust programming language full course. In this course, I will be covering everything..."
  },
  "meta": {
    "source": "yt-dlp",
    "video_id": "rQ_J9WH6CGk",
    "segment_count": 1200,
    "schema_version": 1,
    "latency_ms": 4200
  }
}
```

**Predictable output size:** By default, output includes `segments` (array) and `full_text` (string). For very long videos (>2 hours), `full_text` can be large. The `--pretty` flag is for human display (truncates to first/last segments with count). The raw envelope always includes full data for piping to search-transcript.

### scripts/search-transcript

**Type:** Sensor (no side effects)

```
Usage: scripts/search-transcript <query> [--input FILE|-] [--video VIDEO_ID]
                                          [--context 30] [--limit 10] [--offset 0]
                                          [--pretty]

Examples:
  scripts/search-transcript "ownership" --input transcript.json
  scripts/get-transcript "rQ_J9WH6CGk" | scripts/search-transcript "ownership"
  scripts/search-transcript "photosynthesis" --video "CMiPYHNNg28" --context 60
```

When `--video` is provided without `--input`, the script calls `get-transcript` internally.

**Search approach:**
- Case-insensitive substring match across segment texts
- `--context N` includes N seconds of surrounding transcript before/after each match (default 30s)
- Overlapping matches merged into continuous segments
- Sentence boundary expansion: expand to natural sentence breaks, don't clip mid-word
- For each match, compute both a "watch URL" and a "download section" range

**Output envelope:**

```json
{
  "success": true,
  "data": [
    {
      "text": "...let's talk about ownership. In Rust, ownership is the key concept that makes the language unique...",
      "start": 1847.2,
      "end": 1892.5,
      "start_fmt": "30:47",
      "end_fmt": "31:32",
      "watch_url": "https://www.youtube.com/watch?v=rQ_J9WH6CGk&t=1847",
      "download_section": "*30:47-31:32",
      "context_before": "...and that brings us to the most important topic in Rust...",
      "context_after": "...so every value in Rust has exactly one owner at a time..."
    }
  ],
  "meta": {
    "query": "ownership",
    "video_id": "rQ_J9WH6CGk",
    "video_title": "Rust Programming Full Course",
    "total": 5,
    "offset": 0,
    "limit": 10,
    "latency_ms": 45
  }
}
```

**Output format notes:**
- `watch_url` uses `?t=` parameter (seconds, integer) — for "watch from here" links
- `download_section` uses yt-dlp's `--download-sections` format (`*MM:SS-MM:SS`) — for clip extraction
- `start_fmt`/`end_fmt` are human-readable `MM:SS` or `H:MM:SS` timestamps

### scripts/explore

**Type:** ACTUATOR (writes a file) — supports `--dry-run`

```
Usage: scripts/explore <video-id-or-url> [--deep-dive-json FILE]
                                          [--output FILE]
                                          [--dry-run]
                                          [--pretty]

Examples:
  scripts/explore "rQ_J9WH6CGk" --dry-run
  scripts/explore "rQ_J9WH6CGk" -o /tmp/explore.html
  scripts/explore "rQ_J9WH6CGk" --deep-dive-json deep-dive-output.json -o explore.html
```

**What it does:** Generates a self-contained HTML file that makes long-form YouTube videos explorable. This is the **longform-explorer** artifact.

**Data sources:**
1. If `--deep-dive-json FILE` provided: reads video metadata (chapters, heatmap, captions) from the file (shared state contract from youtube-search)
2. Otherwise: calls `python3 -m yt_dlp --dump-json --no-download` to fetch its own metadata
3. Always fetches transcript via the get-transcript path (unless deep-dive JSON includes it)

**HTML output — self-contained single file with:**

1. **Header:** Video title, channel, duration, view count, upload date, thumbnail
2. **Heatmap timeline bar:**
   - CSS gradient visualization from dim (low retention) to bright green/yellow (high retention)
   - 100 data points mapped across the video duration
   - Each segment is clickable — links to `?t=` URL
   - Visual indicator of which parts people actually watch
3. **Chapter list with heatmap intensity:**
   - Each chapter shows title, start-end time, and a mini heatmap bar
   - Background color reflects average retention for that chapter
   - Immediately answers "which chapter is worth watching?" at a glance
   - Each chapter is a clickable `?t=` link
4. **Searchable transcript:**
   - Full transcript with timestamps, rendered in a scrollable panel
   - Every timestamp is a `?t=` link
   - Browser Ctrl+F search works across the full text
   - Segments visually aligned with heatmap (retention-colored left border)
5. **No external dependencies:** All CSS/JS inline. Works offline once generated.

**For channel-level exploration** (future enhancement): could generate an index page with grid of videos, each showing a mini heatmap sparkline. Not in v1.

**`--dry-run`:** Shows what would be generated — video title, chapter count, heatmap points, transcript segment count, estimated file size — without writing anything.

**Output envelope (actuator — echoes what it did):**

```json
{
  "success": true,
  "data": {
    "output_path": "/tmp/explore-rQ_J9WH6CGk.html",
    "video_id": "rQ_J9WH6CGk",
    "title": "Rust Programming Full Course",
    "chapter_count": 22,
    "heatmap_points": 100,
    "transcript_segments": 1200
  },
  "meta": {
    "source": "generated",
    "dry_run": false,
    "latency_ms": 320
  }
}
```

### scripts/evaluate

**Type:** Sensor

```
Usage: scripts/evaluate [FILE]
       cat results.json | scripts/evaluate
```

Scores clip search results (1-5):
- 5: Found precise, relevant segments with clear boundaries
- 4: Found relevant segments, boundaries reasonable
- 3: Found matches but context is noisy or boundaries imprecise
- 2: Few/poor matches
- 1: No matches found or transcript unavailable

## SKILL.md Workflow

### 1. Get Transcript (Script)

```bash
scripts/get-transcript "VIDEO_ID" --lang en
```

If transcript unavailable, report to user and suggest alternatives (different language, different video).

### 2. Search Within (Script or LLM)

**For keyword searches:**
```bash
scripts/search-transcript "photosynthesis" --input transcript.json --context 30
```

**For conceptual/semantic searches** (e.g., "the part where they explain why X happens"): the LLM reads the full transcript text from the get-transcript output and identifies relevant sections manually, outputting the same match format. This is where the LLM adds value beyond substring matching.

**For indexed channel semantic search** (when yt-fts is available):
```bash
yt-fts vsearch "energy conversion in cells" -c "Khan Academy" --limit 5
```
Document this as an enhanced mode in SKILL.md — not required but significantly more powerful for conceptual searches.

### 3. Present Results (LLM)

For each match:
```
**[30:47] Ownership in Rust** (30:47 → 31:32)
> "...let's talk about ownership. In Rust, ownership is the key concept..."
- Watch from here: https://youtube.com/watch?v=rQ_J9WH6CGk&t=1847
- Download clip: `python3 -m yt_dlp --download-sections "*30:47-31:32" --force-keyframes-at-cuts "URL"`
```

### 4. Batch Mode (LLM)

When searching across multiple videos:
```
| Video | Match | Timestamp | Watch URL |
|-------|-------|-----------|-----------|
| Rust Full Course | Ownership explained | 30:47-31:32 | [link] |
| Rust in 100 Seconds | Ownership mention | 0:42-1:15 | [link] |
```

### 5. Explore (Script, optional)

When the user wants a navigable overview of a long video:
```bash
scripts/explore "rQ_J9WH6CGk" -o explore.html
```
Then tell the user to open the HTML file.

### After Execution

Run `scripts/evaluate`, ask user for feedback, log to `FEEDBACK.jsonl`.

## Gotchas

- **json3 merging is the hardest part.** Raw json3 has word-level granularity with overlapping timestamps. The merge-to-sentences logic needs careful handling of: punctuation detection in auto-generated captions (which often lack punctuation), timing gaps, and maximum chunk duration.
- **Auto-generated captions have no punctuation** in many languages. The merging logic should use timing gaps as the primary boundary signal, not punctuation, when punctuation is sparse.
- **Manual subtitles may not exist.** Most videos only have auto-generated captions. Use `--write-subs --write-auto-subs` and prefer manual when available.
- **yt-dlp subtitle language codes vary.** `en` may miss `en-US` or `en-GB`. Use `--sub-lang "en.*"` regex to match all English variants.
- **Heatmap may be null** for new/low-view videos. The explore script should handle this gracefully — show chapters and transcript without heatmap.
- **Cross-segment phrase matching** is a known limitation. If a phrase spans two subtitle segments, substring match won't find it. For important searches, the LLM should read the full_text field and search manually.
- **yt-fts's Rich terminal output** has no JSON mode. The facade must parse ANSI-colored terminal output — fragile and may break across yt-fts versions. Consider using yt-fts's SQLite database directly if possible.
- **`--force-keyframes-at-cuts`** in download commands is slow (re-encodes) but produces clean clip boundaries. Always include it in suggested download commands.

## Optional yt-fts Enhanced Modes

Document these in SKILL.md as capabilities available when yt-fts is installed:

| Mode | Command | What it enables |
|------|---------|----------------|
| **Channel indexing** | `yt-fts download CHANNEL_URL` | Index entire channel for fast repeated searches |
| **Semantic search** | `yt-fts vsearch "concept" -c CHANNEL` | Find conceptual matches, not just keywords |
| **Video summary** | `yt-fts summarize VIDEO_URL` | LLM-powered timestamped summary (single video, no indexing needed) |
| **Channel RAG** | `yt-fts llm -c CHANNEL` | Interactive Q&A over entire channel's transcripts |

These are powerful but require additional setup (yt-fts install, optional API keys for embeddings/LLM). SKILL.md should present them as "if you have yt-fts, you can also..." — not as core functionality.

## Evals

```json
{
  "skill_name": "youtube-clip",
  "evals": [
    {
      "id": 1,
      "prompt": "Find where ownership is discussed in this Rust tutorial (video ID: rQ_J9WH6CGk)",
      "expected_output": "Timestamped matches showing segments where ownership is discussed, with watch URLs",
      "assertions": [
        "Envelope has success: true",
        "At least 1 match returned",
        "Each match has watch_url with ?t= parameter",
        "Each match has download_section in *MM:SS-MM:SS format",
        "Match text contains 'ownership' (case-insensitive)"
      ]
    },
    {
      "id": 2,
      "prompt": "Generate an explorer page for this 3-hour Rust lecture (video ID: rQ_J9WH6CGk)",
      "expected_output": "A valid HTML file with heatmap, chapters, and searchable transcript",
      "assertions": [
        "Envelope has success: true",
        "output_path exists and is a valid HTML file",
        "HTML contains at least 10 chapter entries",
        "HTML contains heatmap visualization elements",
        "HTML contains timestamped transcript lines with youtube.com links"
      ]
    }
  ]
}
```

## CONFIG.yaml

```yaml
skill:
  name: youtube-clip
  version: 0.1.0
  created: 2026-04-19
  updated: 2026-04-19
  author: kevin

triggers:
  phrases:
    - "find where they discuss"
    - "search transcript"
    - "find the part about"
    - "timestamp for"
    - "clip from video"
    - "explore this video"
    - "navigate long video"
    - "longform explorer"
  keywords:
    - transcript search
    - timestamp
    - clip
    - explore video
    - heatmap
    - chapters

dependencies:
  tools:
    - Bash
  cli:
    - python3
    - jq
  pip:
    - yt-dlp
  optional_pip:
    - yt-fts

loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml

compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0
```

## Key Design Decisions

- **Two transcript paths** — yt-dlp for ad-hoc single videos (zero setup), yt-fts for indexed channel search (powerful but requires indexing). Each skill works standalone.
- **json3 subtitle format** — richest structure (word-level timestamps), parsed into sentence-level segments for usability. The merging logic is the core value-add.
- **Two output formats per match** — `?t=` for sharing/watching, `--download-sections` for extracting via yt-dlp. Both always present.
- **Longform explorer HTML** — self-contained file combining heatmap + chapters + transcript. Heatmap-per-chapter overlay answers "which part should I watch?" at a glance.
- **`--force-keyframes-at-cuts`** in download commands — slower but produces clean clip boundaries. Always suggested.
- **yt-fts as optional enhancement** — semantic search, summarization, and RAG are powerful but not required. Core functionality works with just yt-dlp.
- **Shared state contract** — accepts deep-dive JSON from youtube-search to avoid redundant metadata fetches (principle #11).
- **Invoke as `python3 -m yt_dlp`** — consistent with youtube-search and yt-dlp skill.
