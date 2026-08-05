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

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-08-04 | 1.0.0 | Initial | Skill created against pj 0.3.1; scoped to implemented commands only |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
