---
name: youtube
description: >
  All-in-one YouTube research and curation. Combines youtube-search (find and
  rank videos), youtube-clip (search transcripts, extract timestamps, generate
  explorer pages), and yt-dlp (download) into end-to-end workflows. Use when
  the task chains finding, inspecting, clipping, or downloading YouTube content.
---

## Prerequisites

Run `scripts/check-prereqs.sh` and parse the JSON output.

| Missing | Action |
|---------|--------|
| python3 | Install Python 3.10+ via system package manager |
| npx | Install Node.js 18+; yt-dlp is acquired lazily on use |
| jq | `brew install jq` or `apt install jq` -- offer to run |
| yt-dlp runner | Deploy the sibling `yt-dlp` skill; no global yt-dlp install |
| ffmpeg | `brew install ffmpeg` -- optional, needed for `--download-sections` clip extraction |
| youtube-search | Deploy sibling skill: find & download still works without youtube-clip |
| youtube-clip | Deploy sibling skill: transcript/clip features unavailable without it |

## Workflow Selection

| Pattern | Workflow | Requires |
|---------|----------|----------|
| Find videos + download them | **Find & Download** | youtube-search, yt-dlp |
| Find videos + extract clips/timestamps | **Find & Clip** | youtube-search, youtube-clip |
| Bulk transcript search across many videos | **Bulk Research** | youtube-search, youtube-clip |

See `references/workflows.md` for full step-by-step commands.

## Core Loop

All three workflows follow the same pattern:

1. **Search** (sensor): Run `../youtube-search/scripts/search` with appropriate queries
2. **Inspect** (sensor): Run `../youtube-search/scripts/deep-dive` on top candidates
3. **Validate**: Confirm search results are non-empty and relevant. If results look off (wrong language, unrelated content, zero-caption videos for clip workflows), adjust query and re-search before presenting.
4. **PAUSE -- present results and wait for approval.** Never auto-proceed to actuators.
5. **Act** (actuator): Download, explore, or clip per approved selections
6. **Validate output**: Confirm downloads completed (file exists, non-zero size) or transcripts returned results. Report failures explicitly.
7. **Present** consolidated results (table with timestamps, watch URLs, or file paths)

## Sensor vs Actuator Rules

Sensors (search, deep-dive, get-transcript, search-transcript) -- safe to run freely.
Actuators (explore, yt-dlp download) -- ALWAYS get approval first. See `references/sensor-actuator-map.md`.

## Rate Limiting

| Scale | Action |
|-------|--------|
| 1-5 searches | no delay |
| 6-20 | `--sleep-requests 1` |
| 20+ | `--sleep-requests 2`, batches of 5, 10s pause between |
| Transcripts | 2-3s pause between videos |
| Downloads | always `-t sleep` |
| Bot-blocked | add `--cookies-from-browser firefox` |

Full details: `references/rate-limits.md`

## Batch Parallelization

Use Agent tool to parallelize: one agent per 5-item slice (search) or one agent per video (transcripts). Each agent respects rate limits internally.

## Gotchas

- **Wrong:** Running `search-transcript` on a video without captions. **Fix:** Always use `--subtitles-only` on the initial search when the workflow will need transcripts. If deep-dive shows no captions, skip that video for clip workflows.
- **Wrong:** Relying on a single video for transcript work. Transcript fetch can fail even on videos that passed `--subtitles-only` filtering (YouTube may block the request due to geo-restrictions or bot detection). **Fix:** Always attempt transcript fetch on 2-3 candidate videos. If the first fails, try the next. Present only the ones that succeeded.
- **Wrong:** Running `explore` without passing deep-dive data, causing a redundant metadata fetch. **Fix:** Save deep-dive JSON output and pass it via `--deep-dive-json` to explore.
- **Wrong:** Installing or invoking a global `yt-dlp`, which becomes stale. **Fix:** Route every call through `../yt-dlp/scripts/run`; it checks the latest stable binary only when yt-dlp is actually used.
- **Wrong:** Using `--download-sections` without ffmpeg installed. It silently fails or errors. **Fix:** Check `check-prereqs.sh` output for ffmpeg status. If missing, fall back to full download with `-f "best"`.
- **Wrong:** Resetting rate limit pacing after switching from search to transcript download. **Fix:** Rate limits are per-session across all sub-skills. If you ran 20 searches, start transcript downloads at the conservative tier too.
- **Wrong:** Running `search` with `--filter views` for time-sensitive queries (e.g., "2025 conference talks"). **Fix:** Use `--filter newest` or `--date year` for recency-sensitive searches; `--filter views` biases toward older popular results.

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate.sh   # takes the output on stdin, or as its first argument
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

**Hybrid feedback:** Run `scripts/evaluate.sh` with a log of the session, then ask:
"Did the results match what you were looking for? Any videos missed or misranked?"

Map the answer: yes as-is = 5, minor tweaks = 4, significant gaps = 3, mostly wrong = 2, failed = 1.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"youtube","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"youtube","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
