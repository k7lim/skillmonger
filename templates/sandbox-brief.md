# {{SKILL_NAME}}

{{ONE_LINER}}

Read `PLAN.md` for the full brief. `DESIGN.md` is a thinking template — fill it out before building.

## Artifacts to Produce

### 1. Guide document (`SKILL.md`)

A markdown document that guides an AI agent through the workflow step by step. Begins with YAML frontmatter:

```yaml
---
name: {{SKILL_NAME}}
description: ...
---
```

Constraints: `name` is lowercase, hyphens, numbers only (must match directory). `description` under 1024 chars. Body under 5000 words — move supporting detail to `references/` files.

End the document with a feedback section — see "Feedback mechanism" below.

### 2. Prerequisite checker (`scripts/check-prereqs.sh`)

Checks whether required tools are installed. Any language. Output contract:

```json
{"ready": bool, "checks": [{"name": "...", "status": "ok|missing|outdated", ...}], "context": {}}
```

Exit 0 always — readiness is in the JSON, not the exit code.

The SKILL.md prerequisites section should include a remediation table:

| Missing | Action |
|---------|--------|
| [tool] | How to install, with offer to run if automatable |

For CLI tools installable via npm/pip/brew: Offer to install, don't just instruct.

### 3. Evaluator (if applicable — see "Feedback mechanism")

### 4. Reference files (`references/*.md`)

Supporting docs for topics too detailed for the guide. Each file has YAML frontmatter:

```yaml
---
name: short-name
description: What this reference covers
tags: comma, separated
---
```

### 5. Config (`CONFIG.yaml`)

**REQUIRED:** Update the scaffolded `CONFIG.yaml` with real triggers:

- `triggers.phrases`: 5-10 natural language patterns that should invoke this skill
  - Be specific: "download youtube video", not just "download"
  - Include variations: "get transcript from youtube", "extract audio from video"
- `triggers.keywords`: 3-5 semantic keywords for matching
  - Examples: `youtube`, `transcript`, `download`
- `dependencies.cli`: List required CLI tools (checked by check-prereqs.sh)

### 6. Edge case log (`MEMO.md`)

Optional — create if you encounter edge cases during development.

## Feedback mechanism

The guide document must end with instructions for how the agent logs feedback after execution. The right mechanism depends on what the skill produces.

**Choose one:**

**A. Programmatically verifiable** — the output can be checked by code (structural transforms, data formatting, rule compliance).
Write an evaluate script (`scripts/evaluate.sh`, `.py`, or any executable). Reads output from stdin or file arg. Scores 1-5. Output contract:
```json
{"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}
```
Epilogue tells the agent: run the evaluate script, log the result.

**B. Qualitative / subjective** — the output is prose, creative, or advisory. No program can judge it.
Epilogue tells the agent: ask the user a specific question about quality (not "rate 1-5" — something relevant like "Would you send this as-is?" or "Does this match your tone?"). Map their answer to 1-5 internally. On alternate runs, the agent self-assesses against criteria you define in the epilogue instead of asking.
Log with `"source": "user"` or `"source": "llm"` accordingly.

**C. Delayed verification** — correctness is only knowable later (estimates, forecasts, recommendations that play out over time).
Epilogue tells the agent: skip feedback for now. The user comes back when ground truth is available and logs with `log-feedback.sh --source user`.

**D. Hybrid** — some parts are verifiable, some aren't. Evaluate script for the verifiable parts, qualitative ask for the rest. Log both.

Include the feedback JSON format in the epilogue:
```json
{"ts":"<ISO 8601>","skill":"{{SKILL_NAME}}","version":"<from CONFIG.yaml>","prompt":"<request>","outcome":<1-5>,"note":"...","source":"script|user|llm","schema_version":1}
```
Tell the agent to append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.

## Script conventions

Scripts follow a standard I/O contract: stdin/args in, JSON to stdout. Any language.

- **Bash:** `set -euo pipefail`, resolve own dir, JSON via echo/printf
- **Python:** `#!/usr/bin/env python3`, `import sys, json`, read stdin with `sys.stdin.read()`
- **Any language:** just make the file executable and follow the I/O contract

The scaffold generates `.sh`. Replace with `.py` or any executable if the skill needs libraries or API access.

## Quality Gates

Before shipping, verify:
- [ ] SKILL.md under 100 lines (target: 60-80)
- [ ] No redundant explanations (agent has context)
- [ ] Tables over prose for structured info
- [ ] No "the user" or "the agent" - just instructions
- [ ] CONFIG.yaml triggers populated (not TODO placeholders)
