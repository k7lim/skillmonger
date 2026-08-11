---
name: wait-what
description: Stop. That last message did not land — re-pitch it.
disable-model-invocation: true
---

Wait — I don't understand where you've got to here. Re-pitch that: give me a little bit of context, talk in ASD-STE100 Simplified Technical English, and use the ubiquitous language from `CONTEXT.md`.

---

## After Execution

Self-assess against this skill's own bar:

> Did the re-pitch actually land, or did it repeat the same framing?

**Scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

Append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"wait-what","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
