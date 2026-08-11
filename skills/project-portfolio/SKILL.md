---
name: project-portfolio
description: "Decide what to work on across many parallel projects using the pj CLI, and record state so the next session starts warm. Use for \"what should I work on\", \"what have I been neglecting\", \"what did I touch recently\", \"I have tokens/time to burn\", \"which projects use X\", \"what's still open\", inventorying or triaging projects, and for recording a next step, priority, tag, or archive decision with pj note/prioritize/tag/archive. Also covers pj next, pj list, pj census, and pj ports. For finding or reading a specific past conversation, use project-juggler instead."
metadata:
  short-description: Choose what to work on next and record project state with pj
---

# Project Portfolio

`pj` tracks 150+ projects on this machine. This skill is about the portfolio
view — which ones deserve attention now — and about writing back the small
amount of state that makes that judgement possible next time.

Reading is safe. Writing annotations changes stored state and needs user intent,
with one standing exception noted under **Closing the loop**.

## The scoring gap

`pj next` ranks projects with a fixed weighting:

| Factor | Weight | Source |
|---|---|---|
| priority | 0.35 | `pj prioritize` |
| recency | 0.25 | session timestamps |
| momentum | 0.20 | sessions in last 7 days |
| staleness | 0.10 | last touched 3–7 days ago |
| actionable note | 0.10 | `pj note` |

**45% of that comes from annotations, and on this machine they are empty** —
every project sits at priority `none`, and there are no notes. So `pj next`
currently degrades to a recency ranker and explains nearly every project with
"recently active."

Two consequences. Treat raw `pj next` output as a starting point, not a verdict.
And when you learn something durable about a project's priority or next step,
write it down — that is what makes the ranking mean anything later.

## Reading the portfolio

```bash
pj next --limit 5 --pretty            # scored recommendations, with reasons
pj list --state active --limit 50     # active stale dormant blocked archived
pj list --sort priority --limit 50    # or last-active (default), name
pj list --tag backend
pj list --detail --limit 20           # + hours worked, models used (slower)
pj ports --pretty                     # local listening ports mapped to projects
```

**Always check `meta.total` against what you got back.** `pj list` defaults to
`--limit 20` against ~155 projects, and silently returns the first page. Page
with `--offset`, or raise `--limit`, before concluding a project is not there.

Current shape of the corpus, for calibration: ~26 active, ~32 stale, ~96 dormant.
Dormant is the default resting state, not a problem to fix.

## Answering "what should I work on"

`pj next` alone is thin. Combine three signals:

1. `pj next --limit 10` — the heuristic's opinion.
2. `pj list --state stale` — the genuinely at-risk set. Stale means touched
   recently enough to still be live in the user's head, but drifting.
3. The actual last session for the top candidates — `pj chats <project> --limit 3`,
   then read one. A project's score cannot tell you whether it stopped at a clean
   boundary or mid-refactor. That distinction usually decides which to pick.

Then recommend a small number with a concrete first action each, not a ranked
dump of the whole list.

For a time- or budget-boxed sprint ("I have tokens expiring in 12 hours"),
filter for projects that can absorb parallel work and have an obvious entry
point, and say plainly which ones cannot.

## Answering "which projects use X"

This is a portfolio question but a search implementation. Use
`pj search <terms> --limit 50 | jq -r '.data[] | "\(.name)\t\(.path)"'` to get
candidates, then confirm on disk — session mentions prove discussion, not use.

## Closing the loop

The annotation commands, all writes under `PJ_DATA_DIR` (`~/.local/share/pj`):

```bash
pj note <project> "next: wire the retry path into the client"
pj note <project> "blocked: waiting on upstream token scopes"
pj prioritize <project> <high|medium|low|none>
pj tag <project> <tag>
pj archive <project>
```

Notes are append-only events; `pj list` surfaces the latest as `latest_note`.
A note starting with **`blocked:`** flips the project's state to blocked, which
removes it from `pj next` entirely — precise when true, damaging when careless.

**The one write worth offering unprompted:** after finishing substantive work in
a project, offer to record a next step —

> "Want me to leave a `pj note` so the next session picks up from here?"

Write it as an imperative next action, not a summary of what you did. "next:
port the remaining three handlers" is worth 10% of the score; "did some
refactoring" is worth the same 10% and helps nobody. Do not set priority or
archive on your own initiative — those are the user's calls.

## Census dashboard

`pj census` prints a JSON snapshot. The server subcommands are user-facing
actions — start one only when asked:

```bash
pj census --include-ports        # JSON snapshot, with live ports attached
pj census start                  # background server on 127.0.0.1:8765
pj census status                 # JSON: pid, url, health
pj census stop                   # graceful shutdown
```

## Gotchas

- No `--json` flag exists on any subcommand. JSON is the default; `--pretty` is
  the human layer. Omit `--pretty` when the output feeds your own reasoning.
- `pj show .` and `--project .` fail with `"No project matching '.'"`. Use
  `--here` for the current directory.
- `pj list` can lag if session files changed very recently; if the user says the
  table looks stale, that is a real known failure, not their misreading.
- Inside a sandbox, `pj` sees only that container's session files. Portfolio
  numbers computed there describe the container, not the machine.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `PJ_DATA_DIR` | `~/.local/share/pj` | annotations and cache |
| `PJ_SOURCES` | auto-detected | extra roots, `agent:path:agent:path` |
| `PJ_BACKEND` | `fs` | `cass` for the CASS SQLite backend |

Point `PJ_DATA_DIR` at a temp directory to exercise annotation writes without
touching real state.

---

## After Execution

Self-assess: did the recommendation rest on more than `pj next`'s raw ordering,
and was the portfolio actually left in a better-annotated state than it started?

Map: 5=recommended a small set with concrete first actions grounded in real
session state, and captured a next step where warranted; 4=sound recommendation,
loop not closed; 3=relayed `pj next` output with light verification;
2=unpaginated or unscoped read led to a wrong picture; 1=wrote annotations the
user did not ask for, or mis-set a `blocked:` note.

Append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"project-portfolio","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
