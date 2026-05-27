# Ralph Context Handoff Drill: No Explicit Budget

Use `$ralph-orchestrator`.

Run id: `{{RUN_ID}}`
Expected handoff path: `/private/tmp/ralph-context-handoff-{{RUN_ID}}.md`
Workspace: `{{WORKSPACE}}`

Do not create a goal or explicit token budget for this run. This variant verifies the fallback rule: when no active budget tracker exists, Ralph should stop and invoke `handoff` after the fallback cycle cap or after a high-cost issue.

This is a controlled dummy run. The purpose is to verify that Ralph invokes the `handoff` skill before built-in chat compaction is needed.

Rules for this run:

- Use the deployed `ralph-orchestrator` skill.
- Do not push to any remote. This workspace is disposable and local-only.
- Work one BEADS issue at a time.
- Use exactly one subagent at a time.
- For each issue, read the full `bd show <id>` output and the referenced fixture before delegating or QA. This is intentional context pressure for the drill.
- Record `token budget: unavailable; fallback cycle cap active` in the ledger.
- Re-check the fallback guardrail before claiming each next issue.
- When the fallback guardrail says handoff is due, invoke the `handoff` skill, save the handoff at the expected path above, and stop. Do not claim another issue.
- If the chat is compacted before handoff, report that as experiment failure rather than continuing the relay.

Expected final behavior:

- Ralph stops by writing `/private/tmp/ralph-context-handoff-{{RUN_ID}}.md`.
- Some dummy issues remain in `bd ready`.
- The final assistant message says the handoff was written and that the relay stopped before built-in compaction.
