---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Lead with the single next action and with what the next agent must not do: traps that already cost time, work not to redo, artifacts not to touch, and why. That is the content no other artifact holds.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead. Use absolute paths a fresh session can open; a session scratchpad or a pasted-image path dies with the session, so copy anything only it holds next to the handoff before referencing it.

Say which facts this session verified and which it inferred or could not check. A load-bearing fact that is unverified is the next agent's first task, not a premise.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

---

## After Execution

Self-assess: Could a fresh agent continue from the handoff without rereading the full conversation, while avoiding duplicated artifacts and secrets?

Map: 5=complete and concise handoff, 4=usable with minor omissions, 3=needs some reconstruction, 2=unclear or bloated, 1=unsafe or unusable.

Append one JSON line to `FEEDBACK.jsonl` in this skill directory — the copy you
are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"handoff","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"llm","session":"<this session's id>","schema_version":1}
```

Drop `session` if you do not know this session's id. That line is the whole
record: nothing in `CONFIG.yaml` is edited by a run.

Use `"source":"user"` when the score came from the user rather than from your
own assessment.
