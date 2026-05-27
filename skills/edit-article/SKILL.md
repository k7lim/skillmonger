---
name: edit-article
description: Edit and improve articles by restructuring sections, improving clarity, and tightening prose. Use when user wants to edit, revise, or improve an article draft.
---

1. First, divide the article into sections based on its headings. Think about the main points you want to make during those sections.

Consider that information is a directed acyclic graph, and that pieces of information can depend on other pieces of information. Make sure that the order of the sections and their contents respects these dependencies.

Confirm the sections with the user.

2. For each section:

2a. Rewrite the section to improve clarity, coherence, and flow. Use maximum 240 characters per paragraph.

---

## After Execution

Ask the user: "Does the revised article preserve your meaning while making the structure and prose clearer?"

Map: yes=5, mostly=4, partially=3, no=2. Use 1 if the edit changed the intended meaning or damaged the piece.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
