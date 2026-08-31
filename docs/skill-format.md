# Skill File Format Reference

This document describes the file format for skillmonger skills.

## Format version

`skill.format` is an integer under `skill:` in `CONFIG.yaml`. It versions the
**skill format** — the contract every skill in this repo follows: which files a
skill has, what its epilogue does, what its scripts emit.

```yaml
skill:
  name: my-skill
  format: 1
```

**Missing means 1.** Skills written before the field existed are format 1 and
need no edit. `scripts/validate-skill.sh` reads the field and errors on any
value it does not know; the repo is tagged `format-N.M` at each step of the
ladder, so a skill copied out of the repo carries the contract its epilogue
follows.

Do not confuse it with two neighbouring numbers:

| Number | Lives in | Means |
|--------|----------|-------|
| `skill.format` | `CONFIG.yaml` | The contract this skill follows. One integer for the whole repo. |
| `skill.version` | `CONFIG.yaml` | This skill's own semver. Bumped when its behaviour changes. Says nothing about the format. |
| `schema_version` | each `FEEDBACK.jsonl` line | The trace record shape. Always 1. |

### Format 1

Format 1 is the contract every skill was written against before the field
existed:

- **Quad-file layout:** `SKILL.md` (required), `CONFIG.yaml`, `MEMO.md`, and an
  append-only `FEEDBACK.jsonl` created on first use.
- **Hand-appended epilogue.** Each `SKILL.md` ends with an `## After Execution`
  section written by hand for that skill. There is no renderer, so the wording,
  the heading, and the JSON example drift from skill to skill.
- The epilogue tells the agent to append one trace to `FEEDBACK.jsonl` and then
  to hand-increment `compaction.iteration_count` in `CONFIG.yaml`.
- Trace fields are the seven below plus `schema_version`; `source` is documented
  as `script | llm | user` but nothing enforces it.
- Evaluation mode is implied by whether `scripts/evaluate*` happens to exist, not
  declared anywhere.

### Format 2

Format 2 is a breaking change to the epilogue contract. The quad-file layout is
unchanged; what a skill says at the end of `SKILL.md` is not.

- **The epilogue is rendered, not written.** `scripts/render-epilogue.sh
  skills/<name>/` prints it from `CONFIG.yaml`, so all skills say the same thing
  in the same words. Editing an epilogue by hand means editing the renderer or
  the skill's question, not the file.
- **No `iteration_count` instruction.** A run appends a trace and nothing else;
  `scripts/harvest-feedback.sh` derives `compaction.iteration_count` from the
  traces it brings home (ADR 0002). The word does not appear in a format-2
  epilogue.
- **The trace still goes into the skill's own directory** — the deployed copy
  the agent is running, not this repo. A deployed copy on SRT or Pi cannot reach
  `scripts/log-feedback.sh`, so no epilogue references it. `log-feedback.sh`
  remains for in-repo use (gate runs, manual logging).
- **`source` is `script`, `llm` or `user`.** Nothing else. `hybrid` and `self`
  are not sources.
- **Evaluation is declared.** `evaluation.mode` says how the skill is scored
  instead of leaving it to be inferred from a filename.

Migrate a format-1 skill with `scripts/migrate-format-2.sh [--dry-run]
skills/<name>/`. It lifts the skill's own question out of the old epilogue,
renders the new one, and writes the CONFIG keys below. It is idempotent: a skill
already at format 2 is left alone, so hand fixes survive a re-run.

It treats the epilogue as a *section* — `## After Execution` to the next `## `
heading or end of file — cuts that section out, and appends the rendered
epilogue at end of file, so every `SKILL.md` ends with its epilogue and any
section that used to follow the old one survives. A `SKILL.md` with no
`## After Execution` heading is named and skipped with a non-zero exit rather
than gaining a second epilogue.

It derives `evaluation.mode` from what the skill already has: **hybrid** when
an evaluate script exists *and* the old epilogue carried a question of its own,
**programmatic** when the script exists and there was no question, and
**qualitative** otherwise. A mode already declared in `CONFIG.yaml` wins. The
hybrid default exists because most skills with an evaluate script also ask the
user something, and flattening them to programmatic would throw that question
away. Prose *about* the evaluator reads as a question to the migrator, so a
skill that documents its evaluator at length lands on hybrid and wants a hand
correction to programmatic.

#### The evaluation block

