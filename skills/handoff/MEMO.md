# Handoff - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or needs historical context. Do not load proactively.

## Edge Cases Log

First compaction 2026-08-31 over 169 traces (all `source: llm`, none failing, 21 scored 4). Every mark-down was a "minor omission"; the entries below are the root causes those omissions share, plus the strategies the 5s kept naming. Evidence cites the trace's `ts`, `date` or `timestamp` as written.

### lead-with-traps: open with the next action and the do-not list
- status: graduated (v1.0.1)
- root cause: SKILL.md said what to include but not what to put first, so a handoff could bury the one paragraph a fresh agent most needs — the trap that already cost time, the artifact not to touch, the research not to redo — under state it can recover elsewhere.
- evidence: FEEDBACK 2026-08-17 (what_worked: "leading with the negative instruction ... the single most useful paragraph"), 2026-08-04T21:52:00Z, 2026-07-30T00:00:00-10:00 (two traces: "do-not-repeat", "do-not-run-installer"), 2026-08-13T14:30:00-10:00, 2026-08-17T05:10:00Z, 2026-08-17T22:40:00Z, 2026-08-19T00:00:00Z, 2026-08-23T00:00:00Z ("elevated to STEP 0"), 2026-08-21T21:43:00, 2026-08-21T00:00:00, 2026-08-27T21:30:00-10:00, 2026-08-18T00:00:00Z
- workaround: open the doc with the single next action and a do-not list (traps, do-not-touch, do-not-redo) with the reason for each; everything the artifacts already hold comes after, by reference.
- skill change: "Lead with the single next action and with what the next agent must not do ..." (in SKILL.md since v1.0.1).

### absolute-resolvable-paths: references a fresh session cannot open
- status: graduated (v1.0.1)
- root cause: "reference by path or URL" did not say the path must resolve from a fresh session; session scratchpads, pasted-image paths and relay logs are session-scoped, and a relative path assumes a cwd the next agent does not have.
- evidence: FEEDBACK 2026-07-25T00:00:00Z (docked: "scratchpad-relative references to r1-r3.md"; the sibling trace the same day: "absolute scratchpad paths used, fixing the placeholder-reference flaw docked in the prior iteration"), 2026-08-27T00:35:15.624165Z (docked: "only project-relative"), 2026-08-30T18:45:00Z (docked: "paste paths ephemeral"), 2026-08-05T01:05:00Z ("raw relay log was ephemeral"), 2026-08-24T00:00:00Z ("exact scratchpad path + the garbled-path incident")
- workaround: cite absolute paths; when the only copy of something lives in a scratchpad, paste buffer or relay log, copy it beside the handoff (or to a durable repo path) first and cite that.
- skill change: "Use absolute paths a fresh session can open; a session scratchpad or a pasted-image path dies with the session ..." (in SKILL.md since v1.0.1).

### verified-vs-inferred: facts the session could not check, handed over as premises
- status: graduated (v1.0.1)
- root cause: nothing asked the writer to separate what the session observed from what it read off code, commits or the user's premise, so a fact the session could not confirm (unreadable sibling dir, 403'd parts site, behaviour described from commits, a method from a prior session not recovered) reads like a known one.
- evidence: FEEDBACK 2026-08-30T00:00:00Z, 2026-08-30T22:18:56Z, 2026-08-30T23:59:00Z, 2026-08-31T08:16:45Z (all four scored 4 for an unverified load-bearing fact); 2026-07-25T00:00:00Z ("verified-vs-inferred split preserved"), 2026-08-19T00:00:00Z ("which AniList values are approximate vs verified"), 2026-08-12T18:30:00Z ("inherited paper judgements must be re-verified"), 2026-08-17T23:35:52Z ("pinned the decisive fact before writing rather than handing over the user's premise unverified"), 2026-08-21T21:43:00 ("flagged facts to re-verify")
- workaround: verify the decisive fact before writing when it is cheap; otherwise label it unverified and make verifying it the first task rather than a premise.
- skill change: "Say which facts this session verified and which it inferred or could not check ..." (in SKILL.md since v1.0.1).

### durable-vs-session-split: multi-screen handoffs carrying content that belongs in the repo
- status: open
- root cause: when a session has externalised nothing, the handoff becomes the only home for technique notes, specs and working agreements that outlive the session, and grows past a screen even though it duplicates nothing.
- evidence: FEEDBACK 2026-08-16T10:52:00Z, 2026-08-18T00:00:00Z, 2026-08-18T00:30:00Z (all "complete but multi-screen", scored 4); 2026-08-11T00:00:00Z (split into handoff + docs/credential-isolation.md), 2026-08-13T14:30:00-10:00 (spec and technique notes written to repo files first, handoff references them), 2026-07-21T00:00:00Z (two traces: "persistent docs vs temp handoff separation")
- workaround: before writing, move anything the next-but-one agent will also need (specs, technique notes, gotchas about the environment) into a repo doc or the issue tracker, then reference it; keep the handoff to what only this session knew.
- skill change: if the length mark-downs keep arriving: "When a section would outlive this session, write it to the repo and reference it; the handoff carries only what this session alone knew."

