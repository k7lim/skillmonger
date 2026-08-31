# Skillmonger

Framework for building reusable AI agent skills. Skills deploy to Claude Code, Codex, and Gemini.

## Key Concepts

`CONTEXT.md` pins the vocabulary — trace, wiki, pattern, owner skill, deployed copy, harvest, compaction, maintainer, graduation, fixture, gate run, baseline, regression, format. Use those words; it also lists the near-synonyms to keep out.

**Quad-file architecture** per skill, one file per layer:
- `SKILL.md` — Core instructions, the executable layer (required). Has YAML frontmatter (`name`, `description`).
- `CONFIG.yaml` — Metadata, triggers, `evaluation` and `compaction` settings (recommended).
- `MEMO.md` — The skill's **wiki**: its root-caused **patterns**, loaded on failure (recommended).
- `FEEDBACK.jsonl` — **Traces**, one JSON line per run, append-only (auto-created on first use).

**Feedback loop:** every SKILL.md ends with an "After Execution" epilogue that appends one trace to the `FEEDBACK.jsonl` sitting beside it — the *deployed copy* the agent is running, not this repo, because a copy in a sandbox home or on Pi cannot reach this tree (ADR 0002). `scripts/harvest-feedback.sh` unions every deployed copy back into `skills/<name>/FEEDBACK.jsonl` and derives `compaction.iteration_count` from what it brings home, so a run edits no CONFIG field; `deploy-skill.sh` harvests before it overwrites anything. Harvest is the only way a trace written by a running agent reaches the repo.

`evaluation.mode` in CONFIG.yaml declares how a skill is scored and `scripts/render-epilogue.sh` prints the epilogue from it. The trace schema, the CONFIG block and the format-1/format-2 difference are in `docs/skill-format.md`; the four modes are:
- **Programmatic:** An evaluate script checks output deterministically. Preferred when possible.
- **Qualitative:** Epilogue asks the user a skill-specific question (not generic "rate 1-5"), or the agent self-assesses against defined criteria on alternate runs.
- **Delayed:** Don't score at execution time. Come back when ground truth is available and log with `log-feedback.sh --source user`.
- **Hybrid:** Evaluate script for verifiable parts, qualitative ask for the rest.

**Compaction:** at threshold (`cycle_threshold`, default 15 traces since `last_compaction`) or after three failing traces, compaction is due (the rule lives in `scripts/lib/compaction.py`; `log-feedback.sh`, `harvest-feedback.sh` and `compact-memo.sh` all call it). The agent takes the **Maintainer** role, root-causes the traces into patterns in the wiki, and **graduates** stable ones into SKILL.md with a version bump. `scripts/compact-memo.sh skills/<name>/` is the Maintainer's brief.

**Gate:** an edit to a programmatic or hybrid skill is kept only if a **gate run** holds. `scripts/gate-skill.sh skills/<name>/` runs the skill over the held-out prompts in its `fixtures/`, scores each with the skill's evaluate script, and writes one gate trace per fixture into the repo's FEEDBACK.jsonl. The run is blind: `MEMO.md`, `memo/` and `loading.on_failure` are withheld, so the score measures the skill alone (ADR 0003). The **baseline** is the gate traces at the previous skill version. A **regression** is any fixture more than one point below its baseline, or a mean drop past `evaluation.tolerance`; it prints a revert line and reverts nothing itself. Qualitative skills are never gated. `hooks/pre-push` gates a pushed edit to a gated skill's SKILL.md; `SKILLMONGER_SKIP_GATE=1` bypasses it.

**Deterministic vs natural language split:** Scripts produce data (JSON), prompts interpret meaning. `check-prereqs` is the pre-execution bookend, `evaluate` is the post-execution bookend. See Skill Script Interface below for language options.

**Cross-skill dependencies:** Skills can reference other skills. Document with `dependencies.skills` in CONFIG.yaml. A pattern lives only in its **owner skill's** wiki — the skill whose mechanism it describes — and a dependent skill points at it rather than copying it. The dependent skill's check-prereqs script should detect availability and the SKILL.md should provide fallback guidance when the dependency is missing.

## Directory Layout

