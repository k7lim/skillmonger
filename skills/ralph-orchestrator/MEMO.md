# ralph-orchestrator - MEMO

> **Loading Trigger:** Load only when the Ralph relay encounters failures, ambiguous BEADS state, repeated QA misses, or handoff problems. Do not load proactively.

## Edge Cases Log

_No edge cases logged yet._

---

## Learnings

_Empty - patterns will graduate from iterations._

---

## Known Failure Patterns

- Subagent claims completion without validation. Treat as QA fail until independently checked.
- Context bloat from copying subagent transcripts. Keep only ledger summaries and actionable gaps.
- Repair attempts become broad refactors. Send only QA gaps to a fresh subagent.

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-05-26 | 1.0.0 | Initial | Created Ralph relay orchestrator skill |

---

## Compaction Queue

- (none)