### live-state-refresh: state that goes stale after the handoff is written
- status: open
- root cause: a snapshot of open issues, an artifact URL, or time-sensitive data is presented as current, so the next agent may act on it without refreshing.
- evidence: FEEDBACK 2026-08-19T22:30:00Z (scored 4: "next agent still needs bd ready for live open-issue state"), 2026-08-27T00:35:15.624165Z (scored 4: "did not re-verify the artifact URL is still live"), 2026-08-21T21:43:00 ("front-loaded a refresh-first instruction (data is time-sensitive)"), 2026-08-16T10:45:00-10:00 ("board is source of truth")
- workaround: name the source of truth (the tracker, the live URL, the data feed) and tell the next agent to read it first; do not enumerate what it will re-derive.
- skill change: none yet; four traces, two of them mark-downs. Overlaps verified-vs-inferred and may fold into it.

### suggested-skills-exist-where-run: skills named that the next agent cannot invoke
- status: open
- root cause: a suggested skill can be a project skill, a user skill, or absent in the next agent's environment, and the section is easy to write from memory.
- evidence: FEEDBACK 2026-08-17 (what_to_improve: "managing-d2l-shells is a project skill at .claude/skills/, not a user skill, and would have been easy to cite wrongly"), 2026-08-13T14:30:00-10:00 ("kept to the four that matter"), 2026-08-05T01:05:00Z (each HITL item mapped to a specific grilling skill with a reason)
- workaround: check where each suggested skill lives before naming it, say why it applies, and keep the list to the ones the next task needs.
- skill change: none; one mark-down-adjacent trace, the rest are praise.

### caller-named-destination: the temp-dir default vs a destination the caller sets
- status: open
- root cause: SKILL.md fixes the destination to the OS temp directory, but a calling workflow or the user sometimes names one (ralph-orchestrator's `.ralph/orchestrator-handoff.md`; "copy it into docs/handoffs/"; "handoff AND durable md"), and every such run wrote where asked with no loss.
- evidence: FEEDBACK 2026-05-30 (six traces) and 2026-05-31 (four traces), all `.ralph/orchestrator-handoff.md`; 2026-06-11 (copied into `docs/handoffs/`); 2026-08-11T00:00:00Z (handoff plus committed doc). The `.ralph/` path is ralph-orchestrator's mechanism; if that skill grows a wiki entry for its handoff contract, this entry should point at it.
- workaround: when the user or the calling skill names a destination, write there; the temp directory is the default, not a rule.
- skill change: none; no run was harmed, and the wording change is a clarification rather than a behaviour fix.

---

## Learnings (Graduated from Past Iterations)

- v1.0.1 (2026-08-31): `lead-with-traps`, `absolute-resolvable-paths`, `verified-vs-inferred` — see the entries above for evidence and the exact SKILL.md wording.

---

## Known Failure Patterns

No failing trace (outcome 1 or 2) in 169 runs. The recurring mark-downs are the open entries in the Edge Cases Log.

Trace-shape note for the next Maintainer: 50 of the 169 traces carry no `outcome` or `prompt` field (the score sits in `score`, `self_assessment` or `self_score`; the request in `task`, `args` or `invocation`). They predate the format-2 epilogue and the brief's mean covers only the 119 that conform. That is the epilogue's mechanism, not this skill's, so it is not a pattern here.

---

## Iteration Log

| Date | Version | Change Type | Description | Patterns |
|------|---------|-------------|-------------|----------|
| 2026-05-26 | 1.0.0 | Initial | Imported and normalized for skillmonger deployment | - |
| 2026-08-31 | 1.0.1 | Compaction | First compaction: 169 traces (none failing, mean 4.8) root-caused into seven patterns; three graduated into SKILL.md as one sentence each (lead with next action and do-not list; absolute, session-independent paths; verified vs inferred facts). Four stay open with their evidence. | lead-with-traps, absolute-resolvable-paths, verified-vs-inferred |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- `durable-vs-session-split` — graduate if length mark-downs continue after v1.0.1.
- `live-state-refresh` — watch whether it recurs independently of `verified-vs-inferred`.
- `suggested-skills-exist-where-run`, `caller-named-destination` — clarifications; graduate only on new evidence.
