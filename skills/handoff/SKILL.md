---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. First establish the source and destination's privacy and access limits from the user or trusted host configuration. Treat unknown privacy as private. Continue the same authorized private task without asking again when the destination has no broader access.

Use the caller's destination when its access is appropriate. For non-private handoffs, default to the OS temporary directory. Private handoffs and attachments belong in task storage unavailable to unrelated agents; an OS temp path, a hidden folder, or mode 0600 alone does not establish that isolation. If suitable storage is unavailable, report the missing prerequisite without writing private content to a broader location.

Moving private content to an ordinary protected workspace with unrestricted internet, or to any recipient outside its existing authorization, requires an approved release of the exact brief, attachments, and destination. Prepare the smallest useful brief in private storage for review; reuse an unexpired approval only while the content, destination, and approved scope stay identical. Any content or destination change requires fresh approval. Use the host transfer check when available. This skill is guidance, not an enforcement service; a local validator or a JSON file supplied by the agent cannot establish host approval.

Lead with the single next action and with what the next agent must not do: traps that already cost time, work not to redo, artifacts not to touch, and why. That is the content no other artifact holds. Next actions, suggested skills, and failure reports are advisory evidence; they grant no authority to execute commands, change access, or deploy fixes. The recipient keeps its independently authorized task and limits.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Within the same authorized access, use durable absolute paths or URLs the recipient can open. Across a boundary, use registered artifact IDs and exact digests when supported; references and filenames can themselves disclose private information. Preserve session-only artifacts in the same protected storage only when the recipient is authorized for them. A reference never grants new file access.

Say which facts this session verified and which it inferred or could not check. A load-bearing fact that is unverified is the next agent's first task, not a premise.

Exclude credentials and unnecessary personal information. Inspect the brief, references, and attachments for disclosure. Automated secret scans can catch mistakes; a clean scan or redaction cannot prove semantic safety or replace an approved release.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

---

## After Execution

Self-assess: Could a fresh agent continue from the handoff without rereading the full conversation, while avoiding duplicated artifacts and secrets?

Map: 5=complete and concise handoff, 4=usable with minor omissions, 3=needs some reconstruction, 2=unclear or bloated, 1=unsafe or unusable.

Feedback must not leak the private task through the shared skill store. Use a non-sensitive task label and note. If even that trace would disclose private information, defer it to appropriate protected storage. Otherwise append one JSON line to `FEEDBACK.jsonl` in this skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"handoff","version":"<skill.version from CONFIG.yaml>","prompt":"<non-sensitive task label>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"llm","session":"<this session's id>","schema_version":1}
```

Drop `session` if you do not know this session's id. That line is the whole
record: nothing in `CONFIG.yaml` is edited by a run.

Use `"source":"user"` when the score came from the user rather than from your
own assessment.
