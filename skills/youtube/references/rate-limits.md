---
name: rate-limits
description: Rate limit escalation rules and pacing guidelines for batch YouTube operations
tags: rate-limit, pacing, batch
---

# Rate Limit Escalation

## Pacing Rules

| Scale | Pacing |
|-------|--------|
| 1-5 searches | no sleep needed |
| 6-20 searches | `--sleep-requests 1` on search script |
| 20+ searches | `--sleep-requests 2`, batches of 5, 10s pause between batches |
| Transcript downloads | 2-3 second pause between videos |
| Media downloads | always use `-t sleep` preset |
| If bot-blocked | add `--cookies-from-browser firefox` |

## Key Principles

- Rate limiting is **per-session, not per-skill**. Heavy searching means slower transcript downloads too.
- Each sub-skill handles its own rate limiting for single invocations; the orchestrator paces batch iterations.
- Parallelization via Agent tool does NOT bypass YouTube's bot detection. Each parallel agent must still respect rate limits internally.

## Parallel Batch Strategy

- **Batch search**: One agent per batch slice (5 items per agent) with rate limiting within each agent.
- **Batch transcript download**: One agent per video. Each agent runs get-transcript + search-transcript for all sub-topics on that video.
