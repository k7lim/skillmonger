# project-portfolio - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

- `pj list` returns `data` as a list; `pj show` and `pj chat` return objects.
  `next`, `ports`, `list`, `search`, `chats` all return lists.
- `pj list` default `--limit 20` against 155 projects. The true count is in
  `meta.total`. A 2026-05-11 session shows the user correcting an agent for
  exactly this: "i can tell you didn't go too far into the pj list, page into
  older projects."
- `pj next` excludes `archived` **and** `blocked` projects entirely — they are
  filtered before scoring, not ranked low. A stray `blocked:` note therefore
  makes a project vanish from recommendations with no visible explanation.
- `priority: none` scores 0.4, between `low` (0.2) and `medium` (0.6). Setting a
  project to `low` scores it *below* leaving it unset.
- Annotation writes go to `PJ_DATA_DIR/annotations.jsonl` as append-only events.
  There is no delete or edit; a correcting note is the only way to supersede.
- `pj note` accepts a project name, path, or ID prefix and echoes the resolved
  `project_id` and `project_path`. Check the echo — a fuzzy name match can land
  the note on the wrong project.

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

- Presenting `pj next` output as an answer. With every project at priority
  `none` and zero notes, 45% of the scoring weight is inert and the ranking is
  effectively recency. Reasons will read "recently active" for nearly everything.
- Inventing `--json`. Not a flag on any subcommand; JSON is already the default.
- Using `.` as a project argument. Returns `"No project matching '.'"`; `--here`
  is the cwd affordance, and only `search` and `chats` accept it.
- Treating a session mention of a tool or library as proof the project uses it.
  Confirm on disk before acting on "which projects use X."
- Writing annotations speculatively. Notes are the one write worth *offering*
  after real work; priority, tags, and archive are user decisions.
- Computing portfolio statistics inside a sandbox, where `pj` sees only that
  container's session files.

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-08-10 | 1.0.0 | Initial | Split from project-juggler v1.0.0 after modelling 1,538 historical sessions: portfolio and annotation commands had never been invoked once, so they were separated from the proven recall path and given a real workflow. Scoring-gap table measured against pj/schedule.py. |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
