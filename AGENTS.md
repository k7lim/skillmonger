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

Under skill format 1 each feedback entry increments `iteration_count` in CONFIG.yaml by hand. Under format 2 the epilogue is rendered by `scripts/render-epilogue.sh` from the CONFIG `evaluation:` block, says nothing about `iteration_count`, and the count is derived when traces are harvested. Either way compaction is recommended at the threshold (default 15) **or** once three or more failing traces (outcome 1-2) have arrived since `last_compaction`, whichever comes first. The rule lives in `scripts/lib/compaction.py`; `log-feedback.sh`, `harvest-feedback.sh` and `compact-memo.sh` all call it rather than each computing it. See `docs/skill-format.md`.

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
| `seed-skill.sh` | Capture idea to `seeds/` | nothing |
| `develop-skill.sh` | Scaffold in sandbox (copies seed → PLAN.md) | `templates/DESIGN.md`, `templates/sandbox-brief.md` |
| `skill` | Show current skill status and next step | `~/.skillmonger-state` |
| `ship-skill.sh` | Promote sandbox skill to `skills/` | `validate-skill.sh` |
| `validate-skill.sh` | Check structure, frontmatter, and skill format | nothing |
| `render-epilogue.sh` | Print a skill's format-2 "After Execution" epilogue | skill's CONFIG.yaml |
| `migrate-format-2.sh` | Move a skill from format 1 to format 2 | `render-epilogue.sh` |
| `deploy-skill.sh` | Install skills, link host tool directories, and copy into SRT agent homes | `validate-skill.sh`, `harvest-feedback.sh`, `lib/deploy-targets.sh` |
| `undeploy-skill.sh` | Remove deployed symlinks and installed copies | nothing |
| `sync-skill-back.sh` | Pull deployed changes back to source | nothing |
| `log-feedback.sh` | Record feedback entry | skill's CONFIG.yaml, `lib/compaction.py` |
| `harvest-feedback.sh` | Union traces from every deployed copy into `skills/`, derive `iteration_count` | `lib/deploy-targets.sh`, `lib/harvest.py`, `lib/compaction.py` |
| `analyze-feedback.sh` | Summarize feedback trends | skill FEEDBACK.jsonl files |
| `compact-memo.sh` | Print the Maintainer's brief for one skill's MEMO.md | `harvest-feedback.sh`, `lib/compact_memo.py`, `lib/compaction.py` |
| `install-hooks.sh` | Install git pre-push hook | `hooks/pre-push` |
| `adopt-skill.sh` | Vendor an external skill and scaffold it | `scripts/lib/upstream.py` |
| `check-upstream.sh` | Report upstream/local drift for adopted skills | `scripts/lib/upstream.py` |
| `sync-upstream.sh` | Pull upstream changes into an adopted skill | `scripts/lib/upstream.py` |

## What NOT to Edit

- `vendor/` — External repos. Changes get overwritten.
- `.claude/skills/` — Deployed symlinks. Edit source in `skills/` instead.
- `~/.claude-yolobox/skills/`, `~/.codex-yolobox/skills/` — Deployed copies for SRT agents. Re-deploy from `skills/` to update.
- `~/.pi/agent/skills/` — Deployed copies for Pi on both host and SRT. Re-deploy from `skills/` to update.
- `skills/remotion/references/` — Sourced from upstream remotion-dev/remotion.
- `FEEDBACK.jsonl` files — Append-only. Use `log-feedback.sh` to add entries in
  the repo; `harvest-feedback.sh` appends the ones agents wrote into deployed
  copies. A deployed copy's FEEDBACK.jsonl is the one file agents are meant to
  write to (ADR 0002); everything else under a deploy target is still off limits.

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
# Write seed in skillmonger
echo "idea" > seeds/my-skill.md

# Scaffold in sandbox (copies seed → PLAN.md)
develop-skill.sh

# Check where you left off
scripts/skill status

# Agent builds it in sandbox
cd ~/Development/sandbox/skills/my-skill
claude "Read BRIEF.md and build the skill"

# Promote to skills/
scripts/ship-skill.sh ~/Development/sandbox/skills/my-skill
```

`BRIEF.md` is a disposable task brief with interface contracts and build specs — not long-term context. It is not shipped. `PLAN.md` carries the seed idea and any detailed plan into the sandbox.

**To adopt a skill from someone else's repo:** Follow
`docs/adopting-external-skills.md`. Short version:

```bash
scripts/adopt-skill.sh LaurentiuGabriel/learnscape skills/isometric-explainer
# adapt SKILL.md only; keep references/ and assets/ verbatim
scripts/ship-skill.sh ~/Development/sandbox/skills/isometric-explainer
```

Adopted skills record provenance in `CONFIG.yaml:upstream` (authoritative) and
`SOURCE.md` (generated header + zone table). `scripts/check-upstream.sh` reports
drift; `scripts/sync-upstream.sh <skill>` applies upstream changes, fast-forwarding
`verbatim` files and blocking on `adapted` ones.

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

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
