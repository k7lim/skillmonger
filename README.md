# Skillmonger

**Build reusable AI agent skills that work across Claude Code, OpenAI Codex, and Gemini.**

Write a skill once—like "find centers of excellence for any topic" or "generate release notes from commits"—and it becomes a slash command you can invoke in any conversation. Run `scripts/new-skill.sh` to scaffold a new skill in 30 seconds, then iterate on it over time. The framework tracks edge cases and helps you refine each skill as you use it.

## Why?

AI coding agents are powerful, but they forget everything between sessions. You end up re-explaining the same workflows, catching the same edge cases, and repeating yourself constantly.

Skills fix this. A skill is a reusable prompt with structure:
- **Portable** — Works on Claude Code, Codex, and Antigravity (Gemini)
- **Versionable** — Lives in Git, improves over time
- **Composable** — Reference docs, examples, and decision logic stay organized

The tri-file architecture (`SKILL.md` + `CONFIG.yaml` + `MEMO.md`) prevents context bloat while enabling iterative improvement. Log edge cases as you hit them, then periodically "compact" stable patterns back into the skill.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/yourusername/skillmonger.git
cd skillmonger

# Create your first skill (interactive)
scripts/new-skill.sh

# Validate it
scripts/validate-skill.sh skills/my-skill/

# Deploy to Claude Code
scripts/deploy-skill.sh skills/my-skill/
```

## Requirements

- Bash 4.0+
- Git (optional, for hooks)
- Python 3 with PyYAML (optional, for full CONFIG.yaml validation)

## Example Skill

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

---

## Creating a New Skill

The fastest way:

```bash
scripts/new-skill.sh
```

This prompts for name, description, author, and optional triggers, then generates all the files you need.

### Manual Creation

#### 1. Create the skill directory

```bash
mkdir -p skills/my-new-skill/references
```

#### 2. Create SKILL.md (required)

The core instructions file with YAML frontmatter:

```markdown
---
name: my-new-skill
description: This skill does X when the user asks about Y. Use when the user mentions Z or wants to accomplish W.
---

# My New Skill

You are a [role description].

## When to Use

- Trigger condition 1
- Trigger condition 2

## Execution Workflow

### Step 1: [Action]

[Instructions...]

### Step 2: [Action]

[Instructions...]

## Examples

[Show example inputs and outputs]
```

**Frontmatter requirements:**
- `name`: lowercase, hyphens only, max 64 chars, must match directory name
- `description`: max 1024 chars, describe what it does AND when to use it

#### 3. Create CONFIG.yaml (recommended)

Extended metadata for the tri-file system:

```yaml
skill:
  name: my-new-skill
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

compaction:
  cycle_threshold: 15
  iteration_count: 0
```

#### 4. Create MEMO.md (recommended)

Edge cases and learnings (loaded only on failure):

```markdown
# My New Skill - MEMO

> **Loading Trigger:** Load when skill encounters issues.

## Edge Cases Log

_No edge cases logged yet._

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-01-14 | 1.0.0 | Initial | Skill created |
```

#### 5. Validate

```bash
scripts/validate-skill.sh skills/my-new-skill/
```

---

## Iterating on Skills

The tri-file architecture enables systematic improvement without context bloat.

```
┌─────────────────────────────────────────────────────────┐
│  1. USE SKILL                                           │
│     └─> Works? Done.                                    │
│     └─> Edge case? Continue...                          │
│                                                         │
│  2. LOG TO MEMO.md                                      │
│     - Document the edge case                            │
│     - Note the resolution                               │
│     - Increment iteration_count in CONFIG.yaml          │
│                                                         │
│  3. REPEAT until iteration_count >= 15                  │
│                                                         │
│  4. COMPACT                                             │
│     - Graduate stable patterns to SKILL.md              │
│     - Purge resolved edge cases                         │
│     - Bump version, reset iteration_count               │
└─────────────────────────────────────────────────────────┘
```

### Logging an Edge Case

When you encounter an issue:

1. Add to MEMO.md:

```markdown
### [Descriptive Title]

**Issue:** [What went wrong]
**Resolution:** [How to handle it]
```

2. Update CONFIG.yaml:

```yaml
compaction:
  iteration_count: 1  # increment
```

### Running Compaction

When `iteration_count >= 15`:

```bash
scripts/compact-memo.sh skills/my-skill/
```

Graduate stable patterns to SKILL.md, purge resolved edge cases, bump version.

---

## Deployment

Skills are deployed via symlinks. The global source of truth is `~/.local/share/skillmonger/skills/`.

### Global Deployment

Install to the central skillmonger directory and symlink from tool-specific locations:

```bash
# Deploy to all tools
scripts/deploy-skill.sh skills/my-skill/ --global

# Deploy to specific tools only
scripts/deploy-skill.sh skills/my-skill/ --global --tools claude,codex
```

### Local (Project) Deployment

Symlink from project directories to the skill source:

```bash
# Deploy to current project for all tools
scripts/deploy-skill.sh skills/my-skill/ --local .

# Deploy to specific project and tools
scripts/deploy-skill.sh skills/my-skill/ --local /path/to/project --tools claude
```

### Combined Deployment

```bash
# Global + local deployment
scripts/deploy-skill.sh skills/my-skill/ --global --local .

