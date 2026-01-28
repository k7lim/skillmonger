# Skillmonger

Framework for building reusable AI agent skills. Skills deploy to Claude Code, Codex, and Gemini.

## Key Concepts

**Quad-file architecture** per skill:
- `SKILL.md` — Core instructions (required). Has YAML frontmatter (`name`, `description`).
- `CONFIG.yaml` — Metadata, triggers, compaction settings (recommended).
- `MEMO.md` — Edge cases log, loaded on failure (recommended).
- `FEEDBACK.jsonl` — Execution outcome log, append-only (auto-created on first use).

**Feedback loop:** Every SKILL.md ends with an "After Execution" epilogue. The mechanism should match the output type:
- **Programmatic:** An evaluate script checks output deterministically. Preferred when possible.
- **Qualitative:** Epilogue asks the user a skill-specific question (not generic "rate 1-5"), or the agent self-assesses against defined criteria on alternate runs.
- **Delayed:** Don't log at execution time. Come back when ground truth is available and log with `log-feedback.sh --source user`.
- **Hybrid:** Evaluate script for verifiable parts, qualitative ask for the rest.

Each feedback entry increments `iteration_count` in CONFIG.yaml. At threshold (default 15), compaction is recommended.

**Deterministic vs natural language split:** Scripts produce data (JSON), prompts interpret meaning. `check-prereqs` is the pre-execution bookend, `evaluate` is the post-execution bookend. See Skill Script Interface below for language options.

**Cross-skill dependencies:** Skills can reference other skills. Document with `dependencies.skills` in CONFIG.yaml. The dependent skill's check-prereqs script should detect availability and the SKILL.md should provide fallback guidance when the dependency is missing.

## Directory Layout

```
skills/              # Skill source of truth (edit here)
scripts/             # Framework tooling (shared across all skills)
templates/           # DESIGN.md, sandbox-brief.md for sandbox workflow
docs/                # skill-format.md reference
hooks/               # Git pre-push validation hook
vendor/              # External repos (gitignored content, don't edit)
.claude/skills/      # Deployed skills (symlinks, don't edit directly)
```

## Scripts and Their Relationships

| Script | Purpose | Depends on |
|--------|---------|------------|
| `new-skill.sh` | Create skill in `skills/` | `validate-skill.sh` |
| `seed-skill.sh` | Capture idea to sandbox research dir | nothing |
| `develop-skill.sh` | Scaffold in sandbox with BRIEF.md + PLAN.md | `templates/DESIGN.md`, `templates/sandbox-brief.md` |
| `ship-skill.sh` | Promote sandbox skill to `skills/` | `validate-skill.sh` |
| `validate-skill.sh` | Check structure and frontmatter | nothing |
| `deploy-skill.sh` | Symlink to tool directories | `validate-skill.sh` |
| `log-feedback.sh` | Record feedback entry | skill's CONFIG.yaml |
| `analyze-feedback.sh` | Summarize feedback trends | skill FEEDBACK.jsonl files |
| `compact-memo.sh` | Guide MEMO.md compaction | skill's CONFIG.yaml, FEEDBACK.jsonl |
| `install-hooks.sh` | Install git pre-push hook | `hooks/pre-push` |

## What NOT to Edit

- `vendor/` — External repos. Changes get overwritten.
- `.claude/skills/` — Deployed symlinks. Edit source in `skills/` instead.
- `skills/remotion/references/` — Sourced from upstream remotion-dev/remotion.
- `FEEDBACK.jsonl` files — Append-only. Use `log-feedback.sh` to add entries.

## Validation Constraints

Enforced by `validate-skill.sh` and `hooks/pre-push`:
- `name` in SKILL.md frontmatter: lowercase, hyphens, numbers only. Max 64 chars. No leading/trailing/consecutive hyphens. Must match directory name.
- `description`: max 1024 chars.
- SKILL.md word count warning at >5000 words.
- CONFIG.yaml must be valid YAML (if PyYAML available).

## Working with Skills

**To modify an existing skill:** Edit files directly in `skills/<name>/`. Run `scripts/validate-skill.sh skills/<name>/` after changes. Deploy with `scripts/deploy-skill.sh`.

**To create a new skill (direct):** Run `scripts/new-skill.sh` (interactive). It generates SKILL.md (with epilogue), CONFIG.yaml, and MEMO.md.

**To create a new skill (sandbox):** For skills that need design work or iteration:

```
seed-skill.sh my-skill "idea"           # capture idea → sandbox/research/
develop-skill.sh                         # scaffold → sandbox/projects/skills/
                                         #   copies seed → PLAN.md
                                         #   generates BRIEF.md (task brief)
                                         #   generates DESIGN.md, script templates
cd ~/Development/sandbox/.../my-skill
claude "Read BRIEF.md and build the skill"   # yolo agent builds it
scripts/ship-skill.sh <sandbox-path>     # promote to skills/
```

`BRIEF.md` is a disposable task brief with interface contracts and build specs — not long-term context. It is not shipped. `PLAN.md` carries the seed idea and any detailed plan into the sandbox.

**To add evaluation:** Create an evaluate script in `skills/<name>/scripts/` (any language — see Skill Script Interface). It reads skill output from stdin, outputs JSON with `outcome` (1-5), `note`, `checks`, and `source` fields. See `skills/centers-of-excellence/scripts/evaluate.sh` as the exemplar. Not all skills need this — see feedback patterns above.

## Skill Script Interface

Scripts in a skill's `scripts/` directory are executables that follow a standard I/O contract. Any language — the contract is the interface, not the file extension.

**`check-prereqs`** — run before execution, reports readiness:
- Input: none (reads system state)
- Output (stdout): `{"ready": bool, "checks": [...], "context": {...}}`
- Exit: 0 always (readiness is in the JSON, not the exit code)

**`evaluate`** — run after execution, scores the output:
- Input: skill output via stdin or file argument (`$1` / `sys.argv[1]`)
- Output (stdout): `{"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}`
- Exit: 0 on successful evaluation (even if outcome is low)

**Language choice:**
- Bash (`.sh`) — default scaffold, works everywhere, good for command checks and grep-based evaluation
- Python (`.py`) — for API calls, library access, HTML parsing, structured diffing
- Any executable — Node, Ruby, compiled binary. Just make it executable and follow the contract.

The SKILL.md epilogue references the actual filename. Scaffolding generates `.sh`; replace with another language if the skill needs it.

## Common Patterns

- Bash scripts use `set -euo pipefail` and resolve their own `SCRIPT_DIR`/`PROJECT_ROOT`.
- Python scripts use `#!/usr/bin/env python3` and `import sys, json`.
- Interactive framework scripts use `read -rp` for prompts.
- Framework scripts that modify CONFIG.yaml try python3+PyYAML first, fall back to sed.

## Testing Changes

```bash
# Validate all skills (same as pre-push hook)
for d in skills/*/; do scripts/validate-skill.sh "$d"; done

# Test feedback pipeline
scripts/log-feedback.sh <skill> --outcome 4 --prompt "test" --source user
scripts/analyze-feedback.sh
```
