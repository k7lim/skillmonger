# Skillmonger

Build reusable AI agent skills that work across Claude Code, Codex, and Gemini.

A skill is a directory of instructions that agents load on demand. Write it once, deploy it everywhere, and improve it over time through a built-in feedback loop.

## When to Create a Skill

You don't start by creating a skill. You start by noticing you keep doing the same thing.

The first time you explain a workflow to an agent, it's a conversation. The third time, it's a skill waiting to happen. Rule of thumb: if you've explained the same process to an agent 3+ times, extract it.

**Prompt -> Repeated prompt -> Skill.**

## How Skills Work

Every skill is a directory with up to four files, one per layer:

- **SKILL.md** — Core instructions the agent follows, the executable layer (required)
- **CONFIG.yaml** — Metadata, triggers, evaluation and compaction settings (recommended)
- **MEMO.md** — The skill's *wiki*: the patterns learned about it, loaded on failure (recommended)
- **FEEDBACK.jsonl** — *Traces*, one line per run, auto-created on first use

A run appends its trace to the copy of the skill the agent is running, and
`harvest-feedback.sh` brings those traces back here; enough of them trigger a
compaction pass that turns them into patterns and graduates the stable ones into
SKILL.md. [The Feedback Loop](#the-feedback-loop) walks the whole circuit.

Full format reference: [docs/skill-format.md](docs/skill-format.md). The words
this project uses for each part are pinned in [CONTEXT.md](CONTEXT.md).

## Quick Start

```bash
git clone https://github.com/yourusername/skillmonger.git
cd skillmonger

scripts/new-skill.sh                      # create a skill (interactive)
scripts/validate-skill.sh skills/my-skill/ # validate it
scripts/deploy-skill.sh skills/my-skill/   # deploy to Claude Code
```

## Creating Skills

### Already know what to build?

```bash
scripts/new-skill.sh
```

Prompts for name, description, triggers, then generates all files including the feedback epilogue. This is the transcription path — you already have the workflow in your head and just need it in the right format.

### Need to think it through?

Use the sandbox workflow for skills that need design work:

```bash
# Write your idea
echo "Download videos and extract transcripts" > seeds/my-skill.md

# Scaffold in sandbox (copies seed → PLAN.md)
scripts/develop-skill.sh

# Check where you left off anytime
scripts/skill status

# Launch agent in sandbox
cd ~/Development/sandbox/skills/my-skill
claude "Read BRIEF.md and build the skill"

# Ship when ready
scripts/ship-skill.sh ~/Development/sandbox/skills/my-skill
```

`develop-skill.sh` copies seed notes into `PLAN.md` and generates `BRIEF.md` — a task brief with interface contracts for the sandbox agent. Neither file ships; they're disposable scaffolding. `DESIGN.md` prompts structured thinking about state detection, decision points, and feedback mechanism before building.

### File format reference

See [docs/skill-format.md](docs/skill-format.md) for SKILL.md frontmatter requirements, CONFIG.yaml structure, MEMO.md template, and FEEDBACK.jsonl schema.

## Deploying Skills

```bash
# Global deployment (all tools)
scripts/deploy-skill.sh skills/my-skill/ --global

# Specific tools only
scripts/deploy-skill.sh skills/my-skill/ --global --tools claude,codex,pi

# Local (project) deployment
scripts/deploy-skill.sh skills/my-skill/ --local .

# ZIP for Claude.ai upload
scripts/deploy-skill.sh skills/my-skill/ --global --format zip
```

### Platform Paths

| Platform | Global | Project |
|----------|--------|---------|
| Skillmonger (source) | `~/.local/share/skillmonger/skills/` | — |
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex | `~/.codex/skills/` | `.codex/skills/` |
| OpenCode | `~/.config/opencode/skills/` | `.opencode/skills/` |
| Pi | `~/.pi/agent/skills/` | `.pi/skills/` |
| Claude.ai | Upload zip via Settings > Features | — |

Global deployment also copies skills into the sandbox home that protected
workspaces run every agent under — `$YOLOBOX_SANDBOX_HOME/.claude/skills/` and
`.codex/skills/`, default `~/.local/share/yolobox/home` — which cannot use the
host symlinks because the sandbox denies the shared `~/.local` skill store. Pi
keeps its regular `~/.pi/agent` home there, so its global skills are copied
rather than symlinked too. `scripts/lib/deploy-targets.sh` is the one definition
of the list, and `harvest-feedback.sh` reads the same file, so every copy's
traces come home before a redeploy overwrites it.

## The Feedback Loop

Every SKILL.md includes an "After Execution" epilogue. The mechanism matches the skill's output type.

### Feedback patterns

| Pattern | When | How |
|---------|------|-----|
| **Programmatic** | Output is verifiable by code | Evaluate script scores it (1-5) |
| **Qualitative** | Output is subjective | Ask user a skill-specific question, or agent self-assesses |
| **Delayed** | Correctness knowable later | Skip now, log later with `log-feedback.sh --source user` |
| **Hybrid** | Mix | Evaluate script + qualitative ask |

### How it works

1. **After the agent runs a skill**, the epilogue fires — rendered from `evaluation.mode` in CONFIG.yaml by `render-epilogue.sh`, so every skill says the same thing
2. **Programmatic or hybrid** — run the evaluate script and copy its score straight through
3. **Qualitative** — ask the user the skill's own question, or self-assess against the epilogue's criteria
4. **The trace lands beside the running copy** — one JSON line appended to the `FEEDBACK.jsonl` in the *deployed* skill directory, not this repo, because a copy in a sandbox home or on a Pi cannot reach it. That line is the whole record; a run edits nothing in CONFIG.yaml
5. **`harvest-feedback.sh` brings the traces home** — it unions every deployed copy into `skills/<name>/FEEDBACK.jsonl` and derives `iteration_count` from the result. `deploy-skill.sh` runs it before it overwrites a copy, so a redeploy no longer destroys what that copy accumulated
6. **At the threshold (default 15 traces, or three failures)** — compaction is due

### Writing a trace by hand

`log-feedback.sh` writes into this repo, so it is for your own use here — gate
runs and manual scoring. No epilogue calls it: a deployed copy cannot reach it.

```bash
# Record a trace yourself (a user score overrides the agent's self-assessment)
scripts/log-feedback.sh centers-of-excellence --outcome 4 --prompt "find CoE for tulips"

# Interactive mode
scripts/log-feedback.sh centers-of-excellence

# See trends across all skills
scripts/analyze-feedback.sh

# Detail for one skill
scripts/analyze-feedback.sh --skill centers-of-excellence
```

### Outcome scale

| Score | Label | Meaning |
|-------|-------|---------|
| 1 | Failed | Could not execute or wrong output |
| 2 | Poor | Executed but required major rework |
| 3 | Acceptable | Usable with minor edits |
| 4 | Good | Correct, no edits needed |
| 5 | Excellent | Exceeded expectations |

### Compaction

When the traces accumulate (`iteration_count >= 15`, or three failing runs):

```bash
scripts/harvest-feedback.sh my-skill        # traces first
scripts/compact-memo.sh skills/my-skill/    # then the maintainer's brief
```

`compact-memo.sh` lists the traces since the last pass beside the current
MEMO.md. You then root-cause them into patterns in the wiki, graduate the stable
ones into SKILL.md, purge the ones that no longer happen, and bump the version.
The wiki's iteration log names the patterns each version graduated — that is the
provenance of a skill edit.

### Gating an edit

An edit to a skill scored by a script is kept only if it holds up on held-out
prompts:

```bash
scripts/gate-skill.sh skills/my-skill/
```

The gate copies the skill, withholds `MEMO.md` so the score measures the skill
alone, runs every prompt in the skill's `fixtures/` through it, scores each with
the evaluate script, and compares against the same fixtures at the previous
version. Any fixture more than a point below its baseline, or a mean drop past
`evaluation.tolerance`, is a regression: it prints a revert line and reverts
nothing itself. Skills judged by a person are never gated.

`hooks/pre-push` runs the gate on every `skills/<name>/SKILL.md` a push adds
or modifies whose `evaluation.mode` is `programmatic` or `hybrid`, once per
skill no matter how many commits touch it. A regression blocks the push and
relays the revert line; a skill with fewer than three fixtures also blocks,
naming the `fixtures/<case>.prompt.md` layout it needs (fixtures are required
starting at a skill's first gated edit, no grace window). Any other reason a
skill can't be gated (for example `script_emits_outcome: false`) is reported
but does not block — there's nothing the author could add to fix it.
`SKILLMONGER_SKIP_GATE=1` skips the gate step entirely, printing a warning
that names the skills it skipped.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `new-skill.sh` | Create a new skill directly in skillmonger |
| `seed-skill.sh` | Capture a skill idea to `seeds/` |
| `develop-skill.sh` | Scaffold in sandbox (copies seed → PLAN.md) |
| `skill` | Show current skill status and next step |
| `ship-skill.sh` | Move a sandbox skill into skillmonger |
| `validate-skill.sh` | Validate skill structure, frontmatter, and skill format |
| `deploy-skill.sh` | Deploy skills to the tool directories and sandbox homes |
| `log-feedback.sh` | Write a trace from inside the repo |
| `harvest-feedback.sh` | Bring traces home from every deployed copy |
| `analyze-feedback.sh` | Summarize trace trends across skills |
| `compact-memo.sh` | Brief the maintainer when the threshold is reached |
| `render-epilogue.sh` | Print a skill's "After Execution" epilogue from its CONFIG |
| `gate-skill.sh` | Run a skill blind over its fixtures and compare to baseline |
| `install-hooks.sh` | Install git pre-push hook for validation and gating |

## Directory Structure

```
skillmonger/
├── skills/                    # Skill source (edit here)
│   └── my-skill/
│       ├── SKILL.md           # Core instructions (required)
│       ├── CONFIG.yaml        # Metadata & triggers
│       ├── MEMO.md            # The skill's wiki: its patterns
│       ├── FEEDBACK.jsonl     # Traces, one line per run
│       ├── references/        # Supporting docs
│       ├── fixtures/          # Held-out prompts for gate runs
│       └── scripts/           # evaluate.sh, check-prereqs.sh
├── scripts/                   # Framework tooling
├── templates/                 # DESIGN.md template
├── docs/                      # Format reference
├── hooks/                     # Git hooks
└── .claude/skills/            # Deployed skills (Claude Code reads here)
```

**Workflow:** Edit in `skills/` -> `deploy-skill.sh` -> Agent uses `.claude/skills/`

## Example

The included `centers-of-excellence` skill identifies top global locations for any topic:

```
You: /centers-of-excellence tulips

Claude: ## Top 10 Centers of Excellence for Tulips

1. **Netherlands** - World's largest tulip producer; Keukenhof and Aalsmeer flower auction
2. **Amsterdam, Netherlands** - Historic tulip trade center
3. **Turkey** - Origin of the tulip; Ottoman-era cultivation
...

## Languages for Tulip Research
Dutch (45%), English (30%), Turkish (10%), Japanese (5%), German (5%), Other (5%)
```

## Requirements

- Bash 4.0+
- Git (optional, for hooks)
- Python 3 with PyYAML (optional, for full CONFIG.yaml validation)

## Contributing

Contributions welcome. Fork the repo, create a feature branch, run `scripts/install-hooks.sh` to enable pre-push validation, make your changes, and submit a PR.

For new skills, consider whether they're general enough for the main repo or better suited to your own fork.

## License

MIT License. See [LICENSE](LICENSE) for details.
