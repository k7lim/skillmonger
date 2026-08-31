---
status: accepted
date: 2026-08-30
---

# Gate runs withhold the wiki; running agents still load it on failure

WikiSkill (arXiv:2608.27454) reports that giving the inference agent access
to the wiki degraded task results (63.7 to 60.9) and that the wiki's value
came from the skill proposer reading it at edit time. We adopt the blind
measurement (a gate run withholds `MEMO.md`, `memo/`, and
`loading.on_failure` so the score measures the skill alone) but keep
`loading.on_failure: MEMO.md` for real runs. The paper measured a benchmark
agent on tasks with fixed answers; a human-in-the-loop run that has already
failed is the case the wiki's workarounds exist for, and removing that rescue
path would trade observable recoveries for a purity the traces cannot yet
justify. Revisit if harvested traces show wiki-loaded runs scoring worse.

## Considered options

- Never load the wiki at runtime (the paper's setting): forces graduation to
  happen but leaves a failing run with no recourse until the next compaction.
- Tag traces with `wiki_loaded` and decide after a quarter: kept as a
  follow-up if the question resurfaces; not built now.
