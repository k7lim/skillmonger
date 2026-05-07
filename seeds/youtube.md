# youtube

Orchestrator skill that combines youtube-search, youtube-clip, and yt-dlp into end-to-end YouTube research and curation workflows.

## SKILL.md Frontmatter

```yaml
---
name: youtube
description: >
  All-in-one YouTube research and curation. Combines youtube-search (find and
  rank videos), youtube-clip (search transcripts, extract timestamps, generate
  explorer pages), and yt-dlp (download) into end-to-end workflows. Use when
  the task chains finding, inspecting, clipping, or downloading YouTube content
  — e.g., "find trailers for these movies and download them," "find good
  explainer videos and identify the best clips on each sub-topic," or "search
  conference talks for mentions of X."
---
```

## Problem

The three YouTube skills each solve a piece of the puzzle:
- **youtube-search**: Find videos and assess quality
- **youtube-clip**: Search inside videos for specific moments
- **yt-dlp**: Download videos, audio, and subtitles

But the real user workflow chains them: find → inspect → clip → download. Without an orchestrator, the user manually invokes each skill and pipes context between them. This SKILL.md gives the agent the playbook for chaining them.

## Architecture

**SKILL.md only. No scripts.** (Engineering principle #10: no agent infrastructure.)

The agent reads this SKILL.md and chains commands from the sub-skills. The SKILL.md documents workflows, sensor/actuator classification, rate limiting, and dependency checks. The agent IS the orchestration layer — this skill just gives it the knowledge.

## Sensor/Actuator Map

| Command | Skill | Type | Side effects |
|---------|-------|------|-------------|
| `scripts/search` | youtube-search | **sensor** | none |
| `scripts/deep-dive` | youtube-search | **sensor** | none |
| `scripts/evaluate` | youtube-search | **sensor** | none |
| `scripts/get-transcript` | youtube-clip | **sensor** | none (temp files cleaned up) |
| `scripts/search-transcript` | youtube-clip | **sensor** | none |
| `scripts/explore` | youtube-clip | **actuator** | writes HTML file |
| `python3 -m yt_dlp` | yt-dlp | **actuator** | writes media files |

**Rule:** Sensors are safe to call speculatively. Actuators require user approval before execution.

## Workflows

### Workflow 1: Find & Download

**Use case:** "Find the best trailer for each of these 15 movies and download them."

**Steps:**

1. **Search** (sensor, per item):
   ```bash
   ../youtube-search/scripts/search "{title} official trailer" --limit 5 --filter views --type video
   ```
   For batch: iterate over the list. Use rate limit escalation (see below).

2. **Rank** (LLM): For each item, pick the best result. Prefer:
   - Official channels (verified, high follower count)
   - Trailer-length duration (60-240 seconds)
   - High view count relative to age
   - Present one pick per item with alternatives.

3. **User vets** (interactive): **ALWAYS pause here.** Present the picks and wait for approval. Never auto-proceed past vetting. The user may say "use videos 1, 3, 5" or "search again for item 4."

4. **Download** (actuator):
   ```bash
   python3 -m yt_dlp -t sleep -o "%(title)s.%(ext)s" "URL"
   ```
   Always use `-t sleep` for bulk downloads. Use `--cookies-from-browser firefox` if hitting rate limits.

### Workflow 2: Find & Clip

**Use case:** "I'm teaching photosynthesis to 8th graders. Find good explainer videos, then identify clips for each sub-topic: light reactions, Calvin cycle, chloroplast structure."

**Steps:**

1. **Search** (sensor):
   ```bash
   ../youtube-search/scripts/search "photosynthesis explained" --limit 10 --subtitles-only
   ../youtube-search/scripts/search "photosynthesis for students" --limit 10 --filter views
   ```
   Use `--subtitles-only` since we'll need transcripts for clip search.

2. **Deep dive** (sensor, top candidates):
   ```bash
   ../youtube-search/scripts/deep-dive "VIDEO_ID"
   ```
   Get chapters, heatmap, captions info. Save output JSON for later.

3. **User vets** (interactive): Present candidates with quality signals. **ALWAYS pause.** Teacher selects 3-5 to investigate further.

4. **Get transcripts** (sensor, per selected video):
   ```bash
   ../youtube-clip/scripts/get-transcript "VIDEO_ID" --lang en
   ```

5. **Search transcripts** (sensor, per sub-topic per video):
   ```bash
   ../youtube-clip/scripts/search-transcript "light reactions" --input transcript.json --context 30
   ../youtube-clip/scripts/search-transcript "Calvin cycle" --input transcript.json --context 30
   ```

6. **Explore** (actuator, per video — pass deep-dive JSON):
   ```bash
   ../youtube-clip/scripts/explore "VIDEO_ID" --deep-dive-json deep-dive.json -o explore-VIDEO_ID.html
   ```

7. **Present results** (LLM): Consolidated clip table + explorer HTML links:
   ```
   | Video | Sub-topic | Timestamp | Watch URL |
   |-------|-----------|-----------|-----------|
   | Amoeba Sisters | Light reactions | 3:45-5:12 | [link] |
   | CrashCourse | Calvin cycle | 6:30-8:45 | [link] |
   ```
   Plus: "Open explore-VIDEO_ID.html to navigate the full video with heatmap."

8. **(Optional) Download clips** (actuator, if user requests):
   ```bash
   python3 -m yt_dlp --download-sections "*3:45-5:12" --force-keyframes-at-cuts "URL"
   ```

### Workflow 3: Bulk Research

**Use case:** "Find all conference talks about WebAssembly from 2024-2025, get transcripts, and find every mention of 'component model'."

**Steps:**

1. **Search** (sensor, multiple queries):
   ```bash
   ../youtube-search/scripts/search "WebAssembly conference talk" --limit 20 --date year --type long
   ../youtube-search/scripts/search "WASM summit 2025" --limit 10 --filter newest
   ../youtube-search/scripts/search "WebAssembly component model talk" --limit 10
   ```

2. **Deep dive** (sensor, candidates):
   ```bash
   ../youtube-search/scripts/deep-dive "VIDEO_ID"
   ```

3. **Get transcripts** (sensor, batch):
   ```bash
   ../youtube-clip/scripts/get-transcript "VIDEO_ID"
   ```
   For batch transcript downloads, pace with 2-3 second pauses between videos.

4. **Search transcripts** (sensor, per term across videos):
   ```bash
   ../youtube-clip/scripts/search-transcript "component model" --input transcript_1.json
   ../youtube-clip/scripts/search-transcript "component model" --input transcript_2.json
   ```

5. **Compile findings** (LLM): Consolidated document with timestamped citations:
   ```
   ## "Component Model" mentions across WebAssembly talks

   ### Talk 1: "The Future of WASM" by Speaker X (2025-03-15)
   - [12:30] "The component model is going to change how we think about..."
   - [28:45] "When we integrate the component model with..."
   Watch: https://youtube.com/watch?v=XXX&t=750

   ### Talk 2: ...
   ```

## Rate Limit Escalation

| Scale | Pacing |
|-------|--------|
| 1-5 searches | no sleep needed |
| 6-20 searches | `--sleep-requests 1` on search script |
| 20+ searches | `--sleep-requests 2`, process in batches of 5, 10-second pause between batches |
| Transcript downloads | 2-3 second pause between videos |
| Media downloads | always use `-t sleep` preset |
| If bot-blocked | add `--cookies-from-browser firefox` |

Rate limiting is more conservative for batch operations because they send many sequential requests. Each sub-skill handles its own rate limiting for single invocations, but the orchestrator is responsible for pacing across batch iterations.

## Dependency Check

Before starting any workflow, verify sibling skills exist:

```bash
ls ../youtube-search/scripts/search ../youtube-clip/scripts/get-transcript 2>/dev/null
```

**Graceful degradation:**
- If only youtube-search is deployed: Find & Download works. Find & Clip and Bulk Research are unavailable — tell the user to deploy youtube-clip.
- If only youtube-clip is deployed: transcript search works for known video IDs, but no search capability — tell the user to deploy youtube-search.
- If yt-dlp skill is not available: search and clip work, but download steps are unavailable — suggest manual download commands.

## Parallelization with Agent Tool

For batch operations, use the Agent tool to dispatch parallel work:

**Batch search:** One agent per batch slice (5 items per agent) with rate limiting within each agent.

**Batch transcript download:** One agent per video. Each agent runs get-transcript and search-transcript for all sub-topics on that video.

Always respect rate limits within each agent — parallelization doesn't bypass YouTube's bot detection.

## Gotchas

- **ALWAYS pause for user vetting.** Never auto-proceed from search results to downloads or clip extraction. The human must approve which videos to work with.
- **Search results are non-deterministic.** The same query can return different results. For batch operations, run all searches before presenting results to the user.
- **`:subtitles` filter is critical for clip workflows.** If the user wants to search transcripts, pre-filter search results to only captioned videos. No captions = no transcript = clip skill can't help.
- **deep-dive JSON is the bridge between skills.** When going from search → clip, save the deep-dive output and pass it to explore via `--deep-dive-json`. This avoids redundant metadata fetches.
- **yt-dlp `--download-sections` needs ffmpeg.** If ffmpeg isn't installed, clip downloads will fail. The yt-dlp skill's MEMO.md documents this — suggest `-f "best"` as a fallback.
- **Rate limit escalation is per-session, not per-skill.** If you've been searching heavily, slow down even for transcript downloads.

## Evals

```json
{
  "skill_name": "youtube",
  "evals": [
    {
      "id": 1,
      "prompt": "Find the best official trailer for each of these movies and download them: The Iron Giant, Spirited Away, The Princess Bride, Howl's Moving Castle, My Neighbor Totoro",
      "expected_output": "Agent should search for trailers, present picks, pause for user approval, then download approved trailers",
      "assertions": [
        "Agent runs youtube-search search for each movie",
        "Agent presents results and waits for user approval before downloading",
        "Agent uses yt-dlp with -t sleep for downloads",
        "Agent does NOT auto-download without user confirmation"
      ]
    },
    {
      "id": 2,
      "prompt": "Find good videos about the water cycle for 6th graders, then identify clips about evaporation and condensation",
      "expected_output": "Agent should search, vet with user, then search transcripts for sub-topics",
      "assertions": [
        "Agent runs youtube-search search with educational intent",
        "Agent uses --subtitles-only filter",
        "Agent pauses for user to select videos before transcript search",
        "Agent runs youtube-clip search-transcript for each sub-topic",
        "Agent presents a consolidated clip table with watch URLs"
      ]
    }
  ]
}
```

## CONFIG.yaml

```yaml
skill:
  name: youtube
  version: 0.1.0
  created: 2026-04-19
  updated: 2026-04-19
  author: kevin

triggers:
  phrases:
    - "youtube research"
    - "find and download"
    - "find youtube videos"
    - "youtube clips for"
    - "curate youtube"
    - "movie trailers for"
    - "find videos about"
    - "search conference talks"
  keywords:
    - youtube
    - find and download
    - curate
    - trailers
    - clips
    - research videos

dependencies:
  tools:
    - Bash
    - Agent
  cli:
    - python3
    - jq
  pip:
    - yt-dlp
  sibling_skills:
    - youtube-search
    - youtube-clip
    - yt-dlp

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

- **No scripts** — pure SKILL.md orchestration. The agent reads the workflows and chains commands from sub-skills. No orchestration code to maintain. (Principle #10)
- **Always interactive vetting** — never auto-download or auto-clip without user approval. The vetting step is mandatory in every workflow.
- **Rate limit escalation** — batch operations use more conservative sleep than single queries. Documented in the orchestrator, not hidden in sub-skills.
- **Graceful degradation** — if only youtube-search is deployed, search-only workflows still work. Clip and download features show as unavailable with clear instructions to deploy missing skills.
- **Agent parallelization** — batch search and batch transcript download use parallel agents, each respecting rate limits internally.
- **Shared state contract** — deep-dive JSON flows from youtube-search to youtube-clip's explore. The orchestrator manages this data handoff.
