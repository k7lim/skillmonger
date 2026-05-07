---
name: youtube-search-edge-cases
description: Known edge cases and gotchas for youtube-search skill
---

## Filter Combination Limitations

The `sp` parameter codes from yt-x are single filters. Combining multiple filters (e.g., date + type + sort) in a single URL is unreliable -- YouTube's protobuf encoding may not compose additively. The search script applies only the first filter when multiple are requested. For complex filtering, run multiple searches with different single filters and merge results.

## Flat Playlist vs Full Metadata

`--flat-playlist` returns limited fields: no like_count, comment_count, chapters, heatmap, or channel_followers. Always communicate this limitation -- search gives a fast overview, deep-dive gives the full picture.

## yt-dlp Partial Failures

yt-dlp may return fewer results than requested, or fail on individual entries while succeeding on others. When exit code is non-zero but stdout contains valid JSON, the scripts still parse and return whatever data was extracted.

## Non-Deterministic Results

YouTube search results vary between runs for the same query. This is expected behavior -- YouTube personalizes and randomizes. For reproducibility-sensitive use cases, note this limitation.

## sp Code Durability

The sp filter codes are reverse-engineered from YouTube's protobuf schema. If YouTube changes their encoding, filters will silently stop working (returning unfiltered results). If filter results look wrong, re-verify codes against yt-x's source repository.

## Channel Search Restrictions

Channel-specific search (`$channel_url/search?query=$term`) may require cookies for age-restricted or region-locked channels. The current scripts do not pass cookies.

## Heatmap Availability

Heatmap data requires sufficient view count. Very new or low-view videos return null heatmap. The evaluate script handles this gracefully by skipping the heatmap check when data is absent.
