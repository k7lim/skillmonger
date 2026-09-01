# yell-at-me - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

Written during development; `evidence: manual` means no trace has shown it yet.

### name-per-home: onboarding repeats in a sandbox home
- status: open
- root cause: the name is stored under `$HOME`, and an SRT or yolobox sandbox runs the deployed copy with its own `$HOME`, so the first run there finds no name.
- evidence: manual
- workaround: answer the one question once per home, or export `YELL_AT_ME_NAME` in the sandbox environment; `check-prereqs.sh` reads the variable first.

### name-creep: the yell form leaks into progress lines
- status: open
- root cause: once the mode is on, a name in caps is an easy way to mark anything as important, and every extra use makes the real demands harder to spot.
- evidence: manual
- workaround: the yell form belongs on yell lines only; a turn with no demand ends "Nothing needed from you." with no name.

### prompt-covers-the-yell: a blocking prompt that hides the text before it
- status: open
- root cause: the pre-call yell assumes the harness shows the last text above its prompt; a harness that clears or overlays the screen for a permission dialog hides it.
- evidence: manual
- workaround: when the call returns and the human still has to act, yell again in the landing zone; a yell they never saw does not count as the same demand yelled twice.

### notification-not-sent: the push tool reports it skipped
- status: open
- root cause: a push-notification tool skips when the human is at the terminal or the channel is off; the skill cannot know which in advance.
- evidence: manual
- workaround: treat "not sent" as expected, say nothing about it, and rely on the text yell.

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

_None logged yet_

---

## Iteration Log

| Date | Version | Change Type | Description | Patterns |
|------|---------|-------------|-------------|----------|
| 2026-09-01 | 0.1.0 | Initial | Built from `seeds/yell-at-me.md`: onboarding via check-prereqs/set-name, landing-zone placement, yelling summary, push-notification escalation | - |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- A placement lint (`scripts/lint-yells`) only if traces show yells landing in the wrong place while the demands themselves are right.
