---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch.

---

## After Execution

Self-assess against this skill's own bar:

> Did it implement what the spec said, or what it assumed the spec meant?

**Scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

Append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"implement","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
