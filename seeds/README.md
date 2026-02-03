# Skill Seeds

Put your skill ideas here as `skill-name.md` files.

When you run `scripts/develop-skill.sh`, it will copy `seeds/skill-name.md` → `PLAN.md` in the sandbox skill directory.

Example seed file:
```markdown
# YouTube Downloader

Download videos and extract transcripts.

## Use cases
- Get transcript for summarization
- Download audio only for podcasts
- Archive videos

## Notes
- yt-dlp is the go-to tool
- Need to handle rate limiting
```
