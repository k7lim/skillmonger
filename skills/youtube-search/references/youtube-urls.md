---
name: youtube-urls
description: YouTube URL patterns for search, channel browsing, and personal feeds
tags: youtube, urls, channels, feeds
---

# YouTube URL Patterns

## Search

| Type      | URL Pattern                                                              |
|-----------|--------------------------------------------------------------------------|
| Videos    | `https://www.youtube.com/results?search_query=$q&sp=EgIQAQ%253D%253D`   |
| Channels  | `https://www.youtube.com/results?search_query=$q&sp=EgIQAg%253D%253D`   |
| Playlists | `https://www.youtube.com/results?search_query=$q&sp=EgIQAw%253D%253D`   |

## Channel-Specific

| Type     | URL Pattern                  |
|----------|------------------------------|
| Search   | `$channel_url/search?query=$term` |
| Videos   | `$channel_url/videos`        |
| Streams  | `$channel_url/streams`       |
| Shorts   | `$channel_url/shorts`        |
| Podcasts | `$channel_url/podcasts`      |

## Personal Feeds (require `--cookies-from-browser`)

| Feed                | URL                                                    |
|---------------------|--------------------------------------------------------|
| Watch history       | `https://www.youtube.com/feed/history`                 |
| Liked videos        | `https://www.youtube.com/playlist?list=LL`             |
| Watch later         | `https://www.youtube.com/playlist?list=WL`             |
| Subscriptions feed  | `https://www.youtube.com/feed/subscriptions`           |
| Subscribed channels | `https://www.youtube.com/feed/channels`                |
| Playlists           | `https://www.youtube.com/feed/playlists`               |
