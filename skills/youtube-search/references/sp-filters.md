---
name: sp-filters
description: YouTube search filter sp parameter codes (protobuf-encoded), reverse-engineered from yt-x
tags: youtube, search, filters, sp, protobuf
---

# YouTube Search Filter Codes (`sp` parameter)

These are YouTube's internal protobuf-encoded `sp` parameter values appended to search URLs.

## Upload Date

| Name  | sp Code              |
|-------|----------------------|
| hour  | EgIIAQ%253D%253D     |
| today | EgIIAg%253D%253D     |
| week  | EgIIAw%253D%253D     |
| month | EgIIBA%253D%253D     |
| year  | EgIIBQ%253D%253D     |

## Content Type

| Name     | sp Code              |
|----------|----------------------|
| video    | EgIQAQ%253D%253D     |
| movie    | EgIQBA%253D%253D     |
| live     | EgJAAQ%253D%253D     |
| playlist | EgIQAw%253D%253D     |
| short    | EgQQARgB             |
| long     | EgQQARgC             |

## Quality / Feature

| Name      | sp Code              |
|-----------|----------------------|
| 4k        | EgJwAQ%253D%253D     |
| hd        | EgIgAQ%253D%253D     |
| subtitles | EgIoAQ%253D%253D     |
| 360       | EgJ4AQ%253D%253D     |
| vr        | EgLIAQ%253D%253D     |
| 3d        | EgI4AQ%253D%253D     |
| hdr       | EgPIAQ%253D%253D     |
| local     | EgO4AQ%253D%253D     |

## Sort Order

| Name   | sp Code      |
|--------|--------------|
| newest | CAISAhAB     |
| views  | CAMSAhAB     |
| rating | CAESAhAB     |

## Usage

Append `&sp=<code>` to `https://www.youtube.com/results?search_query=<query>`.

**Note:** Multiple filters may not combine reliably. Sort + type is generally safe. Combining date + type + sort may produce unexpected results. Test combinations before relying on them.