```
skills/              # Skill source of truth (edit here)
scripts/             # Framework tooling (shared across all skills)
templates/           # DESIGN.md, sandbox-brief.md for sandbox workflow
docs/                # skill-format.md, adopting-external-skills.md, adr/
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
| `ship-skill.sh` | Move a sandbox skill into `skills/` | `validate-skill.sh` |
| `validate-skill.sh` | Check structure, frontmatter, and skill format | nothing |
| `render-epilogue.sh` | Print a skill's format-2 "After Execution" epilogue | skill's CONFIG.yaml |
| `migrate-format-2.sh` | Move a skill from format 1 to format 2 | `render-epilogue.sh` |
| `gate-skill.sh` | Run a skill blind over its `fixtures/`, compare to baseline | `log-feedback.sh`, skill's evaluate script, `fixtures/` |
| `deploy-skill.sh` | Install skills, link host tool directories, and copy into SRT agent homes | `validate-skill.sh`, `harvest-feedback.sh`, `lib/deploy-targets.sh` |
| `undeploy-skill.sh` | Remove deployed symlinks and installed copies | nothing |
| `sync-skill-back.sh` | Pull deployed changes back to source | nothing |
| `log-feedback.sh` | Write a trace from inside the repo (gate runs, manual logging) | skill's CONFIG.yaml, `lib/compaction.py` |
| `harvest-feedback.sh` | Union traces from every deployed copy into `skills/`, derive `iteration_count` | `lib/deploy-targets.sh`, `lib/harvest.py`, `lib/compaction.py` |
| `analyze-feedback.sh` | Harvest, then summarize trace trends; `--impact` groups outcomes by skill version | `harvest-feedback.sh`, `lib/impact.py`, skill FEEDBACK.jsonl files |
| `compact-memo.sh` | Brief the Maintainer for a compaction pass | `harvest-feedback.sh`, `lib/compact_memo.py`, `lib/compaction.py` |
| `install-hooks.sh` | Install git pre-push hook | `hooks/pre-push` |
| `adopt-skill.sh` | Vendor an external skill and scaffold it | `scripts/lib/upstream.py` |
| `check-upstream.sh` | Report upstream/local drift for adopted skills | `scripts/lib/upstream.py` |
| `sync-upstream.sh` | Pull upstream changes into an adopted skill | `scripts/lib/upstream.py` |

## What NOT to Edit

- `vendor/` — External repos. Changes get overwritten.
- Deployed copies — edit the source in `skills/` and re-deploy. `scripts/lib/deploy-targets.sh` is the one definition of where they live: the store at `~/.local/share/skillmonger/skills/`, the symlinks into it (`~/.claude/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/`, this repo's `.claude/skills/`), and the copies made where the store is unreachable (`~/.pi/agent/skills/`, and `.claude/skills/` + `.codex/skills/` under `$YOLOBOX_SANDBOX_HOME`, default `~/.local/share/yolobox/home`).
- `skills/remotion/references/` — Sourced from upstream remotion-dev/remotion.
- `FEEDBACK.jsonl` files — Append-only, never rewritten. `log-feedback.sh`
  writes traces in the repo; `harvest-feedback.sh` brings home the ones agents
  wrote into deployed copies. A deployed copy's FEEDBACK.jsonl is the one file
  an agent running that copy is meant to write to (ADR 0002); every other file
  in that copy is edited here, in `skills/`, and re-deployed.

## Validation Constraints

Enforced by `validate-skill.sh` and `hooks/pre-push`:
- `name` in SKILL.md frontmatter: lowercase, hyphens, numbers only. Max 64 chars. No leading/trailing/consecutive hyphens. Must match directory name.
- `description`: max 1024 chars.
- SKILL.md word count warning at >5000 words.
- CONFIG.yaml must be valid YAML (if PyYAML available).
- `skill.format`: an integer the script knows; absent means 1.
- Under format 2, the `evaluation` block: `mode` is required and is one of `programmatic | qualitative | delayed | hybrid`, and `programmatic`/`hybrid` need an `evaluation.script` that exists and is executable.

## Working with Skills

**To modify an existing skill:** Edit files directly in `skills/<name>/`. Run `scripts/validate-skill.sh skills/<name>/` after changes. Deploy with `scripts/deploy-skill.sh`.

**To create a new skill (direct):** Run `scripts/new-skill.sh` (interactive). It generates SKILL.md (with epilogue), CONFIG.yaml, and MEMO.md.

**To create a new skill (sandbox):** For skills that need design work or iteration:

```
echo "idea" > seeds/my-skill.md          # write the seed here
develop-skill.sh                         # scaffold in sandbox (seed → PLAN.md)
scripts/skill status                     # where you left off, any time
cd ~/Development/sandbox/skills/my-skill # the agent builds it there
claude "Read BRIEF.md and build the skill"
scripts/ship-skill.sh ~/Development/sandbox/skills/my-skill   # into skills/
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

**To add evaluation:** Create an evaluate script in `skills/<name>/scripts/` (any language — see Skill Script Interface). It reads skill output from stdin, outputs JSON with `outcome` (1-5), `note`, `checks`, and `source` fields. See `skills/centers-of-excellence/scripts/evaluate.sh` as the exemplar. Then point `evaluation.script` at it and re-render the epilogue. Two CONFIG keys cover the evaluators the template cannot describe: `script_usage` overrides the command line the epilogue shows when the script takes something other than the skill's output, and `script_emits_outcome: false` marks an evaluator whose `outcome` does not judge this skill's own work, which routes the score to self-assessment. Not all skills need an evaluator — see the modes above.

## Skill Script Interface

Scripts in a skill's `scripts/` directory are executables that follow a standard I/O contract. Any language — the contract is the interface, not the file extension.

**`check-prereqs`** — run before execution, reports readiness:
- Input: none (reads system state)
- Output (stdout): `{"ready": bool, "checks": [...], "context": {...}}`
- Exit: 0 always (readiness is in the JSON, not the exit code)

**`evaluate`** — run after execution, scores the output:
- Input: skill output via stdin or file argument (`$1` / `sys.argv[1]`). A script that takes something else instead — a project directory, a saved JSON file — declares the real command line in `evaluation.script_usage` so the epilogue does not state something untrue.
- Output (stdout): `{"outcome": 1-5, "note": "...", "checks": {...}, "source": "script"}`. A script whose `outcome` scores something other than this skill's own work declares `evaluation.script_emits_outcome: false`; the epilogue then runs it for evidence and scores by self-assessment.
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

# Test the trace pipeline
scripts/log-feedback.sh <skill> --outcome 4 --prompt "test" --source user
scripts/analyze-feedback.sh

# Bring traces home from every deployed copy (idempotent; run before compaction)
scripts/harvest-feedback.sh <skill>
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase --autostash
   # bd 1.0.0 exports; it has no sync. Check the DB is hydrated first -- a
   # partial one overwrites .beads/issues.jsonl with fewer issues.
   bd list                                     # is this the issue set you expect?
   [ "$(bd list --all --json | jq length)" -ge "$(wc -l < .beads/issues.jsonl)" ] \
     && bd export -o .beads/issues.jsonl
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Push yourself, in this session — stopping short leaves the work stranded locally
- If push fails, resolve and retry until it succeeds
