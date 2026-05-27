---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

---

## After Execution

Self-assess: Did the grilling uncover the key decision branches, resolve dependencies one at a time, and give a recommended answer for each question?

Map: 5=shared understanding reached, 4=major branches covered, 3=some useful questions but incomplete, 2=scattered interview, 1=failed to stress-test the plan.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
