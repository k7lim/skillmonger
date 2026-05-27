---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

---

## After Execution

Self-assess: Could a fresh agent continue from the handoff without rereading the full conversation, while avoiding duplicated artifacts and secrets?

Map: 5=complete and concise handoff, 4=usable with minor omissions, 3=needs some reconstruction, 2=unclear or bloated, 1=unsafe or unusable.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