```yaml
skill:
  format: 2
evaluation:
  mode: programmatic     # programmatic | qualitative | delayed | hybrid
  script: scripts/evaluate.sh   # required for programmatic and hybrid
  blind: true            # gate runs withhold the wiki (ADR 0003)
  tolerance: 0.5         # mean-drop tolerance before a run counts as a regression
  runner: claude         # reserved; codex later
  script_emits_outcome: true    # optional, default true
  script_usage: scripts/evaluate.sh <project-dir>   # optional
```

| Mode | Epilogue |
|------|----------|
| `programmatic` | Run `evaluation.script`, copy its `outcome`, `note` and `checks` into the trace, `source: script`. |
| `qualitative` | Ask the skill's own question, then log `source: llm` (or `user` when the user answered). |
| `delayed` | Do not score at execution time; come back when ground truth exists and log `source: user`. |
| `hybrid` | The script part, then the question. Two traces, one per source. |

`script_emits_outcome: false` marks an evaluator whose JSON carries no `outcome`
this skill can be scored by — writing-voice-coach's `evaluate.py` scores the text
the user brought in, not the critique the skill produced. The rendered epilogue
then runs the script for evidence and routes the score to self-assessment.

`script_usage` overrides the command line the epilogue shows. The documented
contract is "skill output on stdin or as the first argument"; an evaluator that
takes something else (a project directory, a saved JSON file) says so here
rather than letting the epilogue state something untrue.

`validate-skill.sh` under format 2 requires `evaluation.mode` to be one of the
four, and for `programmatic` and `hybrid` requires `evaluation.script` to exist
and be executable.

## Directory Structure

```
skills/my-skill/
├── SKILL.md              # Core instructions (required)
├── CONFIG.yaml           # Metadata & triggers (recommended)
├── MEMO.md               # Edge cases log (recommended)
├── FEEDBACK.jsonl        # Execution feedback log (auto-created)
├── references/           # Supporting docs (optional)
└── scripts/              # Deterministic helpers (optional)
    ├── evaluate.sh       # Post-execution scoring (optional)
    └── check-prereqs.sh  # Prerequisite verification (optional)
```

## SKILL.md (Required)

The core instructions file. Must start with YAML frontmatter.

```markdown
---
name: my-skill
description: What this skill does AND when to use it. Max 1024 chars.
---

# My Skill

[Role description. Instructions. Workflow. Examples.]

---

## After Execution

[Feedback epilogue - see Feedback section below]
```

**Frontmatter requirements:**

| Field | Constraints |
|-------|-------------|
| `name` | Lowercase, hyphens, numbers only. Max 64 chars. No leading/trailing/consecutive hyphens. Must match directory name. |
| `description` | Max 1024 chars. Describe what it does AND when to use it. |

**Size guidance:** Keep under 500 lines / 5000 words. Move details to `references/`.

## CONFIG.yaml (Recommended)

Extended metadata for the tri-file system.

```yaml
skill:
  name: my-skill
  version: 1.0.0
  created: 2026-01-14
  updated: 2026-01-14
  author: your-name

triggers:
  phrases:
    - "phrase that triggers this skill"
  keywords:
    - keyword1

dependencies:
  tools:
    - WebSearch  # if needed

loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml

compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0

budget:
  metadata_max: 100
  skill_max: 5000
  memo_max: 2000
```

**Compaction fields:**
- `cycle_threshold`: Number of iterations before compaction is recommended (default 15)
- `iteration_count`: Auto-incremented by feedback logging. Reset to 0 after compaction.
- `last_compaction`: Date of last compaction (set during compact-memo.sh)

## MEMO.md (Recommended)

Edge cases and learnings. Loaded on failure or when historical context is needed.

```markdown
# my-skill - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues.

## Edge Cases Log

### [Descriptive Title]

**Issue:** [What went wrong]
**Resolution:** [How to handle it]

---

## Learnings (Graduated from Past Iterations)

_Patterns will graduate from iterations._

---

## Known Failure Patterns

_None logged yet._

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-01-14 | 1.0.0 | Initial | Skill created |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
```

## FEEDBACK.jsonl (Auto-created)

Append-only log of execution outcomes. One JSON object per line.

