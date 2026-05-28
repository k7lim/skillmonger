---
name: video-research
description: Provider-neutral video research facade using sm-video for search, probing, transcripts, comments, site discovery, and dry-run-gated media actuators.
---

# Video Research

Use this skill when you need a provider-neutral video research workflow across YouTube, BiliBili, or future video providers. The agent-facing contract is the local `scripts/sm-video` CLI. It wraps upstream video tooling behind one JSON envelope, hardened inputs, normalized command metadata, and a clear sensor/actuator split.

## Migration Position

Prefer `sm-video` for new cross-platform video research workflows as each command becomes available. Existing `youtube`, `youtube-search`, `youtube-clip`, and direct `yt-dlp` workflows remain compatibility workflows until migration tickets explicitly replace them, so preserve their behavior when using or documenting legacy YouTube-only paths.

## Command Surface

Run commands from this skill directory or invoke the script by path:

```bash
skills/video-research/scripts/sm-video --describe --pretty
skills/video-research/scripts/sm-video search --provider youtube --query "topic" --limit 10 --offset 0 --pretty
skills/video-research/scripts/sm-video probe --provider youtube --url "https://www.youtube.com/watch?v=VIDEO_ID" --fields id,title,uploader,duration
skills/video-research/scripts/sm-video comments --provider youtube --url "https://www.youtube.com/watch?v=VIDEO_ID" --limit 200 --offset 0
```

Current YouTube comments support:

```bash
skills/video-research/scripts/sm-video comments --provider youtube --url "URL" --limit N --offset N --sort top|new --query "term" --fields id,text,author,like_count
```

Sensors are read-only and safe to run after normal prerequisite checks:

- `search`
- `probe`
- `transcript`
- `comments`
- `sites`

Actuators can write files or perform heavier media operations. They must be dry-run gated by the agent workflow before execution:

- `download`
- `clip`
- `explore`

Before any actuator non-dry-run execution is added or used, get explicit user approval, run the command once with `--dry-run`, present the dry-run plan, and only then run the non-dry-run command if the user approves that specific plan.

## Contract

Every `sm-video` command path returns the standard envelope:

```json
{
  "success": false,
  "data": [],
  "meta": {
    "source": "yt-dlp",
    "provider": "youtube",
    "latency_ms": 1,
    "schema_version": 1,
    "error": {
      "code": "not_implemented",
      "message": "search is validated but not implemented yet"
    }
  }
}
```

Boundary validation failures also use the envelope. `meta.error` is always an object with `code` and `message`.

## Prerequisites

Run:

```bash
skills/video-research/scripts/check-prereqs.sh
```

`check-prereqs.sh` follows the Skill Script Interface directly and does not use the `sm-video` envelope. It reports `yt-dlp` as required and `ffmpeg` as optional, with `required_for` capabilities.

For read-only workflows, `ffmpeg` is optional. It is required for clip extraction, audio-only output, media merge/remux, recoding, subtitle embedding, and chapter operations.

## Guardrails

- Use only the `yt-dlp` executable path when live provider operations are implemented.
- Do not call `python3 -m yt_dlp`.
- Reject invalid providers at the boundary.
- Reject control characters in string inputs.
- Reject embedded `?` or `#` in resource identifiers.
- Reject percent-encoded resource names.
- Reject absolute output paths and traversal paths for actuators.
- Unknown `--fields` entries fail with `meta.error.code` set to `invalid_field`.
- Actuator commands must include `--dry-run` before future execution.

## After Execution

For scaffold and contract changes, self-assess whether:

- `sm-video --describe` accurately lists all sensors and actuators.
- Boundary validation returns structured envelopes.
- `check-prereqs.sh` exits 0 and reports required/optional tools.
- No live provider calls were implemented before the contract is approved.

Log feedback with:

```bash
scripts/log-feedback.sh video-research --outcome <1-5> --prompt "<brief prompt>" --source llm
```
