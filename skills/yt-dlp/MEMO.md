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

### Runner Bootstrap Fails in npm Cache

**Issue:** The user's default npm cache is unwritable or contains files owned by another user.

**Resolution:** `scripts/run` sets `npm_config_cache` to its own cache-local directory. Preserve that isolation when changing the bootstrap command.

---

### Official Unix Binary Rejects Python

**Issue:** The platform-independent binary reports that Python is unsupported even though `python3` exists.

**Resolution:** yt-dlp requires Python 3.10+. The runner probes versioned executables and Homebrew Python instead of trusting the first `python3` on `PATH`.

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
| 2026-08-16 | 2.0.0 | Runtime | Replaced global/pip yt-dlp with npx bootstrap and daily nightly refresh |
| 2026-08-16 | 2.1.0 | Runtime | Moved updates to lazy stable checks performed only on actual use |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
