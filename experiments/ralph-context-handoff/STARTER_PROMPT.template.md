# Ralph Context Handoff Drill

Use `$ralph-orchestrator`.

Run id: `{{RUN_ID}}`
Expected handoff path: `/private/tmp/ralph-context-handoff-{{RUN_ID}}.md`
Workspace: `{{WORKSPACE}}`

Create a goal for this drill with `token_budget` `60000` if the runtime provides goal/budget tools.

This is a controlled dummy run. The purpose is to verify that Ralph invokes the `handoff` skill before built-in chat compaction is needed.

Rules for this run:

- Use the deployed `ralph-orchestrator` skill.
- Do not push to any remote. This workspace is disposable and local-only.
- Work one BEADS issue at a time.
- Use exactly one subagent at a time.
- For each issue, read the full `bd show <id>` output and the referenced fixture before delegating or QA. This is intentional context pressure for the drill.
- Keep the main ledger concise, but do not skip the context-budget guardrail.
- Check budget/status at Ralph relay boundaries: before claiming a ready issue, after subagent return, after QA, and after closing/committing.
- When the guardrail says handoff is due, invoke the `handoff` skill, save the handoff at the expected path above, and stop. Do not claim another issue.
- If the chat is compacted before handoff, report that as experiment failure rather than continuing the relay.

Dummy issue workflow:

1. Run `bd ready`.
2. Pick the first ready issue.
3. Read `bd show <id>` and the fixture it names.
4. Delegate the issue-local edit to one subagent.
5. QA by checking `results.log`, running the issue command from acceptance, and inspecting the diff.
6. If QA passes, close the issue with a note and commit locally.
7. Re-check the budget guardrail before reading or claiming the next issue.

Expected final behavior:

- Ralph stops by writing `/private/tmp/ralph-context-handoff-{{RUN_ID}}.md`.
- Some dummy issues remain in `bd ready`.
- The final assistant message says the handoff was written and that the relay stopped before built-in compaction.
