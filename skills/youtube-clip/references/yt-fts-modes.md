---
name: yt-fts-modes
description: Enhanced capabilities available when yt-fts is installed
tags: yt-fts, semantic-search, channel-indexing, optional
---

# yt-fts Enhanced Modes

These capabilities require `pip install yt-fts`. They are optional -- core functionality works with yt-dlp alone.

## Available Modes

| Mode | Command | What it enables |
|------|---------|----------------|
| Channel indexing | `yt-fts download CHANNEL_URL` | Index entire channel for fast repeated searches |
| Keyword search | `yt-fts search "query" -c CHANNEL` | Search across all indexed videos |
| Semantic search | `yt-fts vsearch "concept" -c CHANNEL` | Find conceptual matches via embeddings |
| Video summary | `yt-fts summarize VIDEO_URL` | LLM-powered timestamped summary |
| Channel RAG | `yt-fts llm -c CHANNEL` | Interactive Q&A over channel transcripts |

## Channel Indexing

```bash
# Index a channel (one-time, downloads all transcripts)
yt-fts download "https://www.youtube.com/@ChannelName"

# List indexed channels
yt-fts list

# Update an existing index
yt-fts update -c "Channel Name"
```

## Semantic Search (vsearch)

Requires an embedding API key (OpenAI or compatible). Finds conceptual matches, not just keywords.

```bash
yt-fts vsearch "energy conversion in cells" -c "Khan Academy" --limit 5
```

## Important Notes

- yt-fts outputs Rich terminal formatting (ANSI colors), not JSON. Parsing its output is fragile.
- For programmatic use, consider querying yt-fts's SQLite database directly.
- `vsearch` requires API keys for embedding generation.
- Channel indexing can take minutes to hours for large channels.
