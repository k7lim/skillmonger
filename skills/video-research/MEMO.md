---
name: video-research-edge-cases
description: Known edge cases and contract notes for the video-research skill
---

## Scaffold Boundary

The first scaffold intentionally validates command shape but does not run live provider operations. Valid command requests return `success: false` with `meta.error.code: not_implemented`.

## Prerequisite Output

`scripts/check-prereqs.sh` follows the Skill Script Interface directly:

```json
{"ready": true, "checks": [], "context": {}}
```

Do not wrap prereq output in the `sm-video` envelope.

## yt-dlp Invocation

Future live operations must invoke the discovered `yt-dlp` executable path. Do not copy legacy `python3 -m yt_dlp` usage from older YouTube scripts.

## Field Masks

Unknown fields are contract errors, not ignored values. This keeps agents from assuming a field was omitted by upstream data when it was actually misspelled.

## Actuator Paths

Output paths are intentionally constrained to relative paths inside the current working directory. Absolute paths and traversal segments are rejected before any future file-writing command can run.
