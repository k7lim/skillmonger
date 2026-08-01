# Skillmonger

Build reusable AI agent skills that work across Claude Code, Codex, and Gemini.

A skill is a structured prompt that agents load on demand. Write it once, deploy it everywhere, and improve it over time through a built-in feedback loop.

## When to Create a Skill

You don't start by creating a skill. You start by noticing you keep doing the same thing.

The first time you explain a workflow to an agent, it's a conversation. The third time, it's a skill waiting to happen. Rule of thumb: if you've explained the same process to an agent 3+ times, extract it.

**Prompt -> Repeated prompt -> Skill.**

## How Skills Work

Every skill is a directory with up to four files:

- **SKILL.md** — Core instructions the agent follows (required)
- **CONFIG.yaml** — Metadata, triggers, and compaction settings (recommended)
- **MEMO.md** — Edge cases log, loaded on failure (recommended)
- **FEEDBACK.jsonl** — Execution outcome log, auto-created on first use

Full format reference: [docs/skill-format.md](docs/skill-format.md)

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
scripts/deploy-skill.sh skills/my-skill/ --global --tools claude,codex

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
| Claude.ai | Upload zip via Settings > Features | — |

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

1. **After the agent runs a skill**, the epilogue fires
2. **If an evaluate script exists** (`evaluate.sh`, `evaluate.py`, or any executable in `scripts/`) — run it for deterministic scoring
3. **If qualitative** — ask the user or self-assess per the epilogue's criteria
4. **Result** — one JSON line appended to `FEEDBACK.jsonl`, `iteration_count` incremented in CONFIG.yaml
5. **When `iteration_count` reaches the threshold (default 15)** — compaction reminder fires

### Manual feedback

```bash
# Record a manual entry (overrides LLM self-assessment)
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

When feedback accumulates (`iteration_count >= 15`):

```bash
scripts/compact-memo.sh skills/my-skill/
```

This shows feedback summary + MEMO.md content, then guides you through graduating stable patterns to SKILL.md, purging resolved edge cases, and bumping the version.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `new-skill.sh` | Create a new skill directly in skillmonger |
| `seed-skill.sh` | Capture a skill idea to `seeds/` |
| `develop-skill.sh` | Scaffold in sandbox (copies seed → PLAN.md) |
| `skill` | Show current skill status and next step |
| `ship-skill.sh` | Promote sandbox skill to skillmonger |
| `validate-skill.sh` | Validate skill structure and frontmatter |
| `deploy-skill.sh` | Deploy skills via symlinks to tool directories |
| `log-feedback.sh` | Record a feedback entry for a skill |
| `analyze-feedback.sh` | Summarize feedback trends across skills |
| `compact-memo.sh` | Guide compaction when iteration threshold reached |
| `install-hooks.sh` | Install git pre-push hook for validation |

## Directory Structure

```
skillmonger/
├── skills/                    # Skill source (edit here)
│   └── my-skill/
│       ├── SKILL.md           # Core instructions (required)
│       ├── CONFIG.yaml        # Metadata & triggers
│       ├── MEMO.md            # Edge cases log
│       ├── FEEDBACK.jsonl     # Execution feedback log
│       ├── references/        # Supporting docs
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
