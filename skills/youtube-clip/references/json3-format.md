---
name: json3-format
description: Structure and parsing of YouTube's json3 subtitle format
tags: subtitles, json3, parsing, segments
---

# json3 Subtitle Format

YouTube's json3 subtitle format is the richest available via yt-dlp, providing word-level timestamps.

## Structure

```json
{
  "events": [
    {
      "tStartMs": 640,
      "dDurationMs": 5200,
      "segs": [
        {"utf8": "Hello "},
        {"utf8": "and ", "tOffsetMs": 1200},
        {"utf8": "welcome", "tOffsetMs": 2400}
      ]
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `tStartMs` | int | Event start time in milliseconds |
| `dDurationMs` | int | Event duration in milliseconds |
| `segs[].utf8` | string | Word/fragment text |
| `segs[].tOffsetMs` | int | Offset from event start (optional, 0 if absent) |

## Word Timestamp Calculation

```
word_start_ms = event.tStartMs + seg.tOffsetMs
word_end_ms = word_start_ms + event.dDurationMs
```

## Merging Strategy

Raw json3 is word-level -- unusable for search. Merge into ~10-15s chunks using:

1. **Punctuation boundaries** (`. ! ?`) -- only when transcript has punctuation (manual subs)
2. **Timing gaps > 1 second** -- primary signal for auto-generated captions
3. **Max chunk duration ~15 seconds** -- hard ceiling to prevent runaway segments

Auto-generated captions often lack punctuation entirely. The merge logic detects this (punctuation density < 2% of words) and relies on timing gaps instead.

## Manual vs Auto Subtitles

| Property | Manual | Auto-generated |
|----------|--------|----------------|
| Punctuation | Yes | Rarely |
| Accuracy | High | Variable |
| File pattern | `VIDEO.LANG.json3` | `VIDEO.LANG.auto.json3` |
| Availability | Uncommon | Most videos |

yt-dlp command to fetch both: `--write-subs --write-auto-subs --sub-format json3`

Prefer manual when both exist.

## Language Code Matching

Use `--sub-lang "en.*"` to match `en`, `en-US`, `en-GB`, etc. Exact `--sub-lang en` may miss regional variants.