# With zip for Claude.ai upload
scripts/deploy-skill.sh skills/my-skill/ --global --format zip
```

### Cross-Platform Paths

| Platform | Global | Project |
|----------|--------|---------|
| Skillmonger (source) | `~/.local/share/skillmonger/skills/` | — |
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex | `~/.codex/skills/` | `.codex/skills/` |
| OpenCode | `~/.config/opencode/skills/` | `.opencode/skills/` |
| Claude.ai | Upload zip via Settings > Features | — |

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `new-skill.sh` | Create a new skill directly in skillmonger |
| `seed-skill.sh` | Capture a skill idea with minimal friction |
| `develop-skill.sh` | Create a skill scaffold in sandbox for development |
| `ship-skill.sh` | Ship a developed skill from sandbox to skillmonger |
| `validate-skill.sh` | Validate skill structure and frontmatter |
| `deploy-skill.sh` | Build and deploy skills |
| `compact-memo.sh` | Guide compaction when iteration threshold reached |
| `install-hooks.sh` | Install git pre-push hook for validation |

---

## Sandbox Development Workflow

For rapid iteration with unrestricted agent permissions, develop skills in the sandbox first.

```
┌─────────────────────────────────────────────────────────────────┐
│  SANDBOX (yolo permissions)          HOST (skillmonger)        │
│                                                                 │
│  ~/Development/sandbox/              ~/Development/host/        │
│  └── projects/skills/                └── skillmonger/           │
│      └── my-skill/                       └── skills/            │
│          ├── DESIGN.md  ←── think                               │
│          ├── SKILL.md   ←── iterate    ──promote──►  my-skill/  │
│          └── scripts/                                           │
│              └── status-check.sh                                │
└─────────────────────────────────────────────────────────────────┘
```

### Quick Start (Sandbox)

```bash
# Capture an idea (from anywhere)
seed-skill pdf-merger "combine PDFs with page selection"

# When ready to build, create scaffold
develop-skill

# Develop with yolo agent permissions
cd ~/Development/sandbox/projects/skills/my-skill
claude  # runs via yolobox with unrestricted permissions

# When stable, ship to skillmonger
ship-skill ~/Development/sandbox/projects/skills/my-skill

# Deploy for production use
scripts/deploy-skill.sh skills/my-skill/
```

### Deterministic vs Natural Language

The key insight: **scripts produce data, prompts interpret meaning**.

| Aspect | Deterministic (script) | Natural Language (prompt) |
|--------|------------------------|---------------------------|
| State detection | "Is ffmpeg installed?" | "Is this version right for the user's needs?" |
| Actions | `npm install remotion` | "Which template fits their video concept?" |
| Error handling | Exit codes, JSON output | "How to explain this failure helpfully?" |

Use `templates/DESIGN.md` to think through this split before building your skill. Every skill should ask: "What can be known deterministically?"

---

## Directory Structure

```
skillmonger/
├── skills/                   # Development (edit here)
│   └── my-skill/
│       ├── SKILL.md          # Core instructions (required)
│       ├── CONFIG.yaml       # Metadata & triggers (recommended)
│       ├── MEMO.md           # Edge cases log (recommended)
│       └── references/       # Supporting docs (optional)
├── scripts/                  # Framework tooling
├── hooks/                    # Git hooks
├── .claude/skills/           # Deployed skills (Claude Code reads here)
└── dist/                     # External distribution
```

**Workflow:** Edit in `skills/` → `deploy-skill.sh` → Agent uses `.claude/skills/`

---

## Cross-Platform Compatibility

| Platform | Base Standard | Extensions |
|----------|---------------|------------|
| Claude Code | SKILL.md + frontmatter | CONFIG.yaml, MEMO.md |
| OpenAI Codex | agentskills.io | Ignored (no breakage) |
| Antigravity | SKILL.md + frontmatter | Ignored (no breakage) |

Extensions don't break compatibility—platforms that don't understand them simply ignore them.

---

## Best Practices

**Designing Skills:**
- Start with `templates/DESIGN.md` to separate deterministic from natural language
- Build `scripts/status-check.sh` for all detectable prerequisites
- Scripts output JSON; prompts interpret the meaning
- Test status-check.sh edge cases (missing deps, wrong versions, partial installs)

**Writing SKILL.md:**
- Keep under 500 lines; move details to `references/`
- Front-load the description with trigger keywords
- Include interpretation tables for script outputs
- Include concrete examples with expected output

**Managing MEMO.md:**
- Log edge cases immediately—don't rely on memory
- Be specific about what triggered the issue
- Compact regularly; don't let it grow unbounded

**Versioning:**
- `1.0.0 → 1.0.1` — Compaction (patch)
- `1.0.1 → 1.1.0` — New capability (minor)
- `1.1.0 → 2.0.0` — Breaking workflow change (major)

---

## Contributing

Contributions welcome! Please:

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Run `scripts/install-hooks.sh` to enable pre-push validation
4. Make your changes
5. Submit a PR

For new skills, consider whether they're general enough to include in the main repo or better suited to your own fork.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
