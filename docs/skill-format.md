# Skill File Format Reference

This document describes the file format for skillmonger skills.

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
| `schema_version` | int | Always 1 (for future compatibility) |

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
