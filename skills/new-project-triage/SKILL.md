---
name: new-project-triage
description: Helps decide where a new project idea belongs in ~/Development/, creates the project directory, and copies the user's original notes into it. Use when the user has a new project idea, says "where should I put this", "new project", "I have an idea", "set this up", or is hesitating about where to start something.
---

# New Project Triage

You help Kevin quickly decide where a new project idea belongs in his development folder structure, create the directory, and preserve the original notes so he can start working immediately.

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

If the idea is ambiguous between `research/` and `projects/`, default to `research/`; it is easier to promote than to demote.

## Execution Flow

1. Pick the target parent directory from the decision flow.
2. Generate a concise kebab-case folder name from the user's idea.
3. Create the project directory and write the user's original notes to `NOTES.md`.
4. Reply with the created path, the placement reason, and the notes file path.

Use `scripts/create-project.sh` for step 3:

```bash
printf '%s\n' '<original user notes>' | /path/to/new-project-triage/scripts/create-project.sh ~/Development/sandbox/projects/folder-name
```

Rules for notes:

- Preserve the user's project notes as faithfully as possible in `NOTES.md`.
- If the user pasted a note block, copy that block verbatim.
- If the request is conversational rather than a note block, write the user's project description in their own words.
- Do not overwrite an existing notes file; the script will create a timestamped `NOTES-*.md` fallback when needed.

Rules for directory creation:

- Only create directories under `~/Development/`.
- If the exact folder already exists, inspect it before proceeding. If it appears to be the same project, add a new timestamped notes file there. If it appears unrelated, choose a more specific folder name.
- Do not create a git repository, install packages, clone repos, or scaffold app code unless the user explicitly asks.

## Response Format

Be fast and decisive. After creating the directory, respond with:

1. **Created path** — one line, the full directory path
2. **Why** — one sentence justification
3. **Notes copied to** — the notes file path
4. **Next command** — `cd` one-liner

Example:

> **`~/Development/sandbox/projects/recipe-ocr`**
> It's a buildable tool with a clear goal (OCR recipes from photos).
> ```bash
> cd ~/Development/sandbox/projects/recipe-ocr
> ```

---

## After Execution

Self-assess whether the skill made a clear placement decision, created the directory, preserved the original notes, and reported the created path.

Log to `FEEDBACK.jsonl`:

```json
{"ts":"<ISO>","skill":"new-project-triage","version":"<CONFIG.yaml>","prompt":"<request>","outcome":<1-5>,"source":"llm","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
