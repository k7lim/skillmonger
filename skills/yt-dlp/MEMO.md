# yt-dlp - MEMO

> **Loading Trigger:** Load when encountering download errors, rate limits, or format issues.

## Edge Cases Log

### Rate Limiting / IP Bans

**Issue:** YouTube blocks after 10-20 videos or after ~30min videos.

**Resolution:**
- Always use `-t sleep` preset for bulk downloads
- Use `--cookies-from-browser firefox` to authenticate
- For persistent bans, wait 1 week or use rotating VPN

---

### Auto-Generated vs Manual Subtitles

**Issue:** `--write-subs` may return nothing if only auto-generated exist.

**Resolution:**
- Use both: `--write-subs --write-auto-subs`
- Check available with `--list-subs` first
- Prefer manual (`--write-subs`) when available, fallback to auto

---

### Subtitle Language Patterns

**Issue:** Language codes vary; `en` may miss `en-US` or `en-GB`.

**Resolution:**
- Use regex: `--sub-lang "en.*"` to match all English variants
- Use `--sub-lang all,-live_chat` for all subtitles except chat

---

### Browser Cookie Issues

**Issue:** Chromium browsers lock cookie database while open.

**Resolution:**
- Firefox/Safari work with browser open
- For Chrome/Edge/Brave: close browser first
- Alternative: export to Netscape format with browser extension

---

## Known Failure Patterns

### "Sign in to confirm you're not a bot"

- Cause: Too many requests without cookies
- Fix: `--cookies-from-browser firefox`

### "Video unavailable" in playlist

- Cause: Private/deleted videos
- Fix: `--ignore-errors` to skip and continue

### Merge fails

- Cause: ffmpeg missing or incompatible streams
- Fix: Install ffmpeg, or use `-f "best"` for pre-merged

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-01-25 | 1.0.0 | Initial | Skill created with Reddit discussion learnings |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
