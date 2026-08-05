---
name: project-juggler
description: "Use the pj CLI to recover cross-project coding-agent memory: find which project or past Claude Code/Codex session discussed something, list a project's chats, read a specific conversation, get a resume command, or see what to work on next. Trigger on \"what was I working on\", \"where did I discuss X\", \"find that old chat\", \"which project was that in\", \"resume that session\", pj list/next/search/show/chats/chat/resume, or any request needing history older than the current session."
metadata:
  short-description: Search and read past agent sessions with pj
---

# Project Juggler

`pj` is a read sensor over local coding-agent session files. It answers "where
did this happen, and what was said" across every project on the machine, without
a daemon or index step.

Read commands are safe to call speculatively. Annotation commands mutate stored
state and need explicit user intent.

## Data it sees

Filesystem store (default): `~/.claude/projects/`, `~/.claude-*/projects/`,
`~/.codex/sessions/`, `~/.kimi/sessions/`. Full parsing exists for Claude Code
and Codex; other agents get resume templates only.

If `pj` is missing, say so — do not substitute hand-rolled greps over session
JSONL unless the user asks.

## Sensors

```bash
pj next --limit 5                      # scored recommendations, with reasons
pj list --state active --limit 20      # states: active stale dormant blocked archived
pj search auth middleware --limit 8    # cross-project session search
pj show <project> --sessions 5         # project detail + sessions + resume_cmd
pj chats <project> --limit 20          # session list with token/message counts
pj chat <session_id> --last 40 --no-tools   # read one conversation
pj resume <project>                    # shell command to reopen latest session
pj ports --pretty                      # local listening ports mapped to projects
```

`<project>` is a name, path, or ID prefix. `<session_id>` accepts a prefix.
`--here` on `search` and `chats` infers the project from the working directory.

## Search strategy

Search is the entry point; everything else drills into its output.

- Separate words are separate terms, OR-matched. Prefer this for exploration.
- A quoted phrase is an exact substring and misses related sessions.
- `--match all` requires every term; `--regex` enables alternations and stems.
- `--project X` or `--here` narrows before broadening.
- `--sort relevance|newest|oldest` (default `newest`).

Results are projects, each with `matching_sessions` and content `snippet`s. Work
from there to `pj chat <session_id>`.

## Output discipline

Every command but `pj resume` prints one JSON envelope:

```json
{"success": true, "data": [], "meta": {"total": 0, "latency_ms": 12}}
```

Failures are `success: false` with `meta.error`, and exit 1. `pj resume` prints a
plain shell command, not JSON. `--pretty` is a human rendering layer — omit it
when the output feeds your own reasoning.

Raw `pj search` output routinely runs tens of KB because it embeds snippets and
session lists. Project the fields you need instead of dumping it:

```bash
pj search census --limit 5 | jq -r '.data[] | "\(.name)\t\(.path)"'
pj search census --limit 5 | jq -r '.data[].matching_sessions[]? |
  "\(.session_id[0:8]) \(.agent) \(.started_at[0:10]) \(.title[0:60])"'
pj chat <id> --last 30 --no-tools --roles user | jq -r '.data.messages[].content'
```

Use `--no-tools` and `--roles user,assistant` on `pj chat` to keep transcripts
prompt-sized. `--limit`/`--offset` page `list`, `search`, and `chat`.

A machine-wide `pj search` scans many session files and can take several seconds.
Narrow with `--project`/`--here`/`--limit` when you already know the project.

## Actuators

These write annotations under `PJ_DATA_DIR` (default `~/.local/share/pj`). Only
run them when the user asked to record something:

```bash
pj note <project> "text"                        # note starting "blocked:" sets state blocked
pj tag <project> <tag>
pj prioritize <project> <high|medium|low|none>
pj archive <project>
```

`pj census serve|start|status|stop` runs a local dashboard server, which is a
user-facing action, not a sensor. Default bind is `127.0.0.1:8765`.

## Sandbox boundary

Inside a yolobox or Docker sandbox, `pj` sees only the session files present in
that container — usually a fraction of host history, or none. Absence of results
there is not evidence the work never happened.

There is no remote mode today: no `pj health`, no `PJ_REMOTE_URL`. If sandbox
`pj` comes up empty, ask the user to run the query on the host rather than
inventing a host-backed URL or token. Design work for that lives in
`docs/plans/pj-sandbox-agent-access.md` in the project-juggler repo.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `PJ_DATA_DIR` | `~/.local/share/pj` | annotations and cache |
| `PJ_SOURCES` | auto-detected | extra roots, `agent:path:agent:path` |
| `PJ_BACKEND` | `fs` | `cass` for the CASS SQLite backend |
| `CLAUDE_CONFIG_DIR` / `CODEX_HOME` | `~/.claude` / `~/.codex` | agent config dirs |

---

## After Execution

After completing the skill output, log feedback to track quality over time.

**Priority cascade:**
1. If `scripts/evaluate.sh` exists in this skill directory, run it and use the JSON result
2. Otherwise, self-assess using the scale below

**Self-assessment scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

**To log feedback**, append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"project-juggler","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
