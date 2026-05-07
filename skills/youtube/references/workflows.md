---
name: workflows
description: Detailed workflow steps for Find & Download, Find & Clip, and Bulk Research
tags: workflow, orchestration, commands
---

# Workflow Details

## Workflow 1: Find & Download

Use case: "Find the best trailer for each of these movies and download them."

### Steps

1. **Search** (sensor, per item):
   ```bash
   ../youtube-search/scripts/search "{title} official trailer" --limit 5 --filter views --type video
   ```
   For batch: iterate over the list. Apply rate limit escalation.

2. **Rank** (LLM): Pick the best result per item. Prefer:
   - Official channels (verified, high follower count)
   - Trailer-length duration (60-240s)
   - High view count relative to age
   - Present one pick per item with alternatives.

3. **User vets** (MANDATORY): Present picks, wait for approval. Never auto-proceed. User may say "use videos 1, 3, 5" or "search again for item 4."

4. **Download** (actuator):
   ```bash
   python3 -m yt_dlp -t sleep -o "%(title)s.%(ext)s" "URL"
   ```
   Always use `-t sleep` for bulk. Use `--cookies-from-browser firefox` if rate-limited.

## Workflow 2: Find & Clip

Use case: "Find good explainer videos, then identify clips for each sub-topic."

### Steps

1. **Search** (sensor):
   ```bash
   ../youtube-search/scripts/search "TOPIC explained" --limit 10 --subtitles-only
   ../youtube-search/scripts/search "TOPIC for students" --limit 10 --filter views
   ```
   Use `--subtitles-only` since transcripts are needed for clip search.

2. **Deep dive** (sensor, top candidates):
   ```bash
   ../youtube-search/scripts/deep-dive "VIDEO_ID"
   ```
   Save output JSON for later (bridge to youtube-clip).

3. **User vets** (MANDATORY): Present candidates with quality signals. User selects 3-5 to investigate.

4. **Get transcripts** (sensor, per selected video):
   ```bash
   ../youtube-clip/scripts/get-transcript "VIDEO_ID" --lang en
   ```

5. **Search transcripts** (sensor, per sub-topic per video):
   ```bash
   ../youtube-clip/scripts/search-transcript "SUB_TOPIC" --input transcript.json --context 30
   ```

6. **Explore** (actuator, per video):
   ```bash
   ../youtube-clip/scripts/explore "VIDEO_ID" --deep-dive-json deep-dive.json -o explore-VIDEO_ID.html
   ```

7. **Present results**: Consolidated clip table + explorer HTML links:
   ```
   | Video | Sub-topic | Timestamp | Watch URL |
   |-------|-----------|-----------|-----------|
   ```
   Plus: "Open explore-VIDEO_ID.html to navigate the full video with heatmap."

8. **(Optional) Download clips** (actuator, if user requests):
   ```bash
   python3 -m yt_dlp --download-sections "*3:45-5:12" --force-keyframes-at-cuts "URL"
   ```
   Requires ffmpeg.

## Workflow 3: Bulk Research

Use case: "Find all conference talks about X, get transcripts, find every mention of Y."

### Steps

1. **Search** (sensor, multiple queries):
   ```bash
   ../youtube-search/scripts/search "TOPIC conference talk" --limit 20 --date year --type long
   ../youtube-search/scripts/search "CONFERENCE 2025" --limit 10 --filter newest
   ```

2. **Deep dive** (sensor, candidates):
   ```bash
   ../youtube-search/scripts/deep-dive "VIDEO_ID"
   ```

3. **Get transcripts** (sensor, batch): 2-3 second pauses between videos.
   ```bash
   ../youtube-clip/scripts/get-transcript "VIDEO_ID"
   ```

4. **Search transcripts** (sensor, per term across videos):
   ```bash
   ../youtube-clip/scripts/search-transcript "SEARCH_TERM" --input transcript_N.json
   ```

5. **Compile findings** (LLM): Consolidated document with timestamped citations.
