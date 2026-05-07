---
name: skillmonger
description: Manage skillmonger workflow - see WIP status, start developing seeds, continue sandbox work, ship and deploy completed skills. Use when working in the skillmonger project or asking about skill development status.
---

# Skillmonger Workflow Manager

You help the user manage their skillmonger skill development workflow. This skill provides situational awareness and takes action to move skills through the pipeline.

## When to Use

- User asks "what was I working on?" or "skill status"
- User is in the skillmonger project and seems lost
- User wants to start developing a seed
- User wants to ship or deploy a skill

## Pipeline Stages

```
seeds/ → sandbox/skills/ → skills/ → .claude/skills/
(idea)    (WIP build)      (source)   (deployed)
```

## Workflow

### Step 1: Gather State

Collect information from these locations:

1. **Seeds** (ideas waiting to start):
   ```bash
   ls ~/Development/host/skillmonger/seeds/*.md 2>/dev/null
   ls -d ~/Development/host/skillmonger/seeds/*/ 2>/dev/null
   ```

2. **Sandbox WIP** (skills being built):
   ```bash
   ls -d ~/Development/sandbox/skills/*/ 2>/dev/null
   ```

3. **Shipped skills** (in skillmonger source):
   ```bash
   ls -d ~/Development/host/skillmonger/skills/*/ 2>/dev/null
   ```

4. **Deployed skills** (symlinked to Claude Code):
   ```bash
   ls -la ~/Development/host/skillmonger/.claude/skills/ 2>/dev/null
   ```

5. **State file** (last action taken):
   ```bash
   cat ~/.skillmonger-state 2>/dev/null
   ```

Cross-reference to identify:
- Seeds that have no matching sandbox or shipped skill
- Sandbox skills that haven't been shipped
- Shipped skills that differ from deployed versions
- Any recorded state from last session

### Step 2: Present Status

Format output as:

```
Skillmonger Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Seeds (not started):
  • seed-name - "first line of seed file..."

Sandbox WIP:
  • skill-name - last modified X ago

Ready to ship (sandbox → skills/):
  • skill-name - has SKILL.md, CONFIG.yaml, looks complete

Not deployed (skills/ → .claude/skills/):
  • skill-name - shipped but not deployed

Last session:
  • skill-name - "scaffolded" at 2024-01-15 14:30
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Skip any section that's empty.

### Step 3: Offer Actions

Based on state, suggest the most relevant action:

| State | Suggested Action |
|-------|------------------|
| Has unstarted seeds | "Start developing [seed]?" |
| Has sandbox WIP | "Continue [skill] in sandbox?" |
| Sandbox skill looks complete | "Ship [skill] to skills/?" |
| Shipped but not deployed | "Deploy [skill]?" |
| Nothing in flight | "Create a new seed?" |

Ask the user which action to take using AskUserQuestion if multiple options exist.

### Step 4: Execute Action

**Start developing a seed:**
```bash
cd ~/Development/host/skillmonger
scripts/develop-skill.sh
# Select the seed when prompted, or pass name if script supports it
```
Then tell user: `cd ~/Development/sandbox/skills/[name] && claude "Read BRIEF.md and build the skill"`

**Continue sandbox work:**
Tell user to: `cd ~/Development/sandbox/skills/[name]`
Optionally spawn a Task agent to continue the build.

**Ship a skill:**
```bash
cd ~/Development/host/skillmonger
scripts/ship-skill.sh ~/Development/sandbox/skills/[name]
```

**Deploy a skill:**
```bash
cd ~/Development/host/skillmonger
scripts/deploy-skill.sh [name]
```

## Key Paths

| Location | Purpose |
|----------|---------|
| `~/Development/host/skillmonger/` | Skillmonger project root |
| `~/Development/host/skillmonger/seeds/` | Seed ideas (markdown files) |
| `~/Development/host/skillmonger/skills/` | Shipped skill source |
| `~/Development/host/skillmonger/.claude/skills/` | Deployed symlinks |
| `~/Development/sandbox/skills/` | Sandbox development area |
| `~/.skillmonger-state` | Workflow state file |

## Important Notes

- Seeds are `.md` files or directories in `seeds/`
- Skip `README.md` when listing seeds
- A seed is "started" if a matching directory exists in sandbox or skills
- `develop-skill.sh` is interactive - it prompts for seed selection and one-liner
- The sandbox is disposable - real source lives in `skills/`

---

## After Execution

Self-assess based on:
- Did the status accurately reflect the project state?
- Did the suggested action match user intent?
- Did execution complete without errors?

**Scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

Log to `FEEDBACK.jsonl`:
```json
{"ts":"<UTC ISO 8601>","skill":"skillmonger","version":"<from CONFIG.yaml>","prompt":"<user request>","outcome":<1-5>,"note":"<brief note>","source":"llm","schema_version":1}
```
