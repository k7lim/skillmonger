# project-juggler - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

- `pj resume` breaks the JSON contract: it prints a bare `cd ... && claude --resume <id>`
  shell line. Piping it to `jq` fails. Every other command returns an envelope.
- Errors still exit 1 with a well-formed envelope: `pj show nonexistent` →
  `{"success": false, ..., "meta": {"error": "No project matching 'nonexistent'"}}`.
- Search snippets make responses large. A three-result `pj search` was ~39 KB;
  a machine-wide search took ~8 s. Project fields with `jq`, and narrow with
  `--project`/`--here` when the project is already known.
- `pj chat` returns `data` as an object with a `messages` array, not a bare list.
  `pj show` also returns an object; `list`/`search`/`chats`/`next`/`ports` return lists.
- Codex session titles are often boilerplate (`<environment_context>`,
  `# AGENTS.md instructions for ...`), so match on `snippet` rather than `title`
  when scanning Codex results.
- Quoted phrases fail silently and badly. Measured 2026-08-10:
  `pj search "pan sauce steak"` → `No results`; `pj search pan sauce steak` → 9
  results. Same words, same corpus. Nothing in the output hints that quoting was
  the problem.
- `pj show .` and `--project .` return `"No project matching '.'"`. `.` is not a
  path the project matcher resolves; `--here` is the cwd affordance.

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

- Inventing `pj health` or `PJ_REMOTE_URL`. Both appear in the project-juggler
  plan docs (`docs/plans/pj-sandbox-agent-access.md`) but neither is implemented
  in the CLI as of v0.3.1, and the auth policy behind them is an open decision
  (`pj-55m.1`). Teaching them would make agents run commands that error out.
- Treating empty sandbox results as proof that no such work exists. Sandbox `pj`
  usually cannot see host session files.
- Inventing `pj list --json` (or `--json` on any subcommand). No such flag —
  argparse prints usage and exits non-zero. JSON is already the default output;
  `--pretty` is the opt-in for human rendering. Observed repeatedly in 2026-06
  and 2026-07 sessions, followed by hand-rolled Python to re-parse output that
  was already JSON.
- Stopping at `pj search` results without opening a session. Search returns
  leads with snippets; the answer is usually in the conversation. Across all
  historical usage `pj chat` was invoked once, against 27 searches.
- Not paginating. `pj list` defaults to `--limit 20` against 155 projects, and
  the envelope reports the real count in `meta.total`. Check it before concluding
  a project does not exist.

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-08-04 | 1.0.0 | Initial | Skill created against pj 0.3.1; scoped to implemented commands only |
| 2026-08-10 | 1.1.0 | Refine | Modelled 1,538 historical sessions. Broadened trigger surface to implicit recall cues, added scope→search→read→cite workflow and a Common Mistakes table for the four silent failures. Moved portfolio/annotation commands out to the new project-portfolio skill. |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
