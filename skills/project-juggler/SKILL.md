---
name: project-juggler
description: "Recover context from past Claude Code and Codex sessions with the pj CLI: find which project discussed something, read a specific past conversation, or get a resume command. Use whenever a request leans on history older than the current session, including implicit cues — \"have we discussed this before\", \"did I already start this\", \"what did we decide\", \"I thought I'd built that\", \"reload those chats\", \"contextualize yourself first\", \"find prior chats about X\", \"what was I working on\", \"which project was that in\" — and before telling the user that something has never been built or discussed. Also on explicit pj search/show/chats/chat/resume. For picking what to work on next or recording notes, priorities, and tags, use project-portfolio instead."
metadata:
  short-description: Search and read past agent sessions with pj
---

# Project Juggler

`pj` is a read sensor over local coding-agent session files. It answers "where
did this happen, and what was said" across every project on the machine, without
a daemon or index step.

Read commands are safe to call speculatively. Reach for them without being asked:
the user's own history is usually the cheapest source of truth, and "I don't have
context on that" is almost always wrong on this machine.

## When to reach for it unprompted

- The request references work that predates this session — a decision, a URL, a
  config, an approach that was "already figured out."
- You are about to say something has not been built, tried, or discussed.
- You are starting work in a project whose recent history you have not read.
- The user asks you to pick up, resume, or continue anything.
- A plan you are writing would duplicate work that may already exist.

## Workflow

Four steps, in order. Skipping straight to a machine-wide search is the most
common way this goes wrong.

1. **Scope.** If the project is known, use `--here` (cwd) or `--project <name>`.
   Only search machine-wide when the project genuinely is the unknown.
2. **Search.** Separate terms, not quoted phrases. Widen with `--regex` or
   `--sort relevance` before giving up.
3. **Read.** Search results are leads, not answers. Open the actual conversation
   with `pj chat <session_id> --no-tools --roles user,assistant`.
4. **Cite.** Tell the user which session you drew from and offer the resume
   command, so they can verify and reopen it.

## Data it sees

Filesystem store (default): `~/.claude/projects/`, `~/.claude-*/projects/`,
`~/.codex/sessions/`, `~/.kimi/sessions/`. Full parsing exists for Claude Code
and Codex; other agents get resume templates only.

If `pj` is missing, say so — do not substitute hand-rolled greps over session
JSONL unless the user asks.

## Sensors

```bash
pj search auth middleware --limit 8         # cross-project session search
pj search --here rate limit                 # search only the project you are in
pj show <project> --sessions 5              # project detail + sessions + resume_cmd
pj chats <project> --limit 20               # session list with token/message counts
pj chat <session_id> --last 40 --no-tools   # read one conversation
pj resume <project>                         # shell command to reopen latest session
```

`<project>` is a name, path, or ID prefix. `<session_id>` accepts a prefix.
`--here` on `search` and `chats` infers the project from the working directory.

## Common mistakes

These are the four that actually recur. Each one is silent — you get an empty or
misleading result, not an error.

| Mistake | What happens | Do this |
|---|---|---|
| `pj search "pan sauce steak"` | Quoted = exact substring. **0 results.** | `pj search pan sauce steak` → 9 results |
| `pj list --json` | No such flag; prints usage and exits | JSON is already the default; `--pretty` is the opt-in |
| `pj show .` / `--project .` | `"No project matching '.'"` | `--here` is how you say "this directory" |
| Unscoped search for a known project | Scans every session file; can hang for many seconds | Scope with `--here`/`--project` first |

Two more worth knowing: search returns *projects* with nested
`matching_sessions`, so a "1 result" line can still hide the session you want;
and Codex session titles are usually boilerplate
(`<environment_context>`, `# AGENTS.md instructions for ...`), so judge Codex
hits by `snippet`, never by `title`.

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

## Out of scope

Portfolio commands — `pj next`, `pj list`, `pj ports`, `pj census`, and the
annotation writers (`note`, `tag`, `prioritize`, `archive`) — belong to the
**project-portfolio** skill. Use that one when the question is "what should I
work on" or "record this for later" rather than "what happened before."

One handoff worth making: when you finish substantive work in a project, leaving
a `pj note <project> "next: ..."` is what lets the next session start from a
next step instead of re-deriving one. See project-portfolio.

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

Self-assess this run on the standard scale: 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent.

Append one JSON line to `FEEDBACK.jsonl` in this skill directory — the copy you
are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"project-juggler","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"llm","session":"<this session's id>","schema_version":1}
```

Drop `session` if you do not know this session's id. That line is the whole
record: nothing in `CONFIG.yaml` is edited by a run.

Use `"source":"user"` when the score came from the user rather than from your
own assessment.
