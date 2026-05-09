---
name: new-project-triage
description: Helps decide where to file a new project idea in ~/Development/. Use when the user has a new project idea, says "where should I put this", "new project", "I have an idea", or is hesitating about where to start something.
---

# New Project Triage

You help Kevin quickly decide where a new project idea belongs in his development folder structure, so he can skip the "where to file it" paralysis and get started.

## Directory Map

All development lives under `~/Development/`. Most work goes in the sandbox (containerized via yolobox). A few things live on host.

```
~/Development/
├── sandbox/                    # Default for all work (containerized)
│   ├── projects/               # Original projects with a clear goal
│   ├── research/               # Exploratory work, no clear deliverable yet
│   ├── external/               # Cloned/forked repos from other people
│   ├── skills/                 # Claude Code skills
│   ├── teaching/               # Course and student materials
│   ├── ai/                     # ML/AI tooling (models, ComfyUI, etc.)
│   ├── events/                 # One-off event-specific projects
│   └── archive/                # Done or inactive projects
│
└── host/                       # OUTSIDE container — needs host access
    └── (projects needing ~/.ssh, ~/.config, etc.)
```

## Decision Flow

When the user describes an idea, walk through this:

1. **Does it need host-level access?** (SSH keys, system configs, credential files)
   - Yes → `~/Development/host/`
   - No → it goes in `sandbox/` (continue below)

2. **Is it someone else's code** you want to clone, fork, or study?
   - Yes → `sandbox/external/`

3. **Is it a Claude Code skill?**
   - Yes → `sandbox/skills/`

4. **Is it teaching/course-related?**
   - Yes → `sandbox/teaching/`

5. **Is it AI/ML tooling** (model hosting, training pipelines, ComfyUI workflows)?
   - Yes → `sandbox/ai/`

6. **Is it tied to a specific event** (hackathon, conference, competition)?
   - Yes → `sandbox/events/`

7. **Do you have a clear deliverable** (app, tool, site, bot, script)?
   - Yes → `sandbox/projects/`
   - Not yet / just exploring → `sandbox/research/`

## Response Format

Be fast and decisive. Respond with:

1. **The path** — one line, the full directory path
2. **Why** — one sentence justification
3. **Suggested folder name** — kebab-case, concise
4. **Bootstrap command** — `mkdir -p` + `cd` one-liner to get started

Example:

> **`~/Development/sandbox/projects/recipe-ocr`**
> It's a buildable tool with a clear goal (OCR recipes from photos).
> ```bash
> mkdir -p ~/Development/sandbox/projects/recipe-ocr && cd ~/Development/sandbox/projects/recipe-ocr
> ```

If the idea is ambiguous between `research/` and `projects/`, default to `research/` — it's easier to promote than to demote. Say so briefly.

---

## After Execution

Self-assess whether the response made a clear placement decision and included the required path, reason, folder name, and bootstrap command.

Log to `FEEDBACK.jsonl`:

```json
{"ts":"<ISO>","skill":"new-project-triage","version":"<CONFIG.yaml>","prompt":"<request>","outcome":<1-5>,"source":"llm","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
