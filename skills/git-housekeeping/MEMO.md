# git-housekeeping - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

_No edge cases logged yet._

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations._

---

## Known Failure Patterns

- Accidentally mixing generated files, lockfiles, and source behavior into one commit. Prefer separate commits unless the generated artifact is required for the behavior change.
- Treating "clean working tree" as the goal. The goal is preserved work and an accurate commit trail; unrelated local changes may remain uncommitted.

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-06-02 | 1.0.0 | Initial | Created hub skill for turning dirty Git state into atomic commits. |

---

## Compaction Queue

- (none)