```json
{"ts":"2026-01-26T14:30:00Z","skill":"my-skill","version":"1.0.0","prompt":"user's request","outcome":4,"note":"","source":"llm","schema_version":1}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `ts` | string | UTC ISO 8601 timestamp |
| `skill` | string | Skill name |
| `version` | string | Skill version from CONFIG.yaml |
| `prompt` | string | The user's original request |
| `outcome` | int 1-5 | 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent |
| `note` | string | Brief note (especially useful for scores != 4) |
| `source` | string | `script` (deterministic), `llm` (self-assessment), or `user` (manual) |
| `schema_version` | int | Always 1. It versions the record shape, not the skill format; format 2 adds optional fields rather than changing the shape. |

**Optional trace fields** (format 2). Every reader tolerates fields it does not
know, so these are added where they are known and omitted otherwise:

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Id of the session this run came from, when the agent knows it. Points at the transcript; never contains it. |
| `checks` | object | The evaluate script's `checks` object, copied through unchanged. |
| `gate` | bool | `true` when the trace came from a gate run rather than a real run. |
| `fixture` | string | The fixture the gate run used. Only meaningful with `gate: true`. |

**Harvest:** agents run the *deployed copy* of a skill, and its epilogue
appends the trace there, not here — deployed copies cannot reach this repo
(ADR 0002). `scripts/harvest-feedback.sh [skill]` unions every deployed copy's
FEEDBACK.jsonl into `skills/<name>/FEEDBACK.jsonl`: existing lines are never
rewritten, new ones are appended in timestamp order (a trace is new when its
(skill, ts, content digest) key is unseen, so undated and same-ts runs survive), `source` is normalised
(`self` -> `llm`, `hybrid` -> `script` when the trace carries `checks` else
`llm`, missing -> `llm`), `version` is left as written, and unparseable lines
are skipped with a warning. It is idempotent, and `deploy-skill.sh` runs it
before it removes a deployed copy. Harvest also derives
`compaction.iteration_count` from the traces since `last_compaction`, so
nothing has to increment it by hand.

**Source reliability:** `script` > `user` > `llm`. Script ratings are ground truth. LLM ratings bias toward 4-5 but relative trends across versions are valid. User ratings are authoritative overrides.

**Feedback patterns:** Not all skills can be scored the same way. Choose the pattern that fits:
- **Programmatic:** An evaluate script verifies output (structural transforms, data formatting). Preferred when possible.
- **Qualitative:** Epilogue asks the user a skill-specific question or alternates between user and LLM assessment.
- **Delayed:** Don't log at execution time. Come back when ground truth is available and log with `--source user`.
- **Hybrid:** Evaluate script for verifiable parts, qualitative ask for the rest.

## Skill Scripts (Optional)

Scripts in `scripts/` are executables that follow a standard I/O contract. Any language — the contract is the interface, not the file extension.

### check-prereqs

Run before execution. Reports whether prerequisites are met.

- **Input:** none (reads system state)
- **Output (stdout):** `{"ready": bool, "checks": [...], "context": {...}}`
- **Exit:** 0 always (readiness is in the JSON, not the exit code)

### evaluate

Run after execution. Scores the skill's output deterministically.

- **Input:** skill output via stdin or file argument
- **Output (stdout):** `{"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}`
- **Exit:** 0 on successful evaluation (even if outcome is low)

```bash
# Usage:
echo "$OUTPUT" | scripts/evaluate.sh
scripts/evaluate.py output.md
```

### Language choice

| Language | Extension | When to use |
|----------|-----------|-------------|
| Bash | `.sh` | Command checks, grep-based evaluation, no dependencies |
| Python | `.py` | API calls, library access, HTML parsing, structured diffing |
| Any | — | Just make it executable and follow the I/O contract |

The scaffold generates `.sh`. Replace with another language if the skill needs it. The SKILL.md epilogue references the actual filename.

## Versioning Convention

| Change | Version bump | Example |
|--------|-------------|---------|
| Compaction (stable patterns graduated) | Patch | 1.0.0 -> 1.0.1 |
| New capability | Minor | 1.0.1 -> 1.1.0 |
| Breaking workflow change | Major | 1.1.0 -> 2.0.0 |

## Cross-Platform Compatibility

| Platform | Base Standard | Extensions |
|----------|---------------|------------|
| Claude Code | SKILL.md + frontmatter | CONFIG.yaml, MEMO.md, FEEDBACK.jsonl |
| OpenAI Codex | agentskills.io | Ignored (no breakage) |
| Antigravity (Gemini) | SKILL.md + frontmatter | Ignored (no breakage) |

Extensions don't break compatibility. Platforms that don't understand them simply ignore them.
