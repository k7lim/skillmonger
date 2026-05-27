---
name: ralph-orchestrator
description: Orchestrate a one-at-a-time Ralph relay over BEADS issues. Use when asked to run or manage a Ralph issue relay take the first `bd ready` issue, delegate implementation to exactly one subagent at a time, personally QA the result, close only when verified, and hand off cleanly when context or token budget is exhausted.
---

# Ralph Orchestrator

You are the orchestrator for a one-at-a-time Ralph relay over BEADS.

Your job is routing and QA. Subagents implement. Never trust a subagent's "done" claim without verification.

## Operating Rules

- Work one BEADS issue at a time.
- Use one subagent at a time.
- Keep main context lean: store summaries, not transcripts.
- Give subagents narrow, task-local context only.
- Do not include unrelated refactors or opportunistic cleanup.
- Close an issue only after your QA passes.
- If QA fails, keep the issue open and send only the issue plus QA gaps to a fresh subagent.
- If context gets bulky, stop the relay and write a fresh-orchestrator handoff.

## Token Budget

If the user provides a token budget:

1. Start a goal/budget tracker if the runtime provides one.
2. Check remaining budget after every orchestrator turn, including after subagent returns and after QA.
3. When remaining budget is zero or too low for one more safe issue cycle, invoke the `handoff` skill and stop.

For handoff, include:

- current bd issue
- current status
- latest compact summary
- QA result and gaps
- next command
- likely relevant files

## Preflight

Before starting the relay:

1. If available, run `scripts/check-prereqs.sh` from this skill.
2. Confirm `bd ready` works in the target repository.
3. Confirm there is no dirty work from unrelated user changes that would make QA ambiguous. If there is unrelated dirty work, do not revert it; record it in the ledger and avoid touching it.

## Relay Loop

Repeat until `bd ready` is empty:

1. Run `bd ready`.
2. If empty, report done.
3. Pick the first ready issue.
4. Read issue details and only the needed code/docs.
5. Spawn exactly one subagent using the packet format below.
6. On return, QA yourself:
   - inspect the diff
   - run focused tests/checks
   - verify acceptance criteria
   - check for unrelated changes
7. If QA passes:
   - close the bd issue with a concise note
   - update the ledger
   - check token budget
   - continue the loop
8. If QA fails:
   - keep the issue open
   - update the ledger with concrete gaps
   - check token budget
   - spawn a fresh subagent with only the issue and QA gaps
   - repeat QA

## Subagent Packet

Give each subagent only this shape of context:

```text
Issue: <bd id> <title>
Objective: <one concrete outcome>
Context:
- <minimum relevant facts/files>
Constraints:
- <tests/style/files to avoid>
Done means:
- implemented
- validated
- no unrelated work
Return only:
- summary, max 5 bullets
- files changed
- validation run + result
- risks/gaps
- ready for QA? yes/no
```

For repair attempts after failed QA, replace broad context with:

```text
Issue: <bd id> <title>
Objective: fix only the QA gaps below
QA gaps:
- <gap 1>
- <gap 2>
Relevant files:
- <file paths>
Constraints:
- preserve unrelated existing changes
- do not refactor outside the gaps
Return only:
- summary, max 5 bullets
- files changed
- validation run + result
- risks/gaps
- ready for QA? yes/no
```

## Orchestrator Ledger

Maintain a compact ledger in the main context. Update it after each attempt:

```text
current bd id:
attempt count:
subagent summary:
commands run:
QA pass/fail:
open gaps:
token budget:
```

Keep the ledger concise. Do not paste subagent transcripts, large diffs, or full test logs unless a failure detail is needed for the next repair packet.

## QA Standard

QA passes only when all are true:

- The acceptance criteria from the BEADS issue are satisfied.
- The diff is scoped to the issue.
- Focused validation has passed, or any skipped validation has a concrete reason.
- No unrelated user changes were reverted or overwritten.
- The repository is left in a coherent state for the next issue.

If any item is uncertain, QA fails. Send the uncertainty as a specific gap to a fresh subagent.

## Closing Issues

When QA passes, close the issue with a concise note:

```bash
bd close <id> --reason "Done: <brief verified outcome>. Validation: <checks>."
```

If the local BEADS command uses different close syntax, inspect `bd close --help` and use the repository's supported form.

## Fresh-Orchestrator Handoff

Use the `handoff` skill when:

- token budget is exhausted or too low for one more issue cycle
- context has become bulky
- the relay must stop mid-issue

The handoff must include:

- current bd issue
- current status
- latest compact summary
- QA result/gaps
- next command
- likely relevant files

---

## After Execution

Self-assess whether the relay preserved the one-issue/one-subagent constraint, verified work before closing, and left a compact enough handoff trail.

Map: 5=all ready issues handled with verified closures and concise ledger, 4=usable relay with minor skipped checks explained, 3=partial progress with clear handoff, 2=unclear QA or bloated context, 1=closed unverified work or lost track of issue state.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
