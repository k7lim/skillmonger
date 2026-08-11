---
name: skillmonger
description: Manage skillmonger workflow - see WIP status, start developing seeds, continue sandbox work, ship and deploy completed skills, and adopt skills from external repos while keeping them updatable. Use when working in the skillmonger project, asking about skill development status, or wanting to take a skill from someone else's GitHub repo and make it your own.
---

# Skillmonger Workflow Manager

You help the user manage their skillmonger skill development workflow. This skill provides situational awareness and takes action to move skills through the pipeline.

## When to Use

- User asks "what was I working on?" or "skill status"
- User is in the skillmonger project and seems lost
- User wants to start developing a seed
- User wants to ship or deploy a skill

## Pipeline Stages

Two tracks land in the same place. Originals start from an idea; adoptions start
from someone else's repo.

```
ORIGINAL   seeds/ ───────────→ sandbox/skills/ → skills/ → deployed
           (idea)              (WIP build)      (source)

ADOPTED    vendor/<repo> ─────→ sandbox/skills/ → skills/ → deployed
           (upstream, pinned)  (adapt SKILL.md)  (source)
```

Adopted skills carry provenance for the rest of their life: a
`CONFIG.yaml:upstream` block and a `SOURCE.md` zone table saying which files are
still byte-identical to upstream. That is what makes them updatable later.

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

4. **Deployed skills** (installed to the shared store, then linked out):
   ```bash
   ls ~/.local/share/skillmonger/skills/ 2>/dev/null
   ```

5. **Adopted skills needing attention** (upstream moved, or provenance is lying):
   ```bash
   cd ~/Development/host/skillmonger && scripts/check-upstream.sh --offline
   ```
   Use `--offline` for a status sweep — it skips network fetches and is fast.
   Drop the flag only when the user actually wants to know about new upstream
   releases; a full fetch across every vendor repo takes a while.

6. **State file** (last action taken):
   ```bash
   cat ~/.skillmonger-state 2>/dev/null
   ```

Cross-reference to identify:
- Seeds that have no matching sandbox or shipped skill
- Sandbox skills that haven't been shipped
- Shipped skills that differ from deployed versions
- Adopted skills with **local drift** (a verbatim file was edited — the recorded
  provenance is now false, and this is the only condition that exits non-zero)
- Adopted skills with **upstream drift** (upstream released something newer)
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

Not deployed (skills/ → tool directories):
  • skill-name - shipped but not deployed

Adopted skills:
  • skill-name - LOCAL DRIFT: 2 verbatim files edited (provenance is false)
  • skill-name - upstream v1.2.4 available, pinned at v1.2.3
  • skill-name - orphaned upstream (deleted); ours alone now

Last session:
  • skill-name - "scaffolded" at 2024-01-15 14:30
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Skip any section that's empty. Report local drift before upstream drift — local
drift means `SOURCE.md` is currently claiming something untrue, which is worse
than being behind.

### Step 3: Offer Actions

Based on state, suggest the most relevant action:

| State | Suggested Action |
|-------|------------------|
| Adopted skill has local drift | "Reconcile [skill]? Its SOURCE.md is wrong." |
| Has unstarted seeds | "Start developing [seed]?" |
| Has sandbox WIP | "Continue [skill] in sandbox?" |
| Sandbox skill looks complete | "Ship [skill] to skills/?" |
| Shipped but not deployed | "Deploy [skill]?" |
| Upstream released something newer | "Sync [skill] to [ref]?" |
| User names an external repo | "Adopt a skill from it?" |
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
scripts/deploy-skill.sh skills/[name] --global
```
It takes a **path**, not a bare name, and requires a mode: `--global`,
`--store-only`, or `--local <dir>`. It installs to
`~/.local/share/skillmonger/skills/`, symlinks that into the Claude/Codex/
opencode skill directories, and copies into `~/.pi/agent/` and the SRT sandbox
homes (which cannot follow symlinks into the store).

**Adopt a skill from an external repo:**
```bash
cd ~/Development/host/skillmonger
scripts/adopt-skill.sh <owner/repo> <upstream-skill-path> [--ref <tag>]
```
Clones into `vendor/` pinned to a ref, copies into the sandbox, and writes the
provenance. Then adapt it in the sandbox and ship as normal. Read
`docs/adopting-external-skills.md` first — it has the three gates every adoption
must clear (tool portability, dependency adaptation, upstream updatability) and
the verbatim zone policy.

Keep `references/` and `assets/` verbatim. Adapt `SKILL.md` only; anything else
goes in `OVERLAY.md`. That is what keeps future syncs a checksum instead of a
review.

**Sync an adopted skill to a newer upstream:**
```bash
scripts/sync-upstream.sh [name] --dry-run     # always look first
scripts/sync-upstream.sh [name] --to v1.2.3
```
Fast-forwards verbatim files, blocks on adapted ones. Exit 2 means it needs a
human: reconcile the files it lists, then re-run with `--accept`. It writes
nothing at all unless the whole sync can complete, so exit 2 leaves the tree
untouched.

Never pass `--accept` on the user's behalf without them having actually reviewed
the diffs. It re-pins, and re-pinning asserts "this skill is reconciled with
upstream at REF".

**Fix local drift:** a verbatim file was edited. Either revert it, or accept the
edit and re-run `scripts/check-upstream.sh [name] --regenerate`, which
reclassifies it as `adapted` by observing reality. Then write the reason into
`SOURCE.md` under Adaptation notes.

## Key Paths

| Location | Purpose |
|----------|---------|
| `~/Development/host/skillmonger/` | Skillmonger project root |
| `~/Development/host/skillmonger/seeds/` | Seed ideas (markdown files) |
| `~/Development/host/skillmonger/skills/` | Shipped skill source |
| `~/Development/host/skillmonger/vendor/` | Pinned upstream repos (gitignored, never edit) |
| `~/.local/share/skillmonger/skills/` | Installed store that host symlinks point at |
| `~/Development/sandbox/skills/` | Sandbox development area |
| `~/.skillmonger-state` | Workflow state file |

## Important Notes

- Seeds are `.md` files or directories in `seeds/`
- Skip `README.md` when listing seeds
- A seed is "started" if a matching directory exists in sandbox or skills
- `develop-skill.sh` is interactive - it prompts for seed selection and one-liner
- `ship-skill.sh` is also interactive: it prompts before copying anything beyond
  the standard files, which for an adopted skill means `assets/` and `SOURCE.md`.
  Do not run it non-interactively and assume it finished.
- The sandbox is disposable - real source lives in `skills/`
- An adopted skill is any skill with an `upstream:` block in `CONFIG.yaml`
- `vendor/` is gitignored and read-only. Never edit it, and never "fix" an
  adopted skill by editing its vendored copy.
- `skills/remotion` is the one adoption that is **not** MIT and must stay out of
  any public bundle. `scripts/check-upstream.sh --licenses` lists what each
  adopted skill carries.

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
