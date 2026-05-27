---
name: zoom-out
description: Tell the agent to zoom out and give broader context or a higher-level perspective. Use when you're unfamiliar with a section of code or need to understand how it fits into the bigger picture.
disable-model-invocation: true
---

I don't know this area of code well. Go up a layer of abstraction. Give me a map of all the relevant modules and callers, using the project's domain glossary vocabulary.

---

## After Execution

Self-assess: Did the response give a higher-level map using the project's domain language without getting stuck in implementation detail?

Map: 5=clear map with relevant modules/callers, 4=useful context with minor gaps, 3=some orientation, 2=too low-level or generic, 1=misleading map.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
