# Video Research Direction

## Decision

Build a provider-neutral, agent-facing video research facade named `sm-video`. The project/skill concept can use the descriptive name `video-research`, but the executable should avoid generic names like `video`, `media`, `yt`, `vid`, `clipper`, or `videoctl`.

`yt-dlp` remains the primary upstream backend. The new facade does not replace `yt-dlp`; it wraps it with a stable contract for agents: one JSON envelope, normalized schemas, input hardening, pagination, field selection, and dry-run behavior for file-writing commands.

## Why

Raw `yt-dlp` is powerful, but not agent-first:

- Output shape varies by command and extractor.
- Some current scripts call `python3 -m yt_dlp`, which fails on this machine while the `yt-dlp` executable works.
- Comment extraction, BiliBili, danmaku, generic metadata probing, and cross-provider search are available upstream but not exposed through the current skills.
- Agent workflows need predictable JSON, bounded output, validation, and clear sensor/actuator boundaries.

## Naming

Use:

- CLI executable: `sm-video`
- Skill/project name: `video-research`
- Compatibility workflow skill: keep `youtube`

Avoid:

- `video`, `media`, `yt`, `vid`, `viddy`, `clipper`, `clipctl`, `videoctl`, `av`, `ytx`, `vidkit`, `mediakit`

Those names are either too generic or already used in relevant package/tool ecosystems.

## Architecture

```
agent -> skill instructions -> sm-video facade -> yt-dlp -> video providers
```

The facade owns:

- Command schemas and `--describe`
- One response envelope
- Input validation
- Provider normalization
- Field masks and pagination
- Dry-run for actuators
- Output path sandboxing
- Prerequisite checks

The upstream backend owns:

- Extractor support
- Platform-specific metadata fetching
- Media downloading
- Subtitle/comment extraction
- Format handling

## Sensors And Actuators

Sensors are safe to run without approval:

```bash
sm-video search --provider youtube --query "..." --limit 10 --offset 0
sm-video search --provider bilibili --query "..." --limit 10 --offset 0
sm-video probe --url URL --fields id,title,uploader,duration,view_count,comment_count
sm-video transcript --url URL --lang en --prefer manual
sm-video comments --url URL --sort top --limit 200
sm-video sites --query bilibili
```

Actuators write files or perform heavier media operations and must support `--dry-run`:

```bash
sm-video download --url URL --mode video|audio|metadata|subtitles --output-dir ./downloads --dry-run
sm-video clip --url URL --start 10:15 --end 12:30 --output-dir ./clips --dry-run
sm-video explore --url URL --output ./explore.html --dry-run
```

## Envelope

Every command returns the same shape on success and failure:

```json
{
  "success": true,
  "data": [],
  "meta": {
    "source": "yt-dlp",
    "provider": "youtube",
    "query": "dune trailer",
    "limit": 10,
    "offset": 0,
    "count": 10,
    "latency_ms": 842,
    "schema_version": 1
  }
}
```

Failure example:

```json
{
  "success": false,
  "data": [],
  "meta": {
    "source": "yt-dlp",
    "provider": "youtube",
    "error": "ffmpeg required for clipping",
    "latency_ms": 12,
    "schema_version": 1
  }
}
```

## Canonical Schemas

`VideoResult`:

```json
{
  "id": "string",
  "provider": "youtube",
  "url": "https://...",
  "title": "string",
  "uploader": "string",
  "uploader_id": "string",
  "duration": 123,
  "view_count": 1000,
  "like_count": 50,
  "comment_count": 12,
  "upload_date": "2026-05-11",
  "thumbnail": "https://...",
  "has_subtitles": true
}
```

`TimedTextSegment`:

```json
{
  "source_type": "transcript",
  "start": 12.3,
  "end": 18.2,
  "text": "string",
  "language": "en"
}
```

Allowed `source_type` values: `transcript`, `subtitle`, `danmaku`, `comment`.

`Comment`:

```json
{
  "id": "string",
  "parent": "root",
  "author": "string",
  "author_id": "string",
  "text": "string",
  "timestamp": 1710000000,
  "like_count": 10,
  "is_pinned": false,
  "author_is_uploader": false,
  "url": "https://..."
}
```

## Prerequisites

Hard requirement:

- `yt-dlp`

Tiered optional requirement:

- `ffmpeg` is required for clipping, audio extraction, merging separate streams, remuxing, recoding, embedding subtitles/metadata/thumbnails, and splitting chapters.
- `ffmpeg` is not required for read-only search, probe, comments, or transcript metadata workflows.

The local machine currently has working `yt-dlp` and `ffmpeg 8.1`. The current system `python3 -m yt_dlp` path is not reliable and should not be used by new facade code.

## First Feature

Implement YouTube comment search first:

```bash
sm-video comments --url URL --limit 200 --sort top
sm-video comments --url URL --limit 200 --sort top --query "refund"
```

This is the best first slice because it is read-only, fills a known gap, proves the envelope, and can later generalize to BiliBili comments.

## Migration Plan

1. Keep existing `youtube`, `youtube-search`, `youtube-clip`, and `yt-dlp` skills working.
2. Add `sm-video` as a new facade and document it with a `video-research` skill contract.
3. Use `sm-video` for new cross-platform workflows.
4. Gradually refactor existing YouTube scripts to call `sm-video` where the facade has proven coverage.
5. Let the `youtube` skill become a compatibility workflow that orchestrates `sm-video --provider youtube`.

## Guardrails

- Every command supports `--describe`.
- Every list supports `--limit`, `--offset`, and `--fields`.
- All outputs use the envelope.
- Inputs reject control characters.
- Provider is an enum at the boundary.
- Resource identifiers reject embedded query fragments where an ID is expected.
- Output paths are canonicalized and sandboxed to the current working directory unless explicitly approved.
- Actuators support `--dry-run`.
- Downloads and clips require user approval through the skill workflow.
- Readers ignore unknown fields; writers preserve unknown config fields.

## Deferred Work

- BiliBili search/probe/comments/danmaku support.
- Generic provider detection from URL.
- Niconico timed comments as `TimedTextSegment`.
- MCP surface generated from the same command schema.
- Characterization tests against representative `yt-dlp` outputs for YouTube and BiliBili.
